import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _secret = 'test-secret-secure-secret-sample2560binarykey';

String? get _liveSkipReason {
  final missing = <String>[
    if ((Platform.environment['MESHAGENT_API_URL'] ?? '').isEmpty)
      'MESHAGENT_API_URL',
    if ((Platform.environment['MESHAGENT_LIVE_AGENT_ROOM'] ?? '').isEmpty)
      'MESHAGENT_LIVE_AGENT_ROOM',
    if ((Platform.environment['MESHAGENT_LIVE_AGENT_NAME'] ?? '').isEmpty)
      'MESHAGENT_LIVE_AGENT_NAME',
  ];
  if (missing.isEmpty) {
    return null;
  }
  return 'Live assistant tests require ${missing.join(', ')}.';
}

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
    final observedMessages = <AgentMessage>[];

    setUpAll(() async {
      final roomName = Platform.environment['MESHAGENT_LIVE_AGENT_ROOM']!;
      final agentName = Platform.environment['MESHAGENT_LIVE_AGENT_NAME']!;
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
              message:
                  'Reply with a short sentence that includes LIVE_CHAT_START_OK.',
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
                event.message is StartThread &&
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

        await _waitForObservedMessage(
          observedMessages,
          0,
          (message) =>
              message is TurnStarted &&
              message.threadId == createdThreadPath! &&
              message.sourceMessageId == messageId &&
              message.turnId == accepted.turnId,
          'thread start turn started',
        );

        await _waitForSessionMessage(
          session!,
          (message) =>
              message is AgentTextContentDelta &&
              message.threadId == createdThreadPath! &&
              message.turnId == accepted.turnId,
          'thread start assistant text',
        );

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
      'loads the created thread and replays messages on the same session',
      () async {
        final beforeObservedCount = observedMessages.length;
        final opened = chatClient.openThread(
          createdThreadPath!,
          load: true,
          reloadIfOpen: true,
        );
        expect(opened, same(session));

        await _waitForObservedMessage(
          observedMessages,
          beforeObservedCount,
          (message) =>
              message is ThreadLoaded && message.threadId == createdThreadPath!,
          'thread replay completion',
        );
        expect(session!.loadState.phase, ChatThreadSessionLoadPhase.loaded);
        _expectSessionThreadMessagesAreScoped(session!);
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

        final returnedMessageId = await session!.sendText(
          messageId: messageId,
          text:
              'Acknowledge that this turn included one text attachment. Keep the reply short.',
          attachments: <AgentFileContent>[AgentFileContent(url: attachmentUrl)],
          senderName: 'live-dart-test',
        );

        expect(returnedMessageId, messageId);
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

        await _waitForObservedMessage(
          observedMessages,
          0,
          (message) =>
              message is TurnStarted &&
              message.threadId == createdThreadPath! &&
              message.sourceMessageId == messageId &&
              message.turnId == accepted.turnId,
          'attachment turn started',
        );

        await _waitForSessionMessage(
          session!,
          (message) =>
              message is AgentTextContentDelta &&
              message.threadId == createdThreadPath! &&
              message.turnId == accepted.turnId,
          'attachment turn agent response',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'queues steering and interrupts an active turn',
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
        final steerMessageId = await session!.sendText(
          messageId: _liveId('steer'),
          text:
              'Steer this answer: include the exact phrase LIVE_CHAT_STEER_OK before finishing.',
          attachments: const <AgentFileContent>[],
          steer: true,
          turnId: started.turnId,
          senderName: 'live-dart-test',
        );

        await _waitForObservedMessage(
          observedMessages,
          beforeSteerObservedCount,
          (message) =>
              ((message is TurnSteerAccepted &&
                  message.threadId == createdThreadPath! &&
                  message.sourceMessageId == steerMessageId) ||
              (message is TurnSteerRejected &&
                  message.threadId == createdThreadPath! &&
                  message.sourceMessageId == steerMessageId)),
          'steer acknowledgement',
        );

        final beforeInterruptObservedCount = observedMessages.length;
        await session!.interruptTurn(started.turnId);

        await _waitForObservedMessage(
          observedMessages,
          beforeInterruptObservedCount,
          (message) =>
              (message is TurnInterruptAccepted &&
                  message.turnId == started.turnId) ||
              (message is TurnInterrupted &&
                  message.turnId == started.turnId) ||
              (message is TurnEnded && message.turnId == started.turnId),
          'interrupt acknowledgement',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'surfaces client tool requests as typed session messages',
      () async {
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
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
