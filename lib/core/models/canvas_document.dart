import 'dart:math' as math;
import 'package:flutter/material.dart';

enum CanvasTool { pen, highlighter, eraser, lasso, line, rectangle, ellipse, text }

class CanvasPoint {
  const CanvasPoint(this.x, this.y, {this.pressure = 1});
  final double x;
  final double y;
  final double pressure;
  Offset get offset => Offset(x, y);
  Map<String, Object> toJson() => {'x': x, 'y': y, 'pressure': pressure};
  factory CanvasPoint.fromJson(Map<String, dynamic> json) => CanvasPoint(
    (json['x'] as num).toDouble(), (json['y'] as num).toDouble(),
    pressure: (json['pressure'] as num?)?.toDouble() ?? 1,
  );
}

class CanvasStroke {
  const CanvasStroke({required this.id, required this.points, required this.color, required this.width, this.opacity = 1, this.highlighter = false});
  final String id;
  final List<CanvasPoint> points;
  final Color color;
  final double width;
  final double opacity;
  final bool highlighter;
  CanvasStroke copyWith({List<CanvasPoint>? points}) => CanvasStroke(id:id, points:points ?? this.points, color:color, width:width, opacity:opacity, highlighter:highlighter);
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX=points.first.x, maxX=points.first.x, minY=points.first.y, maxY=points.first.y;
    for (final p in points.skip(1)) { minX=math.min(minX,p.x); maxX=math.max(maxX,p.x); minY=math.min(minY,p.y); maxY=math.max(maxY,p.y); }
    final pad=width/2;
    return Rect.fromLTRB(minX-pad,minY-pad,maxX+pad,maxY+pad);
  }
  Map<String,Object> toJson()=>{'id':id,'points':points.map((p)=>p.toJson()).toList(),'color':color.toARGB32(),'width':width,'opacity':opacity,'highlighter':highlighter};
  factory CanvasStroke.fromJson(Map<String,dynamic> json)=>CanvasStroke(
    id:json['id'] as String,
    points:(json['points'] as List<dynamic>).map((p)=>CanvasPoint.fromJson(p as Map<String,dynamic>)).toList(),
    color:Color((json['color'] as num).toInt()),
    width:(json['width'] as num).toDouble(),
    opacity:(json['opacity'] as num?)?.toDouble() ?? 1,
    highlighter:json['highlighter'] as bool? ?? false,
  );
}

class CanvasDocument {
  const CanvasDocument({this.strokes=const []});
  final List<CanvasStroke> strokes;
  CanvasDocument add(CanvasStroke stroke)=>CanvasDocument(strokes:[...strokes,stroke]);
  CanvasDocument remove(String id)=>CanvasDocument(strokes:strokes.where((s)=>s.id!=id).toList());
  CanvasDocument clear()=>const CanvasDocument();
  Map<String,Object> toJson()=>{'strokes':strokes.map((s)=>s.toJson()).toList()};
  factory CanvasDocument.fromJson(Map<String,dynamic> json)=>CanvasDocument(
    strokes:(json['strokes'] as List<dynamic>? ?? const []).map((s)=>CanvasStroke.fromJson(s as Map<String,dynamic>)).toList(),
  );
}
