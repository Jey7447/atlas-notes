import 'package:flutter/material.dart';

import 'core/cloud/atlas_cloud.dart';
import 'data/local/atlas_local_store.dart';
import 'data/local/note_repository.dart';
import 'data/local/notebook_repository.dart';
import 'data/local/atlas_database.dart';
import 'data/local/search_repository.dart';

import 'features/canvas/canvas_editor_page.dart';
import 'features/editor/note_editor_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AtlasCloud.initialize();
  await AtlasLocalStore.instance.initialize();
  runApp(const AtlasNotesApp());
}

class AtlasNotesApp extends StatelessWidget {
  const AtlasNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B5BD6);
    return MaterialApp(
      title: 'Atlas Notes',
      debugShowCheckedModeBanner: false,
      theme: _theme(seed, Brightness.light),
      darkTheme: _theme(seed, Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AtlasShell(),
    );
  }

  ThemeData _theme(Color seed, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF8F8FB)
          : const Color(0xFF111113),
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class AtlasShell extends StatefulWidget {
  const AtlasShell({super.key});

  @override
  State<AtlasShell> createState() => _AtlasShellState();
}

class _AtlasShellState extends State<AtlasShell> {
  int index = 0;

  static const destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Notebooks'),
    NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud_rounded), label: 'Cloud'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onNewNote: _createNote, onCanvas: _openCanvas),
      const NotebooksPage(),
      const SearchPage(),
      const CloudPage(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tablet = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Atlas Notes', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(tooltip: 'New note', onPressed: _createNote, icon: const Icon(Icons.add_rounded)),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (tablet)
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) => setState(() => index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text('Home')),
                    NavigationRailDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: Text('Notebooks')),
                    NavigationRailDestination(icon: Icon(Icons.search_rounded), label: Text('Search')),
                    NavigationRailDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud_rounded), label: Text('Cloud')),
                  ],
                ),
              Expanded(child: IndexedStack(index: index, children: pages)),
            ],
          ),
          bottomNavigationBar: tablet
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  destinations: destinations,
                  onDestinationSelected: (value) => setState(() => index = value),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _createNote,
            icon: const Icon(Icons.edit_rounded),
            label: const Text('New note'),
          ),
        );
      },
    );
  }

  Future<void> _createNote() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NoteEditorPage()),
    );
  }

  Future<void> _openCanvas() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CanvasEditorPage()),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNewNote, required this.onCanvas});

  final VoidCallback onNewNote;
  final VoidCallback onCanvas;

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Good to have you back.',
      subtitle: 'Everything you write stays available offline and will sync when cloud is connected.',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final cards = [
              _ActionCard(icon: Icons.edit_note_rounded, title: 'Quick Capture', subtitle: 'Start writing immediately.', onTap: onNewNote),
              _ActionCard(icon: Icons.draw_rounded, title: 'Canvas', subtitle: 'Open an infinite canvas.', onTap: onCanvas),
            ];
            if (compact) return Column(children: [cards[0], const SizedBox(height: 12), cards[1]]);
            return Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]);
          },
        ),
        const SizedBox(height: 24),
        Text('Recent', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        StreamBuilder<List<Note>>(
          stream: NoteRepository(AtlasLocalStore.instance.db).watchRecentNotes(),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const [];
            if (notes.isEmpty) {
              return const _EmptyState(
                icon: Icons.history_rounded,
                title: 'No notes yet',
                subtitle: 'Your recently opened notes will appear here.',
              );
            }
            return Column(
              children: [
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(note.title),
                        subtitle: Text(note.body.isEmpty ? 'No text yet' : note.body),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteEditorPage(
                              noteId: note.id,
                              initialTitle: note.title,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class NotebooksPage extends StatefulWidget {
  const NotebooksPage({super.key});

  @override
  State<NotebooksPage> createState() => _NotebooksPageState();
}

class _NotebooksPageState extends State<NotebooksPage> {
  final repository = NotebookRepository(AtlasLocalStore.instance.db);

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Notebooks',
      subtitle: 'Organize notes into notebooks and folders.',
      children: [
        _ActionCard(
          icon: Icons.create_new_folder_outlined,
          title: 'Create a notebook',
          subtitle: 'Start a notebook for a course, project, or topic.',
          onTap: _createNotebook,
        ),
        const SizedBox(height: 24),
        StreamBuilder<List<Notebook>>(
          stream: repository.watchNotebooks(AtlasLocalStore.defaultWorkspaceId),
          builder: (context, snapshot) {
            final notebooks = snapshot.data ?? const <Notebook>[];
            if (notebooks.isEmpty) {
              return const _EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No notebooks yet',
                subtitle: 'Create your first notebook to start organizing notes.',
              );
            }
            return Column(
              children: [
                for (final notebook in notebooks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_rounded),
                        title: Text(notebook.name),
                        subtitle: StreamBuilder<List<Note>>(
                          stream: repository.watchNotes(notebook.id),
                          builder: (context, noteSnapshot) {
                            final count = noteSnapshot.data?.length ?? 0;
                            return Text(
                              count.toString() + (count == 1 ? ' note' : ' notes'),
                            );
                          },
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NotebookDetailPage(
                              notebookId: notebook.id,
                              notebookName: notebook.name,
                            ),
                          ),
                        ),
                        onLongPress: () => _renameNotebook(notebook.id, notebook.name),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _createNotebook() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New notebook'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Notebook name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await repository.createNotebook(
      workspaceId: AtlasLocalStore.defaultWorkspaceId,
      name: name.trim(),
    );
  }

  Future<void> _renameNotebook(String id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename notebook'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await repository.renameNotebook(id, name);
  }
}

class NotebookDetailPage extends StatelessWidget {
  const NotebookDetailPage({
    super.key,
    required this.notebookId,
    required this.notebookName,
  });

  final String notebookId;
  final String notebookName;

  @override
  Widget build(BuildContext context) {
    final repository = NotebookRepository(AtlasLocalStore.instance.db);
    return Scaffold(
      appBar: AppBar(
        title: Text(notebookName),
        actions: [
          IconButton(
            tooltip: 'New note',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NoteEditorPage(notebookId: notebookId),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteEditorPage(notebookId: notebookId),
          ),
        ),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New note'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Note>>(
          stream: repository.watchNotes(notebookId),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const <Note>[];
            if (notes.isEmpty) {
              return const Center(
                child: _EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No notes in this notebook',
                  subtitle: 'Create a note and it will appear here automatically.',
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(note.title),
                    subtitle: Text(
                      note.body.isEmpty ? 'No text yet' : note.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: note.pinned
                        ? const Icon(Icons.push_pin_rounded, size: 18)
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NoteEditorPage(
                          noteId: note.id,
                          initialTitle: note.title,
                          notebookId: notebookId,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  String query = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = SearchRepository(AtlasLocalStore.instance.db);
    return _PageFrame(
      title: 'Search',
      subtitle: 'Deterministic search across titles and note text.',
      children: [
        TextField(
          controller: controller,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: 'Search notes…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<Note>>(
          future: repository.searchNotes(query),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const <Note>[];
            if (notes.isEmpty) {
              return const _EmptyState(
                icon: Icons.manage_search_rounded,
                title: 'No matching notes',
                subtitle: 'Search uses exact local text matching and never requires AI.',
              );
            }
            return Column(
              children: [
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(note.title),
                        subtitle: Text(
                          note.body.isEmpty ? 'No text yet' : note.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteEditorPage(
                              noteId: note.id,
                              initialTitle: note.title,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CloudPage extends StatelessWidget {
  const CloudPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Cloud',
      subtitle: 'Sync and backup will connect here once the Supabase project is available.',
      children: [
        const _StatusCard(icon: Icons.cloud_off_rounded, title: 'Cloud not connected', body: 'Atlas Notes is being built local-first. Your notes will remain usable without a connection.'),
        const SizedBox(height: 12),
        const _StatusCard(icon: Icons.security_rounded, title: 'Private by design', body: 'Authentication, row-level security, private storage and signed access will be added in the cloud layer.'),
      ],
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 120),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 28),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
