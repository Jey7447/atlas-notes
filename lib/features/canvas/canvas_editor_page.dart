import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/canvas_document.dart';
import '../../data/local/atlas_local_store.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../data/local/atlas_database.dart' as atlas_db;
import '../../data/local/canvas_repository.dart';
import '../../data/local/note_repository.dart';
import '../../data/local/notebook_repository.dart';

class CanvasEditorPage extends StatefulWidget {
  const CanvasEditorPage({super.key, this.noteId, this.pageId});

  final String? noteId;
  final String? pageId;
  @override
  State<CanvasEditorPage> createState() => _CanvasEditorPageState();
}

enum _SelectionInteraction { none, move, resize, rotate }
enum _SelectionMode { replace, add, subtract }

class _CanvasEditorPageState extends State<CanvasEditorPage> {
  CanvasDocument _document = const CanvasDocument();
  late final CanvasRepository _repository;
  late final NoteRepository _noteRepository;
  late final NotebookRepository _notebookRepository;
  String? _noteId;
  String? _pageId;
  int _pageIndex = 0;
  bool _loading = true;
  bool _saved = true;
  Timer? _saveTimer;
  final List<CanvasDocument> _undo = [];
  final List<CanvasDocument> _redo = [];
  CanvasTool _tool = CanvasTool.pen;
  CanvasPenStyle _penStyle = CanvasPenStyle.ballpoint;
  Color _color = const Color(0xFF1F2430);
  double _width = 3;
  double _zoom = 1;
  late final TransformationController _transformController;
  CanvasStroke? _activeStroke;
  Offset? _shapeStart;
  Offset? _shapeCurrent;
  final List<Offset> _lassoPoints = [];
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  final Set<String> _selectedIds = <String>{};
  _SelectionMode _selectionMode = _SelectionMode.replace;

