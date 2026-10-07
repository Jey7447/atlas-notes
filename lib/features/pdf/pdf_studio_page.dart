import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/local/atlas_local_store.dart';
import '../../data/local/atlas_database.dart' as atlas_db;
import '../../data/local/pdf_repository.dart';

class PdfStudioPage extends StatefulWidget {
  const PdfStudioPage({super.key, this.initialBytes, this.initialName});

  final Uint8List? initialBytes;
  final String? initialName;

  @override
  State<PdfStudioPage> createState() => _PdfStudioPageState();
}

class _PdfStudioPageState extends State<PdfStudioPage> {
  Uint8List? _bytes;
  String _name = 'PDF document';
  String? _pdfId;
  _PdfTool _tool = _PdfTool.select;
  _PdfInk? _activeInk;
  final Map<int, List<_PdfInk>> _annotationsByPage = {};
  final Map<int, Future<void>> _annotationLoads = {};
  PdfViewerController? _controller;
  PdfDocumentRef? _documentRef;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _showThumbnails = true;
  PdfRepository get _repository => PdfRepository(AtlasLocalStore.instance.db);

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _name = widget.initialName ?? _name;
    final bytes = _bytes;
    if (bytes != null) unawaited(_openDocument(bytes, _name));
  }

  Future<void> _openDocument(Uint8List bytes, String name) async {
    final id = await _ensureDocument(name);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _name = name;
      _pdfId = id;
      _currentPage = 1;
      _pageCount = 0;
      _annotationsByPage.clear();
      _annotationLoads.clear();
    });
    _setDocument(bytes);
  }

  Future<String> _ensureDocument(String name) async {
    final docs = await _repository.watchDocuments(AtlasLocalStore.defaultWorkspaceId).first;
    final existing = docs.where((d) => d.name == name).firstOrNull;
    return existing?.id ?? _repository.createDocument(
      workspaceId: AtlasLocalStore.defaultWorkspaceId,
      name: name,
    );
  }

  Future<void> _loadAnnotations(int pageNumber) {
    final id = _pdfId;
    if (id == null) return Future.value();
    final pending = _annotationLoads[pageNumber];
    if (pending != null) return pending;
    final future = _repository.watchAnnotations(id, pageNumber).first.then((rows) {
      if (!mounted) return;
      final values = rows
          .where((r) => r.kind == 'ink' || r.kind == 'highlighter')
          .map(_PdfInk.fromRow)
          .where((i) => i.points.length > 1)
          .toList();
      setState(() => _annotationsByPage[pageNumber] = values);
    }).whenComplete(() => _annotationLoads.remove(pageNumber));
    _annotationLoads[pageNumber] = future;
    return future;
  }

  Future<void> _loadAllAnnotations(int count) async {
    await Future.wait(List<int>.generate(count, (i) => i + 1).map(_loadAnnotations));
  }

  void _setDocument(Uint8List bytes) {
    _documentRef = PdfDocumentRefData(
      bytes,
      sourceName: _name,
      useProgressiveLoading: true,
    );
    _controller = PdfViewerController();
  }

  Future<void> _importPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      await _openDocument(bytes, file.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF: $error')),
      );
    }
  }

  bool _drawingPointer(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      kind == PointerDeviceKind.mouse;

  void _pointerDown(PointerDownEvent event, Size size) {
    if (_tool == _PdfTool.select || !_drawingPointer(event.kind) || _pdfId == null || size.isEmpty) return;
    final p = event.localPosition;
    final point = _PdfInkPoint(
      (p.dx / size.width).clamp(0.0, 1.0),
      (p.dy / size.height).clamp(0.0, 1.0),
      event.pressure.isFinite ? event.pressure.clamp(0.1, 1.0) : 1,
    );
    setState(() {
      _activeInk = _PdfInk(
        id: 'pdfann_${DateTime.now().microsecondsSinceEpoch}',
        kind: _tool == _PdfTool.highlighter ? 'highlighter' : 'ink',
        color: _tool == _PdfTool.highlighter ? Colors.yellow.value : Colors.blue.value,
        width: 2.5,
        opacity: _tool == _PdfTool.highlighter ? 0.32 : 1,
        points: [point],
      );
    });
  }

  void _pointerMove(PointerMoveEvent event, Size size) {
    final ink = _activeInk;
    if (ink == null || !_drawingPointer(event.kind) || size.isEmpty) return;
    final p = event.localPosition;
    final point = _PdfInkPoint(
      (p.dx / size.width).clamp(0.0, 1.0),
      (p.dy / size.height).clamp(0.0, 1.0),
      event.pressure.isFinite ? event.pressure.clamp(0.1, 1.0) : 1,
    );
    setState(() {
      _activeInk = _PdfInk(
        id: ink.id,
        kind: ink.kind,
        color: ink.color,
        width: ink.width,
        opacity: ink.opacity,
        points: [...ink.points, point],
      );
    });
  }

  Future<void> _finishInk() async {
    final ink = _activeInk;
    if (ink == null) return;
    setState(() {
      _activeInk = null;
      if (ink.points.length > 1) {
        _annotationsByPage[_currentPage] = [...?_annotationsByPage[_currentPage], ink];
      }
    });
    final id = _pdfId;
    if (id == null || ink.points.length < 2) return;
    await _repository.saveAnnotation(
      pdfId: id,
      pageNumber: _currentPage,
      kind: ink.kind,
      id: ink.id,
      payload: ink.toPayload(),
    );
  }

  void _goToPage(int page) {
    final controller = _controller;
    if (controller == null || !controller.isReady) return;
    final target = page.clamp(1, _pageCount == 0 ? page : _pageCount);
    controller.goToPage(pageNumber: target);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis),
        actions: [
          if (bytes != null && _pageCount > 0)
            Text(
              '$_currentPage / $_pageCount',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          IconButton(
            tooltip: 'Pen',
            onPressed: () => setState(() => _tool = _PdfTool.pen),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Highlighter',
            onPressed: () => setState(() => _tool = _PdfTool.highlighter),
            icon: const Icon(Icons.highlight_outlined),
          ),
          IconButton(
            tooltip: 'Pan / select',
            onPressed: () => setState(() => _tool = _PdfTool.select),
            icon: const Icon(Icons.pan_tool_alt_outlined),
          ),
          IconButton(
            tooltip: _showThumbnails ? 'Hide thumbnails' : 'Show thumbnails',
            onPressed: bytes == null
                ? null
                : () => setState(() => _showThumbnails = !_showThumbnails),
            icon: Icon(
              _showThumbnails
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Import PDF',
            onPressed: _importPdf,
            icon: const Icon(Icons.file_open_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: bytes == null
          ? _EmptyPdfState(onImport: _importPdf)
          : Row(
              children: [
                if (_showThumbnails)
                  SizedBox(
                    width: 150,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        border: Border(
                          right: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: _PdfThumbnails(
                        documentRef: _documentRef!,
                        currentPage: _currentPage,
                        onPageTap: _goToPage,
                        onLoaded: (count) {
                          if (mounted && _pageCount != count) {
                            setState(() => _pageCount = count);
                          }
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: PdfViewer(
                    _documentRef!,
                    controller: _controller,
                    params: PdfViewerParams(
                      panEnabled: _tool == _PdfTool.select,
                      onPageChanged: (pageNumber) {
                        if (mounted) {
                          final page = pageNumber ?? 1;
                          setState(() => _currentPage = page);
                          unawaited(_loadAnnotations(page));
                        }
                      },
                      onDocumentChanged: (document) {
                        if (mounted) {
                          final count = document?.pages.length ?? 0;
                          setState(() => _pageCount = count);
                          unawaited(_loadAllAnnotations(count));
                          final id = _pdfId;
                          if (id != null) unawaited(_repository.updatePageCount(id, count));
                        }
                      },
                      pageOverlaysBuilder: (context, pageRect, page) {
                        final saved = _annotationsByPage[page.pageNumber] ?? const <_PdfInk>[];
                        final active = page.pageNumber == _currentPage && _activeInk != null ? <_PdfInk>[_activeInk!] : const <_PdfInk>[];
                        return [
                          Positioned.fill(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (e) => _pointerDown(e, pageRect.size),
                              onPointerMove: (e) => _pointerMove(e, pageRect.size),
                              onPointerUp: (_) => unawaited(_finishInk()),
                              onPointerCancel: (_) => unawaited(_finishInk()),
                              child: CustomPaint(painter: _PdfInkPainter(inks: [...saved, ...active])),
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

enum _PdfTool { select, pen, highlighter }

class _PdfInkPoint {
  const _PdfInkPoint(this.x, this.y, this.pressure);
  final double x, y, pressure;
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'pressure': pressure};
  static _PdfInkPoint fromJson(Map<String, dynamic> j) => _PdfInkPoint(
    (j['x'] as num?)?.toDouble() ?? 0,
    (j['y'] as num?)?.toDouble() ?? 0,
    (j['pressure'] as num?)?.toDouble() ?? 1,
  );
}

class _PdfInk {
  const _PdfInk({
    required this.id,
    required this.kind,
    required this.color,
    required this.width,
    required this.opacity,
    required this.points,
  });
  final String id, kind;
  final int color;
  final double width, opacity;
  final List<_PdfInkPoint> points;

  Map<String, dynamic> toPayload() => {
    'color': color,
    'width': width,
    'opacity': opacity,
    'points': points.map((p) => p.toJson()).toList(),
  };

  static _PdfInk fromRow(atlas_db.PdfAnnotation row) {
    final json = Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map);
    final raw = json['points'];
    final points = raw is List
        ? raw.whereType<Map>().map((p) => _PdfInkPoint.fromJson(Map<String, dynamic>.from(p))).toList()
        : <_PdfInkPoint>[];
    return _PdfInk(
      id: row.id,
      kind: row.kind,
      color: (json['color'] as num?)?.toInt() ?? Colors.blue.value,
      width: (json['width'] as num?)?.toDouble() ?? 2.5,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      points: points,
    );
  }
}

class _PdfInkPainter extends CustomPainter {
  const _PdfInkPainter({required this.inks});
  final List<_PdfInk> inks;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ink in inks) {
      if (ink.points.length < 2) continue;
      final path = Path()
        ..moveTo(ink.points.first.x * size.width, ink.points.first.y * size.height);
      for (final point in ink.points.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      final paint = Paint()
        ..color = Color(ink.color).withOpacity(ink.opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = ink.width;
      if (ink.kind == 'highlighter') paint.blendMode = BlendMode.multiply;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PdfInkPainter oldDelegate) => oldDelegate.inks != inks;
}

class _PdfThumbnails extends StatelessWidget {
  const _PdfThumbnails({
    required this.documentRef,
    required this.currentPage,
    required this.onPageTap,
    required this.onLoaded,
  });

  final PdfDocumentRef documentRef;
  final int currentPage;
  final ValueChanged<int> onPageTap;
  final ValueChanged<int> onLoaded;

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder(
      documentRef: documentRef,
      builder: (context, document) {
        final count = document?.pages.length ?? 0;
        if (count > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded(count));
        }
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: count,
          itemBuilder: (context, index) {
            final page = index + 1;
            final selected = page == currentPage;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onPageTap(page),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 150,
                          child: PdfPageView(
                            document: document,
                            pageNumber: page,
                            alignment: Alignment.center,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$page',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyPdfState extends StatelessWidget {
  const _EmptyPdfState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'PDF Studio',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Import a PDF to read, navigate and prepare it for annotation.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
