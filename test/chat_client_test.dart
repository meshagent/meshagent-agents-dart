import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

class _FakeChatClient extends BaseChatClient {
  _FakeChatClient({this.participantName});

  final String? participantName;
  final sent = <AgentMessage>[];
  final attachments = <Uint8List?>[];

  @override
  String? localParticipantName() => participantName;

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
  test('turn start serializes typed MCP server config', () {
    final message = TurnStart(
      threadId: 'dataset://threads/example',
      messageId: 'message-1',
      content: const [],
      mcp: const TurnMcpConfig(
        servers: [
          {
            'server_label': 'docs',
            'server_url': 'https://mcp.example.test/mcp',
            'authorization': 'Bearer secret-token',
          },
        ],
      ),
    );

    final json = message.toJson();
    expect(json['toolkits'], isNull);
    expect(json['mcp'], {
      'servers': [
        {
          'server_label': 'docs',
          'server_url': 'https://mcp.example.test/mcp',
          'authorization': 'Bearer secret-token',
        },
      ],
    });

    final parsed = AgentMessage.fromJson(json);
    expect(parsed, isA<TurnStart>());
    final parsedTurn = parsed as TurnStart;
    expect(parsedTurn.mcp?.servers.single['server_label'], 'docs');
    expect(
      parsedTurn.mcp?.servers.single['authorization'],
      'Bearer secret-token',
    );
  });

  test(
    'turn start serializes client toolkit display title separately from callable name',
    () {
      final message = TurnStart(
        threadId: 'dataset://threads/example',
        messageId: 'message-1',
        content: const [],
        clientToolkits: const [
          ClientToolkitDescription(
            name: 'ask_user',
            title: 'Ask User',
            description: 'Ask the user a question',
            inputSchema: {
              'type': 'object',
              'properties': {
                'question': {'type': 'string'},
              },
            },
          ),
        ],
      );

      final json = message.toJson();
      expect(json['client_toolkits'], [
        {
          'name': 'ask_user',
          'title': 'Ask User',
          'description': 'Ask the user a question',
          'input_schema': {
            'type': 'object',
            'properties': {
              'question': {'type': 'string'},
            },
          },
        },
      ]);

      final parsed = AgentMessage.fromJson(json);
      expect(parsed, isA<TurnStart>());
      final parsedTurn = parsed as TurnStart;
      expect(parsedTurn.clientToolkits, hasLength(1));
      expect(parsedTurn.clientToolkits!.single.name, 'ask_user');
      expect(parsedTurn.clientToolkits!.single.title, 'Ask User');
    },
  );

