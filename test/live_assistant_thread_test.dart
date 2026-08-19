import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _secret = 'test-secret-secure-secret-sample2560binarykey';
const _startPrompt =
    'Reply with a short sentence that includes LIVE_CHAT_START_OK.';
const _startResponseMarker = 'LIVE_CHAT_START_OK';

String? get _liveSkipReason {
  if (Platform.environment['RUN_MESHAGENT_LIVE_ASSISTANT_TESTS'] != '1') {
    return 'Set RUN_MESHAGENT_LIVE_ASSISTANT_TESTS=1 with a live assistant agent to run.';
  }
  final missing = <String>[
    if ((Platform.environment['MESHAGENT_API_URL'] ?? '').isEmpty)
      'MESHAGENT_API_URL',
  ];
  if (missing.isEmpty) {
    return null;
  }
  return 'Live assistant tests require ${missing.join(', ')}.';
}

String get _liveRoomName =>
    (Platform.environment['MESHAGENT_LIVE_AGENT_ROOM'] ?? '').trim().isNotEmpty
    ? Platform.environment['MESHAGENT_LIVE_AGENT_ROOM']!.trim()
    : 'jesse';

String get _liveAgentName =>
    (Platform.environment['MESHAGENT_LIVE_AGENT_NAME'] ?? '').trim().isNotEmpty
    ? Platform.environment['MESHAGENT_LIVE_AGENT_NAME']!.trim()
    : 'assistant';

