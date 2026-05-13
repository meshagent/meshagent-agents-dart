import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:uuid/uuid.dart';

class SavedImage {
  const SavedImage({
    required this.id,
    required this.mimeType,
    required this.createdAt,
    required this.createdBy,
    required this.annotations,
  });

  final String id;
  final String mimeType;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, String> annotations;
}

class ImageDatasetRecord {
  const ImageDatasetRecord({required this.data, required this.mimeType});

  final Uint8List data;
  final String mimeType;
}

class DatasetUriReference {
  const DatasetUriReference({
    required this.table,
    required this.namespace,
    required this.id,
  });

  final String table;
  final List<String>? namespace;
  final String id;
}

class ImageDatasetClient {
  ImageDatasetClient({
    required this.room,
    this.table = ImagesDataset.tableName,
  });

  final RoomClient room;
  final String table;

  static DatasetUriReference datasetUriReference(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme != 'dataset') {
      throw ArgumentError.value(
        uri,
        'uri',
        'dataset image URI must use the dataset:// scheme',
      );
    }
    final id = parsed.queryParameters['id']?.trim();
    if (id == null || id.isEmpty) {
      throw ArgumentError.value(
        uri,
        'uri',
        'dataset image URI must include an id query parameter',
      );
    }
    final segments = <String>[
      if (parsed.host.trim().isNotEmpty) parsed.host.trim(),
      ...parsed.pathSegments.map((segment) => segment.trim()),
    ].where((segment) => segment.isNotEmpty).toList(growable: false);
    if (segments.isEmpty) {
      throw ArgumentError.value(
        uri,
        'uri',
        'dataset image URI must include a table path',
      );
    }
    return DatasetUriReference(
      table: segments.last,
      namespace: segments.length == 1
          ? null
          : segments.sublist(0, segments.length - 1),
      id: id,
    );
  }

  Future<ImageDatasetRecord?> readRecord(
    String imageId, {
    String? table,
    List<String>? namespace,
    String? fallbackMimeType,
  }) async {
    final normalizedId = _normalizeImageId(imageId);
    final rows = await room.datasets.searchTable(
      table: table ?? this.table,
      where: {'id': normalizedId},
      limit: 1,
      select: const ['data', 'mime_type'],
      namespace: namespace,
    );
    final record = rows.toRows().firstOrNull;
    if (record == null) {
      return null;
    }
    final data = record['data'];
    final bytes = data is Uint8List
        ? data
        : data is List<int>
        ? Uint8List.fromList(data)
        : null;
    if (bytes == null) {
      return null;
    }
    final rawMimeType = record['mime_type'];
    return ImageDatasetRecord(
      data: bytes,
      mimeType: rawMimeType is String && rawMimeType.trim().isNotEmpty
          ? rawMimeType.trim()
          : fallbackMimeType ?? 'image/png',
    );
  }

  Future<ImageDatasetRecord?> readRecordFromUri(
    String uri, {
    String? fallbackMimeType,
  }) {
    final reference = datasetUriReference(uri);
    return readRecord(
      reference.id,
      table: reference.table,
      namespace: reference.namespace,
      fallbackMimeType: fallbackMimeType,
    );
  }
}

class ImagesDataset extends ImageDatasetClient {
  ImagesDataset({required super.room, super.table = tableName, this.namespace});

  static const String tableName = 'images';

  static const ArrowSchema schema = ArrowSchema([
    ArrowField(name: 'id', type: ArrowUtf8Type(), nullable: false),
    ArrowField(
      name: 'data',
      type: ArrowBinaryType(large: true),
      nullable: false,
      metadata: {'content-type': 'image/*'},
    ),
    ArrowField(name: 'mime_type', type: ArrowUtf8Type(), nullable: false),
    ArrowField(
      name: 'created_at',
      type: ArrowTimestampType(
        unit: ArrowTimeUnit.microsecond,
        timezone: 'UTC',
      ),
      nullable: false,
    ),
    ArrowField(name: 'created_by', type: ArrowUtf8Type(), nullable: false),
    ArrowField(
      name: 'annotations',
      type: ArrowListType(
        ArrowField(
          name: 'item',
          type: ArrowStructType([
            ArrowField(name: 'key', type: ArrowUtf8Type(), nullable: false),
            ArrowField(name: 'value', type: ArrowUtf8Type()),
          ]),
        ),
      ),
    ),
  ]);

  final List<String>? namespace;
  Future<void>? _ready;