  Set<String> get _editableSelectionIds => _selectedIds.difference(_document.lockedIds);
  Offset? _selectionMoveLast;
  bool _movingSelection = false;
  _SelectionInteraction _selectionInteraction = _SelectionInteraction.none;
  CanvasDocument? _selectionStartDocument;
  Rect? _selectionStartBounds;
  Offset? _selectionStartPoint;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _repository = CanvasRepository(AtlasLocalStore.instance.db);
    _noteRepository = NoteRepository(AtlasLocalStore.instance.db);
    _notebookRepository = NotebookRepository(AtlasLocalStore.instance.db);
    _noteId = widget.noteId;
    _pageId = widget.pageId;
    unawaited(_initializeDocument());
  }

  Future<void> _initializeDocument() async {
    await AtlasLocalStore.instance.initialize();
    if (_noteId == null) {
      _noteId = await _noteRepository.createBlankNote(
        workspaceId: AtlasLocalStore.defaultWorkspaceId,
        title: 'Canvas',
      );
    }

    if (_pageId == null) {
      final page = await _notebookRepository.getFirstPage(_noteId!);
      if (page != null) {
        _pageId = page.id;
        _pageIndex = page.pageIndex;
      } else {
        _pageId = await _notebookRepository.createPage(noteId: _noteId!);
      }
    }

    final id = _pageId;
    if (id != null) {
      final document = await _repository.loadPageDocument(id);
      if (document != null) _document = document;
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _saved = true;
      });
    }
  }

  void _scheduleSave() {
    if (_loading || _pageId == null || _noteId == null) return;
    _saveTimer?.cancel();
    setState(() => _saved = false);
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveDocument);
  }

  Future<void> _switchPage(atlas_db.Page page) async {
    if (page.id == _pageId) return;
    await _saveDocument();
    final document = await _repository.loadPageDocument(page.id);
    if (!mounted) return;
    setState(() {
      _pageId = page.id;
      _pageIndex = page.pageIndex;
      _document = document ?? const CanvasDocument();
      _activeStroke = null;
      _shapeStart = null;
      _shapeCurrent = null;
      _undo.clear();
      _redo.clear();
      _saved = true;
    });
  }

  Future<void> _addPage() async {
    final noteId = _noteId;
    if (noteId == null) return;
    await _saveDocument();
    final id = await _notebookRepository.createPage(noteId: noteId);
    final page = await _notebookRepository.getPage(id);
    if (!mounted || page == null) return;
    await _switchPage(page);
  }

  Future<void> _duplicateCurrentPage() async {
    final pageId = _pageId;
    if (pageId == null) return;
    await _saveDocument();
    final id = await _notebookRepository.duplicatePage(pageId);
    if (!mounted || id == null) return;
    final page = await _notebookRepository.getPage(id);
    if (page != null) await _switchPage(page);
  }

  Future<void> _deleteCurrentPage() async {
    final noteId = _noteId;
    final pageId = _pageId;
    if (noteId == null || pageId == null) return;
    final pages = await (AtlasLocalStore.instance.db.select(AtlasLocalStore.instance.db.pages)
          ..where((p) => p.noteId.equals(noteId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    if (pages.length <= 1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A note must keep at least one page.')),
      );
      return;
    }
    final deletedIndex = pages.indexWhere((page) => page.id == pageId);
    await _saveDocument();
    await _notebookRepository.deletePage(pageId);
    final remaining = await (AtlasLocalStore.instance.db.select(AtlasLocalStore.instance.db.pages)
          ..where((p) => p.noteId.equals(noteId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    if (!mounted || remaining.isEmpty) return;
    final nextIndex = deletedIndex.clamp(0, remaining.length - 1);
    await _switchPage(remaining[nextIndex]);
  }

  Future<void> _moveCurrentPage(int direction) async {
    final pageId = _pageId;
    if (pageId == null) return;
    await _saveDocument();
    await _notebookRepository.movePage(pageId, direction);
    final page = await _notebookRepository.getPage(pageId);
    if (mounted && page != null) setState(() => _pageIndex = page.pageIndex);
  }

  Future<void> _showPageMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Duplicate page'), onTap: () => Navigator.pop(context, 'duplicate')),
            ListTile(leading: const Icon(Icons.arrow_back_rounded), title: const Text('Move page left'), onTap: () => Navigator.pop(context, 'left')),
            ListTile(leading: const Icon(Icons.arrow_forward_rounded), title: const Text('Move page right'), onTap: () => Navigator.pop(context, 'right')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete page'), onTap: () => Navigator.pop(context, 'delete')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'duplicate': await _duplicateCurrentPage();
      case 'left': await _moveCurrentPage(-1);
      case 'right': await _moveCurrentPage(1);
      case 'delete': await _deleteCurrentPage();
    }
  }

  Future<void> _saveDocument() async {
    final pageId = _pageId;
    final noteId = _noteId;
    if (pageId == null || noteId == null) return;
    await _repository.savePageDocument(
      pageId: pageId,
      noteId: noteId,
      pageIndex: _pageIndex,
      document: _document,
    );
    if (mounted) setState(() => _saved = true);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_loading && _pageId != null && _noteId != null) {
      unawaited(_repository.savePageDocument(
        pageId: _pageId!,
        noteId: _noteId!,
        pageIndex: _pageIndex,
        document: _document,
      ));
    }
    _transformController.dispose();
    super.dispose();
  }

  bool get _drawingTool =>
      _tool == CanvasTool.pen || _tool == CanvasTool.highlighter;

  bool get _selectionTool =>
      _tool == CanvasTool.lasso ||
      _tool == CanvasTool.rectangleSelection ||
      _tool == CanvasTool.circleSelection;

  void _pushHistory() {
    _undo.add(_document);
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_document);
      _document = _undo.removeLast();
    });
    _scheduleSave();
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_document);
      _document = _redo.removeLast();
    });
    _scheduleSave();
  }

  Offset _canvasPosition(PointerEvent event) => _transformController.toScene(event.localPosition);

  bool _near(Offset point, Offset target, {double radius = 18}) =>
      (point - target).distance <= radius;

  Offset? get _resizeHandle => _selectionBounds?.bottomRight;
  Offset? get _rotateHandle {
    final bounds = _selectionBounds;
    return bounds == null ? null : Offset(bounds.center.dx, bounds.top - 34);
  }

  void _beginSelectionTransform(_SelectionInteraction interaction, Offset point) {
    _pushHistory();
    setState(() {
      _selectionInteraction = interaction;
      _selectionStartDocument = _document;
      _selectionStartBounds = _selectionBounds;
      _selectionStartPoint = point;
      _movingSelection = interaction == _SelectionInteraction.move;
      _selectionMoveLast = _movingSelection ? point : null;
    });
  }

  void _finishSelectionTransform() {
    final active = _selectionInteraction != _SelectionInteraction.none;
    setState(() {
      _selectionInteraction = _SelectionInteraction.none;
      _selectionStartDocument = null;
      _selectionStartBounds = null;
      _selectionStartPoint = null;
      _selectionMoveLast = null;
      _movingSelection = false;
      _selectionInteraction = _SelectionInteraction.none;
      _selectionStartDocument = null;
      _selectionStartBounds = null;
      _selectionStartPoint = null;
    });
    if (active) _scheduleSave();
  }

  CanvasDocument _selectedDocument() => CanvasDocument(
    strokes: _document.strokes.where((s) => _selectedIds.contains(s.id)).toList(),
    texts: _document.texts.where((t) => _selectedIds.contains(t.id)).toList(),
    paperColor: _document.paperColor,
    showGrid: _document.showGrid,
    lockedIds: _selectedIds.intersection(_document.lockedIds),
  );

  Future<void> _copySelection({bool cut = false}) async {
    if (_selectedIds.isEmpty) return;
    final selected = _selectedDocument();
    await Clipboard.setData(ClipboardData(
      text: 'ATLAS_CANVAS_CLIPBOARD:' + jsonEncode(selected.toJson()),
    ));
    if (cut) {
      _pushHistory();
      setState(() {
        _document = _document.removeIds(_editableSelectionIds);
        _selectedIds.clear();
      });
      _scheduleSave();
    }
  }

  Future<void> _pasteSelection() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    const prefix = 'ATLAS_CANVAS_CLIPBOARD:';
    if (raw == null || !raw.startsWith(prefix)) return;
    try {
      final pasted = CanvasDocument.fromJson(
        jsonDecode(raw.substring(prefix.length)) as Map<String, dynamic>,
      );
      final ids = <String>{
        ...pasted.strokes.map((s) => s.id),
        ...pasted.texts.map((t) => t.id),
      };
      final moved = pasted.duplicateIds(ids, delta: const Offset(40, 40));
      final newStrokes = moved.strokes.where((s) => !pasted.strokes.any((p) => p.id == s.id)).toList();
      final newTexts = moved.texts.where((t) => !pasted.texts.any((p) => p.id == t.id)).toList();
      _pushHistory();
      setState(() {
        _document = CanvasDocument(
          strokes: [..._document.strokes, ...newStrokes],
          texts: [..._document.texts, ...newTexts],
          paperColor: _document.paperColor,
          showGrid: _document.showGrid,
          lockedIds: _document.lockedIds,
        );
        _selectedIds
          ..clear()
          ..addAll([...newStrokes.map((s) => s.id), ...newTexts.map((t) => t.id)]);
      });
      _scheduleSave();
    } catch (_) {
      // Ignore non-Atlas clipboard content.
    }
  }

  void _duplicateSelection() {
    if (_editableSelectionIds.isEmpty) return;
    _pushHistory();
    final before = _document;
    final duplicated = before.duplicateIds(_editableSelectionIds);
    final newIds = <String>{
      ...duplicated.strokes.where((s) => !before.strokes.any((b) => b.id == s.id)).map((s) => s.id),
      ...duplicated.texts.where((t) => !before.texts.any((b) => b.id == t.id)).map((t) => t.id),
    };
    setState(() {
      _document = duplicated;
      _selectedIds..clear()..addAll(newIds);
    });
    _scheduleSave();
  }

  void _deleteSelection() {
    if (_editableSelectionIds.isEmpty) return;
    _pushHistory();
    setState(() {
      _document = _document.removeIds(_editableSelectionIds);
      _selectedIds.clear();
    });
    _scheduleSave();
  }


  void _toggleSelectionLock() {
    if (_selectedIds.isEmpty) return;
    _pushHistory();
    final locked = _selectedIds.intersection(_document.lockedIds);
    setState(() {
      _document = locked.length == _selectedIds.length
          ? _document.unlockIds(_selectedIds)
          : _document.lockIds(_selectedIds);
    });
    _scheduleSave();
  }

  void _pointerDown(PointerDownEvent event) {
    final point = _canvasPosition(event);
    if (_selectionTool) {
      final selectionBounds = _selectionBounds;
      final resizeHandle = _resizeHandle;
      final rotateHandle = _rotateHandle;
      if (_selectedIds.isNotEmpty && _document.lockedIds.intersection(_selectedIds).isEmpty && selectionBounds != null) {
        if (rotateHandle != null && _near(point, rotateHandle)) {
          _beginSelectionTransform(_SelectionInteraction.rotate, point);
          return;
        }
        if (resizeHandle != null && _near(point, resizeHandle)) {
          _beginSelectionTransform(_SelectionInteraction.resize, point);
          return;
        }
        if (selectionBounds.inflate(18).contains(point)) {
          _beginSelectionTransform(_SelectionInteraction.move, point);
          return;
        }
      }
      setState(() {
        _lassoPoints
          ..clear()
          ..add(point);
        _selectionStart = point;
        _selectionCurrent = point;
        _selectedIds.clear();
        _selectionInteraction = _SelectionInteraction.none;
        _selectionStartDocument = null;
        _selectionStartBounds = null;
        _selectionStartPoint = null;
        _selectionMoveLast = null;
        _movingSelection = false;
      });
      return;
    }
    if (_tool == CanvasTool.text) {
      unawaited(_addTextAt(point));
      return;
    }

    if (_tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }
    if (_selectionTool || _tool == CanvasTool.text) return;

    if (_tool == CanvasTool.line ||
        _tool == CanvasTool.rectangle ||
        _tool == CanvasTool.ellipse) {
      _pushHistory();
      setState(() {
        _shapeStart = point;
        _shapeCurrent = point;
      });
      return;
    }

    _pushHistory();
    setState(() {
      _activeStroke = CanvasStroke(
        id: 'stroke_${DateTime.now().microsecondsSinceEpoch}',
        points: [
          CanvasPoint(point.dx, point.dy,
              pressure: event.pressure.clamp(0.1, 1.0)),
        ],
        color: _color,
        width: _width,
        opacity: _tool == CanvasTool.highlighter ? 0.26 : 1,
        highlighter: _tool == CanvasTool.highlighter,
        penStyle: _penStyle,
      );
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    final point = _canvasPosition(event);
    if (_selectionTool) {
      final startDocument = _selectionStartDocument;
      final startBounds = _selectionStartBounds;
      final startPoint = _selectionStartPoint;
      if (_selectionInteraction == _SelectionInteraction.move) {
        final last = _selectionMoveLast;
        if (last != null) {
          final delta = point - last;
          if (delta != Offset.zero) {
            setState(() {
              _document = _document.translateIds(_editableSelectionIds, delta);
              _selectionMoveLast = point;
            });
          }
        }
      } else if (_selectionInteraction == _SelectionInteraction.resize &&
          startDocument != null && startBounds != null) {
        final width = math.max(24.0, point.dx - startBounds.left).toDouble();
        final height = math.max(24.0, point.dy - startBounds.top).toDouble();
        final target = Rect.fromLTWH(startBounds.left, startBounds.top, width, height);
        setState(() => _document = startDocument.scaleIds(_editableSelectionIds, startBounds, target));
      } else if (_selectionInteraction == _SelectionInteraction.rotate &&
          startDocument != null && startBounds != null && startPoint != null) {
        final center = startBounds.center;
        final startAngle = math.atan2(startPoint.dy - center.dy, startPoint.dx - center.dx);
        final currentAngle = math.atan2(point.dy - center.dy, point.dx - center.dx);
        setState(() => _document = startDocument.rotateIds(_editableSelectionIds, currentAngle - startAngle, center));
      } else {
        setState(() {
          _selectionCurrent = point;
          if (_tool == CanvasTool.lasso) {
            _lassoPoints.add(point);
          }
        });
      }
      return;
    }

    if (_tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }
    if (_shapeStart != null) {
      setState(() => _shapeCurrent = point);
      return;
    }

    final active = _activeStroke;
    if (active == null) return;
    setState(() {
      _activeStroke = active.copyWith(
        points: [
          ...active.points,
          CanvasPoint(point.dx, point.dy,
              pressure: event.pressure.clamp(0.1, 1.0)),
        ],
      );
    });
  }

  void _pointerUp(PointerUpEvent event) {
    if (_selectionTool) {
      if (_selectionInteraction != _SelectionInteraction.none) {
        _finishSelectionTransform();
        return;
      }

      final start = _selectionStart;
      final current = _selectionCurrent ?? (_lassoPoints.isNotEmpty ? _lassoPoints.last : null);
      final lasso = List<Offset>.from(_lassoPoints);
      _selectionStart = null;
      _selectionCurrent = null;
      _lassoPoints.clear();

      if (_tool == CanvasTool.lasso && lasso.length >= 3) {
        final bounds = _boundsOf(lasso);
        _selectObjectsInBounds(bounds);
      } else if (_tool == CanvasTool.rectangleSelection && start != null && current != null) {
        _selectObjectsInBounds(Rect.fromPoints(start, current));
      } else if (_tool == CanvasTool.circleSelection && start != null && current != null) {
        final bounds = Rect.fromPoints(start, current);
        _selectObjectsInCircle(bounds);
      }
      return;
    }

    final start = _shapeStart;
    final current = _shapeCurrent;
    if (start != null && current != null) {
      final points = _shapePoints(_tool, start, current);
      if (points.length >= 2) {
        setState(() {
          _document = _document.add(CanvasStroke(
            id: 'stroke_${DateTime.now().microsecondsSinceEpoch}',
            points: points,
            color: _color,
            width: _width,
            penStyle: _penStyle,
          ));
        });
      }
      _scheduleSave();
      setState(() {
        _shapeStart = null;
        _shapeCurrent = null;
      });
      return;
    }

    final active = _activeStroke;
    if (active == null) return;
    setState(() {
      _document = _document.add(active);
      _activeStroke = null;
    });
    _scheduleSave();
  }

  void _pointerCancel(PointerCancelEvent event) {
    setState(() {
      _activeStroke = null;
      _shapeStart = null;
      _shapeCurrent = null;
      _lassoPoints.clear();
      _selectionStart = null;
      _selectionCurrent = null;
      _selectionMoveLast = null;
      _movingSelection = false;
    });
  }

  void _applySelectionSet(Set<String> candidates) {
    setState(() {
      switch (_selectionMode) {
        case _SelectionMode.replace:
          _selectedIds
            ..clear()
            ..addAll(candidates);
        case _SelectionMode.add:
          _selectedIds.addAll(candidates);
        case _SelectionMode.subtract:
          _selectedIds.removeAll(candidates);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll([
          ..._document.strokes.map((s) => s.id),
          ..._document.texts.map((t) => t.id),
        ]);
      _selectionMode = _SelectionMode.replace;
    });
  }

  void _setSelectionMode(_SelectionMode mode) {
    setState(() => _selectionMode = mode);
  }

  Rect? get _selectionBounds {
    final rects = <Rect>[
      ..._document.strokes.where((s) => _selectedIds.contains(s.id)).map((s) => s.bounds),
      ..._document.texts.where((t) => _selectedIds.contains(t.id)).map((t) => t.bounds),
    ];
    if (rects.isEmpty) return null;
    var result = rects.first;
    for (final rect in rects.skip(1)) {
      result = result.expandToInclude(rect);
    }
    return result.inflate(10);
  }

  void _selectObjectsInBounds(Rect bounds) {
    final selected = <String>{
      ..._document.strokes
          .where((s) => s.bounds.overlaps(bounds) || bounds.contains(s.bounds.center))
          .map((s) => s.id),
      ..._document.texts
          .where((t) => t.bounds.overlaps(bounds) || bounds.contains(t.bounds.center))
          .map((t) => t.id),
    };
    _applySelectionSet(selected);
  }

  void _selectObjectsInCircle(Rect bounds) {
    final center = bounds.center;
    final radiusX = math.max(bounds.width / 2, 1);
    final radiusY = math.max(bounds.height / 2, 1);
    bool inside(Offset point) {
      final dx = (point.dx - center.dx) / radiusX;
      final dy = (point.dy - center.dy) / radiusY;
      return dx * dx + dy * dy <= 1;
    }
    final selected = <String>{
      ..._document.strokes
          .where((s) => inside(s.bounds.center))
          .map((s) => s.id),
      ..._document.texts
          .where((t) => inside(t.bounds.center))
          .map((t) => t.id),
    };
    _applySelectionSet(selected);
  }

  Rect _boundsOf(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8);
  }

  Future<void> _addTextAt(Offset point) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Type your text…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    _pushHistory();
    setState(() {
      _document = _document.addText(CanvasText(
        id: 'text_${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        x: point.dx,
        y: point.dy,
        color: _color,
      ));
    });
    _scheduleSave();
  }

  Future<void> _choosePenStyle() async {
    final selected = await showModalBottomSheet<CanvasPenStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final style in CanvasPenStyle.values)
              ListTile(
                leading: Icon(_penIcon(style)),
                title: Text(_penLabel(style)),
                trailing: style == _penStyle ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, style),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _penStyle = selected);
  }

  IconData _penIcon(CanvasPenStyle style) {
    switch (style) {
      case CanvasPenStyle.ballpoint: return Icons.edit_rounded;
      case CanvasPenStyle.pencil: return Icons.create_rounded;
      case CanvasPenStyle.marker: return Icons.brush_rounded;
      case CanvasPenStyle.fountain: return Icons.auto_awesome_rounded;
      case CanvasPenStyle.dashed: return Icons.more_horiz_rounded;
    }
  }

  String _penLabel(CanvasPenStyle style) {
    switch (style) {
      case CanvasPenStyle.ballpoint: return 'Ballpoint';
      case CanvasPenStyle.pencil: return 'Pencil';
      case CanvasPenStyle.marker: return 'Marker';
      case CanvasPenStyle.fountain: return 'Fountain pen';
      case CanvasPenStyle.dashed: return 'Dashed pen';
    }
  }

  List<CanvasPoint> _shapePoints(CanvasTool tool, Offset start, Offset end) {
    if (tool == CanvasTool.line) {
      return [CanvasPoint(start.dx, start.dy), CanvasPoint(end.dx, end.dy)];
    }
    final rect = Rect.fromPoints(start, end);
    if (tool == CanvasTool.rectangle) {
      return [
        CanvasPoint(rect.left, rect.top),
        CanvasPoint(rect.right, rect.top),
        CanvasPoint(rect.right, rect.bottom),
        CanvasPoint(rect.left, rect.bottom),
        CanvasPoint(rect.left, rect.top),
      ];
    }
    if (tool == CanvasTool.ellipse) {
      final center = rect.center;
      final rx = rect.width / 2;
      final ry = rect.height / 2;
      if (rx == 0 || ry == 0) return [];
      return List.generate(49, (i) {
        final angle = i / 48 * math.pi * 2;
        return CanvasPoint(
          center.dx + rx * math.cos(angle),
          center.dy + ry * math.sin(angle),
        );
      });
    }
    return [];
  }

  void _eraseAt(Offset point) {
    final hit = _document.strokes.lastWhere(
      (stroke) => stroke.bounds
          .inflate(math.max(stroke.width, _width) * 1.5)
          .contains(point),
      orElse: () => const CanvasStroke(
        id: '',
        points: [],
        color: Colors.transparent,
        width: 0,
      ),
    );
    if (hit.id.isEmpty) return;
    _pushHistory();
    setState(() => _document = _document.remove(hit.id));
    _scheduleSave();
  }

  void _clear() {
    if (_document.strokes.isEmpty && _document.texts.isEmpty) return;
    _pushHistory();
    setState(() => _document = _document.clear());
    _scheduleSave();
  }

  Future<void> _showJson() async {
    final pretty = const JsonEncoder.withIndent('  ').convert(_document.toJson());
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Canvas document'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(pretty,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseColor() async {
    const colors = [
      Color(0xFF111827), Color(0xFF374151), Color(0xFF6B7280), Color(0xFFFFFFFF),
      Color(0xFFEF4444), Color(0xFFF97316), Color(0xFFF59E0B), Color(0xFFFACC15),
      Color(0xFF84CC16), Color(0xFF22C55E), Color(0xFF14B8A6), Color(0xFF06B6D4),
      Color(0xFF0EA5E9), Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6),
      Color(0xFFA855F7), Color(0xFFEC4899), Color(0xFF92400E), Color(0xFF8D6E63),
      Color(0xFFFDE68A), Color(0xFFA7F3D0), Color(0xFFBAE6FD), Color(0xFFE9D5FF),
    ];
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final color in colors)
                InkWell(
                  onTap: () => Navigator.pop(context, color),
                  borderRadius: BorderRadius.circular(30),
                  child: CircleAvatar(radius: 24, backgroundColor: color),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) setState(() => _color = selected);
  }

  Future<void> _choosePaper() async {
    const papers = [
      Color(0xFFF8F7F3), Color(0xFFFFFFFF), Color(0xFFFFF8E7), Color(0xFFFFF1F2),
      Color(0xFFFFF7ED), Color(0xFFFEFCE8), Color(0xFFF0FDF4), Color(0xFFECFEFF),
      Color(0xFFEFF6FF), Color(0xFFF5F3FF), Color(0xFFFDF4FF), Color(0xFFF3F4F6),
      Color(0xFF1B1D23), Color(0xFF23252D), Color(0xFF111827),
    ];
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final paper in papers)
                InkWell(
                  onTap: () => Navigator.pop(context, paper),
                  borderRadius: BorderRadius.circular(28),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: paper,
                    child: paper == _document.backgroundColor
                        ? Icon(Icons.check, color: paper.computeLuminance() > .5 ? Colors.black : Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      _pushHistory();
      setState(() => _document = _document.withPaper(color: selected));
      _scheduleSave();
    }
  }

  void _toggleGrid() {
    _pushHistory();
    setState(() => _document = _document.withPaper(grid: !_document.showGrid));
    _scheduleSave();
  }

  void _setZoom(double value) {
    final next = value.clamp(0.5, 3.0).toDouble();
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale == 0) return;
    final factor = next / scale;
    _transformController.value = _transformController.value.clone()..scaleByDouble(factor, factor, factor, 1);
    setState(() => _zoom = next);
  }

  void _selectTool(CanvasTool tool) => setState(() {
    _tool = tool;
    _activeStroke = null;
    _shapeStart = null;
    _shapeCurrent = null;
    if (_selectionTool) _selectionMode = _SelectionMode.replace;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Canvas', style: TextStyle(fontWeight: FontWeight.w700)),
            if (!_loading) ...[
              const SizedBox(width: 10),
              Text(
                _saved ? 'Saved' : 'Saving…',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _undo.isEmpty ? null : _undoAction,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _redo.isEmpty ? null : _redoAction,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: 'Add page',
            onPressed: _loading ? null : _addPage,
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            tooltip: 'Document JSON',
            onPressed: _showJson,
            icon: const Icon(Icons.data_object_rounded),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: (_document.strokes.isEmpty && _document.texts.isEmpty) ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _toolButton(CanvasTool.pen, Icons.edit_rounded, 'Pen'),
                  _toolButton(CanvasTool.highlighter, Icons.highlight_rounded,
                      'Highlighter'),
                  _toolButton(CanvasTool.eraser, Icons.auto_fix_normal_rounded,
                      'Eraser'),
                  _toolButton(CanvasTool.lasso, Icons.gesture_rounded, 'Freehand Lasso'),
                  _toolButton(CanvasTool.rectangleSelection, Icons.select_all_rounded, 'Rectangle Selection'),
                  _toolButton(CanvasTool.circleSelection, Icons.circle_outlined, 'Circle Selection'),
                  _toolButton(CanvasTool.line, Icons.show_chart_rounded, 'Line'),
                  _toolButton(CanvasTool.rectangle, Icons.crop_square_rounded,
                      'Rectangle'),
                  _toolButton(CanvasTool.ellipse, Icons.circle_outlined, 'Ellipse'),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Ink color',
                    onPressed: _chooseColor,
                    icon: CircleAvatar(
                      radius: 12,
                      backgroundColor: _color,
                      child: _color.computeLuminance() > 0.6
                          ? const Icon(Icons.check, size: 14, color: Colors.black)
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pen style',
                    onPressed: _choosePenStyle,
                    icon: Icon(_penIcon(_penStyle)),
                  ),
                  IconButton(
                    tooltip: 'Paper color',
                    onPressed: _choosePaper,
                    icon: Icon(Icons.article_outlined, color: _document.backgroundColor),
                  ),
                  IconButton(
                    tooltip: _document.showGrid ? 'Hide grid' : 'Show grid',
                    onPressed: _toggleGrid,
                    icon: Icon(_document.showGrid ? Icons.grid_4x4_rounded : Icons.grid_off_rounded),
                  ),
                  SizedBox(
                    width: 150,
                    child: Row(
                      children: [
                        const Icon(Icons.line_weight_rounded, size: 18),
                        Expanded(
                          child: Slider(
                            value: _width,
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: _width.toStringAsFixed(0),
                            onChanged: (value) =>
                                setState(() => _width = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: _zoom <= 0.5
                        ? null
                        : () => _setZoom(_zoom - 0.25),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Text('${(_zoom * 100).round()}%'),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: _zoom >= 3
                        ? null
                        : () => _setZoom(_zoom + 0.25),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_selectionTool)
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      _selectedIds.isEmpty ? 'Selection' : '${_selectedIds.length} selected',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<_SelectionMode>(
                      segments: const [
                        ButtonSegment(value: _SelectionMode.replace, icon: Icon(Icons.select_all_rounded, size: 18), label: Text('Replace')),
                        ButtonSegment(value: _SelectionMode.add, icon: Icon(Icons.add_rounded, size: 18), label: Text('Add')),
                        ButtonSegment(value: _SelectionMode.subtract, icon: Icon(Icons.remove_rounded, size: 18), label: Text('Subtract')),
                      ],
                      selected: {_selectionMode},
                      onSelectionChanged: (values) => _setSelectionMode(values.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: _selectAll, icon: const Icon(Icons.select_all_rounded, size: 18), label: const Text('Select all')),
                    const SizedBox(width: 4),
                    IconButton(tooltip: 'Duplicate', onPressed: _selectedIds.isEmpty ? null : _duplicateSelection, icon: const Icon(Icons.copy_all_rounded)),
                    IconButton(tooltip: 'Copy', onPressed: _selectedIds.isEmpty ? null : () => _copySelection(), icon: const Icon(Icons.content_copy_rounded)),
                    IconButton(tooltip: 'Cut', onPressed: _selectedIds.isEmpty ? null : () => _copySelection(cut: true), icon: const Icon(Icons.content_cut_rounded)),
                    IconButton(tooltip: 'Paste', onPressed: _pasteSelection, icon: const Icon(Icons.content_paste_rounded)),
                    IconButton(
                      tooltip: _selectedIds.isNotEmpty && _document.lockedIds.intersection(_selectedIds).length == _selectedIds.length ? 'Unlock' : 'Lock',
                      onPressed: _selectedIds.isEmpty ? null : _toggleSelectionLock,
                      icon: Icon(_selectedIds.isNotEmpty && _document.lockedIds.intersection(_selectedIds).length == _selectedIds.length ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                    ),
                    IconButton(tooltip: 'Delete', onPressed: _editableSelectionIds.isEmpty ? null : _deleteSelection, icon: const Icon(Icons.delete_outline_rounded)),
                    TextButton.icon(onPressed: _selectedIds.isEmpty ? null : () => setState(() => _selectedIds.clear()), icon: const Icon(Icons.close_rounded, size: 18), label: const Text('Deselect')),
                  ],
                ),
              ),
            ),
          if (!_loading && _noteId != null)
            StreamBuilder<List<atlas_db.Page>>(
              stream: _notebookRepository.watchPages(_noteId!),
              builder: (context, snapshot) {
                final pages = snapshot.data ?? const <atlas_db.Page>[];
                if (pages.isEmpty) return const SizedBox.shrink();
                return Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: SizedBox(
                    height: 52,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      scrollDirection: Axis.horizontal,
                      itemCount: pages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        final selected = page.id == _pageId;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ChoiceChip(
                              selected: selected,
                              label: Text('Page ${page.pageIndex + 1}'),
                              onSelected: (_) => _switchPage(page),
                            ),
                            if (selected)
                              IconButton(
                                tooltip: 'Page actions',
                                visualDensity: VisualDensity.compact,
                                onPressed: _showPageMenu,
                                icon: const Icon(Icons.more_vert_rounded, size: 18),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: ColoredBox(
              color: theme.brightness == Brightness.light
                  ? const Color(0xFFF0F1F5)
                  : const Color(0xFF191A1F),
              child: InteractiveViewer(
                transformationController: _transformController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(1000),
                minScale: 0.5,
                maxScale: 3.0,
                panEnabled: !(_drawingTool || _tool == CanvasTool.eraser || _selectionTool || _tool == CanvasTool.text || _tool == CanvasTool.line || _tool == CanvasTool.rectangle || _tool == CanvasTool.ellipse),
                scaleEnabled: true,
                clipBehavior: Clip.none,
                onInteractionUpdate: (_) {
                  final scale = _transformController.value.getMaxScaleOnAxis();
                  if (scale.isFinite && mounted && (scale - _zoom).abs() > 0.01) {
                    setState(() => _zoom = scale.clamp(0.5, 3.0).toDouble());
                  }
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: _pointerUp,
                  onPointerCancel: _pointerCancel,
                  child: CustomPaint(
                    size: const Size(2000, 1400),
                    painter: _CanvasPainter(
                      document: _document,
                      activeStroke: _activeStroke,
                      previewTool: _tool,
                      previewStart: _shapeStart,
                      previewCurrent: _shapeCurrent,
                      selectedIds: _selectedIds,
                      lassoPoints: _lassoPoints,
                      selectionStart: _selectionStart,
                      selectionCurrent: _selectionCurrent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(CanvasTool tool, IconData icon, String label) {
    final selected = _tool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: label,
        child: IconButton.filledTonal(
          onPressed: () => _selectTool(tool),
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.document,
    required this.activeStroke,
    required this.previewTool,
    required this.previewStart,
    required this.previewCurrent,
    required this.selectedIds,
    required this.lassoPoints,
    required this.selectionStart,
    required this.selectionCurrent,
  });

  final CanvasDocument document;
  final CanvasStroke? activeStroke;
  final CanvasTool previewTool;
  final Offset? previewStart;
  final Offset? previewCurrent;
  final Set<String> selectedIds;
  final List<Offset> lassoPoints;
  final Offset? selectionStart;
  final Offset? selectionCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = document.backgroundColor);
    if (document.showGrid) _drawGrid(canvas, size);
    for (final stroke in document.strokes) {
      _drawStroke(canvas, stroke);
    }
    for (final text in document.texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(color: text.color, fontSize: text.size, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900);
      if (text.rotation.abs() < 0.0001) {
        painter.paint(canvas, Offset(text.x, text.y));
      } else {
        canvas.save();
        final center = text.bounds.center;
        canvas.translate(center.dx, center.dy);
        canvas.rotate(text.rotation);
        canvas.translate(-center.dx, -center.dy);
        painter.paint(canvas, Offset(text.x, text.y));
        canvas.restore();
      }
    }
    if (activeStroke != null) _drawStroke(canvas, activeStroke!);
    final selectedRects = <Rect>[
      ...document.strokes.where((s) => selectedIds.contains(s.id)).map((s) => s.bounds),
      ...document.texts.where((t) => selectedIds.contains(t.id)).map((t) => t.bounds),
    ];
    if (selectedRects.isNotEmpty) {
      var selection = selectedRects.first;
      for (final rect in selectedRects.skip(1)) {
        selection = selection.expandToInclude(rect);
      }
      final box = selection.inflate(10);
      final outline = Paint()
        ..color = Colors.blueAccent.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(box, outline);
      final handle = Paint()..color = Colors.blueAccent;
      canvas.drawCircle(box.topLeft, 6, handle);
      canvas.drawCircle(box.topRight, 6, handle);
      canvas.drawCircle(box.bottomLeft, 6, handle);
      canvas.drawCircle(box.bottomRight, 7, handle);
      final rotateHandle = Offset(box.center.dx, box.top - 34);
      canvas.drawLine(box.topCenter, rotateHandle, Paint()..color = Colors.blueAccent..strokeWidth = 2);
      canvas.drawCircle(rotateHandle, 7, handle);
    }

    if (previewStart != null && previewCurrent != null) {
      final points = _previewPoints(previewTool, previewStart!, previewCurrent!);
      if (points.length >= 2) {
        _drawStroke(
          canvas,
          CanvasStroke(
            id: 'preview',
            points: points,
            color: Colors.black54,
            width: 2,
            opacity: 0.65,
          ),
        );
      }
    }

    if (selectionStart != null && selectionCurrent != null) {
      final selectionPaint = Paint()
        ..color = Colors.blueAccent.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      if (previewTool == CanvasTool.rectangleSelection) {
        canvas.drawRect(Rect.fromPoints(selectionStart!, selectionCurrent!), selectionPaint);
      } else if (previewTool == CanvasTool.circleSelection) {
        canvas.drawOval(Rect.fromPoints(selectionStart!, selectionCurrent!), selectionPaint);
      }
    }

    if (lassoPoints.length >= 2) {
      final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (final p in lassoPoints.skip(1)) { path.lineTo(p.dx, p.dy); }
      canvas.drawPath(path, Paint()..color = Colors.blueAccent.withValues(alpha: .7)..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    if (previewStart != null && previewCurrent != null) {
      final points = _previewPoints(previewTool, previewStart!, previewCurrent!);
      if (points.length >= 2) {
        _drawStroke(
          canvas,
          CanvasStroke(
            id: 'preview',
            points: points,
            color: Colors.black54,
            width: 2,
            opacity: 0.65,
          ),
        );
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x18000000)
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawStroke(Canvas canvas, CanvasStroke stroke) {
    if (stroke.points.length < 2) return;
    for (var i = 1; i < stroke.points.length; i++) {
      final previous = stroke.points[i - 1];
      final current = stroke.points[i];
      final pressure = ((previous.pressure + current.pressure) / 2).clamp(0.1, 1.0);
      final style = stroke.penStyle;
      final styleWidth = switch (style) {
        CanvasPenStyle.ballpoint => 1.0,
        CanvasPenStyle.pencil => .72,
        CanvasPenStyle.marker => 1.65,
        CanvasPenStyle.fountain => 1.15,
        CanvasPenStyle.dashed => 1.0,
      };
      final alpha = switch (style) {
        CanvasPenStyle.pencil => .68,
        CanvasPenStyle.marker => .52,
        _ => stroke.opacity,
      };
      final pressureWidth = stroke.width * styleWidth * (0.55 + pressure * 0.9);
      final paint = Paint()
        ..color = stroke.color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = pressureWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (stroke.highlighter) paint.blendMode = BlendMode.multiply;
      if (style == CanvasPenStyle.dashed) {
        final delta = current.offset - previous.offset;
        final distance = delta.distance;
        if (distance > 0) {
          final unit = delta / distance;
          const dash = 9.0;
          const gap = 6.0;
          for (double d = 0; d < distance; d += dash + gap) {
            final a = previous.offset + unit * d;
            final b = previous.offset + unit * math.min(d + dash, distance);
            canvas.drawLine(a, b, paint);
          }
        }
      } else {
        canvas.drawLine(previous.offset, current.offset, paint);
      }
    }
  }

  List<CanvasPoint> _previewPoints(
      CanvasTool tool, Offset start, Offset end) {
    if (tool == CanvasTool.line) {
      return [CanvasPoint(start.dx, start.dy), CanvasPoint(end.dx, end.dy)];
    }
    final rect = Rect.fromPoints(start, end);
    if (tool == CanvasTool.rectangle) {
      return [
        CanvasPoint(rect.left, rect.top),
        CanvasPoint(rect.right, rect.top),
        CanvasPoint(rect.right, rect.bottom),
        CanvasPoint(rect.left, rect.bottom),
        CanvasPoint(rect.left, rect.top),
      ];
    }
    if (tool == CanvasTool.ellipse) {
      final center = rect.center;
      final rx = rect.width / 2;
      final ry = rect.height / 2;
      return List.generate(49, (i) {
        final angle = i / 48 * math.pi * 2;
        return CanvasPoint(
          center.dx + rx * math.cos(angle),
          center.dy + ry * math.sin(angle),
        );
      });
    }
    return [];
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
