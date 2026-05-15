import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/status.dart' as websocket_status;
import 'package:web_socket_channel/web_socket_channel.dart';

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
  AgentConnectionStatus? _connectionStatus;

  Stream<AgentMessageEvent> get events => _events.stream;

  AgentConnectionStatus? get connectionStatus => _connectionStatus;

  Iterable<ChatThreadSession> get sessions =>
      List<ChatThreadSession>.unmodifiable(_sessionsByPath.values);

  Future<void> start() async {}

  Future<void> stop() async {}

  RemoteParticipant? agentParticipant() => null;

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
    String? name,
    String? provider,
    String? model,
    String? voice,
    List<String>? outputModalities,
    String? realtimeProtocol,
    String? senderName,
    bool omitContent = false,
  }) async {
    final messageId = const Uuid().v4();
    final payload = StartThread(
      messageId: messageId,
      content: omitContent
          ? null
          : agentInputContent(text: message, attachments: attachments),
      name: name != null && name.trim().isNotEmpty ? name.trim() : null,
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
      senderName: senderName != null && senderName.trim().isNotEmpty
          ? senderName.trim()
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
    if (message is AgentConnectionStatus) {
      _connectionStatus = message;
      for (final session in _sessionsByPath.values) {
        if (session.isOpen) {
          session.addAgentMessage(
            AgentMessageEvent(message: message, attachment: attachment),
          );
        }
      }
    }
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
    for (final session in _sessionsByPath.values) {
      if (session.isOpen) {
        session.addAgentMessage(AgentMessageEvent(message: event));
      }
    }
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
  String? _agentParticipantId;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    room.messaging.start();
    await room.messaging.enable();
  }

  @override
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
    if (_agentParticipantId != null) {
      _agentParticipantId = null;
      emitConnectionStatus(
        status: 'disconnected',
        message: 'Agent messaging disconnected',
        reason: 'client_stopped',
      );
    }
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
    final participantId = participant?.id;
    if (participantId != _agentParticipantId) {
      if (participantId == null) {
        if (_agentParticipantId != null) {
          emitConnectionStatus(
            status: 'disconnected',
            message: 'Agent messaging disconnected',
            reason: 'participant_disconnected',
          );
        }
      } else {
        emitConnectionStatus(
          status: 'connected',
          message: 'Agent messaging connected',
        );
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
        emitConnectionStatus(
          status: status,
          message: event.message.trim().isNotEmpty
              ? event.message
              : 'Room connection restored',
        );
      } else if (status == 'disconnected' || status == 'reconnecting') {
        emitConnectionStatus(
          status: status,
          message: event.message.trim().isNotEmpty
              ? event.message
              : 'Room connection lost',
        );
      }
      return;
    }
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

class WebSocketChatClient extends BaseChatClient {
  WebSocketChatClient({
    required this.url,
    required this.token,
    this.protocols = const <String>['meshagent-msgpack'],
    this.reconnect = true,
    this.reconnectInitialDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 10),
  });

  final Uri url;
  final String token;
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

  bool get isConnected => _webSocket != null;

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
    bool ignoreOffline = false,
  }) async {
    if (attachment != null) {
      throw UnsupportedError(
        'WebSocketChatClient does not support binary attachments yet.',
      );
    }
    final webSocket = _webSocket;
    if (webSocket == null) {
      if (ignoreOffline) {
        return;
      }
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
      await sendAgentMessage(
        OpenThread(
          threadId: session.threadPath,
          load: true,
          sinceTurn: session.lastCompletedTurnId,
        ),
        ignoreOffline: true,
      );
      await session.requestModels(ignoreOffline: true);
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
      resolved.add('bearer.$normalizedToken');
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
      handleAgentMessage(AgentMessage.fromJson(_stringKeyMap(decoded)));
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
  final Map<String, PendingAgentInput> _pendingInputs =
      <String, PendingAgentInput>{};
  bool _open = false;
  String? _lastCompletedTurnId;

  List<AgentMessageEvent> get messages =>
      List<AgentMessageEvent>.unmodifiable(_messages);

  List<PendingAgentInput> get pendingInputs =>
      List<PendingAgentInput>.unmodifiable(_pendingInputs.values);

  bool get isOpen => _open;

  String? get lastCompletedTurnId => _lastCompletedTurnId;

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
      if (message is TurnEnded && message.turnId.trim().isNotEmpty) {
        _lastCompletedTurnId = message.turnId.trim();
      }
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
