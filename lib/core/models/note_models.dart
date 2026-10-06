import 'package:flutter/foundation.dart';

enum NoteKind { page, canvas, pdf }

@immutable
class AtlasNoteDraft {
  const AtlasNoteDraft({
    required this.title,
    this.kind = NoteKind.page,
    this.body = '',
  });

  final String title;
  final NoteKind kind;
  final String body;
}

@immutable
class CanvasPoint {
  const CanvasPoint(this.x, this.y, {this.pressure = 1});

  final double x;
  final double y;
  final double pressure;

  Map<String, Object> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
      };
}

@immutable
class Stroke {
  const Stroke({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
    this.opacity = 1,
  });

  final String id;
  final List<CanvasPoint> points;
  final int color;
  final double width;
  final double opacity;

  Map<String, Object> toJson() => {
        'id': id,
        'points': points.map((p) => p.toJson()).toList(),
        'color': color,
        'width': width,
        'opacity': opacity,
      };
}
