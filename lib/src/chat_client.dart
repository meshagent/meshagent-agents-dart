import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/status.dart' as websocket_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'agent_messages.dart';

class AgentMessageEvent {
  AgentMessageEvent({
    required AgentMessage message,
    DateTime? createdAt,
    this.attachment,
  }) : _message = message,
       createdAt = (createdAt ?? message.createdAtUtc).toUtc();

  AgentMessage _message;
  final DateTime createdAt;
  final Uint8List? attachment;
  final List<void Function()> _listeners = <void Function()>[];

  AgentMessage get message => _message;

  AgentPayload get payload {
    final json = message.toJson();
    json['created_at'] = createdAt.toIso8601String();
    return json;
  }

  void addEventListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeEventListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void replaceMessage(AgentMessage message) {
    _message = message;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

class PendingAgentInput {
  const PendingAgentInput({
    required this.messageId,
    required this.messageType,
    required this.threadPath,
    required this.payload,
    required this.createdAt,
    this.awaitingAcceptance = false,
    this.awaitingApplication = false,
    this.awaitingOnline = false,
  });

  final String messageId;
  final String messageType;
  final String threadPath;
  final AgentMessage payload;
  final DateTime createdAt;
  final bool awaitingAcceptance;
  final bool awaitingApplication;
  final bool awaitingOnline;

  PendingAgentInput copyWith({
    bool? awaitingAcceptance,
    bool? awaitingApplication,
    bool? awaitingOnline,
  }) {
    return PendingAgentInput(
      messageId: messageId,
      messageType: messageType,
      threadPath: threadPath,
      payload: payload,
      createdAt: createdAt,
      awaitingAcceptance: awaitingAcceptance ?? this.awaitingAcceptance,
      awaitingApplication: awaitingApplication ?? this.awaitingApplication,
      awaitingOnline: awaitingOnline ?? this.awaitingOnline,
    );
  }
}

DateTime? _createdAtFromPayload(Map<String, dynamic> payload) {
  final value = payload['created_at'];
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value.trim());
    return parsed?.toUtc();
  }
  return null;
}

enum ChatThreadSessionLoadPhase { idle, loading, loaded, failed }

class ChatThreadSessionLoadState {
  const ChatThreadSessionLoadState({
    required this.phase,
    this.startedAt,
    this.completedAt,
    this.requestMessageId,
    this.sinceTurn,
    this.error,
    this.lastMessageType,
    this.lastMessageAt,
  });

  const ChatThreadSessionLoadState.idle()
    : phase = ChatThreadSessionLoadPhase.idle,
      startedAt = null,
      completedAt = null,
      requestMessageId = null,
      sinceTurn = null,
      error = null,
      lastMessageType = null,
      lastMessageAt = null;

  final ChatThreadSessionLoadPhase phase;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? requestMessageId;
  final String? sinceTurn;
  final String? error;
  final String? lastMessageType;
  final DateTime? lastMessageAt;

  bool get isLoading => phase == ChatThreadSessionLoadPhase.loading;
}

class ChatThreadStartResult {
  const ChatThreadStartResult({
    required this.session,
    required this.threadPath,
    this.realtimeConnection,
  });

  final ChatThreadSession session;
  final String threadPath;
  final Map<String, dynamic>? realtimeConnection;
}

class PendingThreadStartCandidate {
  const PendingThreadStartCandidate({
    required this.messageId,
    required this.senderName,
  });

  final String messageId;
  final String? senderName;
}

typedef ThreadCreatedPendingStartMatcher =
    String? Function(
      ThreadCreated message,
      List<PendingThreadStartCandidate> candidates,
    );

class _PendingThreadStartRequest {
  const _PendingThreadStartRequest({
    required this.request,
    required this.completer,
  });

  final StartThread request;
  final Completer<AgentMessage> completer;
}

abstract class BaseChatClient extends ChangeEmitter {
  BaseChatClient({
    this.threadCreatedPendingStartMatcher,
    this.deduplicateClientToolRequests = false,
  });

  final ThreadCreatedPendingStartMatcher? threadCreatedPendingStartMatcher;
  final bool deduplicateClientToolRequests;
  final Map<String, ChatThreadSession> _sessionsByPath =
      <String, ChatThreadSession>{};
  final Map<String, _PendingThreadStartRequest> _pendingStartRequests =
      <String, _PendingThreadStartRequest>{};
  final Map<String, List<AgentMessageEvent>> _pendingSessionEventsByPath =
      <String, List<AgentMessageEvent>>{};
  final StreamController<AgentMessageEvent> _events =
      StreamController<AgentMessageEvent>.broadcast();
  AgentConnectionStatus? _connectionStatus;
  final Set<String> _claimedClientToolRequests = <String>{};

  Stream<AgentMessageEvent> get events => _events.stream;

  AgentConnectionStatus? get connectionStatus => _connectionStatus;

  /// Whether messages must wait for a room agent participant before sending.
  ///
  /// Direct transports, such as managed-agent WebSockets, do not expose a
  /// room participant and can send as soon as their transport is connected.
  bool get requiresAgentParticipant => false;

  Iterable<ChatThreadSession> get sessions =>
      List<ChatThreadSession>.unmodifiable(_sessionsByPath.values);

  Future<void> start() async {}

  Future<void> stop() async {}

  RemoteParticipant? agentParticipant() => null;

  String? localParticipantName() => null;

  String? localParticipantId() => null;

