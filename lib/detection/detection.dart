import 'dart:ui';

class Detection {
  final Rect box;
  final double confidence;
  final int classId;
  final String label;

  const Detection({
    required this.box,
    required this.confidence,
    required this.classId,
    required this.label,
  });

  double get area => box.width * box.height;
}
