import 'dart:typed_data';

import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

class _FakeChatClient extends BaseChatClient {
  final sent = <AgentPayload>[];
  final attachments = <Uint8List?>[];

  @override
  Future<void> sendAgentMessage(
    AgentPayload payload, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  }) async {
    sent.add(payload);
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
        (payload) => payload['type'] == agentTurnStartType,
      );
      final messageId = turnStart['message_id'] as String;
      expect(session.pendingInputs, hasLength(1));
      expect(session.pendingInputs.single.awaitingAcceptance, isTrue);

      client.handleAgentMessage({
        'type': agentTurnStartAcceptedType,
        'thread_id': session.threadPath,
        'source_message_id': messageId,
        'content': agentInputContent(text: 'hello', attachments: const []),
      });

      expect(session.pendingInputs.single.awaitingAcceptance, isFalse);
      expect(session.pendingInputs.single.awaitingApplication, isTrue);

      client.handleAgentMessage({
        'type': agentTurnStartedType,
        'thread_id': session.threadPath,
        'source_message_id': messageId,
      });

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

      final sourceMessageId = client.sent.single['message_id'] as String;
      client.handleAgentMessage({
        'type': agentThreadStartedType,
        'source_message_id': sourceMessageId,
        'thread_id': 'dataset://threads/created',
        'realtime_connection': {'type': 'webrtc', 'token': 'token'},
      });

      final result = await startFuture;
      expect(result.threadPath, 'dataset://threads/created');
      expect(result.session.threadPath, 'dataset://threads/created');
      expect(result.session.isOpen, isTrue);
      expect(result.realtimeConnection, {'type': 'webrtc', 'token': 'token'});
    },
  );
}