  String? _cleanParticipantName(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _clientToolRequestKey(String threadPath, String requestId) {
    final normalizedThreadPath = threadPath.trim();
    final normalizedRequestId = requestId.trim();
    if (normalizedThreadPath.isEmpty || normalizedRequestId.isEmpty) {
      return null;
    }
    return '$normalizedThreadPath\n$normalizedRequestId';
  }

  bool _claimClientToolRequest(String threadPath, String requestId) {
    if (!deduplicateClientToolRequests) {
      return true;
    }
    final key = _clientToolRequestKey(threadPath, requestId);
    return key == null || _claimedClientToolRequests.add(key);
  }

  void _finishClientToolRequest(
    String threadPath,
    String requestId, {
    required bool responseSent,
  }) {
    if (!deduplicateClientToolRequests || responseSent) {
      return;
    }
    final key = _clientToolRequestKey(threadPath, requestId);
    if (key != null) {
      _claimedClientToolRequests.remove(key);
    }
  }

  ChatThreadSession openThread(
    String threadPath, {
    bool load = true,
    String? sinceTurn,
    bool reloadIfOpen = false,
  }) {
    final normalized = threadPath.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        threadPath,
        'threadPath',
        'thread path cannot be empty',
      );
    }
    final existing = _sessionsByPath[normalized];
    if (existing != null) {
      if (!existing.isOpen || reloadIfOpen) {
        unawaited(existing.open(load: load, sinceTurn: sinceTurn));
      }
      return existing;
    }
    final created = ChatThreadSession._(client: this, threadPath: normalized);
    _sessionsByPath[normalized] = created;
    unawaited(created.open(load: load, sinceTurn: sinceTurn));
    notifyListeners();
    return created;
  }

  Future<ChatThreadStartResult> startThread({
    String? messageId,
    required String message,
    required List<AgentFileContent> attachments,
    String? name,
    String? backend,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
    String? realtimeProtocol,
    String? senderName,
    List<ClientToolkitDescription>? clientToolkits,
    bool omitContent = false,
  }) async {
    final resolvedMessageId = messageId == null || messageId.trim().isEmpty
        ? const Uuid().v4()
        : messageId.trim();
    final resolvedSenderName =
        _cleanParticipantName(senderName) ?? localParticipantName();
    final payload = StartThread(
      messageId: resolvedMessageId,
      content: omitContent
          ? null
          : agentInputContent(text: message, attachments: attachments),
      name: name != null && name.trim().isNotEmpty ? name.trim() : null,
      backend: backend != null && backend.trim().isNotEmpty
          ? backend.trim()
          : null,
      provider: provider != null && provider.trim().isNotEmpty
          ? provider.trim()
          : null,
      model: model != null && model.trim().isNotEmpty ? model.trim() : null,
      voice: voice != null && voice.trim().isNotEmpty ? voice.trim() : null,
      outputModalities: outputModalities != null && outputModalities.isNotEmpty
          ? outputModalities
          : null,
      realtimeProtocol:
          realtimeProtocol != null && realtimeProtocol.trim().isNotEmpty
          ? realtimeProtocol.trim()
          : null,
      senderName: resolvedSenderName,
      clientToolkits: clientToolkits != null && clientToolkits.isNotEmpty
          ? clientToolkits
          : null,
    );
    final completer = Completer<AgentMessage>();
    _pendingStartRequests[resolvedMessageId] = _PendingThreadStartRequest(
      request: payload,
      completer: completer,
    );
    try {
      await sendAgentMessage(payload);
      final response = await completer.future;
      final threadPath = response is ThreadStarted
          ? response.threadId.trim()
          : response is AgentThreadMessage
          ? response.threadId.trim()
          : '';
      if (threadPath.isEmpty) {
        throw StateError(
          'Agent did not return a thread_id for the new thread.',
        );
      }
      final session = openThread(threadPath, load: false);
      if (!omitContent) {
        session.addAgentMessage(
          AgentMessageEvent(
            message: _resolvedStartThreadMessage(
              payload: payload,
              threadPath: threadPath,
            ),
            createdAt: payload.createdAtUtc,
          ),
        );
      }
      _drainPendingSessionEvents(threadPath, session);
      final realtimeConnection = response is ThreadStarted
          ? response.realtimeConnection?.toJson()
          : null;
      return ChatThreadStartResult(
        session: session,
        threadPath: threadPath,
        realtimeConnection: realtimeConnection,
      );
    } finally {
      _pendingStartRequests.remove(resolvedMessageId);
    }
  }

  TurnStart _resolvedStartThreadMessage({
    required StartThread payload,
    required String threadPath,
  }) {
    return TurnStart(
      threadId: threadPath,
      messageId: payload.messageId,
      senderName: payload.senderName,
      content: payload.content ?? <AgentInputContent>[],
      backend: payload.backend,
      provider: payload.provider,
      model: payload.model,
      voice: payload.voice,
      outputModalities: payload.outputModalities,
      instructions: payload.instructions,
      mcp: payload.mcp,
      clientToolkits: payload.clientToolkits,
      toolkits: payload.toolkits,
      toolChoice: payload.toolChoice,
    );
  }

  Future<void> sendAgentMessage(AgentMessage message, {Uint8List? attachment});

  void handleAgentMessage(
    AgentMessage message, {
    DateTime? createdAt,
    Uint8List? attachment,
  }) {
    if (message is AgentClientToolCallRequested) {
      final targetParticipantId = message.targetParticipantId?.trim();
      if (targetParticipantId != null &&
          targetParticipantId.isNotEmpty &&
          targetParticipantId != localParticipantId()) {
        return;
      }
    }
    if (message is AgentConnectionStatus) {
      _connectionStatus = message;
    }
    _events.add(
      AgentMessageEvent(
        message: message,
        createdAt: createdAt,
        attachment: attachment,
      ),
    );
    final sourceMessageId = _sourceMessageId(message);
    if ((message is ThreadStarted || message is ThreadStartRejected) &&
        sourceMessageId != null &&
        sourceMessageId.trim().isNotEmpty) {
      final pending = _pendingStartRequests[sourceMessageId.trim()];
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.complete(message);
      }
    }
    if (message is ThreadCreated) {
      _acknowledgePendingStartFromThreadCreated(message);
    }
    final threadPath = message is AgentThreadMessage
        ? message.threadId.trim()
        : null;
    if (threadPath == null || threadPath.isEmpty) {
      notifyListeners();
      return;
    }
    final session = _sessionsByPath[threadPath];
    final event = AgentMessageEvent(
      message: message,
      createdAt: createdAt,
      attachment: attachment,
    );
    if (session != null) {
      session.addAgentMessage(event);
    } else {
      (_pendingSessionEventsByPath[threadPath] ??= <AgentMessageEvent>[]).add(
        event,
      );
    }
    notifyListeners();
  }

  void _acknowledgePendingStartFromThreadCreated(ThreadCreated message) {
    final matcher = threadCreatedPendingStartMatcher;
    final threadPath = message.thread.path.trim();
    if (matcher == null || threadPath.isEmpty) {
      return;
    }

    final candidates = _pendingStartRequests.entries
        .where((entry) => !entry.value.completer.isCompleted)
        .map(
          (entry) => PendingThreadStartCandidate(
            messageId: entry.key,
            senderName: entry.value.request.senderName,
          ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return;
    }

    String? matchedMessageId;
    try {
      matchedMessageId = matcher(message, candidates)?.trim();
    } catch (_) {
      return;
    }
    if (matchedMessageId == null || matchedMessageId.isEmpty) {
      return;
    }

    final pending = _pendingStartRequests[matchedMessageId];
    if (pending == null || pending.completer.isCompleted) {
      return;
    }
    pending.completer.complete(
      ThreadStarted(sourceMessageId: matchedMessageId, threadId: threadPath),
    );
  }

  void _drainPendingSessionEvents(
    String threadPath,
    ChatThreadSession session,
  ) {
    final pending = _pendingSessionEventsByPath.remove(threadPath);
    if (pending == null) {
      return;
    }
    for (final event in pending) {
      session.addAgentMessage(event);
    }
  }

  void emitConnectionStatus({
    required String status,
    String? message,
    String? reason,
    Duration? retryDelay,
  }) {
    final event = AgentConnectionStatus(
      status: status,
      message: message,
      reason: reason,
      retryInSeconds: retryDelay == null
          ? null
          : retryDelay.inMilliseconds / Duration.millisecondsPerSecond,
    );
    _connectionStatus = event;
    _events.add(AgentMessageEvent(message: event));
    notifyListeners();
  }

  void removeThreadSession(String threadPath) {
    final normalized = threadPath.trim();
    final removed = _sessionsByPath.remove(normalized);
    removed?._markClosed(notify: false);
    if (removed != null) {
      notifyListeners();
    }
  }
}

