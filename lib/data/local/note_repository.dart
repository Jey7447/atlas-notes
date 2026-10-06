import 'package:drift/drift.dart';

import 'atlas_database.dart';

class NoteRepository {
  NoteRepository(this.db);

  final AtlasDatabase db;

  Stream<List<Note>> watchRecentNotes({int limit = 20}) {
    final query = db.select(db.notes)
      ..where((n) => n.deletedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
      ..limit(limit);
    return query.watch();
  }

  Future<Note?> getNote(String noteId) {
    return (db.select(db.notes)..where((n) => n.id.equals(noteId))).getSingleOrNull();
  }

  Future<String> createBlankNote({
    required String workspaceId,
    String title = 'Untitled note',
    String? notebookId,
  }) async {
    final id = await db.createNote(
      workspaceId: workspaceId,
      title: title,
      notebookId: notebookId,
    );
    return id;
  }

  Future<void> updateContent(
    String noteId, {
    String? title,
    String? body,
    bool? pinned,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: body == null ? const Value.absent() : Value(body),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> moveToNotebook(String noteId, String? notebookId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(
        notebookId: Value(notebookId),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> updateTitle(String noteId, String title) async {
    await updateContent(noteId, title: title);
  }

  Future<void> moveToTrash(String noteId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }
}
