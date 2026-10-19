import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

class _PendingTokenProvider implements AccessTokenProvider {
  final token = Completer<String>();
  @override
  Future<String> getToken() => token.future;
}

void main() {
  for (final denied in [false, true]) {
    test(
      'anonymous agent refreshes credentials on reconnect with the same cookie (denied: $denied)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final cookies = <String?>[];
        final protocols = <String?>[];
        final sockets = <WebSocket>[];
        final connectedTwice = Completer<void>();
        var issued = 0;
        final serverTask = () async {
          await for (final request in server) {
            if (request.uri.path == '/.well-known/meshagent/authorize') {
              cookies.add(request.headers.value('cookie'));
              if (denied && issued == 1) {
                issued++;
                request.response.statusCode = 403;
                request.response.write('Anonymous access was revoked');
                await request.response.close();
                continue;
              }
              request.response.headers.add(
                'set-cookie',
                '__meshagent_anonymous=visitor-one; HttpOnly; Path=/',
              );
              request.response.write(
                jsonEncode({
                  'jwt': 'token-${++issued}',
                  'connect_path': '/.well-known/meshagent/agent/connect',
                  'expires_in': 0.01,
                }),
              );
              await request.response.close();
            } else {
              expect(request.uri.path, '/.well-known/meshagent/agent/connect');
              protocols.add(request.headers.value('sec-websocket-protocol'));
              final socket = await WebSocketTransformer.upgrade(
                request,
                protocolSelector: (_) => 'meshagent-msgpack',
              );
              sockets.add(socket);
              if (sockets.length == 1) {
                Timer(const Duration(milliseconds: 30), () => socket.close());
              } else if (!connectedTwice.isCompleted) {
                connectedTwice.complete();
              }
            }
          }
        }();
        final client = WebSocketChatClient.withAnonymous(
          authorizationUrl: Uri.parse(
            'http://127.0.0.1:${server.port}/.well-known/meshagent/authorize',
          ),
          reconnectInitialDelay: const Duration(milliseconds: 1),
        );
        final deniedEvent = Completer<AgentConnectionStatus>();
        final subscription = client.events.listen((event) {
          final message = event.message;
          if (message is AgentConnectionStatus &&
              (message.reason?.contains('Anonymous access was revoked') ??
                  false) &&
              !deniedEvent.isCompleted) {
            deniedEvent.complete(message);
          }
        });
        try {
          await client.start();
          if (denied) {
            final event = await deniedEvent.future.timeout(
              const Duration(seconds: 5),
            );
            expect(event.status, 'disconnected');
            expect(event.reason, contains('403'));
            expect(protocols, hasLength(1));
            expect(issued, 2);
            return;
          }
          await connectedTwice.future.timeout(const Duration(seconds: 5));
          expect(protocols[0], contains('meshagent-agent.token-1'));
          expect(protocols[1], contains('meshagent-agent.token-2'));
          expect(cookies, [null, '__meshagent_anonymous=visitor-one']);
        } finally {
          await subscription.cancel();
          await client.stop();
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
          await serverTask;
        }
      },
    );
  }

  test('stopping during authorization does not create a socket', () async {
    final provider = _PendingTokenProvider();
    final client = WebSocketChatClient(
      url: Uri.parse('ws://127.0.0.1:1'),
      tokenProvider: provider,
    );
    final starting = client.start();
    await client.stop();
    provider.token.complete('late');
    await starting;
    expect(client.isConnected, isFalse);
  });

  test('authorization failure never falls back to an old token', () async {
    final provider = _PendingTokenProvider();
    final client = WebSocketChatClient(
      url: Uri.parse('ws://127.0.0.1:1'),
      token: 'old',
      tokenProvider: provider,
    );
    final starting = client.start();
    provider.token.completeError(StateError('revoked'));
    await expectLater(starting, throwsStateError);
    await client.stop();
  });
}
