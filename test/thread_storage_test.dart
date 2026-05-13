import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

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
