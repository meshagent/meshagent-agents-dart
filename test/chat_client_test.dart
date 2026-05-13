import 'dart:typed_data';

import 'package:meshagent_agents/meshagent_agents.dart';
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
}
