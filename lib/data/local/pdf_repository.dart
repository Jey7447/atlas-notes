import 'dart:convert';

import 'package:drift/drift.dart';

import 'atlas_database.dart';

class PdfRepository {
  PdfRepository(this.db);

  final AtlasDatabase db;

  Stream<List<PdfDocument>> watchDocuments(String workspaceId) {
    return (db.select(db.pdfDocuments)
          ..where((p) => p.workspaceId.equals(workspaceId))
          ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]))
        .watch();
  }

  Future<PdfDocument?> getDocument(String id) {
    return (db.select(db.pdfDocuments)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> createDocument({
    required String workspaceId,
    required String name,
    String? noteId,
    String? localPath,
    int pageCount = 0,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'pdf_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.pdfDocuments).insert(
      PdfDocumentsCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        noteId: Value(noteId),
        name: name,
        pageCount: Value(pageCount),
        localPath: Value(localPath),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _queue(id, 'upsert', {
      'id': id,
      'workspaceId': workspaceId,
      'noteId': noteId,
      'name': name,
      'pageCount': pageCount,
      'localPath': localPath,
    });
    return id;
  }

  Future<void> updatePageCount(String id, int pageCount) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (db.update(db.pdfDocuments)..where((p) => p.id.equals(id))).write(
      PdfDocumentsCompanion(
        pageCount: Value(pageCount),
        updatedAt: Value(now),
      ),
    );
    await _queue(id, 'upsert', {'id': id, 'pageCount': pageCount});
  }

  Future<void> saveAnnotation({
    required String pdfId,
    required int pageNumber,
    required String kind,
    required Map<String, dynamic> payload,
    String? id,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final annotationId = id ?? 'pdfann_${DateTime.now().microsecondsSinceEpoch}';
    await db.into(db.pdfAnnotations).insertOnConflictUpdate(
      PdfAnnotationsCompanion.insert(
        id: annotationId,
        pdfId: pdfId,
        pageNumber: pageNumber,
        kind: kind,
        payloadJson: jsonEncode(payload),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _queue(annotationId, 'upsert', {
      'id': annotationId,
      'pdfId': pdfId,
      'pageNumber': pageNumber,
      'kind': kind,
      'payload': payload,
    });
  }

  Stream<List<PdfAnnotation>> watchAnnotations(String pdfId, int pageNumber) {
    return (db.select(db.pdfAnnotations)
          ..where((a) => a.pdfId.equals(pdfId) & a.pageNumber.equals(pageNumber))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .watch();
  }

  Future<void> deleteAnnotation(String id) async {
    await (db.delete(db.pdfAnnotations)..where((a) => a.id.equals(id))).go();
    await _queue(id, 'delete', {'id': id});
  }

  Future<void> _queue(
    String entityId,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    await db.into(db.syncQueue).insert(
      SyncQueueCompanion.insert(
        entityType: 'pdf',
        entityId: entityId,
        operation: operation,
        payloadJson: Value(jsonEncode(payload)),
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }
}