  test(
    'thread sessions track pending inputs through acceptance and application',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');
      await session.sendText(
        text: 'hello',
        attachments: const <AgentFileContent>[],
      );

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
          content: agentInputContent(
            text: 'hello',
            attachments: const <AgentFileContent>[],
          ),
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

  test('thread sessions include client toolkits on non-steer turns', () async {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');
    await session.sendText(
      text: 'use the client tool',
      attachments: const <AgentFileContent>[],
      clientToolkits: const [
        ClientToolkitDescription(
          name: 'ask_user',
          title: 'Ask User',
          description: 'Ask the user',
          inputSchema: {'type': 'object'},
        ),
      ],
    );

    final sent = client.sent.whereType<TurnStart>().single;
    expect(sent.clientToolkits, hasLength(1));
    expect(sent.clientToolkits!.single.name, 'ask_user');
    expect(sent.clientToolkits!.single.title, 'Ask User');
  });

  test(
    'thread sessions decode and respond to client toolkit requests',
    () async {
      final client = _FakeChatClient(participantName: 'jesse.ezell@timu.com');
      final session = client.openThread('dataset://threads/example');
      await session.sendText(
        text: 'use the client tool',
        attachments: const <AgentFileContent>[],
        clientToolkits: const [
          ClientToolkitDescription(
            name: 'ask_user',
            title: 'Ask User',
            description: 'Ask the user a question',
            inputSchema: {
              'type': 'object',
              'additionalProperties': false,
              'required': ['prompt'],
              'properties': {
                'prompt': {
                  'type': 'string',
                  'description': 'Prompt or question for the user.',
                },
              },
            },
          ),
        ],
      );

      final sentTurnStart = client.sent.whereType<TurnStart>().single;
      expect(sentTurnStart.clientToolkits, hasLength(1));
      expect(sentTurnStart.clientToolkits!.single.name, 'ask_user');

      final request = AgentMessage.fromJson({
        'type': agentClientToolCallRequestedType,
        'message_id': 'request-message-1',
        'thread_id': session.threadPath,
        'turn_id': 'turn-1',
        'request_id': 'request-1',
        'provider': 'openai',
        'model': 'gpt-5.5',
        'toolkit': 'client',
        'tool': 'ask_user',
        'arguments': {'prompt': 'What should I answer?'},
      });
      expect(request, isA<AgentClientToolCallRequested>());

      client.handleAgentMessage(request);

      final localRequest = session.messages
          .map((event) => event.message)
          .whereType<AgentClientToolCallRequested>()
          .single;
      expect(localRequest.turnId, 'turn-1');
      expect(localRequest.requestId, 'request-1');
      expect(localRequest.toolkit, 'client');
      expect(localRequest.tool, 'ask_user');
      expect(localRequest.arguments, {'prompt': 'What should I answer?'});

      await session.respondToClientToolCall(
        turnId: localRequest.turnId,
        requestId: localRequest.requestId,
        response: JsonContent(json: {'answer': 'blue'}),
      );

      final response = client.sent
          .whereType<AgentClientToolCallResponse>()
          .single;
      expect(response.threadId, session.threadPath);
      expect(response.turnId, 'turn-1');
      expect(response.requestId, 'request-1');
      expect(response.toJson(), {
        'type': agentClientToolCallResponseType,
        'message_id': response.messageId,
        'thread_id': session.threadPath,
        'turn_id': 'turn-1',
        'request_id': 'request-1',
        'response': {
          'type': 'json',
          'json': {'answer': 'blue'},
        },
      });

      final parsedResponse = AgentMessage.fromJson(response.toJson());
      expect(parsedResponse, isA<AgentClientToolCallResponse>());
      final parsedContent =
          (parsedResponse as AgentClientToolCallResponse).response;
      expect(parsedContent, isA<JsonContent>());
      expect((parsedContent as JsonContent).json, {'answer': 'blue'});
    },
  );

  test(
    'openThread reuses already open sessions without replay by default',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');

      await _waitFor(
        () => client.sent.any((message) => message is ModelsRequest),
      );
      client.sent.clear();
      session.addAgentMessage(
        AgentMessageEvent(
          message: TurnEnded(threadId: session.threadPath, turnId: 'turn-1'),
        ),
      );

      final reopened = client.openThread('dataset://threads/example');
      expect(reopened, same(session));
      await Future<void>.delayed(Duration.zero);
      expect(client.sent.whereType<OpenThread>(), isEmpty);
      expect(client.sent.whereType<ModelsRequest>(), isEmpty);
    },
  );

