import 'dart:async';
import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';

Future<void> main(List<String> args) async {
  final baseUrl = _requiredEnv('MESHAGENT_URL');
  final token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYW1lIjoiY29udGFjdC1zdWJtaXNzaW9ucy1leHBvcnRlciIsImdyYW50cyI6W3sibmFtZSI6InJvbGUiLCJzY29wZSI6InVzZXIifSx7Im5hbWUiOiJyb29tIiwic2NvcGUiOiJnZW5lcmFsIn0seyJuYW1lIjoiYXBpIiwic2NvcGUiOnsiZGF0YXNldCI6eyJ0YWJsZXMiOlt7Im5hbWUiOiJjb250YWN0X3N1Ym1pc3Npb25zIn1dLCJsaXN0X3RhYmxlcyI6ZmFsc2V9LCJhZ2VudHMiOnsicmVnaXN0ZXJfYWdlbnQiOmZhbHNlLCJyZWdpc3Rlcl9wdWJsaWNfdG9vbGtpdCI6ZmFsc2UsInJlZ2lzdGVyX3ByaXZhdGVfdG9vbGtpdCI6ZmFsc2UsImNhbGwiOmZhbHNlLCJ1c2VfYWdlbnRzIjpmYWxzZSwiYWxsb3dlZF90b29sa2l0cyI6WyJkYXRhYmFzZSIsImxsbSJdfSwibGxtIjp7fX19XSwidmVyc2lvbiI6IjAuNDEuMCIsImtpZCI6ImRlNjc2MjlhLWYzOWItNGQ4ZS1hODM3LWYzNDBlYmM5ZTc4MSIsInN1YiI6Ijg3YjIxZTUxLTg5MjctNDBjNS1iYTUwLTUzNGM3MDAxOWU1NiJ9.FTvRZc92dmT8NbNInTJ9pTq2DRuzMSv31c0D_3zfOtk';
  final projectId = _requiredEnv('MESHAGENT_PROJECT_ID');
  const roomName = 'josef';
  final agentName = Platform.environment['MESHAGENT_AGENT_NAME'];
  final prompt = args.isEmpty
      ? 'Write a short hello from Meshagent.'
      : args.join(' ');

  final meshagent = Meshagent(baseUrl: baseUrl, token: token);
  final connection = await meshagent.connectRoom(
    projectId: projectId,
    roomName: roomName,
    client: 'meshagent-agents-dart-example',
  );
  final room = RoomClient(
    protocolFactory: WebSocketClientProtocol.createFactory(
      url: connection.roomUrl,
      token: connection.jwt,
    ),
  );

  final chat = MessagingChatClient(room: room, agentName: agentName);
  StreamSubscription<AgentMessageEvent>? subscription;

  try {
    await room.start();
    await room.ready;

    subscription = chat.events.listen((event) {
      final message = event.message;
      if (message is AgentTextContentDelta) {
        stdout.write(message.text);
      } else if (message is AgentToolCallStarted) {
        stdout.writeln('\n[tool started] ${message.toolkit}.${message.tool}');
      } else if (message is AgentToolCallEnded) {
        final toolName = [
          if (message.toolkit != null) message.toolkit,
          if (message.tool != null) message.tool,
        ].join('.');
        stdout.writeln(
          toolName.isEmpty ? '\n[tool ended]' : '\n[tool ended] $toolName',
        );
      } else if (message is TurnEnded) {
        stdout.writeln('\n[turn ended] ${message.turnId}');
      } else if (message is TurnStartRejected) {
        stderr.writeln('Turn rejected: ${message.error.message}');
      } else if (message is ThreadStartRejected) {
        stderr.writeln('Thread rejected: ${message.error.message}');
      }
    });

    await chat.start();
    final result = await chat.startThread(
      message: prompt,
      attachments: const <AgentFileContent>[],
    );
    stdout.writeln('Started thread: ${result.threadPath}');

    await _waitForTurnEnd(chat.events);
  } finally {
    await chat.stop();
    await subscription?.cancel();
    room.dispose();
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('$name is required.');
    exitCode = 64;
    throw StateError('missing $name');
  }
  return value;
}

Future<void> _waitForTurnEnd(Stream<AgentMessageEvent> events) async {
  await events
      .firstWhere((event) => event.message is TurnEnded)
      .timeout(const Duration(minutes: 5));
}
