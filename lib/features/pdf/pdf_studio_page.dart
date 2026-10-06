import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/local/atlas_local_store.dart';
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
  PdfViewerController? _controller;
  PdfDocumentRef? _documentRef;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _showThumbnails = true;
  String? _pdfId;
  PdfRepository get _repository => PdfRepository(AtlasLocalStore.instance.db);

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _name = widget.initialName ?? _name;
    final bytes = _bytes;
    if (bytes != null) {
      _setDocument(bytes);
      WidgetsBinding.instance.addPostFrameCallback((_) => _registerDocument());
    }
  }

  Future<void> _registerDocument() async {
    final name = _name;
    final existing = await _repository.watchDocuments(AtlasLocalStore.defaultWorkspaceId).first;
    final match = existing.where((d) => d.name == name).cast<PdfDocument?>().firstOrNull;
    if (match != null) {
      _pdfId = match.id;
      return;
    }
    _pdfId = await _repository.createDocument(
      workspaceId: AtlasLocalStore.defaultWorkspaceId,
      name: name,
    );
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
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _name = file.name;
        _currentPage = 1;
        _pageCount = 0;
      });
      _setDocument(bytes);
      await _registerDocument();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF: $error')),
      );
    }
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
                      onPageChanged: (pageNumber) {
                        if (mounted) setState(() => _currentPage = pageNumber ?? 1);
                      },
                      onDocumentChanged: (document) {
                        if (mounted) {
                          setState(() => _pageCount = document?.pages.length ?? 0);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
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
