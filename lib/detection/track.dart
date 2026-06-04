import 'dart:collection';
import 'dart:ui';

import 'detection.dart';

class DetectionSample {
  final int timestampMs;
  final String classKey;
  final int sourceClassId;
  final String modelId;
  final String modelDisplayName;
  final String label;
  final double confidence;
  final double rawConfidence;
  final double calibratedConfidence;
  final double finalScore;

  const DetectionSample({
    required this.timestampMs,
    required this.classKey,
    required this.sourceClassId,
    required this.modelId,
    required this.modelDisplayName,
    required this.label,
    required this.confidence,
    required this.rawConfidence,
    required this.calibratedConfidence,
    required this.finalScore,
  });
}

class Track {
  Track({
    required this.id,
    required this.bbox,
    required this.createdAtMs,
    required this.lastSeenMs,
  })  : window = ListQueue<DetectionSample>(),
        lastMFrameWinners = ListQueue<String>(),
        lockedSinceMs = createdAtMs;

  final int id;
  Rect bbox;
  final int createdAtMs;
  int lastSeenMs;

  final ListQueue<DetectionSample> window;
  final ListQueue<String> lastMFrameWinners;

  int? lockedClassId;
  String? lockedClassKey;
  String? lockedModelId;
  String? lockedModelDisplayName;
  String? lockedLabel;
  int lockedSinceMs;
  double lockedAvgConf = 0.0;

  String? candidateClassKey;
  int consecutiveWinsForCandidate = 0;

  double get area => bbox.width * bbox.height;

  void addSample(int timestampMs, Detection detection) {
    window.addLast(
      DetectionSample(
        timestampMs: timestampMs,
        classKey: detection.namespacedClassId,
        sourceClassId: detection.sourceClassId,
        modelId: detection.modelId,
        modelDisplayName: detection.sourceDisplayName,
        label: detection.speciesName,
        confidence: detection.confidence,
        rawConfidence: detection.rawConfidence,
        calibratedConfidence: detection.calibratedConfidence,
        finalScore: detection.finalScore,
      ),
    );
    lastSeenMs = timestampMs;
  }

  void trimWindow(int nowMs, int windowMs, int maxFrames) {
    while (window.isNotEmpty &&
        nowMs - window.first.timestampMs > windowMs) {
      window.removeFirst();
    }
    while (window.length > maxFrames) {
      window.removeFirst();
    }
  }

  void pushWinner(String classKey, int maxFrames) {
    lastMFrameWinners.addLast(classKey);
    while (lastMFrameWinners.length > maxFrames) {
      lastMFrameWinners.removeFirst();
    }
  }
}
