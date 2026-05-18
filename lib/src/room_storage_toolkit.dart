import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';

const int defaultRoomStorageToolkitMaxLength = 20000;

class RoomStorageToolkit extends Toolkit {
  RoomStorageToolkit({
    required Meshagent client,
    required String projectId,
    required List<String> rooms,
    bool readOnly = false,
    int maxLength = defaultRoomStorageToolkitMaxLength,
  }) : super(
         name: 'room_storage',
         title: 'room storage',
         description:
             'tools for interacting with explicitly shared room storage',
         tools: _tools(
           config: _RoomStorageToolkitConfig(
             client: client,
             projectId: projectId,
             rooms: _normalizeRooms(rooms),
             maxLength: maxLength,
           ),
           readOnly: readOnly,
         ),
       );

  static List<BaseTool> _tools({
    required _RoomStorageToolkitConfig config,
    required bool readOnly,
  }) {
    final tools = <BaseTool>[
      _ListRoomFilesTool(config),
      _ReadRoomFileTool(config),
      _GrepRoomFileTool(config),
      _GetRoomFileDownloadUrlTool(config),
    ];
    if (!readOnly) {
      tools.addAll([
        _WriteRoomFileTool(config),
        _CopyRoomFileTool(config),
        _DeleteRoomFileTool(config),
      ]);
    }
    return tools;
  }
}

class _RoomStorageToolkitConfig {
  _RoomStorageToolkitConfig({
    required this.client,
    required this.projectId,
    required this.rooms,
    required this.maxLength,
  }) : allowedRooms = Set<String>.unmodifiable(rooms) {
    if (rooms.isEmpty) {
      throw ArgumentError.value(
        rooms,
        'rooms',
        'RoomStorageToolkit requires at least one allowed room.',
      );
    }
    if (maxLength <= 0) {
      throw ArgumentError.value(maxLength, 'maxLength', 'must be positive.');
    }
  }

  final Meshagent client;
  final String projectId;
  final List<String> rooms;
  final Set<String> allowedRooms;
  final int maxLength;

  String requireRoom(Object? value) {
    return requireRoomField(value, field: 'room_name');
  }

  String requireRoomField(Object? value, {required String field}) {
    if (value is! String || value.trim().isEmpty) {
      throw RoomServerException('$field is required.');
    }
    final roomName = value.trim();
    if (!allowedRooms.contains(roomName)) {
      throw RoomServerException(
        "room '$roomName' is not shared with this toolkit.",
      );
    }
    return roomName;
  }

  String requirePath(Object? value) {
    return requirePathField(value, field: 'path');
  }

  String requirePathField(Object? value, {required String field}) {
    if (value is! String) {
      throw RoomServerException('$field is required.');
    }
    final path = value.trim();
    final parts = path.split('/').where((part) => part.isNotEmpty);
    if (parts.any((part) => part == '.' || part == '..')) {
      throw RoomServerException('$field may not contain . or .. segments.');
    }
    return path;
  }

  Future<T> withRoom<T>(
    String roomName,
    Future<T> Function(RoomClient room) callback,
  ) async {
    final connection = await client.connectRoom(
      projectId: projectId,
      roomName: roomName,
      client: 'room-storage-toolkit',
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
}

abstract class _RoomStorageTool extends FunctionTool {
  _RoomStorageTool(
    this.config, {
    required super.name,
    required super.description,
    required super.title,
    required Map<String, dynamic> properties,
    required List<String> requiredFields,
    super.outputSpec,
  }) : super(
         inputSchema: _schema(
           config.rooms,
           properties: properties,
           requiredFields: requiredFields,
         ),
       );

  final _RoomStorageToolkitConfig config;

  static Map<String, dynamic> _schema(
    List<String> rooms, {
    required Map<String, dynamic> properties,
    required List<String> requiredFields,
  }) {
    return {
      'type': 'object',
      'additionalProperties': false,
      'required': ['room_name', ...requiredFields],
      'properties': {
        'room_name': {
          'type': 'string',
          'enum': rooms,
          'description': 'The shared room whose storage should be used.',
        },
        ...properties,
      },
    };
  }

  String roomName(Map<String, dynamic> arguments) =>
      config.requireRoom(arguments['room_name']);

  String path(Map<String, dynamic> arguments) =>
      config.requirePath(arguments['path']);
}

class _ListRoomFilesTool extends _RoomStorageTool {
  _ListRoomFilesTool(super.config)
    : super(
        name: 'list_files_in_room',
        title: 'list files in room',
        description: 'list files in shared room storage',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage directory path to list.',
          },
        },
        requiredFields: ['path'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.json],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    return config.withRoom(selectedRoom, (room) async {
      final entries = await room.storage.list(selectedPath);
      return JsonContent(
        json: {'files': entries.map(_storageEntryJson).toList()},
      );
    });
  }
}

