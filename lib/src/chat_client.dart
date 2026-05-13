import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:uuid/uuid.dart';

import 'agent_messages.dart';

class AgentMessageEvent {
  const AgentMessageEvent({required this.message, this.attachment});

  final AgentMessage message;
  final Uint8List? attachment;

  AgentPayload get payload => message.toJson();
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

abstract class BaseChatClient extends ChangeEmitter {
  final Map<String, ChatThreadSession> _sessionsByPath =
      <String, ChatThreadSession>{};
  final Map<String, Completer<AgentMessage>> _pendingStartRequests =
      <String, Completer<AgentMessage>>{};
  final StreamController<AgentMessageEvent> _events =
      StreamController<AgentMessageEvent>.broadcast();

  Stream<AgentMessageEvent> get events => _events.stream;

  Iterable<ChatThreadSession> get sessions =>
      List<ChatThreadSession>.unmodifiable(_sessionsByPath.values);

  ChatThreadSession openThread(String threadPath) {
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
      unawaited(existing.open());
      return existing;
    }
    final created = ChatThreadSession._(client: this, threadPath: normalized);
    _sessionsByPath[normalized] = created;
    unawaited(created.open());
    notifyListeners();
    return created;
  }

  Future<ChatThreadStartResult> startThread({
    required String message,
    required List<String> attachments,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
    String? realtimeProtocol,
  }) async {
    final messageId = const Uuid().v4();
    final payload = StartThread(
      messageId: messageId,
      content: agentInputContent(text: message, attachments: attachments),
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
    );
    final completer = Completer<AgentMessage>();
    _pendingStartRequests[messageId] = completer;
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
      final session = openThread(threadPath);
      session.addAgentMessage(AgentMessageEvent(message: payload));
      final realtimeConnection = response is ThreadStarted
          ? response.realtimeConnection?.toJson()
          : null;
      return ChatThreadStartResult(
        session: session,
        threadPath: threadPath,
        realtimeConnection: realtimeConnection,
      );
    } finally {
      _pendingStartRequests.remove(messageId);
    }
  }

  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  });

  void handleAgentMessage(AgentMessage message, {Uint8List? attachment}) {
    _events.add(AgentMessageEvent(message: message, attachment: attachment));
    final sourceMessageId = _sourceMessageId(message);
    if ((message is ThreadStarted || message is ThreadStartRejected) &&
        sourceMessageId != null &&
        sourceMessageId.trim().isNotEmpty) {
      final pending = _pendingStartRequests[sourceMessageId.trim()];
      if (pending != null && !pending.isCompleted) {
        pending.complete(message);
      }
    }

    final threadPath = message is AgentThreadMessage
        ? message.threadId.trim()
        : null;
    if (threadPath == null || threadPath.isEmpty) {
      notifyListeners();
      return;
    }
    final session = _sessionsByPath[threadPath];
    session?.addAgentMessage(
      AgentMessageEvent(message: message, attachment: attachment),
    );
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

class MessagingChatClient extends BaseChatClient {
  MessagingChatClient({required this.room, this.agentName}) {
    _roomSubscription = room.listen(_onRoomEvent);
    room.messaging.addListener(_onMessagingChanged);
  }

  final RoomClient room;
  final String? agentName;
  StreamSubscription<RoomEvent>? _roomSubscription;
  final Map<String, Completer<RemoteParticipant>> _pendingParticipantWaits =
      <String, Completer<RemoteParticipant>>{};
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    room.messaging.start();
    await room.messaging.enable();
  }

  Future<void> stop() async {
    _started = false;
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    room.messaging.removeListener(_onMessagingChanged);
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
  }

  RemoteParticipant? agentParticipant() {
    final normalizedAgentName = agentName?.trim();
    for (final participant in room.messaging.remoteParticipants) {
      if (normalizedAgentName != null &&
          normalizedAgentName.isNotEmpty &&
          participant.getAttribute('name') != normalizedAgentName) {
        continue;
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
    bool ignoreOffline = false,
  }) async {
    await start();
    final participant =
        agentParticipant() ??
        await waitForAgentParticipant(waitKey: message.messageId);
    await room.messaging.sendMessage(
      to: participant,
      type: agentRoomMessageType,
      message: message.toJson(),
      attachment: attachment,
      ignoreOffline: ignoreOffline,
    );
  }

  void _onMessagingChanged() {
    final participant = agentParticipant();
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
    if (event is! RoomMessageEvent ||
        event.message.type != agentRoomMessageType) {
      return;
    }
    final participant = agentParticipant();
    if (participant == null ||
        event.message.fromParticipantId != participant.id) {
      return;
    }
    final message = event.message.message;
    final rawPayload = message['type'] is String ? message : message['payload'];
    if (rawPayload is Map<String, dynamic>) {
      handleAgentMessage(
        AgentMessage.fromJson(rawPayload),
        attachment: event.message.attachment,
      );
    } else if (rawPayload is Map) {
      handleAgentMessage(
        AgentMessage.fromJson(Map<String, dynamic>.from(rawPayload)),
        attachment: event.message.attachment,
      );
    }
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
  final Map<String, PendingAgentInput> _pendingInputs =
      <String, PendingAgentInput>{};
  bool _open = false;

  List<AgentMessageEvent> get messages =>
      List<AgentMessageEvent>.unmodifiable(_messages);

  List<PendingAgentInput> get pendingInputs =>
      List<PendingAgentInput>.unmodifiable(_pendingInputs.values);

  bool get isOpen => _open;

  Future<void> open() async {
    if (_open) {
      return;
    }
    _open = true;
    notifyListeners();
    await _client.sendAgentMessage(
      OpenThread(threadId: threadPath),
      ignoreOffline: true,
    );
    await requestModels(ignoreOffline: true);
  }

  Future<void> close() async {
    if (!_open) {
      return;
    }
    _markClosed();
    await _client.sendAgentMessage(
      CloseThread(threadId: threadPath),
      ignoreOffline: true,
    );
  }

  Future<void> requestModels({bool ignoreOffline = false}) {
    return _client.sendAgentMessage(
      ModelsRequest(messageId: const Uuid().v4()),
      ignoreOffline: ignoreOffline,
    );
  }

  Future<void> changeModel({
    required String provider,
    required String model,
    String? voice,
  }) {
    return _client.sendAgentMessage(
      ChangeModel(
        threadId: threadPath,
        messageId: const Uuid().v4(),
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

  Future<String> sendText({
    String? messageId,
    required String text,
    required List<String> attachments,
    bool steer = false,
    String? turnId,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
    String? senderName,
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
          );
    _markPending(
      PendingAgentInput(
        messageId: resolvedMessageId,
        messageType: payload.type,
        threadPath: threadPath,
        payload: payload,
        createdAt: DateTime.now().toUtc(),
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
    _messages.add(event);
    final message = event.message;
    final type = message.type;
    final messageId = message.messageId;
    final sourceMessageId = _sourceMessageId(message);
    if (type == agentTurnStartType || type == agentTurnSteerType) {
      final normalizedMessageId = messageId.trim();
      if (normalizedMessageId.isNotEmpty) {
        _markPending(
          PendingAgentInput(
            messageId: normalizedMessageId,
            messageType: type,
            threadPath: threadPath,
            payload: message,
            createdAt: DateTime.now().toUtc(),
            awaitingAcceptance: true,
            awaitingApplication: true,
          ),
        );
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
    } else if (type == agentTurnStartRejectedType ||
        type == agentTurnSteerRejectedType) {
      _pendingInputs.remove(sourceMessageId);
    } else if (type == agentTurnEndedType || type == agentThreadClearedType) {
      _pendingInputs.clear();
    }
    notifyListeners();
  }

  void _markClosed({bool notify = true}) {
    _open = false;
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
