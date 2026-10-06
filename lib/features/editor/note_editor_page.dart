import 'dart:async';

import 'package:flutter/material.dart';

import '../canvas/canvas_editor_page.dart';
import '../../data/local/atlas_local_store.dart';
import '../../data/local/note_repository.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    this.initialTitle = 'Untitled note',
    this.noteId,
    this.notebookId,
  });

  final String initialTitle;
  final String? noteId;
  final String? notebookId;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController titleController;
  late final TextEditingController bodyController;
  late final NoteRepository repository;

  bool pinned = false;
  bool saved = true;
  bool _loading = true;
  String? _noteId;
  Timer? _saveTimer;
  int _saveGeneration = 0;

  @override
  void initState() {
    super.initState();
    repository = NoteRepository(AtlasLocalStore.instance.db);
    _noteId = widget.noteId;
    titleController = TextEditingController(text: widget.initialTitle);
    bodyController = TextEditingController();
    titleController.addListener(_markDirty);
    bodyController.addListener(_markDirty);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await AtlasLocalStore.instance.initialize();

    if (_noteId != null) {
      final note = await repository.getNote(_noteId!);
      if (!mounted) return;
      if (note != null) {
        _loading = true;
        titleController.value = TextEditingValue(text: note.title);
        bodyController.value = TextEditingValue(text: note.body);
        pinned = note.pinned;
      }
    } else {
      _noteId = await repository.createBlankNote(
        workspaceId: AtlasLocalStore.defaultWorkspaceId,
        title: titleController.text.trim().isEmpty
            ? 'Untitled note'
            : titleController.text.trim(),
        notebookId: widget.notebookId,
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
        saved = true;
      });
    }
  }

  void _markDirty() {
    if (_loading) return;
    if (saved) setState(() => saved = false);
    _saveTimer?.cancel();
    final generation = ++_saveGeneration;
    _saveTimer = Timer(
      const Duration(milliseconds: 350),
      () => _persist(generation),
    );
  }

  Future<void> _persist(int generation) async {
    final id = _noteId;
    if (id == null) return;
    await repository.updateContent(
      id,
      title: titleController.text,
      body: bodyController.text,
      pinned: pinned,
    );
    if (mounted && generation == _saveGeneration) {
      setState(() => saved = true);
    }
  }

  void _flushPendingSave() {
    _saveTimer?.cancel();
    final id = _noteId;
    if (id == null || _loading) return;
    final title = titleController.text;
    final body = bodyController.text;
    final pinState = pinned;
    unawaited(
      repository.updateContent(
        id,
        title: title,
        body: body,
        pinned: pinState,
      ),
    );
  }

  @override
  void dispose() {
    _flushPendingSave();
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(_loading ? 'Loading…' : (saved ? 'Saved' : 'Unsaved changes')),
        actions: [
          IconButton(
            tooltip: pinned ? 'Unpin note' : 'Pin note',
            onPressed: _loading
                ? null
                : () {
                    setState(() => pinned = !pinned);
                    _markDirty();
                  },
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: _loading ? null : () => _showMore(context),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 140),
                    children: [
                      TextField(
                        controller: titleController,
                        enabled: !_loading,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        decoration: const InputDecoration(
                          hintText: 'Untitled note',
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: bodyController,
                        enabled: !_loading,
                        minLines: 16,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Start writing…',
                          border: InputBorder.none,
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
                _EditorToolbar(
                  onBold: () => _wrapSelection('**'),
                  onItalic: () => _wrapSelection('_'),
                  onBullet: () => _insertAtCursor('• '),
                  onCanvas: _openCanvas,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCanvas() {
    final id = _noteId;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanvasEditorPage(noteId: id),
      ),
    );
  }

  void _wrapSelection(String marker) {
    final value = bodyController.value;
    if (!value.selection.isValid || value.selection.isCollapsed) return;
    final selected = value.text.substring(value.selection.start, value.selection.end);
    bodyController.value = value.replaced(
      value.selection,
      '$marker$selected$marker',
    );
  }

  void _insertAtCursor(String text) {
    final value = bodyController.value;
    final start = value.selection.isValid ? value.selection.start : value.text.length;
    final end = value.selection.isValid ? value.selection.end : value.text.length;
    bodyController.value = value.replaced(
      TextRange(start: start, end: end),
      text,
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Version history'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Export'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Move to trash'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.onBold,
    required this.onItalic,
    required this.onBullet,
    required this.onCanvas,
  });

  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onBullet;
  final VoidCallback onCanvas;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(tooltip: 'Bold', onPressed: onBold, icon: const Icon(Icons.format_bold)),
              IconButton(tooltip: 'Italic', onPressed: onItalic, icon: const Icon(Icons.format_italic)),
              IconButton(tooltip: 'Bullet list', onPressed: onBullet, icon: const Icon(Icons.format_list_bulleted)),
              const VerticalDivider(width: 20),
              IconButton(tooltip: 'Open canvas', onPressed: onCanvas, icon: const Icon(Icons.draw_rounded)),
              IconButton(tooltip: 'Add image', onPressed: () {}, icon: const Icon(Icons.image_outlined)),
              IconButton(tooltip: 'Attach file', onPressed: () {}, icon: const Icon(Icons.attach_file_rounded)),
              IconButton(tooltip: 'Record audio', onPressed: () {}, icon: const Icon(Icons.mic_none_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}