class _ReadRoomFileTool extends _RoomStorageTool {
  _ReadRoomFileTool(super.config)
    : super(
        name: 'read_file',
        title: 'read file',
        description: 'read a file from shared room storage',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage file path to read.',
          },
          'offset': {
            'type': ['integer', 'null'],
            'description': 'Optional character offset for text files.',
          },
        },
        requiredFields: ['path', 'offset'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.text, ToolContentType.file],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    final offset =
        _optionalNonNegativeInt(arguments['offset'], field: 'offset') ?? 0;
    return config.withRoom(selectedRoom, (room) async {
      final content = await room.storage.download(selectedPath);
      if (!_isTextLike(content)) {
        return content;
      }
      final text = utf8.decode(content.data, allowMalformed: true);
      return TextContent(
        text: _sliceText(text, offset: offset, maxLength: config.maxLength),
      );
    });
  }
}

class _GrepRoomFileTool extends _RoomStorageTool {
  _GrepRoomFileTool(super.config)
    : super(
        name: 'grep_file',
        title: 'grep file',
        description:
            'search a text file in shared room storage with a regular expression',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage file path to search.',
          },
          'pattern': {
            'type': 'string',
            'description': 'A Dart regular expression pattern.',
          },
          'offset': {
            'type': ['integer', 'null'],
            'description': 'Optional match offset.',
          },
          'before': {
            'type': ['integer', 'null'],
            'description':
                'Optional number of context lines before each match.',
          },
          'after': {
            'type': ['integer', 'null'],
            'description': 'Optional number of context lines after each match.',
          },
        },
        requiredFields: ['path', 'pattern', 'offset', 'before', 'after'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.text],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    final rawPattern = arguments['pattern'];
    if (rawPattern is! String || rawPattern.isEmpty) {
      throw RoomServerException('pattern is required.');
    }
    final offset =
        _optionalNonNegativeInt(arguments['offset'], field: 'offset') ?? 0;
    final before =
        _optionalNonNegativeInt(arguments['before'], field: 'before') ?? 0;
    final after =
        _optionalNonNegativeInt(arguments['after'], field: 'after') ?? 0;
    final pattern = RegExp(rawPattern);

    return config.withRoom(selectedRoom, (room) async {
      final content = await room.storage.download(selectedPath);
      if (!_isTextLike(content)) {
        return TextContent(
          text:
              'grep_file only supports text-like files. Use read_file for binary files.',
        );
      }
      final text = utf8.decode(content.data, allowMalformed: true);
      return TextContent(
        text: _grepText(
          text,
          pattern: pattern,
          offset: offset,
          before: before,
          after: after,
          maxLength: config.maxLength,
        ),
      );
    });
  }
}

class _GetRoomFileDownloadUrlTool extends _RoomStorageTool {
  _GetRoomFileDownloadUrlTool(super.config)
    : super(
        name: 'get_file_download_url',
        title: 'get file download url',
        description:
            'get a temporary download URL for a file in shared room storage',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage file path.',
          },
        },
        requiredFields: ['path'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.link],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    return config.withRoom(selectedRoom, (room) async {
      final url = await room.storage.downloadUrl(selectedPath);
      return LinkContent(url: url, name: _basename(selectedPath));
    });
  }
}

class _WriteRoomFileTool extends _RoomStorageTool {
  _WriteRoomFileTool(super.config)
    : super(
        name: 'write_file',
        title: 'write file',
        description: 'write a text file to shared room storage',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage file path to write.',
          },
          'text': {
            'type': 'string',
            'description': 'The text content to write.',
          },
          'overwrite': {
            'type': 'boolean',
            'description': 'Whether to overwrite an existing file.',
          },
        },
        requiredFields: ['path', 'text', 'overwrite'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.text],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    final text = arguments['text'];
    if (text is! String) {
      throw RoomServerException('text is required.');
    }
    final overwrite = arguments['overwrite'] == true;
    return config.withRoom(selectedRoom, (room) async {
      await room.storage.upload(
        selectedPath,
        Uint8List.fromList(utf8.encode(text)),
        overwrite: overwrite,
        name: _basename(selectedPath),
        mimeType: 'text/plain',
      );
      return TextContent(text: 'the file was saved');
    });
  }
}

class _DeleteRoomFileTool extends _RoomStorageTool {
  _DeleteRoomFileTool(super.config)
    : super(
        name: 'delete_file',
        title: 'delete file',
        description: 'delete a file or directory from shared room storage',
        properties: {
          'path': {
            'type': 'string',
            'description': 'The room storage path to delete.',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to recursively delete directories.',
          },
        },
        requiredFields: ['path', 'recursive'],
        outputSpec: ToolContentSpec(
          types: [ToolContentType.empty],
          stream: false,
        ),
      );

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final selectedRoom = roomName(arguments);
    final selectedPath = path(arguments);
    final recursive = arguments['recursive'] == true;
    return config.withRoom(selectedRoom, (room) async {
      await room.storage.delete(selectedPath, recursive: recursive);
      return EmptyContent();
    });
  }
}

