import 'dart:ui';

class Detection {
  final Rect box;
  final double confidence;
  final int classId;
  final String label;
  final String modelId;
  final String modelDisplayName;
  final int sourceClassId;
  final String namespacedClassId;
  final String speciesName;
  final double rawConfidence;
  final double calibratedConfidence;
  final double finalScore;
  final List<String> sourceModelIds;
  final List<String> sourceModelDisplayNames;

  const Detection({
    required this.box,
    required this.confidence,
    required this.classId,
    required this.label,
    this.modelId = 'model_2',
    this.modelDisplayName = 'Model 2',
    int? sourceClassId,
    String? namespacedClassId,
    String? speciesName,
    double? rawConfidence,
    double? calibratedConfidence,
    double? finalScore,
    List<String>? sourceModelIds,
    List<String>? sourceModelDisplayNames,
  })  : sourceClassId = sourceClassId ?? classId,
        namespacedClassId = namespacedClassId ?? '$modelId:$classId',
        speciesName = speciesName ?? label,
        rawConfidence = rawConfidence ?? confidence,
        calibratedConfidence = calibratedConfidence ?? confidence,
        finalScore = finalScore ?? calibratedConfidence ?? confidence,
        sourceModelIds = sourceModelIds ?? const <String>[],
        sourceModelDisplayNames =
            sourceModelDisplayNames ?? const <String>[];

  double get area => box.width * box.height;

  String get sourceDisplayName {
    if (sourceModelDisplayNames.isNotEmpty) {
      return sourceModelDisplayNames.join(' + ');
    }
    return modelDisplayName;
  }

  String get overlayLabel {
    final int percent = (finalScore * 100).round().clamp(0, 100);
    return '$speciesName $percent% $sourceDisplayName';
  }
}
