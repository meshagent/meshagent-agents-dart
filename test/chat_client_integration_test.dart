import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _secret = 'test-secret-secure-secret-sample2560binarykey';

String? get _serverSkipReason {
  if ((Platform.environment['MESHAGENT_API_URL'] ?? '').isEmpty) {
    return 'MESHAGENT_API_URL must point at a local roomserver.';
  }
  return null;
}

class _ReceivedAgentMessage {
  _ReceivedAgentMessage({required this.payload, this.attachment});

  final AgentPayload payload;
  final Uint8List? attachment;
}

class _ChatRoomHarness {
  _ChatRoomHarness._({
    required this.roomName,
    required this.agentName,
    required this.userRoom,
    required this.agentRoom,
    required this.client,
  });

  final String roomName;
  final String agentName;
  final RoomClient userRoom;
  final RoomClient agentRoom;
  final MessagingChatClient client;
  late final StreamSubscription<RoomEvent> _agentSubscription;
  final List<_ReceivedAgentMessage> _agentMessages = <_ReceivedAgentMessage>[];

  static Future<_ChatRoomHarness> start() async {
    final suffix = const Uuid().v4();
    final roomName = 'dart-chat-sessions-$suffix';
    final agentName = 'agent-$suffix';
    final userRoom = _newRoomClient(
      roomName: roomName,
      participantName: 'user',
    );
    final agentRoom = _newRoomClient(
      roomName: roomName,
      participantName: agentName,
      role: 'agent',
    );

    await agentRoom.start();
    agentRoom.localParticipant!.setAttribute('supports_agent_messages', true);
    agentRoom.localParticipant!.setAttribute(
      'meshagent.chatbot.threading',
      'default-new',
    );
    agentRoom.localParticipant!.setAttribute(
      'meshagent.chatbot.thread-dir',
      'dataset://agents/$agentName/threads',
    );
    agentRoom.messaging.start();
    await agentRoom.messaging.enable();

    await userRoom.start();
    userRoom.messaging.start();
    await userRoom.messaging.enable();

    await _waitUntil(
      () => userRoom.messaging.remoteParticipants.any(
        (participant) =>
            participant.getAttribute('name') == agentName &&
            participant.getAttribute('supports_agent_messages') == true,
      ),
    );
    await _waitUntil(
      () => agentRoom.messaging.remoteParticipants.any(
        (participant) => participant.id == userRoom.localParticipant!.id,
      ),
    );

    final harness = _ChatRoomHarness._(
      roomName: roomName,
      agentName: agentName,
      userRoom: userRoom,
      agentRoom: agentRoom,
      client: MessagingChatClient(room: userRoom, agentName: agentName),
    );
    harness._agentSubscription = agentRoom.listen(harness._onAgentRoomEvent);
    await harness.client.start();
    return harness;
  }

  Future<void> dispose() async {
    await client.stop();
    await _agentSubscription.cancel();
    userRoom.dispose();
    agentRoom.dispose();
  }

