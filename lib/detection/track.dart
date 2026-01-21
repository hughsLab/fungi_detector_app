import 'dart:collection';
import 'dart:ui';

class DetectionSample {
  final int timestampMs;
  final int classId;
  final double confidence;

  const DetectionSample({
    required this.timestampMs,
    required this.classId,
    required this.confidence,
  });
}

class Track {
  Track({
    required this.id,
    required this.bbox,
    required this.createdAtMs,
    required this.lastSeenMs,
  })  : window = ListQueue<DetectionSample>(),
        lastMFrameWinners = ListQueue<int>(),
        lockedSinceMs = createdAtMs;

  final int id;
  Rect bbox;
  final int createdAtMs;
  int lastSeenMs;

  final ListQueue<DetectionSample> window;
  final ListQueue<int> lastMFrameWinners;

  int? lockedClassId;
  int lockedSinceMs;
  double lockedAvgConf = 0.0;

  int? candidateClassId;
  int consecutiveWinsForCandidate = 0;

  double get area => bbox.width * bbox.height;

  void addSample(int timestampMs, int classId, double confidence) {
    window.addLast(
      DetectionSample(
        timestampMs: timestampMs,
        classId: classId,
        confidence: confidence,
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

  void pushWinner(int classId, int maxFrames) {
    lastMFrameWinners.addLast(classId);
    while (lastMFrameWinners.length > maxFrames) {
      lastMFrameWinners.removeFirst();
    }
  }
}
