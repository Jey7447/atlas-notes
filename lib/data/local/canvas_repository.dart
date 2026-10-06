import 'dart:convert';

import '../../core/models/canvas_document.dart';
import 'atlas_database.dart';

class CanvasRepository {
  CanvasRepository(this.db);

  final AtlasDatabase db;

  Future<void> savePageDocument({
    required String pageId,
    required String noteId,
    required int pageIndex,
    required CanvasDocument document,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final json = jsonEncode(document.toJson());

    await db.into(db.pages).insertOnConflictUpdate(
      PagesCompanion.insert(
        id: pageId,
        noteId: noteId,
        pageIndex: pageIndex,
        contentJson: Value(json),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.syncQueue).insert(
      SyncQueueCompanion.insert(
        entityType: 'page',
        entityId: pageId,
        operation: 'upsert',
        payloadJson: Value(jsonEncode({
          'id': pageId,
          'note_id': noteId,
          'page_index': pageIndex,
          'content': document.toJson(),
        })),
        createdAt: now,
      ),
    );
  }

  Future<CanvasDocument?> loadPageDocument(String pageId) async {
    final row = await (db.select(db.pages)
          ..where((page) => page.id.equals(pageId)))
        .getSingleOrNull();

    if (row == null || row.contentJson.isEmpty) return null;

    try {
      return CanvasDocument.fromJson(
        jsonDecode(row.contentJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
