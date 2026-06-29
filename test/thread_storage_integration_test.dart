import 'dart:io';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _secret = 'test-secret-secure-secret-sample2560binarykey';

String? get _serverSkipReason {
  if (Platform.environment['RUN_MESHAGENT_DATASET_THREAD_STORAGE_TESTS'] !=
      '1') {
    return 'Set RUN_MESHAGENT_DATASET_THREAD_STORAGE_TESTS=1 to run.';
  }
  if ((Platform.environment['MESHAGENT_API_URL'] ?? '').isEmpty) {
    return 'MESHAGENT_API_URL must point at a local roomserver.';
  }
  return null;
}

RoomClient _newRoomClient({
  required String roomName,
  required String participantName,
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
        ..addRoleGrant('agent')
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

void main() {
  group(
    'DatasetThreadStorageRepository integration',
    skip: _serverSkipReason,
    () {
      test(
        'lists, watches, renames, and deletes dataset threads',
        () async {
          final suffix = const Uuid().v4();
          final room = _newRoomClient(
            roomName: 'dart-thread-storage-$suffix',
            participantName: 'tester',
          );
          await room.start();

          final path = 'dataset://dart-agents/$suffix/thread_list';
          final watcher = DatasetThreadStorageRepository(
            room: room,
            path: path,
          );
          final writer = DatasetThreadStorageRepository(room: room, path: path);
          addTearDown(() async {
            await watcher.close();
            await writer.close();
            room.dispose();
          });
          await watcher.open();
          await writer.open();

          final entry = ThreadListEntry(
            path: 'dataset://dart-agents/$suffix/threads/one',
            name: 'First thread',
            createdAt: '2026-01-01T00:00:00.000Z',
            modifiedAt: '2026-01-01T00:00:00.000Z',
          );
          await writer.addOrUpdateThread(entry);
          await _waitUntil(
            () => watcher.entries().any(
              (item) => item.path == entry.path && item.name == 'First thread',
            ),
          );

          await writer.renameThread(entry.path, 'Renamed thread');
          await _waitUntil(
            () => watcher.entries().any(
              (item) =>
                  item.path == entry.path && item.name == 'Renamed thread',
            ),
          );

          await watcher.deleteThread(entry.path);
          await _waitUntil(
            () => watcher.entries().every((item) => item.path != entry.path),
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
  );
}
