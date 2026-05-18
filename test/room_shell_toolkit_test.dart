import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart';
import 'package:test/test.dart';

void main() {
  Meshagent meshagent() =>
      Meshagent(baseUrl: 'http://example.test', token: 'test-token');

  test('requires at least one room', () {
    expect(
      () => RoomShellToolkit(
        client: meshagent(),
        projectId: 'project-1',
        rooms: const [],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('adds allowed room enum to shell schema', () {
    final toolkit = RoomShellToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha', ' beta ', 'alpha'],
    );

    expect(toolkit.name, 'room_shell');
    expect(toolkit.title, 'room shell');
    expect(toolkit.tools, hasLength(1));
    final tool = toolkit.tools.single;
    expect(tool.name, 'container_shell');
    expect(tool.inputSchema['required'], contains('room_name'));
    final properties = tool.inputSchema['properties'] as Map<String, dynamic>;
    final roomName = properties['room_name'] as Map<String, dynamic>;
    expect(roomName['enum'], ['alpha', 'beta']);
  });

  test('rejects rooms outside allowed list before connecting', () async {
    final toolkit = RoomShellToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha'],
    );

    await expectLater(
      toolkit.execute(
        const ToolContext(),
        'container_shell',
        ToolContentInput(
          JsonContent(
            json: const {
              'room_name': 'beta',
              'commands': ['pwd'],
              'max_output_length': null,
              'timeout_ms': null,
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
  });

  test('rejects empty commands before connecting', () async {
    final toolkit = RoomShellToolkit(
      client: meshagent(),
      projectId: 'project-1',
      rooms: const ['alpha'],
    );

    await expectLater(
      toolkit.execute(
        const ToolContext(),
        'container_shell',
        ToolContentInput(
          JsonContent(
            json: const {
              'room_name': 'alpha',
              'commands': [],
              'max_output_length': null,
              'timeout_ms': null,
            },
          ),
        ),
      ),
      throwsA(
        isA<RoomServerException>().having(
          (error) => error.message,
          'message',
          contains('commands'),
        ),
      ),
    );
  });
}