class _CopyRoomFileTool extends FunctionTool {
  _CopyRoomFileTool(this.config)
    : super(
        name: 'copy_file',
        title: 'copy file',
        description: 'copy a file between explicitly shared room storage',
        inputSchema: {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'source_room_name',
            'source_path',
            'destination_room_name',
            'destination_path',
            'overwrite',
          ],
          'properties': {
            'source_room_name': {
              'type': 'string',
              'enum': config.rooms,
              'description': 'The shared room to copy the file from.',
            },
            'source_path': {
              'type': 'string',
              'description': 'The room storage file path to copy from.',
            },
            'destination_room_name': {
              'type': 'string',
              'enum': config.rooms,
              'description': 'The shared room to copy the file to.',
            },
            'destination_path': {
              'type': 'string',
              'description': 'The room storage file path to copy to.',
            },
            'overwrite': {
              'type': 'boolean',
              'description':
                  'Whether to overwrite an existing destination file.',
            },
          },
        },
        outputSpec: ToolContentSpec(
          types: [ToolContentType.text],
          stream: false,
        ),
      );

  final _RoomStorageToolkitConfig config;

  @override
  Future<Content> execute(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final sourceRoom = config.requireRoomField(
      arguments['source_room_name'],
      field: 'source_room_name',
    );
    final sourcePath = config.requirePathField(
      arguments['source_path'],
      field: 'source_path',
    );
    final destinationRoom = config.requireRoomField(
      arguments['destination_room_name'],
      field: 'destination_room_name',
    );
    final destinationPath = config.requirePathField(
      arguments['destination_path'],
      field: 'destination_path',
    );
    final overwrite = arguments['overwrite'] == true;

    if (sourceRoom == destinationRoom) {
      return config.withRoom(sourceRoom, (room) async {
        final content = await room.storage.download(sourcePath);
        await room.storage.upload(
          destinationPath,
          content.data,
          overwrite: overwrite,
          name: _basename(destinationPath),
          mimeType: content.mimeType,
        );
        return TextContent(text: 'the file was copied');
      });
    }

    final content = await config.withRoom(
      sourceRoom,
      (room) => room.storage.download(sourcePath),
    );
    return config.withRoom(destinationRoom, (room) async {
      await room.storage.upload(
        destinationPath,
        content.data,
        overwrite: overwrite,
        name: _basename(destinationPath),
        mimeType: content.mimeType,
      );
      return TextContent(text: 'the file was copied');
    });
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

Map<String, dynamic> _storageEntryJson(StorageEntry entry) {
  return {
    'name': entry.name,
    'is_folder': entry.isFolder,
    if (entry.size != null) 'size': entry.size,
    if (entry.createdAt != null)
      'created_at': entry.createdAt!.toIso8601String(),
    if (entry.updatedAt != null)
      'updated_at': entry.updatedAt!.toIso8601String(),
  };
}

int? _optionalNonNegativeInt(Object? value, {required String field}) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 0) {
    throw RoomServerException('$field must be a non-negative integer.');
  }
  return value;
}

bool _isTextLike(FileContent content) {
  final mimeType = content.mimeType.toLowerCase();
  if (mimeType.startsWith('text/') ||
      mimeType == 'application/json' ||
      mimeType == 'application/xml' ||
      mimeType == 'image/svg+xml') {
    return true;
  }
  final name = content.name.toLowerCase();
  return const {
    '.csv',
    '.htm',
    '.html',
    '.js',
    '.json',
    '.md',
    '.txt',
    '.ts',
    '.tsx',
    '.xml',
    '.yaml',
    '.yml',
  }.any(name.endsWith);
}

String _sliceText(String text, {required int offset, required int maxLength}) {
  final start = offset > text.length ? text.length : offset;
  final end = start + maxLength > text.length ? text.length : start + maxLength;
  final sliced = text.substring(start, end);
  if (end >= text.length) {
    return sliced;
  }
  return '$sliced\n... truncated at $end of ${text.length} characters ...';
}

String _grepText(
  String text, {
  required RegExp pattern,
  required int offset,
  required int before,
  required int after,
  required int maxLength,
}) {
  final lines = text.split('\n');
  final selectedLines = <int>{};
  var matchCount = 0;
  for (var index = 0; index < lines.length; index += 1) {
    if (!pattern.hasMatch(lines[index])) {
      continue;
    }
    if (matchCount < offset) {
      matchCount += 1;
      continue;
    }
    matchCount += 1;
    final start = index - before < 0 ? 0 : index - before;
    final end = index + after >= lines.length
        ? lines.length - 1
        : index + after;
    for (var line = start; line <= end; line += 1) {
      selectedLines.add(line);
    }
  }
  if (selectedLines.isEmpty) {
    return 'No matches found.';
  }

  final sorted = selectedLines.toList()..sort();
  final buffer = StringBuffer();
  var previous = -2;
  for (final index in sorted) {
    if (previous >= 0 && index != previous + 1) {
      buffer.writeln('--');
    }
    buffer.writeln('${index + 1}: ${lines[index]}');
    previous = index;
    if (buffer.length > maxLength) {
      final output = buffer.toString();
      return '${output.substring(0, maxLength)}\n... truncated ...';
    }
  }
  return buffer.toString();
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? 'download' : parts.last;
}
