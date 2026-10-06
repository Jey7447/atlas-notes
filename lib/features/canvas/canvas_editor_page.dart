import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/models/canvas_document.dart';
import '../../data/local/atlas_local_store.dart';
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
  Color _color = const Color(0xFF1F2430);
  double _width = 3;
  double _zoom = 1;
  late final TransformationController _transformController;
  CanvasStroke? _activeStroke;
  Offset? _shapeStart;
  Offset? _shapeCurrent;

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

  Future<void> _switchPage(Page page) async {
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
    final page = await (AtlasLocalStore.instance.db.select(AtlasLocalStore.instance.db.pages)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    if (!mounted) return;
    await _switchPage(page);
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

  void _pointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch && _drawingTool) return;
    final point = _canvasPosition(event);

    if (_tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }
    if (_tool == CanvasTool.lasso || _tool == CanvasTool.text) return;

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
      );
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch && _drawingTool) return;
    final point = _canvasPosition(event);

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
    if (event.kind == PointerDeviceKind.touch && _drawingTool) return;

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
    });
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
    if (_document.strokes.isEmpty) return;
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
      Color(0xFF1F2430), Color(0xFFE53935), Color(0xFFFB8C00),
      Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF1E88E5),
      Color(0xFF5E35B1), Color(0xFF00897B), Color(0xFF8D6E63),
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

  void _setZoom(double value) {
    final next = value.clamp(0.5, 3.0).toDouble();
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale == 0) return;
    final factor = next / scale;
    _transformController.value = _transformController.value.clone()..scale(factor);
    setState(() => _zoom = next);
  }

  void _selectTool(CanvasTool tool) => setState(() {
    _tool = tool;
    _activeStroke = null;
    _shapeStart = null;
    _shapeCurrent = null;
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
            onPressed: _document.strokes.isEmpty ? null : _clear,
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
                  _toolButton(CanvasTool.line, Icons.show_chart_rounded, 'Line'),
                  _toolButton(CanvasTool.rectangle, Icons.crop_square_rounded,
                      'Rectangle'),
                  _toolButton(CanvasTool.ellipse, Icons.circle_outlined, 'Ellipse'),
                  _toolButton(CanvasTool.lasso, Icons.gesture_rounded, 'Lasso'),
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
          if (!_loading && _noteId != null)
            StreamBuilder<List<Page>>(
              stream: _notebookRepository.watchPages(_noteId!),
              builder: (context, snapshot) {
                final pages = snapshot.data ?? const <Page>[];
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
                        return ChoiceChip(
                          selected: selected,
                          label: Text('Page ${page.pageIndex + 1}'),
                          onSelected: (_) => _switchPage(page),
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
                panEnabled: !_drawingTool,
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
  });

  final CanvasDocument document;
  final CanvasStroke? activeStroke;
  final CanvasTool previewTool;
  final Offset? previewStart;
  final Offset? previewCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    for (final stroke in document.strokes) {
      _drawStroke(canvas, stroke);
    }
    if (activeStroke != null) _drawStroke(canvas, activeStroke!);
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
    final paint = Paint()
      ..color = stroke.color.withValues(alpha: stroke.opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (stroke.highlighter) paint.blendMode = BlendMode.multiply;

    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (var i = 1; i < stroke.points.length; i++) {
      final previous = stroke.points[i - 1];
      final current = stroke.points[i];
      final midpoint = Offset(
        (previous.x + current.x) / 2,
        (previous.y + current.y) / 2,
      );
      path.quadraticBezierTo(
        previous.x,
        previous.y,
        midpoint.dx,
        midpoint.dy,
      );
    }
    final last = stroke.points.last;
    path.lineTo(last.x, last.y);
    canvas.drawPath(path, paint);
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
