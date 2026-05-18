import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';

const int defaultRoomShellMaxOutputLength = 50 * 1024;

final ContainerMountSpec defaultRoomShellMounts = ContainerMountSpec(
  room: [RoomStorageMountSpec(path: '/data')],
);

class RoomShellToolkit extends Toolkit {
  RoomShellToolkit({
    required Meshagent client,
    required String projectId,
    required List<String> rooms,
    String image = 'meshagent/python:default',
    String? workingDir,
    ContainerMountSpec? mounts,
    Map<String, String> env = const {},
  }) : super(
         name: 'room_shell',
         title: 'room shell',
         description:
             'execute shell commands in containers for explicitly shared rooms',
         tools: [
           _RoomShellTool(
             _RoomShellToolkitConfig(
               client: client,
               projectId: projectId,
               rooms: _normalizeRooms(rooms),
               image: image,
               workingDir: workingDir,
               mounts: mounts ?? defaultRoomShellMounts,
               env: Map<String, String>.unmodifiable(env),
             ),
           ),
         ],
       );
}

class _RoomShellToolkitConfig {
  _RoomShellToolkitConfig({
    required this.client,
    required this.projectId,
    required this.rooms,
    required this.image,
    required this.workingDir,
    required this.mounts,
    required this.env,
  }) : allowedRooms = Set<String>.unmodifiable(rooms) {
    if (rooms.isEmpty) {
      throw ArgumentError.value(
        rooms,
        'rooms',
        'RoomShellToolkit requires at least one allowed room.',
      );
    }
    if (image.trim().isEmpty) {
      throw ArgumentError.value(image, 'image', 'must not be empty.');
    }
  }

  final Meshagent client;
  final String projectId;
  final List<String> rooms;
  final Set<String> allowedRooms;
  final String image;
  final String? workingDir;
  final ContainerMountSpec mounts;
  final Map<String, String> env;
  final Map<String, String> _containerIdsByRoom = {};

  String requireRoom(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw RoomServerException('room_name is required.');
    }
    final roomName = value.trim();
    if (!allowedRooms.contains(roomName)) {
      throw RoomServerException(
        "room '$roomName' is not shared with this toolkit.",
      );
    }
    return roomName;
  }

  Future<T> withRoom<T>(
    String roomName,
    Future<T> Function(RoomClient room) callback,
  ) async {
    final connection = await client.connectRoom(
      projectId: projectId,
      roomName: roomName,
      client: 'room-shell-toolkit',
    );
    final room = RoomClient(
      protocolFactory: WebSocketClientProtocol.createFactory(
        url: connection.roomUrl,
        token: connection.jwt,
      ),
      reconnectTimeout: Duration.zero,
    );
    try {
      await room.start();
      await room.ready;
      return await callback(room);
    } finally {
      room.dispose();
    }
  }

  Future<String> getContainerId(
    RoomClient room, {
    required String roomName,
  }) async {
    final cachedContainerId = _containerIdsByRoom[roomName];
    if (cachedContainerId != null) {
      final containers = await room.containers.list();
      if (containers.any((container) => container.id == cachedContainerId)) {
        return cachedContainerId;
      }
    }

    final containerId = await room.containers.run(
      image: image,
      command: 'sleep infinity',
      mounts: mounts,
      writableRootFs: true,
      env: env,
    );
    _containerIdsByRoom[roomName] = containerId;
    return containerId;
  }
}