RoomClient _newRoomClient({
  required String roomName,
  required String participantName,
}) {
  final baseUrl = Platform.environment['MESHAGENT_API_URL']!;
  final url = Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/rooms/$roomName',
  );
  final envToken = Platform.environment['MESHAGENT_TOKEN'];
  final token = envToken != null && envToken.trim().isNotEmpty
      ? envToken.trim()
      : (ParticipantToken(
                name: participantName,
                projectId:
                    Platform.environment['MESHAGENT_PROJECT_ID'] ??
                    'testproject',
                apiKeyId:
                    Platform.environment['MESHAGENT_KEY_ID'] ??
                    'test-key-secure-key-sample2560binarykey',
              )
              ..addRoomGrant(roomName)
              ..addRoleGrant('user')
              ..addApiGrant(ApiScope.agentDefault()))
            .toJwt(
              token: Platform.environment['MESHAGENT_SECRET'] ?? _secret,
              apiKey: Platform.environment['MESHAGENT_API_KEY'],
            );

  return RoomClient(
    protocolFactory: WebSocketClientProtocol.createFactory(
      url: url,
      token: token,
    ),
    reconnectTimeout: Duration.zero,
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<AgentMessage> _waitForObservedMessage(
  List<AgentMessage> messages,
  int afterCount,
  bool Function(AgentMessage message) predicate,
  String label, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final skipped = messages.skip(afterCount);
    for (final message in skipped) {
      if (predicate(message)) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('$label was not observed. Observed events: ${_summarize(messages)}');
}

Future<AgentMessage> _waitForSessionMessage(
  ChatThreadSession session,
  bool Function(AgentMessage message) predicate,
  String label, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final event in session.messages) {
      if (predicate(event.message)) {
        return event.message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(
    '$label was not observed. Observed session events: '
    '${_summarize(session.messages.map((event) => event.message).toList())}',
  );
}

Future<String> _waitForTurnText(
  ChatThreadSession session,
  String turnId,
  String marker,
  String label, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final text = _turnText(session, turnId);
    if (text.contains(marker)) {
      return text;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(
    '$label was not observed. Assistant text for turn $turnId: '
    '${_turnText(session, turnId)}. Observed session events: '
    '${_summarize(session.messages.map((event) => event.message).toList())}',
  );
}

String _liveId(String prefix) {
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}';
}

String _summarize(List<AgentMessage> messages) {
  return messages
      .map((message) {
        final parts = <String>[message.type];
        if (message is AgentThreadMessage) {
          parts.add('thread=${message.threadId}');
        }
        final sourceMessageId = _sourceMessageId(message);
        if (sourceMessageId != null && sourceMessageId.isNotEmpty) {
          parts.add('source=$sourceMessageId');
        }
        final turnId = _turnId(message);
        if (turnId != null && turnId.isNotEmpty) {
          parts.add('turn=$turnId');
        }
        return parts.join(' ');
      })
      .join(', ');
}

String _turnText(ChatThreadSession session, String turnId) {
  return session.messages
      .map((event) => event.message)
      .whereType<AgentTextContentDelta>()
      .where((message) => message.turnId == turnId)
      .map((message) => message.text)
      .join();
}

String _inputTextForTurn(ChatThreadSession session, String turnId) {
  final content = <AgentInputContent>[];
  for (final event in session.messages) {
    final message = event.message;
    if (message is TurnStart && message.turnId == turnId) {
      content.addAll(message.content);
    } else if (message is TurnStartAccepted && message.turnId == turnId) {
      content.addAll(message.content);
    }
  }
  return content
      .whereType<AgentTextContent>()
      .map((entry) => entry.text)
      .join('\n');
}

String? _sourceMessageId(AgentMessage message) {
  if (message is ThreadStarted) {
    return message.sourceMessageId;
  }
  if (message is ThreadLoaded) {
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

String? _turnId(AgentMessage message) {
  if (message is TurnStartAccepted) {
    return message.turnId;
  }
  if (message is TurnInterruptAccepted) {
    return message.turnId;
  }
  if (message is TurnSteerRejected) {
    return message.turnId;
  }
  if (message is TurnEnded) {
    return message.turnId;
  }
  if (message is AgentTextContentStarted) {
    return message.turnId;
  }
  if (message is AgentToolCallArgumentsDelta) {
    return message.turnId;
  }
  if (message is AgentClientToolCallRequested) {
    return message.turnId;
  }
  return null;
}

void _expectSessionThreadMessagesAreScoped(ChatThreadSession session) {
  for (final event in session.messages) {
    final message = event.message;
    if (message is AgentThreadMessage) {
      expect(message.threadId, session.threadPath);
    }
  }
}

void main() {
  group('live assistant agent-message threads', skip: _liveSkipReason, () {
    late RoomClient room;
    late MessagingChatClient chatClient;
    late AgentThreadStorageRepository threadList;
    StreamSubscription<AgentMessageEvent>? eventSubscription;
    ChatThreadSession? session;
    String? createdThreadPath;
    String? initialTurnId;
    final observedMessages = <AgentMessage>[];

    setUpAll(() async {
      final roomName = _liveRoomName;
      final agentName = _liveAgentName;
      room = _newRoomClient(
        roomName: roomName,
        participantName: 'dart-live-thread-${const Uuid().v4()}',
      );
      chatClient = MessagingChatClient(room: room, agentName: agentName);
      threadList = AgentThreadStorageRepository(chatClient: chatClient);
      eventSubscription = chatClient.events.listen(
        (event) => observedMessages.add(event.message),
      );

      await room.start();
      room.messaging.start();
      await room.messaging.enable();
      await _waitUntil(
        () => room.messaging.remoteParticipants.any(
          (participant) =>
              participant.getAttribute('name') == agentName &&
              participant.getAttribute('supports_agent_messages') == true,
        ),
        timeout: const Duration(seconds: 30),
        description: 'assistant participant',
      );
      final agentParticipant = chatClient.agentParticipant();
      expect(agentParticipant, isNotNull);
      expect(
        agentParticipant!.getAttribute('meshagent.chatbot.threading'),
        'default-new',
        reason: 'the process agent must advertise the multi-thread chat mode',
      );
      final advertisedThreadDir = agentParticipant.getAttribute(
        'meshagent.chatbot.thread-dir',
      );
      expect(advertisedThreadDir, startsWith('dataset://'));
      expect(
        agentParticipant.getAttribute('meshagent.chatbot.thread-list'),
        '$advertisedThreadDir/index',
      );
      await chatClient.start();
      await threadList.open().timeout(const Duration(seconds: 15));
    });

    tearDownAll(() async {
      await eventSubscription?.cancel();
      await threadList.close();
      await session?.close().catchError((_) {});
      await chatClient.stop().catchError((_) {});
      room.dispose();
    });

    test(
      'starts a thread and routes typed assistant messages into the session',
      () async {
        final messageId = _liveId('thread-start');
        final result = await chatClient
            .startThread(
              messageId: messageId,
              name: 'Live Dart chat test ${DateTime.now().toIso8601String()}',
              message: _startPrompt,
              attachments: const <AgentFileContent>[],
              outputModalities: const ['text'],
              senderName: 'live-dart-test',
            )
            .timeout(const Duration(seconds: 45));
        session = result.session;
        createdThreadPath = result.threadPath;

        expect(createdThreadPath!, isNotEmpty);
        expect(
          chatClient.sessions.map((entry) => entry.threadPath),
          contains(createdThreadPath!),
        );
        expect(
          session!.messages.any(
            (event) =>
                event.message is TurnStart &&
                (event.message as TurnStart).threadId == createdThreadPath! &&
                event.message.messageId == messageId,
          ),
          isTrue,
        );

        final accepted =
            await _waitForObservedMessage(
                  observedMessages,
                  0,
                  (message) =>
                      message is TurnStartAccepted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == messageId,
                  'thread start turn acceptance',
                )
                as TurnStartAccepted;

        final started =
            await _waitForObservedMessage(
                  observedMessages,
                  0,
                  (message) =>
                      message is TurnStarted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == messageId &&
                      message.turnId == accepted.turnId,
                  'thread start turn started',
                )
                as TurnStarted;
        initialTurnId = started.turnId;

        final responseText = await _waitForTurnText(
          session!,
          started.turnId,
          _startResponseMarker,
          'thread start assistant response marker',
        );
        expect(responseText, contains(_startResponseMarker));

        final ended =
            await _waitForObservedMessage(
                  observedMessages,
                  0,
                  (message) =>
                      message is TurnEnded &&
                      message.threadId == createdThreadPath! &&
                      message.turnId == started.turnId,
                  'thread start turn ended',
                )
                as TurnEnded;
        expect(ended.error, isNull);
        expect(session!.lastCompletedTurnId, started.turnId);
        expect(session!.pendingInputs, isEmpty);

        final threadPath = createdThreadPath!;
        await _waitForObservedMessage(
          observedMessages,
          0,
          (message) =>
              message is ThreadCreated && message.thread.path == threadPath,
          'thread created event',
          timeout: const Duration(seconds: 5),
        );
        await _waitUntil(
          () => threadList.entries().any((entry) => entry.path == threadPath),
          timeout: const Duration(seconds: 20),
          description: 'thread list entry for $threadPath',
        );
        final entry = threadList.entries().singleWhere(
          (entry) => entry.path == threadPath,
        );
        expect(entry.createdAt.trim(), isNotEmpty);
        expect(entry.modifiedAt.trim(), isNotEmpty);

        _expectSessionThreadMessagesAreScoped(session!);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'loads the completed thread into a cold client and replays its content',
      () async {
        final previousSession = session!;

        await eventSubscription?.cancel();
        eventSubscription = null;
        await threadList.close();
        await previousSession.close();
        await chatClient.stop();
        room.dispose();

        observedMessages.clear();
        room = _newRoomClient(
          roomName: _liveRoomName,
          participantName: 'dart-cold-thread-${const Uuid().v4()}',
        );
        chatClient = MessagingChatClient(room: room, agentName: _liveAgentName);
        threadList = AgentThreadStorageRepository(chatClient: chatClient);
        eventSubscription = chatClient.events.listen(
          (event) => observedMessages.add(event.message),
        );

        await room.start();
        room.messaging.start();
        await room.messaging.enable();
        await _waitUntil(
          () => room.messaging.remoteParticipants.any(
            (participant) =>
                participant.getAttribute('name') == _liveAgentName &&
                participant.getAttribute('supports_agent_messages') == true,
          ),
          timeout: const Duration(seconds: 30),
          description: 'assistant participant for cold client',
        );
        await chatClient.start();
        await threadList.open().timeout(const Duration(seconds: 15));
        await _waitUntil(
          () => threadList.entries().any(
            (entry) => entry.path == createdThreadPath!,
          ),
          timeout: const Duration(seconds: 20),
          description: 'cold thread list entry for $createdThreadPath',
        );

        expect(chatClient.sessions, isEmpty);
        final coldSession = chatClient.openThread(createdThreadPath!);
        session = coldSession;
        expect(coldSession, isNot(same(previousSession)));

        await _waitForObservedMessage(
          observedMessages,
          0,
          (message) =>
              message is ThreadLoaded && message.threadId == createdThreadPath!,
          'cold thread replay completion',
        );
        expect(coldSession.loadState.phase, ChatThreadSessionLoadPhase.loaded);
        expect(
          _inputTextForTurn(coldSession, initialTurnId!),
          contains(_startPrompt),
          reason: 'the cold replay must contain the original user input',
        );
        expect(
          _turnText(coldSession, initialTurnId!),
          contains(_startResponseMarker),
          reason: 'the cold replay must contain the prior assistant response',
        );
        expect(
          coldSession.messages.any(
            (event) =>
                event.message is TurnEnded &&
                (event.message as TurnEnded).turnId == initialTurnId,
          ),
          isTrue,
          reason: 'the cold replay must include the completed turn boundary',
        );
        expect(coldSession.lastCompletedTurnId, initialTurnId);
        expect(coldSession.pendingInputs, isEmpty);
        _expectSessionThreadMessagesAreScoped(coldSession);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'sends attachments and tracks pending input until acknowledgement',
      () async {
        final beforeObservedCount = observedMessages.length;
        final messageId = _liveId('attachment-turn');
        final attachmentUrl =
            'data:text/plain;base64,${base64Encode(utf8.encode('meshagent live chat attachment'))}';

        final sendFuture = session!.sendText(
          messageId: messageId,
          text:
              'Acknowledge that this turn included one text attachment. '
              'Include the exact phrase LIVE_CHAT_ATTACHMENT_OK and keep the reply short.',
          attachments: <AgentFileContent>[AgentFileContent(url: attachmentUrl)],
          senderName: 'live-dart-test',
        );

        final localTurn = session!.messages
            .map((event) => event.message)
            .whereType<TurnStart>()
            .where((message) => message.messageId == messageId)
            .single;
        expect(
          localTurn.content.map((entry) => entry.toJson()),
          contains(
            allOf(
              containsPair('type', 'file'),
              containsPair('url', attachmentUrl),
            ),
          ),
        );
        expect(
          session!.pendingInputs.map((pending) => pending.messageId),
          contains(messageId),
        );
        final returnedMessageId = await sendFuture;
        expect(returnedMessageId, messageId);

        final accepted =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeObservedCount,
                  (message) =>
                      message is TurnStartAccepted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == messageId,
                  'attachment turn acceptance',
                )
                as TurnStartAccepted;

        final started =
            await _waitForObservedMessage(
                  observedMessages,
                  0,
                  (message) =>
                      message is TurnStarted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == messageId &&
                      message.turnId == accepted.turnId,
                  'attachment turn started',
                )
                as TurnStarted;

        await _waitForTurnText(
          session!,
          started.turnId,
          'LIVE_CHAT_ATTACHMENT_OK',
          'attachment turn agent response marker',
        );
        final ended =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeObservedCount,
                  (message) =>
                      message is TurnEnded &&
                      message.threadId == createdThreadPath! &&
                      message.turnId == started.turnId,
                  'attachment turn ended',
                )
                as TurnEnded;
        expect(ended.error, isNull);
        expect(session!.pendingInputs, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'applies steering, completes the response, and clears pending state',
      () async {
        final beforeObservedCount = observedMessages.length;
        final startMessageId = _liveId('long-turn');
        await session!.sendText(
          messageId: startMessageId,
          text:
              'Start a deliberately long answer with at least twenty numbered points. Do not stop after the first few points.',
          attachments: const <AgentFileContent>[],
          senderName: 'live-dart-test',
        );

        final accepted =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeObservedCount,
                  (message) =>
                      message is TurnStartAccepted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == startMessageId,
                  'long turn acceptance',
                )
                as TurnStartAccepted;
        final started =
            await _waitForObservedMessage(
                  observedMessages,
                  0,
                  (message) =>
                      message is TurnStarted &&
                      message.threadId == createdThreadPath! &&
                      message.sourceMessageId == startMessageId &&
                      message.turnId == accepted.turnId,
                  'long turn start',
                )
                as TurnStarted;
        expect(started.turnId, isNotEmpty);

        final beforeSteerObservedCount = observedMessages.length;
        final requestedSteerMessageId = _liveId('steer');
        final steerSendFuture = session!.sendText(
          messageId: requestedSteerMessageId,
          text:
              'Steer this answer: include the exact phrase LIVE_CHAT_STEER_OK before finishing.',
          attachments: const <AgentFileContent>[],
          steer: true,
          turnId: started.turnId,
          senderName: 'live-dart-test',
        );
        expect(
          session!.pendingInputs.map((pending) => pending.messageId),
          contains(requestedSteerMessageId),
        );
        final steerMessageId = await steerSendFuture;
        expect(steerMessageId, requestedSteerMessageId);

        final steerAccepted =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeSteerObservedCount,
                  (message) =>
                      message is TurnSteerAccepted &&
                      message.threadId == createdThreadPath! &&
                      message.turnId == started.turnId &&
                      message.sourceMessageId == steerMessageId,
                  'steer acceptance',
                )
                as TurnSteerAccepted;
        expect(steerAccepted.turnId, started.turnId);

        final steered =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeSteerObservedCount,
                  (message) =>
                      message is TurnSteered &&
                      message.threadId == createdThreadPath! &&
                      message.turnId == started.turnId &&
                      message.sourceMessageId == steerMessageId,
                  'steer application',
                )
                as TurnSteered;
        expect(steered.sourceMessageId, steerMessageId);
        await _waitUntil(
          () => !session!.pendingInputs.any(
            (pending) => pending.messageId == steerMessageId,
          ),
          timeout: const Duration(seconds: 5),
          description: 'steer pending input cleanup',
        );
        expect(
          observedMessages.whereType<TurnSteerRejected>().where(
            (message) => message.sourceMessageId == steerMessageId,
          ),
          isEmpty,
        );

        await _waitForTurnText(
          session!,
          started.turnId,
          'LIVE_CHAT_STEER_OK',
          'steered turn response marker',
        );
        final ended =
            await _waitForObservedMessage(
                  observedMessages,
                  beforeObservedCount,
                  (message) =>
                      message is TurnEnded &&
                      message.threadId == createdThreadPath! &&
                      message.turnId == started.turnId,
                  'steered turn ended',
                )
                as TurnEnded;
        expect(ended.error, isNull);
        expect(
          observedMessages.whereType<TurnSteerRejected>().where(
            (message) => message.sourceMessageId == steerMessageId,
          ),
          isEmpty,
        );
        expect(session!.pendingInputs, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('interrupts an active turn and clears its session state', () async {
      final beforeObservedCount = observedMessages.length;
      final startMessageId = _liveId('interrupt-turn');
      await session!.sendText(
        messageId: startMessageId,
        text: 'Write two hundred numbered points. Continue until interrupted.',
        attachments: const <AgentFileContent>[],
        senderName: 'live-dart-test',
      );

      final accepted =
          await _waitForObservedMessage(
                observedMessages,
                beforeObservedCount,
                (message) =>
                    message is TurnStartAccepted &&
                    message.threadId == createdThreadPath! &&
                    message.sourceMessageId == startMessageId,
                'interrupt turn acceptance',
              )
              as TurnStartAccepted;
      final started =
          await _waitForObservedMessage(
                observedMessages,
                beforeObservedCount,
                (message) =>
                    message is TurnStarted &&
                    message.threadId == createdThreadPath! &&
                    message.sourceMessageId == startMessageId &&
                    message.turnId == accepted.turnId,
                'interrupt turn started',
              )
              as TurnStarted;

      final beforeInterruptObservedCount = observedMessages.length;
      await session!.interruptTurn(started.turnId);
      await _waitForObservedMessage(
        observedMessages,
        beforeInterruptObservedCount,
        (message) =>
            message is TurnInterruptAccepted &&
            message.type == agentTurnInterruptAcceptedType &&
            message.threadId == createdThreadPath! &&
            message.turnId == started.turnId,
        'interrupt acceptance',
      );
      await _waitForObservedMessage(
        observedMessages,
        beforeInterruptObservedCount,
        (message) =>
            message is TurnInterrupted &&
            message.threadId == createdThreadPath! &&
            message.turnId == started.turnId,
        'turn interrupted',
      );
      final ended =
          await _waitForObservedMessage(
                observedMessages,
                beforeInterruptObservedCount,
                (message) =>
                    message is TurnEnded &&
                    message.threadId == createdThreadPath! &&
                    message.turnId == started.turnId,
                'interrupted turn ended',
              )
              as TurnEnded;
      expect(
        ended.error?.code,
        anyOf(isNull, 'cancelled'),
        reason:
            'Codex reports an interrupted turn as completed while the default LLM backend reports it as cancelled',
      );
      expect(session!.lastCompletedTurnId, started.turnId);
      expect(session!.pendingInputs, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('surfaces client tool requests as typed session messages', () async {
      final beforeObservedCount = observedMessages.length;
      final messageId = _liveId('client-tool');
      await session!.sendText(
        messageId: messageId,
        text:
            'Use the ask_user client tool to ask whether the live Dart chat test is connected.',
        attachments: const <AgentFileContent>[],
        senderName: 'live-dart-test',
        clientToolkits: const <ClientToolkitDescription>[
          ClientToolkitDescription(
            name: 'ask_user',
            title: 'Ask User',
            description: 'Ask the user a short question.',
            inputSchema: <String, dynamic>{
              'type': 'object',
              'additionalProperties': false,
              'required': <String>['prompt'],
              'properties': <String, dynamic>{
                'prompt': <String, dynamic>{'type': 'string'},
              },
            },
          ),
        ],
      );

      final accepted =
          await _waitForObservedMessage(
                observedMessages,
                beforeObservedCount,
                (message) =>
                    message is TurnStartAccepted &&
                    message.threadId == createdThreadPath! &&
                    message.sourceMessageId == messageId,
                'client tool turn acceptance',
              )
              as TurnStartAccepted;

      await _waitForObservedMessage(
        observedMessages,
        0,
        (message) =>
            message is TurnStarted &&
            message.threadId == createdThreadPath! &&
            message.sourceMessageId == messageId &&
            message.turnId == accepted.turnId,
        'client tool turn started',
      );

      await _waitForSessionMessage(
        session!,
        (message) =>
            message is AgentThreadMessage &&
            message.threadId == createdThreadPath! &&
            ((message is AgentClientToolCallRequested &&
                    message.turnId == accepted.turnId) ||
                (message is AgentToolCallArgumentsDelta &&
                    message.turnId == accepted.turnId) ||
                (message is AgentTextContentDelta &&
                    message.turnId == accepted.turnId)),
        'client tool capable turn',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
