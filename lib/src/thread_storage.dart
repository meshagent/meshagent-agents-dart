import 'dart:async';

import 'package:meshagent/meshagent.dart';

import 'agent_messages.dart';
import 'chat_client.dart';

const String defaultUntitledThreadName = 'New Chat';

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class ThreadListEntry {
  const ThreadListEntry({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final String createdAt;
  final String modifiedAt;

  ThreadListEntry renamed(String name, String modifiedAt) {
    return ThreadListEntry(
      path: path,
      name: name,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
    );
  }

  static ThreadListEntry? fromDatasetRow(Map<String, Object?> row) {
    final rawPath = row['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return null;
    }
    final threadPath = rawPath.trim();
    final rawName = row['name'];
    final rawCreatedAt = row['created_at'];
    final rawModifiedAt = row['modified_at'];
    return ThreadListEntry(
      path: threadPath,
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : defaultThreadDisplayNameFromPath(threadPath),
      createdAt: rawCreatedAt is String ? rawCreatedAt : '',
      modifiedAt: rawModifiedAt is String ? rawModifiedAt : '',
    );
  }
}

abstract class ThreadStorage {
  String get path;

  Future<void> start();

  Future<void> stop();

  Future<void> waitUntilReady();

  List<AgentThreadMessage> agentMessages();

  void pushMessage({required AgentThreadMessage message, Participant? sender});
}

abstract class ThreadStorageRepository extends ChangeEmitter {
  Future<void> open();

  Future<void> close();

  List<ThreadListEntry> entries();

  Future<void> addOrUpdateThread(ThreadListEntry entry);

  Future<void> deleteThread(String threadPath);

  Future<void> renameThread(String threadPath, String name);
}

class DatasetThreadListRef {
  const DatasetThreadListRef({required this.namespace, required this.table});

  final List<String>? namespace;
  final String table;

  static DatasetThreadListRef parse(String url) {
    var path = url.trim();
    if (!path.startsWith('dataset://')) {
      throw ArgumentError.value(
        url,
        'url',
        'dataset thread list URL must start with dataset://',
      );
    }
    path = path.substring('dataset://'.length);
    if (path.startsWith('/')) {
      throw ArgumentError.value(
        url,
        'url',
        'dataset thread list URL must use dataset://path',
      );
    }
    final parts = path
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'dataset thread list URL must include a table name',
      );
    }
    return DatasetThreadListRef(
      namespace: parts.length == 1 ? null : parts.sublist(0, parts.length - 1),
      table: parts.last,
    );
  }
}

class DatasetThreadStorageRepository extends ThreadStorageRepository {
  DatasetThreadStorageRepository({required this.room, required String path})
    : path = path.trim(),
      ref = DatasetThreadListRef.parse(path.trim());

  static const ArrowSchema schema = ArrowSchema([
    ArrowField(name: 'path', type: ArrowUtf8Type(), nullable: false),
    ArrowField(name: 'name', type: ArrowUtf8Type()),
    ArrowField(name: 'created_at', type: ArrowUtf8Type()),
    ArrowField(name: 'modified_at', type: ArrowUtf8Type()),
  ]);

  final RoomClient room;
  final String path;
  final DatasetThreadListRef ref;
  final Map<String, ThreadListEntry> _entriesByPath =
      <String, ThreadListEntry>{};
  StreamSubscription<DatasetTableWatchEvent>? _subscription;
  Future<void>? _refreshEntriesFuture;
  bool _initialSnapshotReady = false;
  bool _closed = true;

  @override
  Future<void> open() async {
    _closed = false;
    await _ensureTable();
    final ready = Completer<void>();
    _subscription = room.datasets
        .watchTable(table: ref.table, namespace: ref.namespace)
        .listen(
          (event) {
            final initialSnapshotCompleted = _handleWatchEvent(event);
            if (initialSnapshotCompleted && !ready.isCompleted) {
              ready.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_closed) {
              return;
            }
            if (!ready.isCompleted) {
              ready.completeError(error, stackTrace);
            } else {
              Zone.current.handleUncaughtError(error, stackTrace);
            }
          },
          onDone: () {
            if (_closed) {
              return;
            }
            if (!ready.isCompleted) {
              ready.completeError(
                StateError(
                  'Dataset thread list watch closed before initial snapshot.',
                ),
              );
            }
          },
        );
    await ready.future;
  }