class _RoomShellTool extends FunctionTool {
  _RoomShellTool(this.config)
    : super(
        name: 'container_shell',
        title: 'container shell',
        description:
            'execute shell commands in a container for explicitly shared room storage',
        inputSchema: {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'room_name',
            'commands',
            'max_output_length',
            'timeout_ms',
          ],
          'properties': {
            'room_name': {
              'type': 'string',
              'enum': config.rooms,
              'description': 'The shared room where the shell should run.',
            },
            'commands': {
              'type': 'array',
              'minItems': 1,
              'items': {'type': 'string'},
              'description': 'Shell commands to execute.',
            },
            'max_output_length': {
              'type': ['integer', 'null'],
              'description':
                  'Optional maximum number of characters to return per output stream.',
            },
            'timeout_ms': {
              'type': ['integer', 'null'],
              'description': 'Optional timeout per command in milliseconds.',
            },
          },
        },
        outputSpec: ToolContentSpec(
          types: [ToolContentType.json],
          stream: false,
        ),
      );

  final _RoomShellToolkitConfig config;

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final roomName = config.requireRoom(arguments['room_name']);
    final commands = _requiredStringList(
      arguments['commands'],
      field: 'commands',
    );
    final maxOutputLength =
        _optionalPositiveInt(
          arguments['max_output_length'],
          field: 'max_output_length',
        ) ??
        defaultRoomShellMaxOutputLength;
    final timeoutMs =
        _optionalPositiveInt(arguments['timeout_ms'], field: 'timeout_ms') ??
        60000;
    final timeout = Duration(milliseconds: timeoutMs);

    return config.withRoom(roomName, (room) async {
      final containerId = await config.getContainerId(room, roomName: roomName);
      final results = <Map<String, dynamic>>[];

      for (final command in commands) {
        final commandToRun = _commandWithWorkingDir(
          command,
          workingDir: config.workingDir,
        );
        final session = room.containers.exec(
          containerId: containerId,
          command: 'bash -lc ${_shellQuote(commandToRun)}',
        );
        final stdout = _OutputAccumulator(maxLength: maxOutputLength);
        final stderr = _OutputAccumulator(maxLength: maxOutputLength);
        final stdoutTask = _collectOutput(session.output, stdout);
        final stderrTask = _collectOutput(session.stderr, stderr);

        try {
          final exitCode = await session.result.timeout(timeout);
          await _finishOutputTasks(stdoutTask, stderrTask);
          results.add({
            'outcome': {'type': 'exit', 'exit_code': exitCode},
            'stdout': stdout.finish(),
            'stderr': stderr.finish(),
          });
        } on TimeoutException {
          await session.kill();
          await _finishOutputTasks(stdoutTask, stderrTask);
          results.add({
            'outcome': {'type': 'timeout'},
            'stdout': stdout.finish(),
            'stderr': stderr.finish(),
          });
          break;
        } catch (error) {
          await _finishOutputTasks(stdoutTask, stderrTask);
          results.add({
            'outcome': {'type': 'exit', 'exit_code': 1},
            'stdout': stdout.finish(),
            'stderr': error.toString(),
          });
          break;
        }
      }

      return JsonContent(json: {'results': results});
    });
  }
}

Future<void> _finishOutputTasks(
  Future<void> stdoutTask,
  Future<void> stderrTask,
) async {
  for (final task in [stdoutTask, stderrTask]) {
    try {
      await task;
    } catch (_) {
      // The exec result carries the command failure. Stream errors should not
      // prevent returning the structured shell result.
    }
  }
}

List<String> _normalizeRooms(List<String> rooms) {
  final seen = <String>{};
  final output = <String>[];
  for (final room in rooms) {
    final normalized = room.trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    output.add(normalized);
  }
  return List<String>.unmodifiable(output);
}

List<String> _requiredStringList(Object? value, {required String field}) {
  if (value is! List || value.isEmpty) {
    throw RoomServerException('$field must be a non-empty string array.');
  }
  final output = <String>[];
  for (final item in value) {
    if (item is! String || item.isEmpty) {
      throw RoomServerException('$field must be a non-empty string array.');
    }
    output.add(item);
  }
  return output;
}

int? _optionalPositiveInt(Object? value, {required String field}) {
  if (value == null) {
    return null;
  }
  if (value is! int || value <= 0) {
    throw RoomServerException('$field must be a positive integer.');
  }
  return value;
}

String _commandWithWorkingDir(String command, {required String? workingDir}) {
  if (workingDir == null || workingDir.trim().isEmpty) {
    return command;
  }
  return 'cd ${_shellQuote(workingDir)} && $command';
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<void> _collectOutput(
  Stream<Uint8List> stream,
  _OutputAccumulator accumulator,
) async {
  await for (final chunk in stream) {
    accumulator.add(chunk);
  }
}

class _OutputAccumulator {
  _OutputAccumulator({required this.maxLength});

  final int maxLength;
  final _buffer = StringBuffer();
  var _truncated = false;

  void add(Uint8List data) {
    if (_buffer.length >= maxLength) {
      _truncated = true;
      return;
    }
    final text = utf8.decode(data, allowMalformed: true);
    final remaining = maxLength - _buffer.length;
    if (text.length <= remaining) {
      _buffer.write(text);
      return;
    }
    _buffer.write(text.substring(0, remaining));
    _truncated = true;
  }

  String finish() {
    final text = _buffer.toString();
    if (!_truncated) {
      return text;
    }
    return '$text\n... truncated ...';
  }
}