  Future<SavedImage> save({
    required Uint8List data,
    required String mimeType,
    required String createdBy,
    Map<String, String> annotations = const {},
    String? imageId,
    DateTime? createdAt,
  }) async {
    final normalizedId = imageId?.trim().isNotEmpty == true
        ? imageId!.trim()
        : const Uuid().v4();
    final normalizedMimeType = mimeType.trim();
    if (normalizedMimeType.isEmpty) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'image MIME type cannot be empty',
      );
    }
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError.value(
        createdBy,
        'createdBy',
        'creator cannot be empty',
      );
    }
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final saved = SavedImage(
      id: normalizedId,
      mimeType: normalizedMimeType,
      createdAt: timestamp,
      createdBy: normalizedCreatedBy,
      annotations: Map.unmodifiable(annotations),
    );
    final batch = _batchFor([(image: saved, data: data)]);

    await _ensureReady();
    await _retryCommitConflicts(() {
      return room.datasets.insert(
        table: table,
        records: batch,
        namespace: namespace,
      );
    });
    return saved;
  }

  Future<SavedImage?> read(String imageId) async {
    await _ensureReady();
    final rows = await room.datasets.searchTable(
      table: table,
      where: {'id': _normalizeImageId(imageId)},
      limit: 1,
      select: const ['id', 'mime_type', 'created_at', 'created_by'],
      namespace: namespace,
    );
    final row = rows.toRows().firstOrNull;
    return row == null ? null : _savedImageFromRow(row);
  }

  Future<List<SavedImage>> search({Object? where, int? limit}) async {
    await _ensureReady();
    final rows = await room.datasets.searchTable(
      table: table,
      where: where,
      limit: limit,
      select: const ['id', 'mime_type', 'created_at', 'created_by'],
      namespace: namespace,
    );
    return rows
        .toRows()
        .map(_savedImageFromRow)
        .whereType<SavedImage>()
        .toList(growable: false);
  }

  @override
  Future<ImageDatasetRecord?> readRecord(
    String imageId, {
    String? table,
    List<String>? namespace,
    String? fallbackMimeType,
  }) async {
    await _ensureReady();
    return super.readRecord(
      imageId,
      table: table ?? this.table,
      namespace: namespace ?? this.namespace,
      fallbackMimeType: fallbackMimeType,
    );
  }

  Future<void> _ensureReady() {
    return _ready ??= _createTable();
  }

  Future<void> _createTable() async {
    await room.datasets.createTableWithSchema(
      name: table,
      schema: schema,
      mode: CreateMode.createIfNotExists,
      namespace: namespace,
    );
    try {
      await room.datasets.createIndex(
        table: table,
        config: const DatasetIndexConfig(column: 'id', indexType: 'BTREE'),
        namespace: namespace,
      );
    } catch (_) {
      // The index may already exist or the backend may not need it.
    }
  }

  ArrowRecordBatch _batchFor(List<({SavedImage image, Uint8List data})> rows) {
    return ArrowRecordBatch.fromColumns(
      schema: schema,
      columns: [
        ArrowValueArray(
          field: schema.fields[0],
          values: rows.map((row) => row.image.id).toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[1],
          values: rows.map((row) => row.data).toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[2],
          values: rows.map((row) => row.image.mimeType).toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[3],
          values: rows
              .map((row) => row.image.createdAt)
              .toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[4],
          values: rows
              .map((row) => row.image.createdBy)
              .toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[5],
          values: rows
              .map((row) {
                return row.image.annotations.entries
                    .map((entry) => {'key': entry.key, 'value': entry.value})
                    .toList(growable: false);
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

String _normalizeImageId(String imageId) {
  final normalized = imageId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(imageId, 'imageId', 'image id cannot be empty');
  }
  return normalized;
}

SavedImage? _savedImageFromRow(Map<String, Object?> row) {
  final id = _stringFromDatasetValue(row['id']);
  final mimeType = _stringFromDatasetValue(row['mime_type']);
  final createdAt = row['created_at'];
  final createdBy = _stringFromDatasetValue(row['created_by']);
  if (id == null || mimeType == null || createdBy == null) {
    return null;
  }
  final parsedCreatedAt =
      _dateTimeFromDatasetValue(createdAt) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return SavedImage(
    id: id,
    mimeType: mimeType,
    createdAt: parsedCreatedAt,
    createdBy: createdBy,
    annotations: _annotationsFromValue(row['annotations']),
  );
}

DateTime? _dateTimeFromDatasetValue(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  if (value is int) {
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }
  if (value is num) {
    return DateTime.fromMicrosecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is BigInt) {
    return DateTime.fromMicrosecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}

String? _stringFromDatasetValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

Map<String, String> _annotationsFromValue(Object? value) {
  if (value is! List) {
    return const {};
  }
  final annotations = <String, String>{};
  for (final item in value) {
    if (item is Map) {
      final key = item['key'];
      final annotationValue = item['value'];
      if (key is String && annotationValue is String) {
        annotations[key] = annotationValue;
      }
    }
  }
  return Map.unmodifiable(annotations);
}

Future<void> _retryCommitConflicts(Future<void> Function() action) async {
  for (var attempt = 0; attempt < 6; attempt += 1) {
    try {
      await action();
      return;
    } on RoomServerException catch (error) {
      final retryable =
          error.retryable ||
          error.message.toLowerCase().contains('commit conflict') ||
          error.message.toLowerCase().contains('conflicting commit');
      if (!retryable || attempt == 5) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
