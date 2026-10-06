import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atlas_notes/core/models/canvas_document.dart';

void main() {
  group('CanvasDocument', () {
    test('serializes and restores strokes', () {
      const original = CanvasDocument(
        strokes: [
          CanvasStroke(
            id: 'stroke-1',
            points: [
              CanvasPoint(10, 20, pressure: 0.5),
              CanvasPoint(30, 40, pressure: 1),
            ],
            color: Color(0xFF112233),
            width: 4,
            opacity: 0.7,
            highlighter: true,
          ),
        ],
      );

      final restored = CanvasDocument.fromJson(original.toJson());

      expect(restored.strokes, hasLength(1));
      expect(restored.strokes.first.id, 'stroke-1');
      expect(restored.strokes.first.points, hasLength(2));
      expect(restored.strokes.first.points.last.x, 30);
      expect(restored.strokes.first.points.last.pressure, 1);
      expect(restored.strokes.first.color.value, 0xFF112233);
      expect(restored.strokes.first.width, 4);
      expect(restored.strokes.first.opacity, 0.7);
      expect(restored.strokes.first.highlighter, isTrue);
    });

    test('removes only the requested stroke', () {
      const document = CanvasDocument(
        strokes: [
          CanvasStroke(
            id: 'a',
            points: [CanvasPoint(0, 0), CanvasPoint(1, 1)],
            color: Color(0xFF000000),
            width: 2,
          ),
          CanvasStroke(
            id: 'b',
            points: [CanvasPoint(2, 2), CanvasPoint(3, 3)],
            color: Color(0xFFFFFFFF),
            width: 2,
          ),
        ],
      );

      final result = document.remove('a');

      expect(result.strokes.map((stroke) => stroke.id), ['b']);
    });
  });
}