  @override
  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    _initialSnapshotReady = false;
    _closed = true;
    await subscription?.cancel();
    final refreshEntriesFuture = _refreshEntriesFuture;
    _refreshEntriesFuture = null;
    if (refreshEntriesFuture != null) {
      try {
        await refreshEntriesFuture;
      } catch (_) {}
    }
  }

  @override
  List<ThreadListEntry> entries() {
    return _entriesByPath.values.toList(growable: false);
  }

  @override
  Future<void> addOrUpdateThread(ThreadListEntry entry) async {
    await _ensureTable();
    await room.datasets.merge(
      table: ref.table,
      on: 'path',
      records: _batchFor([entry]),
      namespace: ref.namespace,
    );
  }

  @override
  Future<void> deleteThread(String threadPath) async {
    final normalized = _normalizeThreadPath(threadPath);
    await _ensureTable();
    await room.datasets.delete(
      table: ref.table,
      where: _pathWhere(normalized),
      namespace: ref.namespace,
    );
    if (_entriesByPath.remove(normalized) != null) {
      notifyListeners();
    }
  }

  @override
  Future<void> renameThread(String threadPath, String name) async {
    final normalized = _normalizeThreadPath(threadPath);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'thread name cannot be empty');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = _entriesByPath[normalized];
    await addOrUpdateThread(
      ThreadListEntry(
        path: normalized,
        name: trimmedName,
        createdAt: existing?.createdAt ?? now,
        modifiedAt: now,
      ),
    );
  }

  Future<void> _ensureTable() async {
    await room.datasets.createTableWithSchema(
      name: ref.table,
      schema: schema,
      mode: CreateMode.createIfNotExists,
      namespace: ref.namespace,
    );
  }

  bool _handleWatchEvent(DatasetTableWatchEvent event) {
    final rows = event.batch?.toRows() ?? const <DatasetRecord>[];
    if (event.phase == DatasetTableWatchPhase.initial) {
      for (final row in rows) {
        final entry = ThreadListEntry.fromDatasetRow(row);
        if (entry != null) {
          _entriesByPath[entry.path] = entry;
        }
      }
      if (event.kind == 'ready') {
        _initialSnapshotReady = true;
        return true;
      }
      if (_initialSnapshotReady && rows.isNotEmpty) {
        notifyListeners();
      }
      return false;
    }

    if (event.kind == 'ready') {
      return false;
    }

    final changeType = event.changeType?.trim().toLowerCase() ?? '';
    if (changeType == 'deleted' ||
        changeType == 'delete' ||
        changeType == 'removed' ||
        changeType == 'remove' ||
        event.deletePredicate != null ||
        event.kind.trim().toLowerCase() == 'delete') {
      var removed = false;
      for (final row in rows) {
        final entry = ThreadListEntry.fromDatasetRow(row);
        if (entry != null) {
          removed = _entriesByPath.remove(entry.path) != null || removed;
        }
      }
      final deletedPath = _threadPathFromDeletePredicate(event.deletePredicate);
      if (deletedPath != null) {
        removed = _entriesByPath.remove(deletedPath) != null || removed;
      }
      if (rows.isEmpty && deletedPath == null) {
        final refreshEntriesFuture = _refreshEntries();
        _refreshEntriesFuture = refreshEntriesFuture;
        unawaited(refreshEntriesFuture.catchError((_) {}));
        return false;
      }
      if (removed || rows.isEmpty) {
        notifyListeners();
      }
      return false;
    }

    var changed = false;
    for (final row in rows) {
      final entry = ThreadListEntry.fromDatasetRow(row);
      if (entry != null) {
        _entriesByPath[entry.path] = entry;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
    return false;
  }

  Future<void> _refreshEntries() async {
    if (_closed) {
      return;
    }
    final table = await room.datasets.searchTable(
      table: ref.table,
      namespace: ref.namespace,
      select: const ['path', 'name', 'created_at', 'modified_at'],
    );
    if (_closed) {
      return;
    }
    final nextEntries = <String, ThreadListEntry>{};
    for (final row in table.toRows()) {
      final entry = ThreadListEntry.fromDatasetRow(row);
      if (entry != null) {
        nextEntries[entry.path] = entry;
      }
    }
    _entriesByPath
      ..clear()
      ..addAll(nextEntries);
    if (!_closed) {
      notifyListeners();
    }
  }

  ArrowRecordBatch _batchFor(List<ThreadListEntry> entries) {
    return ArrowRecordBatch.fromColumns(
      schema: schema,
      columns: [
        ArrowValueArray(
          field: schema.fields[0],
          values: entries.map((entry) => entry.path).toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[1],
          values: entries.map((entry) => entry.name).toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[2],
          values: entries
              .map((entry) => entry.createdAt)
              .toList(growable: false),
        ),
        ArrowValueArray(
          field: schema.fields[3],
          values: entries
              .map((entry) => entry.modifiedAt)
              .toList(growable: false),
        ),
      ],
    );
  }
}

class AgentThreadStorageRepository extends ThreadStorageRepository {
  AgentThreadStorageRepository({required this.chatClient, this.limit = 200});

  final BaseChatClient chatClient;
  final int limit;
  final Map<String, ThreadListEntry> _entriesByPath =
      <String, ThreadListEntry>{};
  StreamSubscription<AgentMessageEvent>? _subscription;
  Completer<void>? _pendingOpen;
  String? _pendingListMessageId;
  bool _closed = true;

  @override
  Future<void> open() async {
    if (!_closed) {
      return;
    }
    _closed = false;
    _subscription = chatClient.events.listen(_handleEvent);
    final ready = Completer<void>();
    _pendingOpen = ready;
    await chatClient.sendAgentMessage(WatchThreads(), ignoreOffline: true);
    await _requestList();
    await ready.future;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final subscription = _subscription;
    _subscription = null;
    _pendingListMessageId = null;
    final pendingOpen = _pendingOpen;
    _pendingOpen = null;
    if (pendingOpen != null && !pendingOpen.isCompleted) {
      pendingOpen.complete();
    }
    await chatClient
        .sendAgentMessage(UnwatchThreads(), ignoreOffline: true)
        .catchError((_) {});
    await subscription?.cancel();
  }

  @override
  List<ThreadListEntry> entries() => _entriesByPath.values.toList();

  @override
  Future<void> addOrUpdateThread(ThreadListEntry entry) {
    throw UnsupportedError(
      'Agent thread storage cannot directly upsert thread entries.',
    );
  }

  @override
  Future<void> deleteThread(String threadPath) async {
    final normalized = _normalizeThreadPath(threadPath);
    await chatClient.sendAgentMessage(DeleteThread(threadId: normalized));
    if (_entriesByPath.remove(normalized) != null) {
      notifyListeners();
    }
    unawaited(_requestList());
  }

  @override
  Future<void> renameThread(String threadPath, String name) async {
    final normalized = _normalizeThreadPath(threadPath);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'thread name cannot be empty');
    }
    await chatClient.sendAgentMessage(
      RenameThread(threadId: normalized, name: trimmedName),
    );
    final existing = _entriesByPath[normalized];
    if (existing != null) {
      _entriesByPath[normalized] = existing.renamed(
        trimmedName,
        DateTime.now().toUtc().toIso8601String(),
      );
      notifyListeners();
    }
    unawaited(_requestList());
  }

  Future<void> _requestList() async {
    if (_closed) {
      return;
    }
    final request = ListThreads(limit: limit);
    _pendingListMessageId = request.messageId;
    await chatClient.sendAgentMessage(request, ignoreOffline: true);
  }

  void _handleEvent(AgentMessageEvent event) {
    final message = event.message;
    if (message is AgentConnectionStatus) {
      final status = message.status.trim().toLowerCase();
      if (status == 'connected' || status == 'reconnected') {
        unawaited(_reconnectWatch());
      }
      return;
    }
    if (message is ThreadsListed) {
      _handleThreadsListed(message);
      return;
    }
    if (message is ThreadStarted) {
      unawaited(_requestList());
      return;
    }
    if (message is ThreadCreated) {
      _upsertThread(message.thread);
      return;
    }
    if (message is ThreadUpdated) {
      _upsertThread(message.thread);
      return;
    }
    if (message is ThreadDeleted) {
      final normalized = _normalizeThreadPath(message.path);
      if (_entriesByPath.remove(normalized) != null && !_closed) {
        notifyListeners();
      }
    }
  }

  Future<void> _reconnectWatch() async {
    if (_closed) {
      return;
    }
    await chatClient.sendAgentMessage(WatchThreads(), ignoreOffline: true);
    await _requestList();
  }

  void _handleThreadsListed(ThreadsListed message) {
    final nextEntries = <String, ThreadListEntry>{};
    for (final thread in message.threads) {
      final entry = _entryFromAgentThread(thread);
      if (entry != null) {
        nextEntries[entry.path] = entry;
      }
    }
    _entriesByPath
      ..clear()
      ..addAll(nextEntries);
    final pendingOpen = _pendingOpen;
    if (pendingOpen != null &&
        !pendingOpen.isCompleted &&
        (_pendingListMessageId == null ||
            message.sourceMessageId == _pendingListMessageId)) {
      pendingOpen.complete();
      _pendingOpen = null;
    }
    if (!_closed) {
      notifyListeners();
    }
  }

  void _upsertThread(AgentThreadListEntry thread) {
    final entry = _entryFromAgentThread(thread);
    if (entry == null) {
      return;
    }
    _entriesByPath[entry.path] = entry;
    if (!_closed) {
      notifyListeners();
    }
  }

  ThreadListEntry? _entryFromAgentThread(AgentThreadListEntry thread) {
    final path = thread.path.trim();
    if (path.isEmpty) {
      return null;
    }
    final name = thread.name.trim();
    return ThreadListEntry(
      path: path,
      name: name.isNotEmpty ? name : defaultThreadDisplayNameFromPath(path),
      createdAt: thread.createdAt,
      modifiedAt: thread.modifiedAt,
    );
  }
}

