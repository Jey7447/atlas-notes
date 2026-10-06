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

  Future<Page?> getFirstPage(String noteId) {
    final query = db.select(db.pages)
      ..where((p) => p.noteId.equals(noteId))
      ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)])
      ..limit(1);
    return query.getSingleOrNull();
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

  Future<Page?> getPage(String pageId) async {
    return (db.select(db.pages)..where((p) => p.id.equals(pageId))).getSingleOrNull();
  }

  Future<String?> duplicatePage(String pageId) async {
    final source = await getPage(pageId);
    if (source == null) return null;
    final existing = await (db.select(db.pages)
          ..where((p) => p.noteId.equals(source.noteId))
          ..orderBy([(p) => OrderingTerm.desc(p.pageIndex)])
          ..limit(1))
        .getSingleOrNull();
    final nextIndex = (existing?.pageIndex ?? -1) + 1;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'page_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.pages).insert(
      PagesCompanion.insert(
        id: id,
        noteId: source.noteId,
        pageIndex: nextIndex,
        title: Value(source.title == null ? null : source.title! + ' copy'),
        template: Value(source.template),
        width: Value(source.width),
        contentJson: Value(source.contentJson),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> deletePage(String pageId) async {
    final page = await getPage(pageId);
    if (page == null) return;
    final count = await (db.select(db.pages)..where((p) => p.noteId.equals(page.noteId))).get();
    if (count.length <= 1) return;
    await (db.delete(db.pages)..where((p) => p.id.equals(pageId))).go();
    final pages = await (db.select(db.pages)
          ..where((p) => p.noteId.equals(page.noteId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].pageIndex != i) {
        await (db.update(db.pages)..where((p) => p.id.equals(pages[i].id))).write(
          PagesCompanion(pageIndex: Value(i), updatedAt: Value(DateTime.now().toUtc().toIso8601String())),
        );
      }
    }
  }

  Future<void> movePage(String pageId, int direction) async {
    final page = await getPage(pageId);
    if (page == null) return;
    final targetIndex = page.pageIndex + direction;
    if (targetIndex < 0) return;
    final target = await (db.select(db.pages)
          ..where((p) => p.noteId.equals(page.noteId) & p.pageIndex.equals(targetIndex))
          ..limit(1))
        .getSingleOrNull();
    if (target == null) return;
    await db.transaction(() async {
      await (db.update(db.pages)..where((p) => p.id.equals(page.id))).write(PagesCompanion(pageIndex: Value(targetIndex)));
      await (db.update(db.pages)..where((p) => p.id.equals(target.id))).write(PagesCompanion(pageIndex: Value(page.pageIndex)));
    });
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