const String messagingChatThreadSubscribeType =
    'meshagent.chat.thread.subscribe';
const String messagingChatThreadListSubscribeType =
    'meshagent.chat.thread_list.subscribe';

sealed class MessagingChatSubscription {
  MessagingStream get stream;
  Future<void> close();
}

class ThreadSubscribe implements MessagingChatSubscription {
  ThreadSubscribe({required this.threadId, required this.stream});

  final String threadId;
  @override
  final MessagingStream stream;

  bool get closed => stream.closed;

  Future<void> send(AgentMessage message, {Uint8List? attachment}) {
    return stream.sendMessage(
      type: agentRoomMessageType,
      message: message.toJson(),
      attachment: attachment,
    );
  }

  @override
  Future<void> close() => stream.close();
}

class ThreadListSubscribe implements MessagingChatSubscription {
  ThreadListSubscribe({required this.stream});

  @override
  final MessagingStream stream;

  bool get closed => stream.closed;

  @override
  Future<void> close() => stream.close();
}

class BaseMessagingChatClient extends BaseChatClient {
  BaseMessagingChatClient({
    required this.room,
    this.agentName,
    super.threadCreatedPendingStartMatcher,
    super.deduplicateClientToolRequests = true,
  }) {
    _attachListeners();
  }

  final RoomClient room;
  final String? agentName;
  StreamSubscription<RoomEvent>? _roomSubscription;
  final Map<String, Completer<RemoteParticipant>> _pendingParticipantWaits =
      <String, Completer<RemoteParticipant>>{};
  bool _started = false;
  String? _agentParticipantId;
  bool _hasConnected = false;
  bool _waitingForParticipant = false;
  bool _messagingListenerAttached = false;

  @override
  bool get requiresAgentParticipant => true;

  @override
  String? localParticipantName() {
    final name = room.localParticipant?.getAttribute('name');
    return name is String ? _cleanParticipantName(name) : null;
  }

  @override
  String? localParticipantId() => room.localParticipant?.id;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _attachListeners();
    room.messaging.start();
    await room.messaging.enable();
    _waitingForParticipant = true;
    _onMessagingChanged();
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    _detachMessagingListener();
    for (final wait in _pendingParticipantWaits.values) {
      if (!wait.isCompleted) {
        wait.completeError(
          StateError(
            'Chat client stopped while waiting for an agent participant.',
          ),
        );
      }
    }
    _pendingParticipantWaits.clear();
    if (_agentParticipantId != null) {
      _agentParticipantId = null;
      emitConnectionStatus(
        status: 'disconnected',
        message: 'Agent messaging disconnected',
        reason: 'client_stopped',
      );
    }
  }

  void _attachListeners() {
    _roomSubscription ??= room.listen(_onRoomEvent);
    if (!_messagingListenerAttached) {
      room.messaging.addListener(_onMessagingChanged);
      _messagingListenerAttached = true;
    }
  }

  void _detachMessagingListener() {
    if (!_messagingListenerAttached) {
      return;
    }
    room.messaging.removeListener(_onMessagingChanged);
    _messagingListenerAttached = false;
  }

  @override
  RemoteParticipant? agentParticipant() {
    final normalizedAgentName = agentName?.trim();
    for (final participant in room.messaging.remoteParticipants) {
      if (normalizedAgentName != null &&
          normalizedAgentName.isNotEmpty &&
          participant.getAttribute('name') != normalizedAgentName) {
        continue;
      }
      if (normalizedAgentName != null && normalizedAgentName.isNotEmpty) {
        return participant;
      }
      if (participant.getAttribute('supports_agent_messages') == true) {
        return participant;
      }
    }
    return null;
  }

  Future<RemoteParticipant> waitForAgentParticipant({String? waitKey}) async {
    final existing = agentParticipant();
    if (existing != null) {
      return existing;
    }
    final key = waitKey == null || waitKey.trim().isEmpty
        ? const Uuid().v4()
        : waitKey.trim();
    final completer = Completer<RemoteParticipant>();
    _pendingParticipantWaits[key] = completer;
    _onMessagingChanged();
    try {
      return await completer.future;
    } finally {
      _pendingParticipantWaits.remove(key);
    }
  }

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
  }) async {
    await start();
    final participant = agentParticipant();
    if (participant == null) {
      throw StateError('Agent messaging participant is not available.');
    }
    await room.messaging.sendMessage(
      to: participant,
      type: agentRoomMessageType,
      message: message.toJson(),
      attachment: attachment,
    );
  }

  void _onMessagingChanged() {
    final participant = agentParticipant();
    final participantId = participant?.id;
    if (participantId != _agentParticipantId) {
      if (participantId == null) {
        if (_agentParticipantId != null) {
          _waitingForParticipant = true;
          emitConnectionStatus(
            status: 'disconnected',
            message: 'Agent messaging disconnected',
            reason: 'participant_disconnected',
          );
          emitConnectionStatus(
            status: 'reconnecting',
            message: 'Waiting for agent messaging',
            reason: 'participant_disconnected',
          );
        } else if (_started && _waitingForParticipant) {
          emitConnectionStatus(
            status: 'reconnecting',
            message: 'Waiting for agent messaging',
            reason: 'participant_offline',
          );
        }
      } else {
        final status = _hasConnected ? 'reconnected' : 'connected';
        _hasConnected = true;
        _waitingForParticipant = false;
        emitConnectionStatus(
          status: status,
          message: status == 'reconnected'
              ? 'Agent messaging reconnected'
              : 'Agent messaging connected',
        );
        if (status == 'reconnected') {
          unawaited(_reopenOpenSessions());
        }
      }
      _agentParticipantId = participantId;
    }
    if (participant != null) {
      for (final wait in _pendingParticipantWaits.values) {
        if (!wait.isCompleted) {
          wait.complete(participant);
        }
      }
    }
    notifyListeners();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is RoomStatusEvent) {
      final status = event.status.trim().toLowerCase();
      if (status == 'connected' || status == 'reconnected') {
        _waitingForParticipant = true;
        _onMessagingChanged();
      } else if (status == 'disconnected' || status == 'reconnecting') {
        _agentParticipantId = null;
        _waitingForParticipant = true;
        emitConnectionStatus(
          status: status == 'disconnected' ? 'disconnected' : 'reconnecting',
          message: event.message.trim().isNotEmpty
              ? event.message
              : (status == 'disconnected'
                    ? 'Agent messaging disconnected'
                    : 'Waiting for agent messaging'),
        );
      }
      return;
    }
    if (event is! RoomMessageEvent ||
        event.message.type != agentRoomMessageType) {
      return;
    }
    final message = event.message.message;
    final rawPayload = message['type'] is String ? message : message['payload'];
    if (rawPayload is Map<String, dynamic>) {
      final participant = agentParticipant();
      final fromSelectedAgent =
          participant != null &&
          event.message.fromParticipantId == participant.id;
      final fromParticipantlessThreadList =
          event.message.fromParticipantId.trim().isEmpty &&
          _isThreadListPayload(rawPayload);
      if (!fromSelectedAgent && !fromParticipantlessThreadList) {
        return;
      }
      handleAgentMessage(
        AgentMessage.fromJson(rawPayload),
        createdAt: _createdAtFromPayload(rawPayload),
        attachment: event.message.attachment,
      );
    } else if (rawPayload is Map) {
      final payload = Map<String, dynamic>.from(rawPayload);
      final participant = agentParticipant();
      final fromSelectedAgent =
          participant != null &&
          event.message.fromParticipantId == participant.id;
      final fromParticipantlessThreadList =
          event.message.fromParticipantId.trim().isEmpty &&
          _isThreadListPayload(payload);
      if (!fromSelectedAgent && !fromParticipantlessThreadList) {
        return;
      }
      handleAgentMessage(
        AgentMessage.fromJson(payload),
        createdAt: _createdAtFromPayload(payload),
        attachment: event.message.attachment,
      );
    }
  }

  Future<void> _reopenOpenSessions() async {
    for (final session in sessions) {
      if (!session.isOpen) {
        continue;
      }
      await session.open(load: true, sinceTurn: session.lastCompletedTurnId);
    }
  }
}

