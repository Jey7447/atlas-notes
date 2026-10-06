import 'package:drift/drift.dart';

import 'atlas_database.dart';

class SearchRepository {
  SearchRepository(this.db);

  final AtlasDatabase db;

  Future<List<Note>> searchNotes(
    String query, {
    int limit = 50,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return db.recentNotes(limit: limit);

    final pattern = '%$normalized%';
    return (db.select(db.notes)
          ..where(
            (note) =>
                note.deletedAt.isNull() &
                (note.title.like(pattern) | note.body.like(pattern)),
          )
          ..orderBy([(note) => OrderingTerm.desc(note.updatedAt)])
          ..limit(limit))
        .get();
  }
}