class DatasetThreadStorage extends DatasetThreadStorageRepository {
  DatasetThreadStorage({required super.room, required super.path});
}

String defaultThreadDisplayNameFromPath(String path) {
  final segments = path.split('/').where((segment) => segment.isNotEmpty);
  final basename = segments.isEmpty ? path : segments.last;
  final rawName = basename.endsWith('.thread')
      ? basename.substring(0, basename.length - '.thread'.length)
      : basename;
  final trimmed = rawName.trim();
  if (trimmed.isEmpty || _uuidPattern.hasMatch(trimmed)) {
    return defaultUntitledThreadName;
  }

  final normalized = trimmed
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) {
    return defaultUntitledThreadName;
  }

  return normalized
      .split(' ')
      .where((segment) => segment.isNotEmpty)
      .map(
        (segment) => segment.length == 1
            ? segment.toUpperCase()
            : '${segment[0].toUpperCase()}${segment.substring(1)}',
      )
      .join(' ');
}

String _normalizeThreadPath(String threadPath) {
  final normalized = threadPath.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      threadPath,
      'threadPath',
      'thread path cannot be empty',
    );
  }
  return normalized;
}

String _pathWhere(String threadPath) {
  return 'path = ${_datasetStringLiteral(threadPath)}';
}

String _datasetStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String? _threadPathFromDeletePredicate(String? predicate) {
  final trimmed = predicate?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'''^path\s*=\s*(['"])(.*)\1$''',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  return match.group(2)?.replaceAll("''", "'");
}