class MessagingChatClient extends BaseMessagingChatClient {
  MessagingChatClient({
    required super.room,
    super.agentName,
    super.threadCreatedPendingStartMatcher,
    super.deduplicateClientToolRequests = true,
  });

  final Map<String, ThreadSubscribe> _threadSubscriptions =
      <String, ThreadSubscribe>{};
  ThreadListSubscribe? _threadListSubscription;
  final Set<StreamSubscription<MessagingStreamEvent>> _streamSubscriptions =
      <StreamSubscription<MessagingStreamEvent>>{};

  bool _supportsThreadSubscriptions(RemoteParticipant participant) {
    return participant.getAttribute('supports_messaging_streams') == true;
  }

  void _trackSubscription(MessagingChatSubscription subscription) {
    late StreamSubscription<MessagingStreamEvent> eventSubscription;
    eventSubscription = subscription.stream.events.listen(
      (event) {
        if (event is! MessagingStreamMessage ||
            event.message.type != agentRoomMessageType) {
          return;
        }
        final payload = event.message.message;
        if (payload['type'] is! String) {
          return;
        }
        handleAgentMessage(
          AgentMessage.fromJson(payload),
          createdAt: _createdAtFromPayload(payload),
          attachment: event.message.attachment,
        );
      },
      onDone: () {
        _streamSubscriptions.remove(eventSubscription);
        if (subscription is ThreadSubscribe) {
          if (identical(
            _threadSubscriptions[subscription.threadId],
            subscription,
          )) {
            _threadSubscriptions.remove(subscription.threadId);
          }
        } else if (identical(_threadListSubscription, subscription)) {
          _threadListSubscription = null;
        }
      },
    );
    _streamSubscriptions.add(eventSubscription);
  }

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
  }) async {
    await start();
    final participant = agentParticipant();
    if (participant == null) {
      throw StateError('Agent messaging participant is not available.');
    }
    if (!_supportsThreadSubscriptions(participant)) {
      await super.sendAgentMessage(message, attachment: attachment);
      return;
    }
    if (message is OpenThread) {
      await _threadSubscriptions.remove(message.threadId)?.close();
      final stream = await room.messaging.stream(
        to: participant,
        type: messagingChatThreadSubscribeType,
        message: message.toJson(),
        attachment: attachment,
      );
      final subscription = ThreadSubscribe(
        threadId: message.threadId,
        stream: stream,
      );
      _threadSubscriptions[message.threadId] = subscription;
      _trackSubscription(subscription);
      return;
    }
    if (message is CloseThread) {
      final subscription = _threadSubscriptions.remove(message.threadId);
      if (subscription != null) {
        await subscription.close();
        return;
      }
    }
    if (message is WatchThreads) {
      await _threadListSubscription?.close();
      final stream = await room.messaging.stream(
        to: participant,
        type: messagingChatThreadListSubscribeType,
        message: message.toJson(),
        attachment: attachment,
      );
      final subscription = ThreadListSubscribe(stream: stream);
      _threadListSubscription = subscription;
      _trackSubscription(subscription);
      return;
    }
    if (message is UnwatchThreads && _threadListSubscription != null) {
      final subscription = _threadListSubscription;
      _threadListSubscription = null;
      await subscription!.close();
      return;
    }
    if (message is AgentThreadMessage) {
      final subscription = _threadSubscriptions[message.threadId];
      if (subscription != null) {
        await subscription.send(message, attachment: attachment);
        return;
      }
    }
    await super.sendAgentMessage(message, attachment: attachment);
  }

  @override
  Future<void> stop() async {
    final subscriptions = <MessagingChatSubscription>[
      ..._threadSubscriptions.values,
      ?_threadListSubscription,
    ];
    _threadSubscriptions.clear();
    _threadListSubscription = null;
    await Future.wait(
      subscriptions.map((subscription) => subscription.close()),
    );
    final eventSubscriptions =
        List<StreamSubscription<MessagingStreamEvent>>.from(
          _streamSubscriptions,
        );
    _streamSubscriptions.clear();
    await Future.wait(
      eventSubscriptions.map((subscription) => subscription.cancel()),
    );
    await super.stop();
  }
}

bool _isThreadListPayload(Map<String, dynamic> payload) {
  final type = payload['type'];
  return type == agentThreadListedType ||
      type == agentThreadCreatedType ||
      type == agentThreadUpdatedType ||
      type == agentThreadDeletedType;
}

