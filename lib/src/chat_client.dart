import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:uuid/uuid.dart';

const String agentRoomMessageType = 'agent-message';
const String agentTurnStartType = 'meshagent.agent.turn.start';
const String agentTurnSteerType = 'meshagent.agent.turn.steer';
const String agentTurnInterruptType = 'meshagent.agent.turn.interrupt';
const String agentRealtimeAudioChunkType =
    'meshagent.agent.realtime_audio.chunk';
const String agentRealtimeAudioCommitType =
    'meshagent.agent.realtime_audio.commit';
const String agentThreadStartType = 'meshagent.agent.thread.start';
const String agentThreadStartedType = 'meshagent.agent.thread.started';
const String agentThreadStartRejectedType =
    'meshagent.agent.thread.start.rejected';
const String agentThreadOpenType = 'meshagent.agent.thread.open';
const String agentThreadCloseType = 'meshagent.agent.thread.close';
const String agentThreadDeleteType = 'meshagent.agent.thread.delete';
const String agentThreadRenameType = 'meshagent.agent.thread.rename';
const String agentTurnStartAcceptedType = 'meshagent.agent.turn.start.accepted';
const String agentTurnStartRejectedType = 'meshagent.agent.turn.start.rejected';
const String agentTurnSteerAcceptedType = 'meshagent.agent.turn.steer.accepted';
const String agentTurnSteerRejectedType = 'meshagent.agent.turn.steer.rejected';
const String agentTurnInterruptAcceptedType =
    'meshagent.agent.turn.interrupt.accepted';
const String agentTurnInterruptedType = 'meshagent.agent.turn.interrupted';
const String agentTurnStartedType = 'meshagent.agent.turn.started';
const String agentTurnSteeredType = 'meshagent.agent.turn.steered';
const String agentTurnEndedType = 'meshagent.agent.turn.ended';
const String agentThreadClearedType = 'meshagent.agent.thread.cleared';
const String agentModelsRequestType = 'meshagent.agent.models.request';
const String agentModelsResponseType = 'meshagent.agent.models.response';
const String agentModelChangeType = 'meshagent.agent.model.change';
const String agentModelChangedType = 'meshagent.agent.model.changed';

typedef AgentPayload = Map<String, dynamic>;

class AgentMessageEvent {
  const AgentMessageEvent({required this.payload, this.attachment});

