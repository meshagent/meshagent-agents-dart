import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

class _FakeChatClient extends BaseChatClient {
  _FakeChatClient({
    this.participantName,
    this.participantId,
    super.threadCreatedPendingStartMatcher,
    super.deduplicateClientToolRequests,
  });

  final String? participantName;
  final String? participantId;
  final sent = <AgentMessage>[];
  final attachments = <Uint8List?>[];

  @override
  String? localParticipantName() => participantName;

  @override
  String? localParticipantId() => participantId;

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
  }) async {
    sent.add(message);
    attachments.add(attachment);
  }
}

class _RejectingOpenChatClient extends BaseChatClient {
  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
  }) async {
    if (message is OpenThread) {
      throw StateError('agent unavailable');
    }
  }
}

void main() {
  test(
    'chat thread sessions inject typed messages into their thread',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread(
        'dataset://threads/example',
        load: false,
      );
      await Future<void>.delayed(Duration.zero);
      client.sent.clear();
      client.attachments.clear();
      final replay = <AgentMessage>[
        TurnStart(
          threadId: session.threadPath,
          messageId: 'stored-1',
          content: agentInputContent(
            text: 'stored',
            attachments: const <AgentFileContent>[],
          ),
        ),
        ThreadLoaded(threadId: session.threadPath, sourceMessageId: 'open-1'),
      ];

      await session.injectMessages(replay);

      final injected = client.sent.last as InjectMessages;
      expect(injected.type, agentMessagesInjectType);
      expect(injected.threadId, session.threadPath);
      expect(injected.messages, replay);
      final json = injected.toJson();
      expect(json['type'], agentMessagesInjectType);
      expect(json['thread_id'], session.threadPath);
      expect(
        (json['messages'] as List).cast<Map<String, dynamic>>().map(
          (message) => message['thread_id'],
        ),
        everyElement(session.threadPath),
      );
      final parsed = AgentMessage.fromJson(json) as InjectMessages;
      expect(parsed.messages.map((message) => message.type), [
        agentTurnStartType,
        agentThreadLoadedType,
      ]);
      expect(session.messages, isEmpty);
      expect(session.pendingInputs, isEmpty);
    },
  );

  test('agent message events expose a stable created_at timestamp', () {
    final eventTime = DateTime.utc(2026, 5, 28, 16, 11, 48, 538);
    final event = AgentMessageEvent(
      message: TurnStarted(
        threadId: 'dataset://threads/example',
        turnId: 'turn-1',
        sourceMessageId: 'message-1',
      ),
      createdAt: eventTime,
    );

    expect(event.payload['created_at'], '2026-05-28T16:11:48.538Z');
  });

  test('agent message parsing preserves created_at timestamps', () {
    final parsed = AgentMessage.fromJson({
      'type': agentTurnStartedType,
      'message_id': 'event-1',
      'thread_id': 'dataset://threads/example',
      'turn_id': 'turn-1',
      'source_message_id': 'message-1',
      'created_at': '2026-05-28T16:11:48.538Z',
    });

    expect(parsed.toJson()['created_at'], '2026-05-28T16:11:48.538Z');
  });

  test('agent message parsing preserves metadata', () {
    final parsed = AgentMessage.fromJson({
      'type': agentReasoningContentEndedType,
      'message_id': 'event-1',
      'thread_id': 'dataset://threads/example',
      'turn_id': 'turn-1',
      'item_id': 'rs-1',
      'content': '',
      'metadata': {
        'openai': {'encrypted_content': 'opaque'},
      },
    });

    expect(parsed.metadata['openai'], {'encrypted_content': 'opaque'});
    expect(parsed.toJson()['metadata'], {
      'openai': {'encrypted_content': 'opaque'},
    });
  });

  test(
    'thread replay uses event metadata timestamps when payload has no created_at',
    () {
      final client = _FakeChatClient();
      final session = client.openThread(
        'dataset://threads/example',
        load: false,
      );
      final turnStartedAt = DateTime.utc(2026, 5, 28, 16, 11, 48, 538);
      final textStartedAt = DateTime.utc(2026, 5, 28, 16, 11, 52, 425);

      final turn = TurnStart(
        threadId: session.threadPath,
        messageId: 'message-1',
        content: agentInputContent(
          text: 'loaded question',
          attachments: const <AgentFileContent>[],
        ),
      );
      final text = AgentTextContentDelta(
        threadId: session.threadPath,
        turnId: 'turn-1',
        itemId: 'assistant-1',
        text: 'loaded answer',
      );

      expect(
        turn.toJson()['created_at'],
        isNot(turnStartedAt.toIso8601String()),
      );
      expect(
        text.toJson()['created_at'],
        isNot(textStartedAt.toIso8601String()),
      );

      client.handleAgentMessage(turn, createdAt: turnStartedAt);
      client.handleAgentMessage(text, createdAt: textStartedAt);
      client.handleAgentMessage(ThreadLoaded(threadId: session.threadPath));

      expect(session.messages[0].createdAt, turnStartedAt);
      expect(
        session.messages[0].payload['created_at'],
        turnStartedAt.toIso8601String(),
      );
      expect(session.pendingInputs.single.createdAt, turnStartedAt);
      expect(session.messages[1].createdAt, textStartedAt);
      expect(
        session.messages[1].payload['created_at'],
        textStartedAt.toIso8601String(),
      );
    },
  );

  test(
    'replayed tool call events use event metadata timestamps when payload has no created_at',
    () {
      final replayedAt = DateTime.utc(2026, 5, 28, 23, 58, 32, 425);
      final message = AgentToolCallStarted(
        threadId: 'dataset://threads/example',
        turnId: 'turn-1',
        itemId: 'tool-1',
        toolkit: 'client',
        tool: 'ask_user',
        arguments: const <String, Object?>{'prompt': 'connected?'},
      );
      final event = AgentMessageEvent(message: message, createdAt: replayedAt);

      expect(
        message.toJson()['created_at'],
        isNot(replayedAt.toIso8601String()),
      );
      expect(event.createdAt, replayedAt);
      expect(event.payload['created_at'], replayedAt.toIso8601String());
    },
  );

  test('completed replay turns do not restore stale pending input', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');

    client.handleAgentMessage(
      TurnEnded(threadId: session.threadPath, turnId: 'turn-complete'),
    );
    client.handleAgentMessage(
      TurnStart(
        threadId: session.threadPath,
        messageId: 'message-complete',
        turnId: 'turn-complete',
        content: agentInputContent(
          text: 'completed input',
          attachments: const <AgentFileContent>[],
        ),
      ),
    );
    client.handleAgentMessage(
      TurnStart(
        threadId: session.threadPath,
        messageId: 'message-pending',
        turnId: 'turn-pending',
        content: agentInputContent(
          text: 'pending input',
          attachments: const <AgentFileContent>[],
        ),
      ),
    );
    client.handleAgentMessage(ThreadLoaded(threadId: session.threadPath));

    expect(session.pendingInputs.map((pending) => pending.messageId), [
      'message-pending',
    ]);
  });

  test(
    'thread sessions use incoming event time for pending input timestamps',
    () {
      final client = _FakeChatClient();
      final session = client.openThread(
        'dataset://threads/example',
        load: false,
      );
      final createdAt = DateTime.utc(2026, 5, 28, 16, 11, 48, 538);

      session.addAgentMessage(
        AgentMessageEvent(
          message: TurnStart(
            threadId: session.threadPath,
            messageId: 'message-1',
            content: agentInputContent(
              text: 'loaded question',
              attachments: const <AgentFileContent>[],
            ),
          ),
          createdAt: createdAt,
        ),
      );

      expect(session.pendingInputs.single.createdAt, createdAt);
      expect(session.messages.single.createdAt, createdAt);
    },
  );

  test('reloading an open thread clears stale order before replay', () async {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example', load: false);
    session.addAgentMessage(
      AgentMessageEvent(
        message: AgentTextContentDelta(
          threadId: session.threadPath,
          turnId: 'turn-1',
          itemId: 'assistant-1',
          text: 'old assistant first',
        ),
        createdAt: DateTime.utc(2026, 5, 28, 16, 12),
      ),
    );
    session.addAgentMessage(
      AgentMessageEvent(
        message: TurnStart(
          threadId: session.threadPath,
          messageId: 'user-1',
          content: agentInputContent(
            text: 'old user second',
            attachments: const <AgentFileContent>[],
          ),
        ),
        createdAt: DateTime.utc(2026, 5, 28, 16, 11),
      ),
    );

    client.openThread(session.threadPath, reloadIfOpen: true);
    await Future<void>.delayed(Duration.zero);
    expect(session.messages, isEmpty);

    client.handleAgentMessage(
      TurnStart(
        threadId: session.threadPath,
        messageId: 'user-1',
        content: agentInputContent(
          text: 'loaded user',
          attachments: const <AgentFileContent>[],
        ),
      ),
      createdAt: DateTime.utc(2026, 5, 28, 16, 11),
    );
    client.handleAgentMessage(
      AgentTextContentDelta(
        threadId: session.threadPath,
        turnId: 'turn-1',
        itemId: 'assistant-1',
        text: 'loaded assistant',
      ),
      createdAt: DateTime.utc(2026, 5, 28, 16, 12),
    );
    client.handleAgentMessage(ThreadLoaded(threadId: session.threadPath));

    expect(session.messages[0].message, isA<TurnStart>());
    expect(session.messages[0].createdAt, DateTime.utc(2026, 5, 28, 16, 11));
    expect(session.messages[1].message, isA<AgentTextContentDelta>());
    expect(session.messages[1].createdAt, DateTime.utc(2026, 5, 28, 16, 12));
  });

  test('usage updates tolerate missing context window token counts', () {
    final parsed = AgentMessage.fromJson({
      'type': agentUsageUpdatedType,
      'thread_id': 'dataset://threads/test',
      'turn_id': 'turn-1',
      'usage': <String, dynamic>{},
      'context_window': <String, dynamic>{'total_tokens': 128000},
    });

    expect(parsed, isA<AgentUsageUpdated>());
    final usage = parsed as AgentUsageUpdated;
    expect(usage.contextWindow.usedTokens, 0);
    expect(usage.contextWindow.totalTokens, 128000);
  });

  test('thread sessions record failed turn ends for rendering', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');
    final message = TurnEnded(
      threadId: session.threadPath,
      turnId: 'turn-1',
      error: const AgentError(
        code: 'RoomException',
        message: 'Error from OpenAI websocket: unknown parameter',
      ),
    );

    session.addAgentMessage(AgentMessageEvent(message: message));

    expect(session.messages.map((event) => event.message), [message]);
    expect(session.pendingInputs, isEmpty);
  });

  test('routes typed assistant content into the matching open session', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');
    final message = AgentTextContentDelta(
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'item-1',
      phase: 'output',
      text: 'hello from the agent',
    );

    client.handleAgentMessage(message);

    expect(message.messageId, isNot('item-1'));
    expect(session.messages.map((event) => event.message), contains(message));
  });

  test('dedupes and merges text delta messages by message id and item id', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');
    final first = AgentTextContentDelta(
      messageId: 'delta-1',
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'item-1',
      phase: 'output',
      text: 'hello',
    );
    final duplicate = AgentTextContentDelta(
      messageId: 'delta-1',
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'item-1',
      phase: 'output',
      text: ' ignored',
    );
    final second = AgentTextContentDelta(
      messageId: 'delta-2',
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'item-1',
      phase: 'output',
      text: ' world',
    );

    session.addAgentMessage(AgentMessageEvent(message: first));
    final event = session.messages.single;
    var eventChanges = 0;
    event.addEventListener(() {
      eventChanges += 1;
    });
    session.addAgentMessage(AgentMessageEvent(message: duplicate));
    expect(eventChanges, 0);
    session.addAgentMessage(AgentMessageEvent(message: second));
    expect(eventChanges, 1);

    final messages = session.messages.map((event) => event.message).toList();
    expect(messages, hasLength(1));
    expect(messages.single, isA<AgentTextContentDelta>());
    expect((messages.single as AgentTextContentDelta).text, 'hello world');
  });

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

  test(
    'thread sessions clear pending inputs on turn end and thread clear',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread(
        'dataset://threads/example',
        load: false,
      );
      await session.sendText(
        messageId: 'message-1',
        text: 'first prompt',
        attachments: const <AgentFileContent>[],
      );
      expect(session.pendingInputs, hasLength(1));

      client.handleAgentMessage(
        TurnEnded(threadId: session.threadPath, turnId: 'turn-1'),
      );
      expect(session.pendingInputs, isEmpty);

      await session.sendText(
        messageId: 'message-2',
        text: 'second prompt',
        attachments: const <AgentFileContent>[],
      );
      expect(session.pendingInputs, hasLength(1));

      client.handleAgentMessage(
        ThreadCleared(threadId: session.threadPath, sourceMessageId: 'clear-1'),
      );
      expect(session.pendingInputs, isEmpty);
    },
  );

  test(
    'thread sessions append remote accepted input before pending local inputs',
    () async {
      final client = _FakeChatClient();
      final session = client.openThread('dataset://threads/example');
      await session.sendText(
        messageId: 'local-message-1',
        text: 'local pending',
        attachments: const <AgentFileContent>[],
      );

      client.handleAgentMessage(
        TurnStartAccepted(
          threadId: session.threadPath,
          turnId: 'turn-1',
          sourceMessageId: 'remote-message-1',
          content: agentInputContent(
            text: 'hello from someone else',
            attachments: const <AgentFileContent>[],
          ),
          senderName: 'teammate',
        ),
      );

      final messages = session.messages.map((event) => event.message).toList();
      expect(messages[0], isA<TurnStartAccepted>());
      expect((messages[0] as TurnStartAccepted).senderName, 'teammate');
      expect(messages[1], isA<TurnStart>());
    },
  );

  test('thread sessions send selected provider and model', () async {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example');

    await session.sendText(
      text: 'hello',
      attachments: const <AgentFileContent>[],
      backend: 'openai-responses',
      provider: 'openai',
      model: 'gpt-5.5',
    );

    final sent = client.sent.whereType<TurnStart>().last;
    expect(sent.backend, 'openai-responses');
    expect(sent.provider, 'openai');
    expect(sent.model, 'gpt-5.5');
  });

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
        'created_at': response.createdAtUtc.toIso8601String(),
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

  test('client tool requests are routed only to their target participant', () {
    final client = _FakeChatClient(participantId: 'local-participant');
    final session = client.openThread('dataset://threads/example', load: false);

    AgentClientToolCallRequested request({
      required String messageId,
      required String requestId,
      required String targetParticipantId,
    }) {
      return AgentMessage.fromJson({
            'type': agentClientToolCallRequestedType,
            'message_id': messageId,
            'thread_id': session.threadPath,
            'turn_id': 'turn-1',
            'request_id': requestId,
            'provider': 'openai',
            'model': 'gpt-5.5',
            'toolkit': 'client',
            'tool': 'ask_user',
            'arguments': <String, Object?>{},
            'target_participant_id': targetParticipantId,
          })
          as AgentClientToolCallRequested;
    }

    client.handleAgentMessage(
      request(
        messageId: 'request-message-local',
        requestId: 'request-local',
        targetParticipantId: 'local-participant',
      ),
    );
    client.handleAgentMessage(
      request(
        messageId: 'request-message-other',
        requestId: 'request-other',
        targetParticipantId: 'other-participant',
      ),
    );

    final requests = session.messages
        .map((event) => event.message)
        .whereType<AgentClientToolCallRequested>()
        .toList();
    expect(requests, hasLength(1));
    expect(requests.single.requestId, 'request-local');
  });

  test('retains failed and client tool completions for rendering', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example', load: false);
    final failed = AgentToolCallEnded(
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'tool-failed',
      toolkit: 'openai',
      tool: 'shell',
      error: const AgentError(message: 'Command failed'),
    );
    final clientCompletion = AgentToolCallEnded(
      threadId: session.threadPath,
      turnId: 'turn-1',
      itemId: 'tool-client',
      toolkit: 'client',
      tool: 'ask_user',
    );

    client.handleAgentMessage(failed);
    client.handleAgentMessage(clientCompletion);

    expect(
      session.messages.map((event) => event.message),
      containsAll(<AgentMessage>[failed, clientCompletion]),
    );
  });

  test('optional client tool guard keeps successful requests claimed', () {
    final client = _FakeChatClient(deduplicateClientToolRequests: true);
    final session = client.openThread('dataset://threads/example', load: false);

    expect(session.claimClientToolCall('request-1'), isTrue);
    session.finishClientToolCall('request-1', responseSent: true);
    expect(session.claimClientToolCall('request-1'), isFalse);
  });

  test(
    'optional client tool guard releases requests whose response failed',
    () {
      final client = _FakeChatClient(deduplicateClientToolRequests: true);
      final session = client.openThread(
        'dataset://threads/example',
        load: false,
      );

      expect(session.claimClientToolCall('request-1'), isTrue);
      session.finishClientToolCall('request-1', responseSent: false);
      expect(session.claimClientToolCall('request-1'), isTrue);
    },
  );

  test('client tool guard remains disabled by default', () {
    final client = _FakeChatClient();
    final session = client.openThread('dataset://threads/example', load: false);

    expect(session.claimClientToolCall('request-1'), isTrue);
    session.finishClientToolCall('request-1', responseSent: true);
    expect(session.claimClientToolCall('request-1'), isTrue);
  });

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

  test('background open failures mark the load state failed', () async {
    final client = _RejectingOpenChatClient();
    final session = client.openThread('dataset://threads/example');

    await _waitFor(
      () => session.loadState.phase == ChatThreadSessionLoadPhase.failed,
    );
    expect(session.loadState.error, isNotNull);
  });

  test('startThread opens the created thread without replay loading', () async {
    final client = _FakeChatClient();
    final startFuture = client.startThread(
      messageId: 'client-message-1',
      message: 'hello',
      name: 'Created Thread',
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
    expect(result.session.messages, hasLength(1));
    final optimisticMessage = result.session.messages.single.message;
    expect(optimisticMessage, isA<TurnStart>());
    final optimisticTurnStart = optimisticMessage as TurnStart;
    expect(optimisticTurnStart.threadId, result.threadPath);
    expect(optimisticTurnStart.messageId, 'client-message-1');
    expect(optimisticTurnStart.content.single.toJson()['text'], 'hello');

    expect(client.openThread(result.threadPath), same(result.session));
    await Future<void>.delayed(Duration.zero);
    expect(
      client.sent.whereType<OpenThread>().where(
        (message) => message.threadId == result.threadPath,
      ),
      hasLength(1),
    );
  });

  test('startThread preserves a server-created thread event', () async {
    final client = _FakeChatClient();
    final events = <AgentMessageEvent>[];
    final subscription = client.events.listen(events.add);
    addTearDown(subscription.cancel);
    final startFuture = client.startThread(
      messageId: 'client-message-1',
      message: 'hello',
      attachments: const <AgentFileContent>[],
    );

    client.handleAgentMessage(
      ThreadCreated(
        thread: const AgentThreadListEntry(
          path: 'dataset://threads/created',
          name: 'Server Generated Name',
          createdAt: '2026-05-28T23:00:00.000Z',
          modifiedAt: '2026-05-28T23:00:00.000Z',
        ),
      ),
    );
    client.handleAgentMessage(
      ThreadStarted(
        sourceMessageId: 'client-message-1',
        threadId: 'dataset://threads/created',
      ),
    );

    final result = await startFuture;
    expect(result.threadPath, 'dataset://threads/created');
    final createdEvents = events
        .map((event) => event.message)
        .whereType<ThreadCreated>()
        .toList();
    expect(createdEvents, hasLength(1));
    expect(createdEvents.single.thread.name, 'Server Generated Name');
  });

  test(
    'optional ThreadCreated matcher resolves the start and drains queued client tool calls',
    () async {
      final client = _FakeChatClient(
        participantName: 'Dinesh',
        threadCreatedPendingStartMatcher: (message, candidates) {
          expect(candidates.single.senderName, 'Dinesh');
          return candidates.single.messageId;
        },
      );
      final startFuture = client.startThread(
        messageId: 'client-message-1',
        message: 'create a website',
        attachments: const <AgentFileContent>[],
      );

      final toolRequest = AgentMessage.fromJson({
        'type': agentClientToolCallRequestedType,
        'message_id': 'request-message-1',
        'thread_id': 'dataset://threads/created',
        'turn_id': 'turn-1',
        'request_id': 'request-1',
        'provider': 'openai',
        'model': 'gpt-5.5',
        'toolkit': 'client',
        'tool': 'list_webserver_files',
        'arguments': <String, Object?>{},
      });
      client.handleAgentMessage(toolRequest);
      client.handleAgentMessage(
        ThreadCreated(
          thread: const AgentThreadListEntry(
            path: 'dataset://threads/created',
            name: 'Website',
            createdAt: '2026-07-15T03:24:12.000Z',
            modifiedAt: '2026-07-15T03:24:12.000Z',
          ),
        ),
      );

      final result = await startFuture;
      expect(result.threadPath, 'dataset://threads/created');
      expect(
        result.session.messages
            .map((event) => event.message)
            .whereType<AgentClientToolCallRequested>(),
        contains(same(toolRequest)),
      );
    },
  );

  test(
    'keeps new-thread lifecycle messages that arrive before the session opens',
    () async {
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
      client.handleAgentMessage(
        TurnStartAccepted(
          threadId: 'dataset://threads/created',
          turnId: 'turn-1',
          sourceMessageId: 'client-message-1',
          content: agentInputContent(
            text: 'hello',
            attachments: const <AgentFileContent>[],
          ),
        ),
      );

      final result = await startFuture;
      client.handleAgentMessage(
        TurnStarted(
          threadId: 'dataset://threads/created',
          turnId: 'turn-1',
          sourceMessageId: 'client-message-1',
        ),
      );

      expect(result.session.pendingInputs, isEmpty);
    },
  );

  test('broadcasts agent events to independent subscribers', () async {
    final client = _FakeChatClient();
    final first = <AgentMessageEvent>[];
    final second = <AgentMessageEvent>[];
    final firstSubscription = client.events.listen(first.add);
    final secondSubscription = client.events.listen(second.add);
    addTearDown(firstSubscription.cancel);
    addTearDown(secondSubscription.cancel);

    final message = AgentTextContentDelta(
      threadId: 'dataset://threads/example',
      turnId: 'turn-1',
      itemId: 'message-1',
      text: 'hello',
    );
    client.handleAgentMessage(message);

    await _waitFor(() => first.isNotEmpty && second.isNotEmpty);
    expect(first.single.message, same(message));
    expect(second.single.message, same(message));
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
          .whereType<TurnStart>()
          .single;
      expect(localThreadStart.messageId, 'client-message-1');
      expect(localThreadStart.threadId, result.threadPath);
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
          .whereType<TurnStart>()
          .single;
      expect(localThreadStart.threadId, result.threadPath);
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
          .whereType<TurnStart>()
          .single;
      expect(localThreadStart.threadId, result.threadPath);
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
      expect(
        await protocolHeader.future,
        contains('meshagent-agent.participant.jwt'),
      );
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
        socket.add(
          msgpack.serialize(<String, dynamic>{
            'type': agentConnectionStatusType,
            'status': 'connected',
            'participant_id': 'websocket-participant-${sockets.length}',
          }),
        );
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
    await _waitFor(
      () => client.localParticipantId() == 'websocket-participant-1',
    );
    final clientEvents = <AgentConnectionStatus>[];
    final clientEventSubscription = client.events.listen((event) {
      final message = event.message;
      if (message is AgentConnectionStatus) {
        clientEvents.add(message);
      }
    });
    addTearDown(clientEventSubscription.cancel);
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
      () => clientEvents.any((event) => event.status == 'reconnecting'),
    );
    expect(
      session.messages.where((event) => event.message is AgentConnectionStatus),
      isEmpty,
    );
    final secondSocket = await waitForSocket(1);
    await _waitFor(
      () => client.localParticipantId() == 'websocket-participant-2',
    );
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
      () => clientEvents.any((event) => event.status == 'reconnected'),
    );
    expect(
      session.messages.where((event) => event.message is AgentConnectionStatus),
      isEmpty,
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