class WebSocketChatClient extends BaseChatClient {
  WebSocketChatClient({
    required this.url,
    required this.token,
    this.participantName,
    this.protocols = const <String>['meshagent-msgpack'],
    this.reconnect = true,
    this.reconnectInitialDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 10),
  }) : super(deduplicateClientToolRequests: true);

  final Uri url;
  final String token;
  final String? participantName;
  final List<String> protocols;
  final bool reconnect;
  final Duration reconnectInitialDelay;
  final Duration reconnectMaxDelay;
  WebSocketChannel? _webSocket;
  StreamSubscription<dynamic>? _subscription;
  Object? _receiveError;
  int? _closeCode;
  String? _closeReason;
  bool _started = false;
  bool _stopping = false;
  bool _connecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  String? _assignedParticipantId;

  bool get isConnected => _webSocket != null;

  @override
  String? localParticipantName() => _cleanParticipantName(participantName);

  @override
  String? localParticipantId() => _assignedParticipantId;

  @override
  Future<void> start() async {
    _started = true;
    _stopping = false;
    if (_webSocket != null || _connecting) {
      return;
    }
    await _connect(isReconnect: false);
  }

  Future<void> _connect({required bool isReconnect}) async {
    if (_webSocket != null || _connecting || !_started || _stopping) {
      return;
    }
    _connecting = true;
    final webSocket = WebSocketChannel.connect(
      url,
      protocols: _resolvedProtocols(),
    );
    _webSocket = webSocket;
    _assignedParticipantId = null;
    try {
      await webSocket.ready;
    } catch (error) {
      _webSocket = null;
      _receiveError = error;
      _connecting = false;
      if (isReconnect && reconnect && !_stopping) {
        _scheduleReconnect(reason: error.toString());
        return;
      }
      emitConnectionStatus(
        status: 'disconnected',
        message: 'Chat websocket connection failed',
        reason: error.toString(),
      );
      rethrow;
    }
    _subscription = webSocket.stream.listen(
      _onData,
      onError: (Object error) {
        _receiveError = error;
        _handleSocketDisconnected(
          webSocket,
          reason: error.toString(),
          wasError: true,
        );
      },
      onDone: () {
        _handleSocketDisconnected(
          webSocket,
          reason: _socketCloseReason(webSocket),
          wasError: false,
        );
      },
    );
    _connecting = false;
    _receiveError = null;
    _closeCode = null;
    _closeReason = null;
    final status = isReconnect ? 'reconnected' : 'connected';
    emitConnectionStatus(
      status: status,
      message: isReconnect
          ? 'Chat websocket reconnected'
          : 'Chat websocket connected',
    );
    if (isReconnect) {
      await _reopenOpenSessions();
    }
    _reconnectAttempts = 0;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _started = false;
    _stopping = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final webSocket = _webSocket;
    _webSocket = null;
    _assignedParticipantId = null;
    await _subscription?.cancel();
    _subscription = null;
    await webSocket?.sink.close(websocket_status.normalClosure);
    emitConnectionStatus(
      status: 'disconnected',
      message: 'Chat websocket disconnected',
      reason: 'client_stopped',
    );
    _stopping = false;
    notifyListeners();
  }

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
  }) async {
    if (attachment != null) {
      throw UnsupportedError(
        'WebSocketChatClient does not support binary attachments yet.',
      );
    }
    final webSocket = _webSocket;
    if (webSocket == null) {
      throw StateError(_closedMessage());
    }
    webSocket.sink.add(msgpack.serialize(message.toJson()));
  }

  void _handleSocketDisconnected(
    WebSocketChannel webSocket, {
    required String reason,
    required bool wasError,
  }) {
    if (!identical(_webSocket, webSocket)) {
      return;
    }
    _closeCode = webSocket.closeCode;
    _closeReason = webSocket.closeReason;
    _webSocket = null;
    _assignedParticipantId = null;
    _subscription = null;
    if (_stopping || !_started) {
      notifyListeners();
      return;
    }
    if (reconnect) {
      _scheduleReconnect(reason: reason);
    } else {
      emitConnectionStatus(
        status: 'disconnected',
        message: 'Chat websocket disconnected',
        reason: reason,
      );
    }
    notifyListeners();
  }

  void _scheduleReconnect({String? reason}) {
    if (_reconnectTimer != null || _stopping || !_started) {
      return;
    }
    final delay = _nextReconnectDelay();
    emitConnectionStatus(
      status: 'reconnecting',
      message: 'Chat websocket disconnected; reconnecting',
      reason: reason,
      retryDelay: delay,
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect(isReconnect: true));
    });
  }

  Duration _nextReconnectDelay() {
    final initialMs = reconnectInitialDelay.inMilliseconds <= 0
        ? 1
        : reconnectInitialDelay.inMilliseconds;
    final maxMs = reconnectMaxDelay.inMilliseconds <= 0
        ? initialMs
        : reconnectMaxDelay.inMilliseconds;
    final factor = 1 << (_reconnectAttempts > 6 ? 6 : _reconnectAttempts);
    _reconnectAttempts += 1;
    final millis = initialMs * factor;
    return Duration(milliseconds: millis > maxMs ? maxMs : millis);
  }

  Future<void> _reopenOpenSessions() async {
    for (final session in sessions) {
      if (!session.isOpen) {
        continue;
      }
      await session.open(load: true, sinceTurn: session.lastCompletedTurnId);
    }
  }

  List<String> _resolvedProtocols() {
    final resolved = <String>[];
    for (final protocol in protocols) {
      final normalized = protocol.trim();
      if (normalized.isNotEmpty && !resolved.contains(normalized)) {
        resolved.add(normalized);
      }
    }
    final normalizedToken = token.trim();
    if (normalizedToken.isNotEmpty) {
      resolved.add('meshagent-agent.$normalizedToken');
    }
    return resolved;
  }

  String _closedMessage() {
    final receiveError = _receiveError;
    if (receiveError != null) {
      return 'chat websocket is closed: $receiveError';
    }
    final closeCode = _closeCode;
    if (closeCode != null) {
      return 'chat websocket is closed (code=$closeCode)';
    }
    final closeReason = _closeReason;
    if (closeReason != null && closeReason.trim().isNotEmpty) {
      return 'chat websocket is closed: $closeReason';
    }
    return 'chat websocket is closed';
  }

  String _socketCloseReason(WebSocketChannel webSocket) {
    final closeCode = webSocket.closeCode;
    final closeReason = webSocket.closeReason;
    if (closeCode != null && closeReason != null && closeReason.isNotEmpty) {
      return 'code=$closeCode: $closeReason';
    }
    if (closeCode != null) {
      return 'code=$closeCode';
    }
    if (closeReason != null && closeReason.isNotEmpty) {
      return closeReason;
    }
    return 'websocket closed';
  }

  void _onData(dynamic data) {
    try {
      final Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else {
        return;
      }
      final decoded = msgpack.deserialize(bytes);
      if (decoded is! Map) {
        throw StateError('chat websocket received a non-object message');
      }
      final message = AgentMessage.fromJson(_stringKeyMap(decoded));
      if (message is AgentConnectionStatus) {
        final participantId = message.participantId?.trim();
        if (participantId != null && participantId.isNotEmpty) {
          _assignedParticipantId = participantId;
        }
      }
      handleAgentMessage(message);
    } catch (error) {
      _receiveError = error;
      emitConnectionStatus(
        status: 'disconnected',
        message: 'Chat websocket message could not be decoded',
        reason: error.toString(),
      );
      unawaited(_webSocket?.sink.close(websocket_status.unsupportedData));
    }
  }

  Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> value) {
    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _normalizeMsgpackValue(nestedValue)),
    );
  }

  dynamic _normalizeMsgpackValue(dynamic value) {
    if (value is Map) {
      return _stringKeyMap(value);
    }
    if (value is List) {
      return value.map(_normalizeMsgpackValue).toList();
    }
    return value;
  }
}

class ChatThreadSession extends ChangeEmitter {
  ChatThreadSession._({
    required BaseChatClient client,
    required this.threadPath,
  }) : _client = client;