  final AgentPayload payload;
  final Uint8List? attachment;
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
  final AgentPayload payload;
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
  final Map<String, Completer<AgentPayload>> _pendingStartRequests =
      <String, Completer<AgentPayload>>{};
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
    final payload = <String, dynamic>{
      'type': agentThreadStartType,
      'message_id': messageId,
      'content': agentInputContent(text: message, attachments: attachments),
      if (provider != null && provider.trim().isNotEmpty)
        'provider': provider.trim(),
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (voice != null && voice.trim().isNotEmpty) 'voice': voice.trim(),
      if (outputModalities != null && outputModalities.isNotEmpty)
        'output_modalities': outputModalities,
      if (realtimeProtocol != null && realtimeProtocol.trim().isNotEmpty)
        'realtime_protocol': realtimeProtocol.trim(),
    };
    final completer = Completer<AgentPayload>();
    _pendingStartRequests[messageId] = completer;
    try {
      await sendAgentMessage(payload);
      final response = await completer.future;
      final threadPath = response['thread_id']?.toString().trim();
      if (threadPath == null || threadPath.isEmpty) {
        throw StateError(
          'Agent did not return a thread_id for the new thread.',
        );
      }
      final session = openThread(threadPath);
      session.addAgentMessage(AgentMessageEvent(payload: payload));
      final realtimeConnection = response['realtime_connection'];
      return ChatThreadStartResult(
        session: session,
        threadPath: threadPath,
        realtimeConnection: realtimeConnection is Map
            ? Map<String, dynamic>.from(realtimeConnection)
            : null,
      );
    } finally {
      _pendingStartRequests.remove(messageId);
    }
  }

  Future<void> sendAgentMessage(
    AgentPayload payload, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  });

  void handleAgentMessage(AgentPayload payload, {Uint8List? attachment}) {
    _events.add(AgentMessageEvent(payload: payload, attachment: attachment));
    final type = payload['type'];
    final sourceMessageId = payload['source_message_id']?.toString();
    if ((type == agentThreadStartedType ||
            type == agentThreadStartRejectedType) &&
        sourceMessageId != null &&
        sourceMessageId.trim().isNotEmpty) {
      final pending = _pendingStartRequests[sourceMessageId.trim()];
      if (pending != null && !pending.isCompleted) {
        pending.complete(payload);
      }
    }

    final threadPath = payload['thread_id']?.toString().trim();
    if (threadPath == null || threadPath.isEmpty) {
      notifyListeners();
      return;
    }
    final session = _sessionsByPath[threadPath];
    session?.addAgentMessage(
      AgentMessageEvent(payload: payload, attachment: attachment),
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
    AgentPayload payload, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  }) async {
    await start();
    final participant =
        agentParticipant() ??
        await waitForAgentParticipant(
          waitKey: payload['message_id']?.toString(),
        );
    await room.messaging.sendMessage(
      to: participant,
      type: agentRoomMessageType,
      message: payload,
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
      handleAgentMessage(rawPayload, attachment: event.message.attachment);
    } else if (rawPayload is Map) {
      handleAgentMessage(
        Map<String, dynamic>.from(rawPayload),
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
    await _client.sendAgentMessage({
      'type': agentThreadOpenType,
      'thread_id': threadPath,
    }, ignoreOffline: true);
    await requestModels(ignoreOffline: true);
  }

  Future<void> close() async {
    if (!_open) {
      return;
    }
    _markClosed();
    await _client.sendAgentMessage({
      'type': agentThreadCloseType,
      'thread_id': threadPath,
    }, ignoreOffline: true);
  }

  Future<void> requestModels({bool ignoreOffline = false}) {
    return _client.sendAgentMessage({
      'type': agentModelsRequestType,
      'message_id': const Uuid().v4(),
    }, ignoreOffline: ignoreOffline);
  }

  Future<void> changeModel({
    required String provider,
    required String model,
    String? voice,
  }) {
    return _client.sendAgentMessage({
      'type': agentModelChangeType,
      'thread_id': threadPath,
      'message_id': const Uuid().v4(),
      'provider': provider,
      'model': model,
      if (voice != null && voice.trim().isNotEmpty) 'voice': voice.trim(),
    });
  }

  Future<void> interruptTurn(String turnId) {
    return _client.sendAgentMessage({
      'type': agentTurnInterruptType,
      'thread_id': threadPath,
      'turn_id': turnId,
    });
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
    final payload = <String, dynamic>{
      'type': steer ? agentTurnSteerType : agentTurnStartType,
      'thread_id': threadPath,
      'message_id': resolvedMessageId,
      'content': agentInputContent(text: text, attachments: attachments),
      if (senderName != null && senderName.trim().isNotEmpty)
        'sender_name': senderName.trim(),
      if (steer && turnId != null && turnId.trim().isNotEmpty)
        'turn_id': turnId.trim(),
      if (!steer && provider != null && provider.trim().isNotEmpty)
        'provider': provider.trim(),
      if (!steer && model != null && model.trim().isNotEmpty)
        'model': model.trim(),
      if (!steer && voice != null && voice.trim().isNotEmpty)
        'voice': voice.trim(),
      if (!steer && outputModalities != null && outputModalities.isNotEmpty)
        'output_modalities': outputModalities,
    };
    _markPending(
      PendingAgentInput(
        messageId: resolvedMessageId,
        messageType: steer ? agentTurnSteerType : agentTurnStartType,
        threadPath: threadPath,
        payload: payload,
        createdAt: DateTime.now().toUtc(),
        awaitingAcceptance: true,
        awaitingApplication: true,
      ),
    );
    addAgentMessage(AgentMessageEvent(payload: payload));
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
    await _client.sendAgentMessage({
      'type': agentRealtimeAudioChunkType,
      'thread_id': threadPath,
      'message_id': const Uuid().v4(),
      'format': format,
    }, attachment: chunk);
  }

  Future<String> commitRealtimeAudio({
    required String turnId,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
  }) async {
    final messageId = const Uuid().v4();
    await _client.sendAgentMessage({
      'type': agentRealtimeAudioCommitType,
      'thread_id': threadPath,
      'message_id': messageId,
      'turn_id': turnId,
    });
    await _client.sendAgentMessage({
      'type': agentTurnStartType,
      'thread_id': threadPath,
      'message_id': const Uuid().v4(),
      'turn_id': turnId,
      if (provider != null && provider.trim().isNotEmpty)
        'provider': provider.trim(),
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (voice != null && voice.trim().isNotEmpty) 'voice': voice.trim(),
      if (outputModalities != null && outputModalities.isNotEmpty)
        'output_modalities': outputModalities,
    });
    return messageId;
  }

  Future<void> deleteThread(String threadPath) {
    return _client.sendAgentMessage({
      'type': agentThreadDeleteType,
      'thread_id': threadPath,
    });
  }

  Future<void> renameThread(String threadPath, String name) {
    return _client.sendAgentMessage({
      'type': agentThreadRenameType,
      'thread_id': threadPath,
      'name': name,
    });
  }

  void addAgentMessage(AgentMessageEvent event) {
    _messages.add(event);
    final payload = event.payload;
    final type = payload['type'];
    final messageId = payload['message_id']?.toString();
    final sourceMessageId = payload['source_message_id']?.toString();
    if (type == agentTurnStartType || type == agentTurnSteerType) {
      final normalizedMessageId = messageId?.trim();
      if (normalizedMessageId != null && normalizedMessageId.isNotEmpty) {
        _markPending(
          PendingAgentInput(
            messageId: normalizedMessageId,
            messageType: type.toString(),
            threadPath: threadPath,
            payload: payload,
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

List<Map<String, dynamic>> agentInputContent({
  required String text,
  required List<String> attachments,
}) {
  final content = <Map<String, dynamic>>[];
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    content.add({'type': 'text', 'text': text});
  }
  for (final attachment in attachments) {
    final normalized = attachment.trim();
    if (normalized.isNotEmpty) {
      content.add({'type': 'file', 'url': normalized});
    }
  }
  return content;
}
