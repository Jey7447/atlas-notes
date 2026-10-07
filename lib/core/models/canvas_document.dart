import 'dart:math' as math;
import 'package:flutter/material.dart';

enum CanvasTool { pen, highlighter, eraser, lasso, rectangleSelection, circleSelection, line, rectangle, ellipse, text }
enum CanvasPenStyle { ballpoint, pencil, marker, fountain, dashed }

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
  const CanvasStroke({required this.id, required this.points, required this.color, required this.width, this.opacity = 1, this.highlighter = false, this.penStyle = CanvasPenStyle.ballpoint});
  final String id;
  final List<CanvasPoint> points;
  final Color color;
  final double width;
  final double opacity;
  final bool highlighter;
  final CanvasPenStyle penStyle;
  CanvasStroke copyWith({List<CanvasPoint>? points}) => CanvasStroke(id:id, points:points ?? this.points, color:color, width:width, opacity:opacity, highlighter:highlighter, penStyle:penStyle);
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX=points.first.x, maxX=points.first.x, minY=points.first.y, maxY=points.first.y;
    for (final p in points.skip(1)) { minX=math.min(minX,p.x); maxX=math.max(maxX,p.x); minY=math.min(minY,p.y); maxY=math.max(maxY,p.y); }
    final pad=width/2;
    return Rect.fromLTRB(minX-pad,minY-pad,maxX+pad,maxY+pad);
  }
  Map<String,Object> toJson()=>{'id':id,'points':points.map((p)=>p.toJson()).toList(),'color':color.toARGB32(),'width':width,'opacity':opacity,'highlighter':highlighter,'penStyle':penStyle.name};
  factory CanvasStroke.fromJson(Map<String,dynamic> json)=>CanvasStroke(
    id:json['id'] as String,
    points:(json['points'] as List<dynamic>).map((p)=>CanvasPoint.fromJson(p as Map<String,dynamic>)).toList(),
    color:Color((json['color'] as num).toInt()),
    width:(json['width'] as num).toDouble(),
    opacity:(json['opacity'] as num?)?.toDouble() ?? 1,
    highlighter:json['highlighter'] as bool? ?? false,
    penStyle:CanvasPenStyle.values.firstWhere((v)=>v.name == json['penStyle'], orElse:()=>CanvasPenStyle.ballpoint),
  );
}

class CanvasText {
  const CanvasText({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    this.size = 28,
    this.rotation = 0,
  });
  final String id;
  final String text;
  final double x;
  final double y;
  final Color color;
  final double size;
  final double rotation;

  CanvasText copyWith({double? x, double? y, double? size, double? rotation}) => CanvasText(
    id: id,
    text: text,
    x: x ?? this.x,
    y: y ?? this.y,
    color: color,
    size: size ?? this.size,
    rotation: rotation ?? this.rotation,
  );

  Rect get bounds => Rect.fromLTWH(
    x, y, math.max(20, text.length * size * .58), size * 1.25,
  );

  Map<String,Object> toJson()=>{
    'id':id, 'text':text, 'x':x, 'y':y, 'color':color.toARGB32(),
    'size':size, 'rotation':rotation,
  };

  factory CanvasText.fromJson(Map<String,dynamic> json)=>CanvasText(
    id:json['id'] as String,
    text:json['text'] as String,
    x:(json['x'] as num).toDouble(),
    y:(json['y'] as num).toDouble(),
    color:Color((json['color'] as num).toInt()),
    size:(json['size'] as num?)?.toDouble() ?? 28,
    rotation:(json['rotation'] as num?)?.toDouble() ?? 0,
  );
}

class CanvasDocument {
  const CanvasDocument({this.strokes=const [],this.texts=const [],this.paperColor=0xFFF8F7F3,this.showGrid=true,this.lockedIds=const <String>{}});
  final List<CanvasStroke> strokes;
  final List<CanvasText> texts;
  final int paperColor;
  final bool showGrid;
  final Set<String> lockedIds;
  Color get backgroundColor => Color(paperColor);
  CanvasDocument add(CanvasStroke stroke)=>CanvasDocument(strokes:[...strokes,stroke],texts:texts,paperColor:paperColor,showGrid:showGrid,lockedIds:lockedIds);
  CanvasDocument addText(CanvasText text)=>CanvasDocument(strokes:strokes,texts:[...texts,text],paperColor:paperColor,showGrid:showGrid);
  CanvasDocument remove(String id)=>CanvasDocument(strokes:strokes.where((s)=>s.id!=id).toList(),texts:texts,paperColor:paperColor,showGrid:showGrid);
  CanvasDocument clear()=>CanvasDocument(paperColor:paperColor,showGrid:showGrid);
  CanvasDocument withPaper({Color? color,bool? grid})=>CanvasDocument(strokes:strokes,texts:texts,paperColor:(color??backgroundColor).toARGB32(),showGrid:grid??showGrid);
  CanvasDocument translateIds(Set<String> ids, Offset delta) => CanvasDocument(
    strokes: [
      for (final stroke in strokes)
        ids.contains(stroke.id)
            ? stroke.copyWith(points: [
                for (final p in stroke.points)
                  CanvasPoint(p.x + delta.dx, p.y + delta.dy, pressure: p.pressure),
              ])
            : stroke,
    ],
    texts: [
      for (final text in texts)
        ids.contains(text.id) ? text.copyWith(x: text.x + delta.dx, y: text.y + delta.dy) : text,
    ],
    paperColor: paperColor, showGrid: showGrid, lockedIds: lockedIds,
  );