  test(
    'openThread can explicitly request replay for an already open session',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');

      await _waitFor(
        () => client.sent.any((message) => message is ModelsRequest),
      );
      client.sent.clear();
      session.addAgentMessage(
        AgentMessageEvent(
          message: TurnEnded(threadId: session.threadPath, turnId: 'turn-1'),
        ),
      );

      final reopened = client.openThread(
        'dataset://threads/example',
        reloadIfOpen: true,
      );
      expect(reopened, same(session));
      await _waitFor(
        () => client.sent.whereType<OpenThread>().any(
          (message) =>
              message.threadId == session.threadPath &&
              message.load == true &&
              message.sinceTurn == null,
        ),
      );
      expect(client.sent.whereType<ModelsRequest>(), isNotEmpty);
    },
  );

  test('thread session reports loading until replay completes', () async {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');
    final firstOpen = client.sent.whereType<OpenThread>().single;

    expect(session.isLoading, isTrue);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loading);
    expect(session.loadState.requestMessageId, firstOpen.messageId);
    expect(session.loadState.sinceTurn, isNull);
    client.handleAgentMessage(
      ThreadLoaded(
        threadId: session.threadPath,
        sourceMessageId: firstOpen.messageId,
      ),
    );
    expect(session.isLoading, isFalse);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loaded);
    expect(session.loadState.requestMessageId, firstOpen.messageId);

    client.sent.clear();
    client.openThread('dataset://threads/example', reloadIfOpen: true);
    final secondOpen = client.sent.whereType<OpenThread>().single;
    expect(session.isLoading, isTrue);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loading);
    expect(session.loadState.requestMessageId, secondOpen.messageId);
    client.handleAgentMessage(
      ThreadLoaded(
        threadId: session.threadPath,
        sourceMessageId: secondOpen.messageId,
      ),
    );
    expect(session.isLoading, isFalse);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loaded);
    expect(session.loadState.requestMessageId, secondOpen.messageId);
  });

  test(
    'thread session clears loading when replay completion arrives',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');

      client.sent.clear();
      client.openThread('dataset://threads/example', reloadIfOpen: true);

      expect(session.isLoading, isTrue);
      client.handleAgentMessage(ThreadLoaded(threadId: session.threadPath));
      expect(session.isLoading, isFalse);
      expect(session.loadState.phase, ChatThreadSessionLoadPhase.loaded);
    },
  );

  test('startThread opens the created thread without replay loading', () async {
    final client = _FakeChatClient();
    final startFuture = client.startThread(
      messageId: 'client-message-1',
      message: 'hello',
      attachments: const <AgentFileContent>[],
    );

    client.handleAgentMessage(
      ThreadStarted(
        sourceMessageId: 'client-message-1',
        threadId: 'dataset://threads/created',
      ),
    );

    final result = await startFuture;
    await _waitFor(
      () => client.sent.whereType<OpenThread>().any(
        (message) => message.threadId == result.threadPath,
      ),
    );
    final open = client.sent.whereType<OpenThread>().lastWhere(
      (message) => message.threadId == result.threadPath,
    );
    expect(open.load, isFalse);
    expect(result.session.isLoading, isFalse);

    expect(client.openThread(result.threadPath), same(result.session));
    await Future<void>.delayed(Duration.zero);
    expect(
      client.sent.whereType<OpenThread>().where(
        (message) => message.threadId == result.threadPath,
      ),
      hasLength(1),
    );
  });

  test(
    'startThread reuses caller message id and records the thread start',
    () async {
      final client = _FakeChatClient();
      final startFuture = client.startThread(
        messageId: 'client-message-1',
        message: 'hello',
        attachments: const <AgentFileContent>[],
        clientToolkits: const [
          ClientToolkitDescription(
            name: 'ask_user',
            title: 'Ask User',
            description: 'Ask the user a question',
            inputSchema: {'type': 'object'},
          ),
        ],
      );

      final startThread = client.sent.whereType<StartThread>().single;
      expect(startThread.messageId, 'client-message-1');
      expect(startThread.clientToolkits, hasLength(1));
      expect(startThread.clientToolkits!.single.title, 'Ask User');

      client.handleAgentMessage(
        ThreadStarted(
          sourceMessageId: 'client-message-1',
          threadId: 'dataset://threads/created',
        ),
      );

      final result = await startFuture;
      expect(result.threadPath, 'dataset://threads/created');
      final localThreadStart = result.session.messages
          .map((event) => event.message)
          .whereType<StartThread>()
          .single;
      expect(localThreadStart.messageId, 'client-message-1');
      expect(localThreadStart.content, isNotEmpty);
      expect(localThreadStart.clientToolkits, hasLength(1));
      expect(localThreadStart.clientToolkits!.single.name, 'ask_user');
    },
  );

  test(
    'startThread fills sender name from local participant identity',
    () async {
      final client = _FakeChatClient(participantName: 'jesse.ezell@timu.com');
      final startFuture = client.startThread(
        messageId: 'client-message-1',
        message: 'hello',
        attachments: const <AgentFileContent>[],
      );

      final startThread = client.sent.whereType<StartThread>().single;
      expect(startThread.senderName, 'jesse.ezell@timu.com');

      client.handleAgentMessage(
        ThreadStarted(
          sourceMessageId: 'client-message-1',
          threadId: 'dataset://threads/created',
        ),
      );

      final result = await startFuture;
      final localThreadStart = result.session.messages
          .map((event) => event.message)
          .whereType<StartThread>()
          .single;
      expect(localThreadStart.senderName, 'jesse.ezell@timu.com');
    },
  );

  test(
    'startThread prefers explicit sender name over local participant identity',
    () async {
      final client = _FakeChatClient(participantName: 'local@example.com');
      final startFuture = client.startThread(
        messageId: 'client-message-1',
        message: 'hello',
        attachments: const <AgentFileContent>[],
        senderName: 'explicit@example.com',
      );

      final startThread = client.sent.whereType<StartThread>().single;
      expect(startThread.senderName, 'explicit@example.com');

      client.handleAgentMessage(
        ThreadStarted(
          sourceMessageId: 'client-message-1',
          threadId: 'dataset://threads/created',
        ),
      );

      final result = await startFuture;
      final localThreadStart = result.session.messages
          .map((event) => event.message)
          .whereType<StartThread>()
          .single;
      expect(localThreadStart.senderName, 'explicit@example.com');
    },
  );

  test(
    'startThread returns realtime connection details and opens the returned thread',
    () async {
      final client = _FakeChatClient();
      final startFuture = client.startThread(
        message: 'hello',
        attachments: const <AgentFileContent>[],
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
        attachments: const <AgentFileContent>[],
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
        attachments: const <AgentFileContent>[],
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
    expect(session.isLoading, isTrue);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loading);
    expect(session.loadState.sinceTurn, 'turn-1');
    client.handleAgentMessage(
      ThreadLoaded(
        threadId: session.threadPath,
        sourceMessageId: reopened['message_id'] as String,
      ),
    );
    expect(session.isLoading, isFalse);
    expect(session.loadState.phase, ChatThreadSessionLoadPhase.loaded);
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
