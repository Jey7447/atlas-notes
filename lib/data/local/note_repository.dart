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

  Future<String> createBlankNote({
    required String workspaceId,
    String title = 'Untitled note',
  }) {
    return db.createNote(
      workspaceId: workspaceId,
      title: title,
    );
  }

  Future<void> updateTitle(String noteId, String title) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(
        title: Value(title),
        updatedAt: Value(now),
      ),
    );
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