  final BaseChatClient _client;
  final String threadPath;
  final List<AgentMessageEvent> _messages = <AgentMessageEvent>[];
  final Map<String, int> _messageIndexes = <String, int>{};
  final Set<String> _localAgentMessageIds = <String>{};
  final Set<String> _pendingLocalInputMessageIds = <String>{};
  final Set<String> _resolvedInputMessageIds = <String>{};
  final Set<String> _completedTurnIds = <String>{};
  final Set<String> _mergedDeltaMessageIds = <String>{};
  final Map<String, PendingAgentInput> _pendingInputs =
      <String, PendingAgentInput>{};
  bool _open = false;
  ChatThreadSessionLoadState _loadState =
      const ChatThreadSessionLoadState.idle();
  String? _lastCompletedTurnId;
  String? _lastAgentMessageType;
  DateTime? _lastAgentMessageAt;

  List<AgentMessageEvent> get messages =>
      List<AgentMessageEvent>.unmodifiable(_messages);

  List<PendingAgentInput> get pendingInputs =>
      List<PendingAgentInput>.unmodifiable(_pendingInputs.values);

  bool get isOpen => _open;

  ChatThreadSessionLoadState get loadState => _loadState;

  bool get isLoading => _loadState.isLoading;

  String? get lastCompletedTurnId => _lastCompletedTurnId;

  Future<void> open({bool load = true, String? sinceTurn}) async {
    if (_open) {
      if (load) {
        if (sinceTurn == null) {
          _resetReplayState();
        }
        final openThread = OpenThread(
          threadId: threadPath,
          load: true,
          sinceTurn: sinceTurn,
        );
        _setLoadState(_loadingStateForOpen(openThread, sinceTurn: sinceTurn));
        try {
          await _client.sendAgentMessage(openThread);
          await requestModels();
        } catch (error) {
          _setLoadState(_failedLoadState(error));
        }
      }
      return;
    }
    _open = true;
    final openThread = OpenThread(
      threadId: threadPath,
      load: load,
      sinceTurn: load ? sinceTurn : null,
    );
    if (load) {
      _setLoadState(_loadingStateForOpen(openThread, sinceTurn: sinceTurn));
    }
    if (!load) {
      notifyListeners();
    }
    try {
      await _client.sendAgentMessage(openThread);
      await requestModels();
    } catch (error) {
      _setLoadState(_failedLoadState(error));
    }
  }

  void _resetReplayState() {
    _messages.clear();
    _messageIndexes.clear();
    _localAgentMessageIds.clear();
    _pendingLocalInputMessageIds.clear();
    _resolvedInputMessageIds.clear();
    _completedTurnIds.clear();
    _mergedDeltaMessageIds.clear();
    _pendingInputs.clear();
    _lastCompletedTurnId = null;
    _lastAgentMessageType = null;
    _lastAgentMessageAt = null;
  }

  Future<void> close() async {
    if (!_open) {
      return;
    }
    _markClosed();
    await _client
        .sendAgentMessage(CloseThread(threadId: threadPath))
        .catchError((_) {});
  }

  Future<void> requestModels() {
    return _client.sendAgentMessage(
      ModelsRequest(messageId: const Uuid().v4()),
    );
  }

  Future<void> changeModel({
    String? backend,
    required String provider,
    required String model,
    String? voice,
  }) {
    return _client.sendAgentMessage(
      ChangeModel(
        threadId: threadPath,
        messageId: const Uuid().v4(),
        backend: backend != null && backend.trim().isNotEmpty
            ? backend.trim()
            : null,
        provider: provider,
        model: model,
        voice: voice != null && voice.trim().isNotEmpty ? voice.trim() : null,
      ),
    );
  }

  Future<void> interruptTurn(String turnId) {
    return _client.sendAgentMessage(
      TurnInterrupt(threadId: threadPath, turnId: turnId),
    );
  }

  Future<void> respondToClientToolCall({
    required String turnId,
    required String requestId,
    required Content response,
  }) {
    return _client.sendAgentMessage(
      AgentClientToolCallResponse(
        threadId: threadPath,
        turnId: turnId,
        requestId: requestId,
        response: response,
      ),
    );
  }

  Future<void> injectMessages(Iterable<AgentMessage> messages) {
    return _client.sendAgentMessage(
      InjectMessages(threadId: threadPath, messages: messages),
    );
  }

  bool claimClientToolCall(String requestId) {
    return _client._claimClientToolRequest(threadPath, requestId);
  }

  void finishClientToolCall(String requestId, {required bool responseSent}) {
    _client._finishClientToolRequest(
      threadPath,
      requestId,
      responseSent: responseSent,
    );
  }

