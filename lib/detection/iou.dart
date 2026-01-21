import 'dart:math' as math;
import 'dart:ui';

double intersectionOverUnion(Rect a, Rect b) {
  final double intersectionLeft = math.max(a.left, b.left);
  final double intersectionTop = math.max(a.top, b.top);
  final double intersectionRight = math.min(a.right, b.right);
  final double intersectionBottom = math.min(a.bottom, b.bottom);

  final double intersectionWidth =
      math.max(0.0, intersectionRight - intersectionLeft);
  final double intersectionHeight =
      math.max(0.0, intersectionBottom - intersectionTop);
  final double intersectionArea = intersectionWidth * intersectionHeight;
  if (intersectionArea <= 0) {
    return 0.0;
  }

  final double areaA = a.width * a.height;
  final double areaB = b.width * b.height;
  final double unionArea = areaA + areaB - intersectionArea;
  if (unionArea <= 0) {
    return 0.0;
  }

  return intersectionArea / unionArea;
}
