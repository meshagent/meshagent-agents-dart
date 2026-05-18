import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

void main() {
  Meshagent meshagent() =>
      Meshagent(baseUrl: 'http://example.test', token: 'test-token');

  test('requires at least one room', () {
    expect(
      () => RoomStorageToolkit(
        client: meshagent(),
        projectId: 'project-1',
        rooms: const [],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('adds allowed room enum to every tool schema', () {
    final toolkit = RoomStorageToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha', ' beta ', 'alpha'],
    );

    expect(toolkit.tools, isNotEmpty);
    for (final tool in toolkit.tools) {
      final properties = tool.inputSchema['properties'] as Map<String, dynamic>;
      if (tool.name == 'copy_file') {
        expect(tool.inputSchema['required'], contains('source_room_name'));
        expect(tool.inputSchema['required'], contains('destination_room_name'));
        final sourceRoomName =
            properties['source_room_name'] as Map<String, dynamic>;
        final destinationRoomName =
            properties['destination_room_name'] as Map<String, dynamic>;
        expect(sourceRoomName['enum'], ['alpha', 'beta']);
        expect(destinationRoomName['enum'], ['alpha', 'beta']);
      } else {
        expect(tool.inputSchema['required'], contains('room_name'));
        final roomName = properties['room_name'] as Map<String, dynamic>;
        expect(roomName['enum'], ['alpha', 'beta']);
      }
    }
  });

  test('read-only mode omits mutating tools', () {
    final toolkit = RoomStorageToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha'],
      readOnly: true,
    );

    final names = toolkit.tools.map((tool) => tool.name).toSet();
    expect(
      names,
      containsAll([
        'list_files_in_room',
        'read_file',
        'grep_file',
        'get_file_download_url',
      ]),
    );
    expect(names, isNot(contains('write_file')));
    expect(names, isNot(contains('copy_file')));
    expect(names, isNot(contains('delete_file')));
  });

  test('rejects rooms outside allowed list before connecting', () async {
    final toolkit = RoomStorageToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha'],
    );

    await expectLater(
      toolkit.execute(
        const ToolContext(),
        'list_files_in_room',
        ToolContentInput(
          JsonContent(json: const {'room_name': 'beta', 'path': ''}),
        ),
      ),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          contains("not shared"),
        ),
      ),
    );
  });

  test('rejects parent directory path segments before connecting', () async {
    final toolkit = RoomStorageToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha'],
    );

    await expectLater(
      toolkit.execute(
        const ToolContext(),
        'list_files_in_room',
        ToolContentInput(
          JsonContent(json: const {'room_name': 'alpha', 'path': '../secrets'}),
        ),
      ),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          contains('..'),
        ),
      ),
    );
  });

  test(
    'copy rejects destination rooms outside allowed list before connecting',
    () async {
      final toolkit = RoomStorageToolkit(
        client: meshagent(),
        projectId: 'project-1',
        rooms: const ['alpha'],
      );

      await expectLater(
        toolkit.execute(
          const ToolContext(),
          'copy_file',
          ToolContentInput(
            JsonContent(
              json: const {
                'source_room_name': 'alpha',
                'source_path': 'input.txt',
                'destination_room_name': 'beta',
                'destination_path': 'output.txt',
                'overwrite': false,
              },
            ),
          ),
        ),
        throwsA(
          isA<RoomServerException>().having(
            (error) => error.message,
            'message',
            contains("not shared"),
          ),
        ),
      );
    },
  );

  test('copy rejects parent destination path before connecting', () async {
    final toolkit = RoomStorageToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha', 'beta'],
    );

    await expectLater(
      toolkit.execute(
        const ToolContext(),
        'copy_file',
        ToolContentInput(
          JsonContent(
            json: const {
              'source_room_name': 'alpha',
              'source_path': 'input.txt',
              'destination_room_name': 'beta',
              'destination_path': '../output.txt',
              'overwrite': false,
            },
          ),
        ),
      ),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          contains('destination_path'),
        ),
      ),
    );
  });
}