  Future<String> sendText({
    String? messageId,
    required String text,
    required List<AgentFileContent> attachments,
    bool steer = false,
    String? turnId,
    String? backend,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
    String? senderName,
    List<ClientToolkitDescription>? clientToolkits,
  }) async {
    final resolvedMessageId = messageId == null || messageId.trim().isEmpty
        ? const Uuid().v4()
        : messageId.trim();
    final payload = steer
        ? TurnSteer(
            threadId: threadPath,
            messageId: resolvedMessageId,
            senderName: senderName != null && senderName.trim().isNotEmpty
                ? senderName.trim()
                : null,
            turnId: turnId != null && turnId.trim().isNotEmpty
                ? turnId.trim()
                : resolvedMessageId,
            content: agentInputContent(text: text, attachments: attachments),
          )
        : TurnStart(
            threadId: threadPath,
            messageId: resolvedMessageId,
            senderName: senderName != null && senderName.trim().isNotEmpty
                ? senderName.trim()
                : null,
            content: agentInputContent(text: text, attachments: attachments),
            backend: backend != null && backend.trim().isNotEmpty
                ? backend.trim()
                : null,
            provider: provider != null && provider.trim().isNotEmpty
                ? provider.trim()
                : null,
            model: model != null && model.trim().isNotEmpty
                ? model.trim()
                : null,
            voice: voice != null && voice.trim().isNotEmpty
                ? voice.trim()
                : null,
            outputModalities:
                outputModalities != null && outputModalities.isNotEmpty
                ? outputModalities
                : null,
            clientToolkits: clientToolkits != null && clientToolkits.isNotEmpty
                ? clientToolkits
                : null,
          );
    _markPending(
      PendingAgentInput(
        messageId: resolvedMessageId,
        messageType: payload.type,
        threadPath: threadPath,
        payload: payload,
        createdAt: payload.createdAtUtc,
        awaitingAcceptance: true,
        awaitingApplication: true,
      ),
    );
    addAgentMessage(AgentMessageEvent(message: payload));
    try {
      await _client.sendAgentMessage(payload);
      return resolvedMessageId;
    } catch (_) {
      _pendingInputs.remove(resolvedMessageId);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendRealtimeAudioChunk({
    required Uint8List chunk,
    required Map<String, dynamic> format,
  }) async {
    await _client.sendAgentMessage(
      AgentRealtimeAudioChunk(
        threadId: threadPath,
        messageId: const Uuid().v4(),
        format: AgentAudioFormat.fromJson(format),
      ),
      attachment: chunk,
    );
  }

  Future<String> commitRealtimeAudio({
    required String turnId,
    String? backend,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
  }) async {
    final messageId = const Uuid().v4();
    await _client.sendAgentMessage(
      AgentRealtimeAudioCommit(
        threadId: threadPath,
        messageId: messageId,
        turnId: turnId,
      ),
    );
    await _client.sendAgentMessage(
      TurnStart(
        threadId: threadPath,
        messageId: const Uuid().v4(),
        turnId: turnId,
        backend: backend != null && backend.trim().isNotEmpty
            ? backend.trim()
            : null,
        provider: provider != null && provider.trim().isNotEmpty
            ? provider.trim()
            : null,
        model: model != null && model.trim().isNotEmpty ? model.trim() : null,
        voice: voice != null && voice.trim().isNotEmpty ? voice.trim() : null,
        outputModalities:
            outputModalities != null && outputModalities.isNotEmpty
            ? outputModalities
            : null,
      ),
    );
    return messageId;
  }

  Future<void> deleteThread(String threadPath) {
    return _client.sendAgentMessage(DeleteThread(threadId: threadPath));
  }

  Future<void> renameThread(String threadPath, String name) {
    return _client.sendAgentMessage(
      RenameThread(threadId: threadPath, name: name),
    );
  }

  void addAgentMessage(AgentMessageEvent event) {
    final message = event.message;
    final type = message.type;
    _lastAgentMessageType = type;
    _lastAgentMessageAt = event.createdAt;
    final messageId = message.messageId;
    final sourceMessageId = _sourceMessageId(message);
    if (type == agentThreadStartType ||
        type == agentTurnStartType ||
        type == agentTurnSteerType) {
      final normalizedMessageId = messageId.trim();
      if (normalizedMessageId.isNotEmpty) {
        final wasPending = _pendingInputs.containsKey(normalizedMessageId);
        final turnId = switch (message) {
          TurnStart(:final turnId) => _normalizedString(turnId),
          TurnSteer(:final turnId) => _normalizedString(turnId),
          _ => null,
        };
        final wasAlreadyResolved =
            !wasPending &&
            (_resolvedInputMessageIds.contains(normalizedMessageId) ||
                (turnId != null && _completedTurnIds.contains(turnId)));
        if (!wasAlreadyResolved) {
          _markPending(
            PendingAgentInput(
              messageId: normalizedMessageId,
              messageType: type,
              threadPath: threadPath,
              payload: message,
              createdAt: event.createdAt,
              awaitingAcceptance: true,
              awaitingApplication: true,
            ),
          );
        }
        _localAgentMessageIds.add(normalizedMessageId);
      }
    } else if (type == agentTurnStartAcceptedType ||
        type == agentTurnSteerAcceptedType) {
      _updatePending(
        sourceMessageId,
        awaitingAcceptance: false,
        awaitingApplication: true,
      );
    } else if (type == agentTurnStartedType || type == agentTurnSteeredType) {
      _pendingInputs.remove(sourceMessageId);
      if (sourceMessageId != null) {
        _resolvedInputMessageIds.add(sourceMessageId);
        _pendingLocalInputMessageIds.remove(sourceMessageId);
      }
    } else if (type == agentThreadStartRejectedType ||
        type == agentTurnStartRejectedType ||
        type == agentTurnSteerRejectedType) {
      _pendingInputs.remove(sourceMessageId);
      if (sourceMessageId != null) {
        _resolvedInputMessageIds.add(sourceMessageId);
        _pendingLocalInputMessageIds.remove(sourceMessageId);
      }
    } else if (type == agentTurnEndedType || type == agentThreadClearedType) {
      _pendingInputs.clear();
      _pendingLocalInputMessageIds.clear();
      if (message is TurnEnded && message.turnId.trim().isNotEmpty) {
        final turnId = message.turnId.trim();
        _completedTurnIds.add(turnId);
        _lastCompletedTurnId = turnId;
      } else if (type == agentThreadClearedType) {
        _resolvedInputMessageIds.clear();
        _completedTurnIds.clear();
      }
    } else if (type == agentThreadLoadedType) {
      _setLoadState(
        ChatThreadSessionLoadState(
          phase: ChatThreadSessionLoadPhase.loaded,
          startedAt: _loadState.startedAt,
          completedAt: _lastAgentMessageAt,
          requestMessageId: _loadState.requestMessageId,
          sinceTurn: _loadState.sinceTurn,
          lastMessageType: type,
          lastMessageAt: _lastAgentMessageAt,
        ),
        notify: false,
      );
    }
    _appendRenderableMessage(event);
    notifyListeners();
  }

  void _appendRenderableMessage(AgentMessageEvent event) {
    final message = event.message;
    if (message is TurnEnded) {
      _appendMessage(event);
      return;
    }
    if (message is StartThread ||
        message is TurnStart ||
        message is TurnSteer) {
      if (_agentInputHasVisibleContent(_messageContent(message))) {
        _appendMessage(event);
        final normalizedMessageId = message.messageId.trim();
        if (normalizedMessageId.isNotEmpty) {
          _pendingLocalInputMessageIds.add(normalizedMessageId);
        }
      }
      return;
    }
    if (message is TurnStartAccepted) {
      final normalizedSourceMessageId = message.sourceMessageId.trim();
      if (normalizedSourceMessageId.isNotEmpty &&
          _localAgentMessageIds.contains(normalizedSourceMessageId)) {
        _pendingLocalInputMessageIds.remove(normalizedSourceMessageId);
        return;
      }
      if (_agentInputHasVisibleContent(message.content)) {
        _appendMessage(event, beforePendingLocalInputs: true);
      }
      return;
    }
    if (_isMergeableDelta(message)) {
      _appendOrMergeDelta(event);
      return;
    }
    if (message is AgentImageGenerationPartial ||
        message is AgentImageGenerationCompleted) {
      _appendMessage(event);
      return;
    }
    if (message is AgentClientToolCallRequested) {
      _appendMessage(event);
      return;
    }
    if (message is AgentConnectionStatus || message is AgentThreadMessage) {
      _appendMessage(event);
    }
  }

  void _appendMessage(
    AgentMessageEvent event, {
    bool beforePendingLocalInputs = false,
  }) {
    final normalizedMessageId = _normalizedString(event.message.messageId);
    if (normalizedMessageId == null ||
        _messageIndexes.containsKey(normalizedMessageId)) {
      return;
    }
    if (beforePendingLocalInputs) {
      final insertIndex = _messages.indexWhere(
        (existing) =>
            _pendingLocalInputMessageIds.contains(existing.message.messageId),
      );
      if (insertIndex >= 0) {
        _messages.insert(insertIndex, event);
        _indexMessagesFrom(insertIndex);
        return;
      }
    }
    _messageIndexes[normalizedMessageId] = _messages.length;
    _messages.add(event);
  }

  void _appendOrMergeDelta(AgentMessageEvent event) {
    final message = event.message;
    final normalizedMessageId = _normalizedString(message.messageId);
    if (normalizedMessageId != null) {
      if (_mergedDeltaMessageIds.contains(normalizedMessageId)) {
        return;
      }
      _mergedDeltaMessageIds.add(normalizedMessageId);
    }
    final itemId = _deltaItemId(message);
    if (itemId == null) {
      return;
    }
    final key = '${message.type}:$itemId';
    final existingIndex = _messageIndexes[key];
    if (existingIndex == null) {
      _messageIndexes[key] = _messages.length;
      _messages.add(event);
      return;
    }
    final existing = _messages[existingIndex].message;
    final merged = _mergeDeltaMessage(existing, message);
    if (merged != null) {
      _messages[existingIndex].replaceMessage(merged);
    }
  }

  void _indexMessagesFrom(int start) {
    for (var index = start < 0 ? 0 : start; index < _messages.length; index++) {
      final key = _messageIndexKey(_messages[index].message);
      if (key != null) {
        _messageIndexes[key] = index;
      }
    }
  }

  void _markClosed({bool notify = true}) {
    _open = false;
    _loadState = ChatThreadSessionLoadState(
      phase: ChatThreadSessionLoadPhase.idle,
      lastMessageType: _lastAgentMessageType,
      lastMessageAt: _lastAgentMessageAt,
    );
    if (notify) {
      notifyListeners();
    }
  }

  ChatThreadSessionLoadState _loadingStateForOpen(
    OpenThread request, {
    required String? sinceTurn,
  }) {
    return ChatThreadSessionLoadState(
      phase: ChatThreadSessionLoadPhase.loading,
      startedAt: DateTime.now().toUtc(),
      requestMessageId: request.messageId,
      sinceTurn: sinceTurn,
      lastMessageType: _lastAgentMessageType,
      lastMessageAt: _lastAgentMessageAt,
    );
  }

  ChatThreadSessionLoadState _failedLoadState(Object error) {
    return ChatThreadSessionLoadState(
      phase: ChatThreadSessionLoadPhase.failed,
      startedAt: _loadState.startedAt,
      completedAt: DateTime.now().toUtc(),
      requestMessageId: _loadState.requestMessageId,
      sinceTurn: _loadState.sinceTurn,
      error: Error.safeToString(error),
      lastMessageType: _lastAgentMessageType,
      lastMessageAt: _lastAgentMessageAt,
    );
  }

  void _setLoadState(
    ChatThreadSessionLoadState loadState, {
    bool notify = true,
  }) {
    _loadState = loadState;
    if (notify) {
      notifyListeners();
    }
  }

  void _markPending(PendingAgentInput pending) {
    _pendingInputs[pending.messageId] = pending;
  }

  void _updatePending(
    String? messageId, {
    bool? awaitingAcceptance,
    bool? awaitingApplication,
    bool? awaitingOnline,
  }) {
    final normalized = messageId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    final existing = _pendingInputs[normalized];
    if (existing == null) {
      return;
    }
    _pendingInputs[normalized] = existing.copyWith(
      awaitingAcceptance: awaitingAcceptance,
      awaitingApplication: awaitingApplication,
      awaitingOnline: awaitingOnline,
    );
  }
}

String? _normalizedString(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

List<AgentInputContent> _messageContent(AgentMessage message) {
  if (message is StartThread) {
    return message.content ?? const <AgentInputContent>[];
  }
  if (message is TurnStart) {
    return message.content;
  }
  if (message is TurnSteer) {
    return message.content;
  }
  return const <AgentInputContent>[];
}

String _agentInputText(List<AgentInputContent> content) {
  return content
      .whereType<AgentTextContent>()
      .map((entry) => entry.text)
      .join('\n');
}

bool _agentInputHasVisibleContent(List<AgentInputContent> content) {
  return _agentInputText(content).trim().isNotEmpty ||
      content.whereType<AgentFileContent>().any(
        (entry) => entry.url.trim().isNotEmpty,
      );
}

String? _deltaItemId(AgentMessage message) {
  if (message is AgentAudioGenerationDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentAudioTranscriptionDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentFileContentDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentReasoningContentDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentTextContentDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentToolCallArgumentsDelta) {
    return _normalizedString(message.itemId);
  }
  if (message is AgentToolCallLogDelta) {
    return _normalizedString(message.itemId);
  }
  return null;
}

bool _isMergeableDelta(AgentMessage message) => _deltaItemId(message) != null;

String? _messageIndexKey(AgentMessage message) {
  if (_isMergeableDelta(message)) {
    final itemId = _deltaItemId(message);
    return itemId == null ? null : '${message.type}:$itemId';
  }
  return _normalizedString(message.messageId);
}

AgentMessage? _mergeDeltaMessage(AgentMessage existing, AgentMessage incoming) {
  if (existing is AgentAudioGenerationDelta &&
      incoming is AgentAudioGenerationDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'data': Uint8List.fromList(<int>[...existing.data, ...incoming.data]),
    });
  }
  if (existing is AgentAudioTranscriptionDelta &&
      incoming is AgentAudioTranscriptionDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'text': '${existing.text}${incoming.text}',
    });
  }
  if (existing is AgentFileContentDelta && incoming is AgentFileContentDelta) {
    return incoming;
  }
  if (existing is AgentReasoningContentDelta &&
      incoming is AgentReasoningContentDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'text': '${existing.text}${incoming.text}',
    });
  }
  if (existing is AgentTextContentDelta && incoming is AgentTextContentDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'text': '${existing.text}${incoming.text}',
    });
  }
  if (existing is AgentToolCallArgumentsDelta &&
      incoming is AgentToolCallArgumentsDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'delta': '${existing.delta}${incoming.delta}',
    });
  }
  if (existing is AgentToolCallLogDelta && incoming is AgentToolCallLogDelta) {
    return AgentMessage.fromJson(<String, dynamic>{
      ...existing.toJson(),
      'lines': <Map<String, dynamic>>[
        ...existing.lines.map((entry) => entry.toJson()),
        ...incoming.lines.map((entry) => entry.toJson()),
      ],
    });
  }
  return null;
}

String? _sourceMessageId(AgentMessage message) {
  if (message is ThreadStarted) {
    return message.sourceMessageId;
  }
  if (message is ThreadStartRejected) {
    return message.sourceMessageId;
  }
  if (message is ThreadCleared) {
    return message.sourceMessageId;
  }
  if (message is TurnStartAccepted) {
    return message.sourceMessageId;
  }
  if (message is TurnStartRejected) {
    return message.sourceMessageId;
  }
  if (message is TurnInterruptAccepted) {
    return message.sourceMessageId;
  }
  if (message is TurnSteerRejected) {
    return message.sourceMessageId;
  }
  return null;
}
