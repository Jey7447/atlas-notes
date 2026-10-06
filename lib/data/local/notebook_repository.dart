import 'package:drift/drift.dart';

import 'atlas_database.dart';

class NotebookRepository {
  NotebookRepository(this.db);

  final AtlasDatabase db;

  Stream<List<Notebook>> watchNotebooks(String workspaceId) {
    final query = db.select(db.notebooks)
      ..where((n) => n.workspaceId.equals(workspaceId))
      ..orderBy([(n) => OrderingTerm.asc(n.name)]);
    return query.watch();
  }

  Stream<List<Note>> watchNotes(String notebookId) {
    final query = db.select(db.notes)
      ..where((n) => n.notebookId.equals(notebookId) & n.deletedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return query.watch();
  }

  Stream<List<Page>> watchPages(String noteId) {
    final query = db.select(db.pages)
      ..where((p) => p.noteId.equals(noteId))
      ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]);
    return query.watch();
  }

  Future<String> createNotebook({
    required String workspaceId,
    String name = 'Untitled notebook',
    String? folderId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'notebook_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.notebooks).insert(
      NotebooksCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        folderId: Value(folderId),
        name: name,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.syncQueue).insert(
      SyncQueueCompanion.insert(
        entityType: 'notebook',
        entityId: id,
        operation: 'upsert',
        payloadJson: Value(
          '{"id":"$id","workspaceId":"$workspaceId","name":"${_escape(name)}"}',
        ),
        createdAt: now,
      ),
    );
    return id;
  }

  Future<String> createPage({
    required String noteId,
    String? title,
    String template = 'blank',
    String width = 'a4',
  }) async {
    final existing = await (db.select(db.pages)
          ..where((p) => p.noteId.equals(noteId))
          ..orderBy([(p) => OrderingTerm.desc(p.pageIndex)])
          ..limit(1))
        .getSingleOrNull();

    final nextIndex = (existing?.pageIndex ?? -1) + 1;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'page_${DateTime.now().microsecondsSinceEpoch}';

    await db.into(db.pages).insert(
      PagesCompanion.insert(
        id: id,
        noteId: noteId,
        pageIndex: nextIndex,
        title: Value(title),
        template: Value(template),
        width: Value(width),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> renameNotebook(String notebookId, String name) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.notebooks)..where((n) => n.id.equals(notebookId))).write(
      NotebooksCompanion(
        name: Value(name.trim().isEmpty ? 'Untitled notebook' : name.trim()),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteNotebook(String notebookId) async {
    await (db.update(db.notes)..where((n) => n.notebookId.equals(notebookId))).write(
      const NotesCompanion(notebookId: Value(null)),
    );
    await (db.delete(db.notebooks)..where((n) => n.id.equals(notebookId))).go();
  }

  String _escape(String value) => value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