  CanvasDocument scaleIds(Set<String> ids, Rect from, Rect to) {
    final sx = from.width.abs() < 0.01 ? 1.0 : to.width / from.width;
    final sy = from.height.abs() < 0.01 ? 1.0 : to.height / from.height;
    final dx = to.left - from.left * sx;
    final dy = to.top - from.top * sy;
    final textScale = ((sx.abs() + sy.abs()) / 2).clamp(0.1, 8.0);
    return CanvasDocument(
      strokes: [
        for (final stroke in strokes)
          if (ids.contains(stroke.id))
            stroke.copyWith(points: [
              for (final p in stroke.points)
                CanvasPoint(p.x * sx + dx, p.y * sy + dy, pressure: p.pressure),
            ])
          else stroke,
      ],
      texts: [
        for (final text in texts)
          if (ids.contains(text.id))
            text.copyWith(x: text.x * sx + dx, y: text.y * sy + dy, size: (text.size * textScale).clamp(8.0, 240.0))
          else text,
      ],
      paperColor: paperColor, showGrid: showGrid,
    );
  }

  CanvasDocument rotateIds(Set<String> ids, double angle, Offset center) {
    Offset rotate(Offset point) {
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      return Offset(center.dx + dx * cosA - dy * sinA, center.dy + dx * sinA + dy * cosA);
    }
    return CanvasDocument(
      strokes: [
        for (final stroke in strokes)
          if (ids.contains(stroke.id))
            stroke.copyWith(points: [
              for (final p in stroke.points)
                (() { final r = rotate(p.offset); return CanvasPoint(r.dx, r.dy, pressure: p.pressure); })(),
            ])
          else stroke,
      ],
      texts: [
        for (final text in texts)
          if (ids.contains(text.id))
            (() {
              final r = rotate(text.bounds.center);
              return text.copyWith(x: r.dx - text.bounds.width / 2, y: r.dy - text.bounds.height / 2, rotation: text.rotation + angle);
            })()
          else text,
      ],
      paperColor: paperColor, showGrid: showGrid,
    );
  }

  CanvasDocument removeIds(Set<String> ids) => CanvasDocument(
    strokes: strokes.where((s) => !ids.contains(s.id)).toList(),
    texts: texts.where((t) => !ids.contains(t.id)).toList(),
    paperColor: paperColor, showGrid: showGrid,
  );

  CanvasDocument lockIds(Set<String> ids) => CanvasDocument(strokes: strokes, texts: texts, paperColor: paperColor, showGrid: showGrid, lockedIds: {...lockedIds, ...ids});
  CanvasDocument unlockIds(Set<String> ids) => CanvasDocument(strokes: strokes, texts: texts, paperColor: paperColor, showGrid: showGrid, lockedIds: lockedIds.difference(ids));

  CanvasDocument duplicateIds(Set<String> ids, {Offset delta = const Offset(24, 24)}) {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    return CanvasDocument(
      strokes: [
        ...strokes,
        for (final stroke in strokes.where((s) => ids.contains(s.id)))
          CanvasStroke(
            id: stroke.id + '_copy_' + suffix.toString(),
            points: [for (final p in stroke.points) CanvasPoint(p.x + delta.dx, p.y + delta.dy, pressure: p.pressure)],
            color: stroke.color, width: stroke.width, opacity: stroke.opacity,
            highlighter: stroke.highlighter, penStyle: stroke.penStyle,
          ),
      ],
      texts: [
        ...texts,
        for (final text in texts.where((t) => ids.contains(t.id)))
          CanvasText(
            id: text.id + '_copy_' + suffix.toString(),
            text: text.text, x: text.x + delta.dx, y: text.y + delta.dy,
            color: text.color, size: text.size, rotation: text.rotation,
          ),
      ],
      paperColor: paperColor, showGrid: showGrid,
    );
  }
  Map<String,Object> toJson()=>{'strokes':strokes.map((s)=>s.toJson()).toList(),'texts':texts.map((t)=>t.toJson()).toList(),'paperColor':paperColor,'showGrid':showGrid,'lockedIds':lockedIds.toList()};
  factory CanvasDocument.fromJson(Map<String,dynamic> json)=>CanvasDocument(
    strokes:(json['strokes'] as List<dynamic>? ?? const []).map((s)=>CanvasStroke.fromJson(s as Map<String,dynamic>)).toList(),
    texts:(json['texts'] as List<dynamic>? ?? const []).map((t)=>CanvasText.fromJson(t as Map<String,dynamic>)).toList(),
    paperColor:(json['paperColor'] as num?)?.toInt() ?? 0xFFF8F7F3,
    showGrid:json['showGrid'] as bool? ?? true,
    lockedIds:(json['lockedIds'] as List<dynamic>? ?? const []).whereType<String>().toSet(),
  );
}
