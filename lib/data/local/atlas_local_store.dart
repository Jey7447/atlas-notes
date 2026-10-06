import 'atlas_database.dart';

class AtlasLocalStore {
  AtlasLocalStore._();

  static final AtlasLocalStore instance = AtlasLocalStore._();

  final AtlasDatabase db = AtlasDatabase();

  static const defaultWorkspaceId = 'workspace_local_default';

  Future<void> initialize() async {
    final existing = await (db.select(db.workspaces)
          ..where((workspace) => workspace.id.equals(defaultWorkspaceId)))
        .getSingleOrNull();

    if (existing != null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await db.into(db.workspaces).insert(
      WorkspacesCompanion.insert(
        id: defaultWorkspaceId,
        name: 'My Workspace',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
