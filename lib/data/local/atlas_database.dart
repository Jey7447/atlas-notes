import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'atlas_database.g.dart';

class Workspaces extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get notebookId => text().nullable()();
  TextColumn get folderId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get kind => text()();
  TextColumn get body => text().withDefault(const Constant(''))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  IntColumn get pageIndex => integer()();
  TextColumn get title => text().nullable()();
  TextColumn get template => text().withDefault(const Constant('blank'))();
  TextColumn get width => text().withDefault(const Constant('a4'))();
  TextColumn get contentJson => text().withDefault(const Constant('{}'))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteTags extends Table {
  TextColumn get noteId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get pageId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get localPath => text().nullable()();
  TextColumn get remotePath => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class PdfDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get name => text()();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get localPath => text().nullable()();
  TextColumn get remotePath => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class PdfAnnotations extends Table {
  TextColumn get id => text()();
  TextColumn get pdfId => text()();
  IntColumn get pageNumber => integer()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get sequence => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get createdAt => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DriftDatabase(
  tables: [
    Workspaces,
    Folders,
    Notebooks,
    Notes,
    Pages,
    Tags,
    NoteTags,
    Assets,
    PdfDocuments,
    PdfAnnotations,
    SyncQueue,
  ],
)
class AtlasDatabase extends _$AtlasDatabase {
  AtlasDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pdfDocuments);
            await m.createTable(pdfAnnotations);
          }
        },
      );

  Future<List<Note>> recentNotes({int limit = 20}) {
    return (select(notes)
          ..where((n) => n.deletedAt.isNull())
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
          ..limit(limit))
        .get();
  }

  Future<String> createNote({
    required String workspaceId,
    required String title,
    String kind = 'page',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'note_${now}_${DateTime.now().microsecondsSinceEpoch}';
    await into(notes).insert(
      NotesCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        title: title,
        kind: kind,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        entityType: 'note',
        entityId: id,
        operation: 'upsert',
        payloadJson: Value(jsonEncode({'id': id, 'title': title, 'kind': kind})),
        createdAt: now,
      ),
    );
    return id;
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'atlas_notes',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.dart.js'),
    ),
  );
}
