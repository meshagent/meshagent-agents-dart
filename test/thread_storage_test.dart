import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

class _FakeChatClient extends BaseChatClient {
  final sent = <AgentMessage>[];

  @override
  Future<void> sendAgentMessage(
    AgentMessage message, {
    Uint8List? attachment,
    bool ignoreOffline = false,
  }) async {
    sent.add(message);
  }

  void receive(AgentMessage message) {
    handleAgentMessage(message);
  }
}

void main() {
  group('DatasetThreadListRef', () {
    test('parses dataset thread list paths', () {
      final ref = DatasetThreadListRef.parse('dataset://agents/test/threads');

      expect(ref.namespace, ['agents', 'test']);
      expect(ref.table, 'threads');
    });

    test('rejects non-dataset paths', () {
      expect(
        () => DatasetThreadListRef.parse('.threads/test/index.threadl'),
        throwsArgumentError,
      );
    });
  });

  group('ThreadListEntry', () {
    test('normalizes rows with default display names', () {
      final entry = ThreadListEntry.fromDatasetRow({
        'path': 'dataset://threads/hello-world',
        'name': '',
        'created_at': '2026-01-01T00:00:00Z',
        'modified_at': '2026-01-02T00:00:00Z',
      });

      expect(entry?.path, 'dataset://threads/hello-world');
      expect(entry?.name, 'Hello World');
      expect(entry?.createdAt, '2026-01-01T00:00:00Z');
      expect(entry?.modifiedAt, '2026-01-02T00:00:00Z');
    });
  });

  group('AgentThreadStorageRepository', () {
    test('lists threads from agent messages', () async {
      final client = _FakeChatClient();
      final repository = AgentThreadStorageRepository(chatClient: client);
      final open = repository.open();
      final request = client.sent.single as ListThreads;

      client.receive(
        ThreadsListed(
          sourceMessageId: request.messageId,
          total: 1,
          offset: 0,
          limit: 200,
          threads: const [
            AgentThreadListEntry(
              path: 'dataset://threads/one',
              name: 'One',
              createdAt: '2026-01-01T00:00:00Z',
              modifiedAt: '2026-01-02T00:00:00Z',
            ),
          ],
        ),
      );

      await open;
      expect(repository.entries().map((entry) => entry.name), ['One']);
      await repository.close();
    });

    test('renames and deletes through agent messages', () async {
      final client = _FakeChatClient();
      final repository = AgentThreadStorageRepository(chatClient: client);
      final open = repository.open();
      final request = client.sent.single as ListThreads;
      client.receive(
        ThreadsListed(
          sourceMessageId: request.messageId,
          total: 1,
          offset: 0,
          limit: 200,
          threads: const [
            AgentThreadListEntry(
              path: 'dataset://threads/one',
              name: 'One',
              createdAt: '2026-01-01T00:00:00Z',
              modifiedAt: '2026-01-02T00:00:00Z',
            ),
          ],
        ),
      );
      await open;

      await repository.renameThread('dataset://threads/one', 'Renamed');
      expect(client.sent.whereType<RenameThread>().single.name, 'Renamed');
      expect(repository.entries().single.name, 'Renamed');

      await repository.deleteThread('dataset://threads/one');
      expect(client.sent.whereType<DeleteThread>(), hasLength(1));
      expect(repository.entries(), isEmpty);
      await repository.close();
    });

    test('updates entries from thread lifecycle events', () async {
      final client = _FakeChatClient();
      final repository = AgentThreadStorageRepository(chatClient: client);
      final changes = <List<String>>[];
      repository.addListener(() {
        changes.add(repository.entries().map((entry) => entry.name).toList());
      });

      final open = repository.open();
      final request = client.sent.single as ListThreads;
      client.receive(
        ThreadsListed(
          sourceMessageId: request.messageId,
          total: 0,
          offset: 0,
          limit: 200,
          threads: const [],
        ),
      );
      await open;

      client.receive(
        ThreadCreated(
          thread: const AgentThreadListEntry(
            path: 'dataset://threads/12345678-1234-4678-9234-123456789abc',
            name: '',
            createdAt: '2026-01-01T00:00:00Z',
            modifiedAt: '2026-01-01T00:00:00Z',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.entries().single.name, defaultUntitledThreadName);

      client.receive(
        ThreadUpdated(
          thread: const AgentThreadListEntry(
            path: 'dataset://threads/12345678-1234-4678-9234-123456789abc',
            name: 'Renamed',
            createdAt: '2026-01-01T00:00:00Z',
            modifiedAt: '2026-01-02T00:00:00Z',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.entries().single.name, 'Renamed');

      client.receive(
        ThreadDeleted(
          path: 'dataset://threads/12345678-1234-4678-9234-123456789abc',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.entries(), isEmpty);
      expect(changes, isNotEmpty);
      await repository.close();
    });

    test('does not allow direct upserts', () {
      final repository = AgentThreadStorageRepository(
        chatClient: _FakeChatClient(),
      );
      expect(
        () => repository.addOrUpdateThread(
          const ThreadListEntry(
            path: 'dataset://threads/one',
            name: 'One',
            createdAt: '',
            modifiedAt: '',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('ImageDatasetClient', () {
    test('parses dataset image URI references', () {
      final ref = ImageDatasetClient.datasetUriReference(
        'dataset://assets/generated/images?id=image-1',
      );

      expect(ref.namespace, ['assets', 'generated']);
      expect(ref.table, 'images');
      expect(ref.id, 'image-1');
    });

    test('rejects missing image ids', () {
      expect(
        () => ImageDatasetClient.datasetUriReference('dataset://images'),
        throwsArgumentError,
      );
    });
  });

  group('ImagesDataset schema', () {
    test('uses a large binary data column with image metadata', () {
      final dataField = ImagesDataset.schema.fields[1];
      final dataType = dataField.type;

      expect(dataField.name, 'data');
      expect(dataField.metadata['content-type'], 'image/*');
      expect(dataType, isA<ArrowBinaryType>());
      expect((dataType as ArrowBinaryType).large, isTrue);
    });
  });
}
