import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

class _FakeChatClient extends BaseChatClient {
  final sent = <AgentMessage>[];
  final attachments = <Uint8List?>[];

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  }) async {
    sent.add(message);
    attachments.add(attachment);
  }
}

void main() {
  test(
    'thread sessions track pending inputs through acceptance and application',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');
      await session.sendText(text: 'hello', attachments: const []);

      final turnStart = client.sent.lastWhere(
        (message) => message.type == agentTurnStartType,
      );
      final messageId = turnStart.messageId;
      expect(session.pendingInputs, hasLength(1));
      expect(session.pendingInputs.single.awaitingAcceptance, isTrue);

      client.handleAgentMessage(
        TurnStartAccepted(
          threadId: session.threadPath,
          sourceMessageId: messageId,
          content: agentInputContent(text: 'hello', attachments: const []),
        ),
      );

      expect(session.pendingInputs.single.awaitingAcceptance, isFalse);
      expect(session.pendingInputs.single.awaitingApplication, isTrue);

      client.handleAgentMessage(
        TurnStarted(
          threadId: session.threadPath,
          turnId: 'turn-1',
          sourceMessageId: messageId,
        ),
      );

      expect(session.pendingInputs, isEmpty);
    },
  );

  test(
    'startThread returns realtime connection details and opens the returned thread',
    () async {
      final client = _FakeChatClient();
      final startFuture = client.startThread(
        message: 'hello',
        attachments: const [],
        provider: 'openai',
        model: 'gpt-realtime',
        realtimeProtocol: 'webrtc',
      );

      final sourceMessageId = client.sent.single.messageId;
      client.handleAgentMessage(
        ThreadStarted(
          sourceMessageId: sourceMessageId,
          threadId: 'dataset://threads/created',
          realtimeConnection: const AgentRealtimeConnectionInfo(
            protocol: 'webrtc',
            url: 'wss://example.invalid',
          ),
        ),
      );

      final result = await startFuture;
      expect(result.threadPath, 'dataset://threads/created');
      expect(result.session.threadPath, 'dataset://threads/created');
      expect(result.session.isOpen, isTrue);
      expect(result.realtimeConnection, {
        'protocol': 'webrtc',
        'url': 'wss://example.invalid',
        'headers': <String, String>{},
      });
    },
  );

  test(
    'websocket chat client uses msgpack and bearer subprotocol auth',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final protocolHeader = Completer<String?>();
      final received = Completer<Map<String, dynamic>>();

      unawaited(() async {
        final request = await server.first;
        protocolHeader.complete(
          request.headers.value('sec-websocket-protocol'),
        );
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('meshagent-msgpack')
              ? 'meshagent-msgpack'
              : '',
        );
        await for (final data in socket) {
          final decoded = msgpack.deserialize(data as Uint8List);
          final payload = Map<String, dynamic>.from(decoded as Map);
          if (!received.isCompleted) {
            received.complete(payload);
          }
          socket.add(
            msgpack.serialize(
              ThreadStarted(
                sourceMessageId: payload['message_id'] as String,
                threadId: 'dataset://threads/websocket-created',
              ).toJson(),
            ),
          );
        }
      }());

      final client = WebSocketChatClient(
        url: Uri.parse('ws://127.0.0.1:${server.port}/messages'),
        token: 'participant.jwt',
      );
      addTearDown(() async {
        await client.stop();
        await server.close(force: true);
      });

      await client.start();
      final result = await client.startThread(
        message: 'hello websocket',
        attachments: const [],
      );

      expect(result.threadPath, 'dataset://threads/websocket-created');
      expect(await protocolHeader.future, contains('meshagent-msgpack'));
      expect(await protocolHeader.future, contains('bearer.participant.jwt'));
      expect(await received.future, containsPair('type', agentThreadStartType));
    },
  );

  test(
    'websocket chat client keeps receiving after large image generation events',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final largeBase64 = 'a' * (1024 * 1024);

      unawaited(() async {
        final request = await server.first;
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('meshagent-msgpack')
              ? 'meshagent-msgpack'
              : '',
        );
        await for (final data in socket) {
          final decoded = msgpack.deserialize(data as Uint8List);
          final payload = Map<String, dynamic>.from(decoded as Map);
          final sourceMessageId = payload['message_id'] as String;
          const threadId = 'dataset://threads/image-created';
          const turnId = 'turn-image';
          const itemId = 'ig-image';
          for (final message in <AgentMessage>[
            ThreadStarted(sourceMessageId: sourceMessageId, threadId: threadId),
            TurnStarted(
              threadId: threadId,
              turnId: turnId,
              sourceMessageId: sourceMessageId,
            ),
            AgentImageGenerationStarted(
              threadId: threadId,
              turnId: turnId,
              itemId: itemId,
              provider: 'openai',
              model: 'gpt-5.5',
            ),
            AgentThreadStatus(
              threadId: threadId,
              turnId: turnId,
              status: 'Generating image',
            ),
            AgentImageGenerationPartial(
              threadId: threadId,
              turnId: turnId,
              itemId: itemId,
              provider: 'openai',
              model: 'gpt-5.5',
              partialIndex: 0,
              image: AgentGeneratedImage(
                uri: 'data:image/png;base64,$largeBase64',
                mimeType: 'image/png',
                width: 1024,
                height: 1024,
                status: 'partial',
              ),
            ),
            AgentImageGenerationCompleted(
              threadId: threadId,
              turnId: turnId,
              itemId: itemId,
              provider: 'openai',
              model: 'gpt-5.5',
              images: [
                AgentGeneratedImage(
                  uri: 'data:image/png;base64,$largeBase64',
                  mimeType: 'image/png',
                  width: 1024,
                  height: 1024,
                  status: 'completed',
                ),
              ],
            ),
            AgentThreadStatus(threadId: threadId, turnId: turnId),
            TurnEnded(threadId: threadId, turnId: turnId),
          ]) {
            socket.add(msgpack.serialize(message.toJson()));
          }
        }
      }());

      final client = WebSocketChatClient(
        url: Uri.parse('ws://127.0.0.1:${server.port}/messages'),
        token: 'participant.jwt',
      );
      addTearDown(() async {
        await client.stop();
        await server.close(force: true);
      });

      await client.start();
      final result = await client.startThread(
        message: 'make an image',
        attachments: const [],
      );
      final session = result.session;

      await _waitFor(
        () => session.messages.any(
          (event) => event.message.type == agentTurnEndedType,
        ),
      );

      final types = session.messages
          .map((event) => event.message.type)
          .toList(growable: false);
      expect(types, contains(agentImageGenerationStartedType));
      expect(types, contains(agentImageGenerationPartialType));
      expect(types, contains(agentImageGenerationCompletedType));
      expect(types, contains(agentThreadStatusType));
      expect(types, contains(agentTurnEndedType));
    },
  );

  test('websocket chat client emits status events and reconnects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final socketEvents = StreamController<WebSocket>.broadcast();

    unawaited(() async {
      await for (final request in server) {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('meshagent-msgpack')
              ? 'meshagent-msgpack'
              : '',
        );
        sockets.add(socket);
        socketEvents.add(socket);
      }
    }());

    Future<WebSocket> waitForSocket(int index) async {
      while (sockets.length <= index) {
        await socketEvents.stream.first;
      }
      return sockets[index];
    }

    Future<Map<String, dynamic>> waitForPayload(
      WebSocket socket,
      String type,
    ) async {
      await for (final data in socket) {
        final decoded = msgpack.deserialize(data as Uint8List);
        final payload = Map<String, dynamic>.from(decoded as Map);
        if (payload['type'] == type) {
          return payload;
        }
      }
      fail('socket closed before receiving $type');
    }

    final client = WebSocketChatClient(
      url: Uri.parse('ws://127.0.0.1:${server.port}/messages'),
      token: 'participant.jwt',
      reconnectInitialDelay: const Duration(milliseconds: 20),
      reconnectMaxDelay: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      await client.stop();
      for (final socket in sockets) {
        await socket.close();
      }
      await socketEvents.close();
      await server.close(force: true);
    });

    await client.start();
    final session = client.openThread('dataset://threads/reconnect');
    final firstSocket = await waitForSocket(0);
    await waitForPayload(firstSocket, agentThreadOpenType);
    session.addAgentMessage(
      AgentMessageEvent(
        message: TurnEnded(threadId: session.threadPath, turnId: 'turn-1'),
      ),
    );
    await firstSocket.close(WebSocketStatus.goingAway, 'test reconnect');

    await _waitFor(
      () => session.messages.any(
        (event) =>
            event.message is AgentConnectionStatus &&
            (event.message as AgentConnectionStatus).status == 'reconnecting',
      ),
    );
    final secondSocket = await waitForSocket(1);
    final reopened = await waitForPayload(secondSocket, agentThreadOpenType);

    expect(reopened, containsPair('thread_id', session.threadPath));
    expect(reopened, containsPair('load', true));
    expect(reopened, containsPair('since_turn', 'turn-1'));
    await _waitFor(
      () => session.messages.any(
        (event) =>
            event.message is AgentConnectionStatus &&
            (event.message as AgentConnectionStatus).status == 'reconnected',
      ),
    );
  });

  test('thread loaded messages parse and serialize replay metadata', () {
    final loaded = AgentMessage.fromJson({
      'type': agentThreadLoadedType,
      'thread_id': 'dataset://threads/test',
      'source_message_id': 'open-1',
      'since_turn': 'turn-1',
    });

    expect(loaded, isA<ThreadLoaded>());
    final typed = loaded as ThreadLoaded;
    expect(typed.threadId, 'dataset://threads/test');
    expect(typed.sourceMessageId, 'open-1');
    expect(typed.sinceTurn, 'turn-1');
    expect(typed.toJson(), containsPair('since_turn', 'turn-1'));
  });
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met within ${timeout.inMilliseconds}ms');
}