  Future<_ReceivedAgentMessage> nextAgentMessageOfType(String type) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final index = _agentMessages.indexWhere(
        (message) => message.payload['type'] == type,
      );
      if (index >= 0) {
        return _agentMessages.removeAt(index);
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('agent message of type $type was not received before timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> sendFromAgent(AgentPayload payload, {Uint8List? attachment}) {
    final user = agentRoom.messaging.remoteParticipants.firstWhere(
      (participant) => participant.id == userRoom.localParticipant!.id,
    );
    return agentRoom.messaging.sendMessage(
      to: user,
      type: agentRoomMessageType,
      message: payload,
      attachment: attachment,
    );
  }

  Future<void> sendFromIntruder(AgentPayload payload) async {
    final intruder = _newRoomClient(
      roomName: roomName,
      participantName: 'intruder-${const Uuid().v4()}',
    );
    addTearDown(intruder.dispose);
    await intruder.start();
    intruder.localParticipant!.setAttribute('supports_agent_messages', true);
    intruder.messaging.start();
    await intruder.messaging.enable();
    await _waitUntil(
      () => intruder.messaging.remoteParticipants.any(
        (participant) => participant.id == userRoom.localParticipant!.id,
      ),
    );
    final user = intruder.messaging.remoteParticipants.firstWhere(
      (participant) => participant.id == userRoom.localParticipant!.id,
    );
    await intruder.messaging.sendMessage(
      to: user,
      type: agentRoomMessageType,
      message: payload,
    );
  }

  void _onAgentRoomEvent(RoomEvent event) {
    if (event is! RoomMessageEvent ||
        event.message.type != agentRoomMessageType ||
        event.message.fromParticipantId != userRoom.localParticipant!.id) {
      return;
    }
    final message = event.message.message;
    final rawPayload = message['type'] is String ? message : message['payload'];
    if (rawPayload is Map<String, dynamic>) {
      _agentMessages.add(
        _ReceivedAgentMessage(
          payload: rawPayload,
          attachment: event.message.attachment,
        ),
      );
    } else if (rawPayload is Map) {
      _agentMessages.add(
        _ReceivedAgentMessage(
          payload: Map<String, dynamic>.from(rawPayload),
          attachment: event.message.attachment,
        ),
      );
    }
  }
}

RoomClient _newRoomClient({
  required String roomName,
  required String participantName,
  String role = 'user',
}) {
  final baseUrl = Platform.environment['MESHAGENT_API_URL']!;
  final url = Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/rooms/$roomName',
  );
  final token =
      ParticipantToken(
          name: participantName,
          projectId:
              Platform.environment['MESHAGENT_PROJECT_ID'] ?? 'testproject',
          apiKeyId:
              Platform.environment['MESHAGENT_KEY_ID'] ??
              'test-key-secure-key-sample2560binarykey',
        )
        ..addRoomGrant(roomName)
        ..addRoleGrant(role)
        ..addApiGrant(ApiScope.agentDefault());

  return RoomClient(
    protocolFactory: WebSocketClientProtocol.createFactory(
      url: url,
      token: token.toJwt(
        token: Platform.environment['MESHAGENT_SECRET'] ?? _secret,
        apiKey: Platform.environment['MESHAGENT_API_KEY'],
      ),
    ),
    reconnectTimeout: Duration.zero,
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

AgentPayload _payload(Map<String, Object?> values) {
  return Map<String, dynamic>.from(values);
}

void main() {
  group('MessagingChatClient integration', skip: _serverSkipReason, () {
    test(
      'opens and routes multiple threads through the selected agent',
      () async {
        final harness = await _ChatRoomHarness.start();
        addTearDown(harness.dispose);

        final first = harness.client.openThread('dataset://threads/first');
        final second = harness.client.openThread('dataset://threads/second');

        final firstOpen = await harness.nextAgentMessageOfType(
          agentThreadOpenType,
        );
        final secondOpen = await harness.nextAgentMessageOfType(
          agentThreadOpenType,
        );
        expect(
          {firstOpen.payload['thread_id'], secondOpen.payload['thread_id']},
          {'dataset://threads/first', 'dataset://threads/second'},
        );
        await harness.sendFromIntruder(
          _payload({
            'type': agentTurnEndedType,
            'thread_id': 'dataset://threads/first',
            'turn_id': 'ignored',
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          first.messages.any(
            (event) =>
                event.message is TurnEnded &&
                (event.message as TurnEnded).turnId == 'ignored',
          ),
          isFalse,
        );

        await harness.sendFromAgent(
          _payload({
            'type': agentTurnEndedType,
            'thread_id': 'dataset://threads/second',
            'turn_id': 'turn-second',
          }),
        );
        await harness.sendFromAgent(
          _payload({
            'type': agentTurnEndedType,
            'thread_id': 'dataset://threads/first',
            'turn_id': 'turn-first',
          }),
        );
        await _waitUntil(
          () =>
              first.messages.any((event) => event.message is TurnEnded) &&
              second.messages.any((event) => event.message is TurnEnded),
        );

        final firstTurnEnded = first.messages
            .map((event) => event.message)
            .whereType<TurnEnded>()
            .single;
        final secondTurnEnded = second.messages
            .map((event) => event.message)
            .whereType<TurnEnded>()
            .single;
        expect(firstTurnEnded.turnId, 'turn-first');
        expect(secondTurnEnded.turnId, 'turn-second');
      },
    );

    test('starts a thread and opens the returned thread path', () async {
      final harness = await _ChatRoomHarness.start();
      addTearDown(harness.dispose);

      final startFuture = harness.client.startThread(
        message: 'hello there',
        attachments: const <AgentFileContent>[
          AgentFileContent(url: 'dataset://files/a.txt'),
        ],
        provider: 'openai',
        model: 'gpt-5.5',
        outputModalities: const ['text'],
        realtimeProtocol: 'webrtc',
      );

      final startMessage = await harness.nextAgentMessageOfType(
        agentThreadStartType,
      );
      expect(startMessage.payload['provider'], 'openai');
      expect(startMessage.payload['model'], 'gpt-5.5');
      expect(startMessage.payload['output_modalities'], ['text']);
      expect(startMessage.payload['realtime_protocol'], 'webrtc');
      expect(
        jsonEncode(startMessage.payload['content']),
        contains('hello there'),
      );
      expect(jsonEncode(startMessage.payload['content']), contains('a.txt'));

      await harness.sendFromAgent(
        _payload({
          'type': agentThreadStartedType,
          'source_message_id': startMessage.payload['message_id'],
          'thread_id': 'dataset://agents/${harness.agentName}/threads/new',
          'realtime_connection': {
            'protocol': 'webrtc',
            'url': 'wss://example.invalid/session',
            'headers': {'authorization': 'Bearer token-1'},
          },
        }),
      );

      final result = await startFuture.timeout(const Duration(seconds: 5));
      expect(
        result.threadPath,
        'dataset://agents/${harness.agentName}/threads/new',
      );
      expect(result.realtimeConnection, {
        'protocol': 'webrtc',
        'url': 'wss://example.invalid/session',
        'headers': {'authorization': 'Bearer token-1'},
      });
      expect(
        result.session.messages.single.payload['type'],
        agentThreadStartType,
      );

      final open = await harness.nextAgentMessageOfType(agentThreadOpenType);
      expect(open.payload['thread_id'], result.threadPath);
    });

    test(
      'ignoreOffline returns when no agent participant is present',
      () async {
        final suffix = const Uuid().v4();
        final room = _newRoomClient(
          roomName: 'dart-chat-offline-$suffix',
          participantName: 'user',
        );
        final client = MessagingChatClient(
          room: room,
          agentName: 'missing-agent-$suffix',
        );
        addTearDown(() async {
          await client.stop().catchError((_) {});
          room.dispose();
        });

        await room.start();
        room.messaging.start();
        await room.messaging.enable();
        await client.start();

        await client
            .sendAgentMessage(WatchThreads(), ignoreOffline: true)
            .timeout(const Duration(milliseconds: 250));
      },
    );

    test(
      'tracks pending text turns through acceptance and application',
      () async {
        final harness = await _ChatRoomHarness.start();
        addTearDown(harness.dispose);

        final session = harness.client.openThread('dataset://threads/pending');
        await harness.nextAgentMessageOfType(agentThreadOpenType);

        await session.sendText(
          messageId: 'message-1',
          text: 'queued prompt',
          attachments: const <AgentFileContent>[],
          provider: 'openai',
          model: 'gpt-5.5',
          voice: 'alloy',
          outputModalities: const ['text'],
          senderName: 'local-user',
        );

        final turnStart = await harness.nextAgentMessageOfType(
          agentTurnStartType,
        );
        expect(turnStart.payload['message_id'], 'message-1');
        expect(turnStart.payload['provider'], 'openai');
        expect(turnStart.payload['model'], 'gpt-5.5');
        expect(turnStart.payload['voice'], 'alloy');
        expect(turnStart.payload['sender_name'], 'local-user');
        expect(session.messages.last.payload['type'], agentTurnStartType);
        expect(session.pendingInputs.single.awaitingAcceptance, isTrue);

        await harness.sendFromAgent(
          _payload({
            'type': agentTurnStartAcceptedType,
            'thread_id': session.threadPath,
            'source_message_id': 'message-1',
          }),
        );
        await _waitUntil(
          () => session.pendingInputs.single.awaitingAcceptance == false,
        );
        expect(session.pendingInputs.single.awaitingApplication, isTrue);

        await harness.sendFromAgent(
          _payload({
            'type': agentTurnStartedType,
            'thread_id': session.threadPath,
            'source_message_id': 'message-1',
            'turn_id': 'turn-1',
          }),
        );
        await _waitUntil(() => session.pendingInputs.isEmpty);

        await harness.sendFromAgent(
          _payload({
            'type': agentTurnEndedType,
            'thread_id': session.threadPath,
            'turn_id': 'turn-1',
          }),
        );
        await _waitUntil(
          () => session.messages.last.payload['type'] == agentTurnEndedType,
        );
      },
    );

    test('sends management, model, interrupt, and realtime messages', () async {
      final harness = await _ChatRoomHarness.start();
      addTearDown(harness.dispose);

      final session = harness.client.openThread('dataset://threads/actions');
      await harness.nextAgentMessageOfType(agentThreadOpenType);

      await session.renameThread(session.threadPath, 'Renamed thread');
      final rename = await harness.nextAgentMessageOfType(
        agentThreadRenameType,
      );
      expect(rename.payload['thread_id'], session.threadPath);
      expect(rename.payload['name'], 'Renamed thread');

      await session.deleteThread(session.threadPath);
      final delete = await harness.nextAgentMessageOfType(
        agentThreadDeleteType,
      );
      expect(delete.payload['thread_id'], session.threadPath);

      await session.changeModel(
        provider: 'openai',
        model: 'gpt-5.5',
        voice: 'verse',
      );
      final modelChange = await harness.nextAgentMessageOfType(
        agentModelChangeType,
      );
      expect(modelChange.payload['provider'], 'openai');
      expect(modelChange.payload['model'], 'gpt-5.5');
      expect(modelChange.payload['voice'], 'verse');

      await session.interruptTurn('turn-1');
      final interrupt = await harness.nextAgentMessageOfType(
        agentTurnInterruptType,
      );
      expect(interrupt.payload['turn_id'], 'turn-1');

      await session.sendRealtimeAudioChunk(
        chunk: Uint8List.fromList([1, 2, 3]),
        format: const {'encoding': 'pcm16', 'sample_rate': 24000},
      );
      final chunk = await harness.nextAgentMessageOfType(
        agentRealtimeAudioChunkType,
      );
      expect(chunk.payload['format'], {
        'type': 'audio/pcm',
        'sample_rate': 24000,
      });
      expect(chunk.attachment, [1, 2, 3]);

      final commitMessageId = await session.commitRealtimeAudio(
        turnId: 'turn-2',
        provider: 'openai',
        model: 'gpt-5.5',
        outputModalities: const ['audio'],
      );
      final commit = await harness.nextAgentMessageOfType(
        agentRealtimeAudioCommitType,
      );
      final turnStart = await harness.nextAgentMessageOfType(
        agentTurnStartType,
      );
      expect(commit.payload['message_id'], commitMessageId);
      expect(commit.payload['turn_id'], 'turn-2');
      expect(turnStart.payload['turn_id'], 'turn-2');
      expect(turnStart.payload['output_modalities'], ['audio']);
    });
  });
}
