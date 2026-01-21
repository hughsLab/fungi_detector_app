import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/detection/detection.dart';
import 'package:realtime_detection_app/detection/iou.dart';
import 'package:realtime_detection_app/detection/stability_engine.dart';

void main() {
  test('intersectionOverUnion returns expected value', () {
    final Rect a = Rect.fromLTWH(0, 0, 1, 1);
    final Rect b = Rect.fromLTWH(0.5, 0.5, 1, 1);
    final double iou = intersectionOverUnion(a, b);
    expect(iou, closeTo(0.142857, 0.0001));
  });

  test('engine reuses track when IoU matches', () {
    final engine = DetectionStabilityEngine(
      labels: const ['a', 'b'],
      config: const StabilityConfig(
        detectConfMin: 0.0,
        iouMatchThreshold: 0.2,
        trackTtlMs: 1000,
        windowMs: 1000,
        windowFrames: 10,
        stabilityWindowFramesM: 2,
        lockWinCount: 1,
        readyConfMin: 0.0,
        readyMinAgeMs: 0,
      ),
    );

    final int t0 = 1000;
    final Detection d1 = Detection(
      box: Rect.fromLTWH(0, 0, 1, 1),
      confidence: 0.9,
      classId: 0,
      label: 'a',
    );
    final int trackId = engine.processFrame([d1], t0).single.trackId;

    final Detection d2 = Detection(
      box: Rect.fromLTWH(0.05, 0.05, 1, 1),
      confidence: 0.9,
      classId: 0,
      label: 'a',
    );
    final int trackId2 = engine.processFrame([d2], t0 + 33).single.trackId;

    expect(trackId2, trackId);
  });

  test('rolling window trims to max frames', () {
    final engine = DetectionStabilityEngine(
      labels: const ['a'],
      config: const StabilityConfig(
        detectConfMin: 0.0,
        windowFrames: 2,
        windowMs: 10000,
        stabilityWindowFramesM: 2,
        lockWinCount: 1,
        readyConfMin: 0.0,
        readyMinAgeMs: 0,
      ),
    );

    final Detection d = Detection(
      box: Rect.fromLTWH(0, 0, 1, 1),
      confidence: 0.9,
      classId: 0,
      label: 'a',
    );

    engine.processFrame([d], 0);
    engine.processFrame([d], 33);
    final StableTrack out = engine.processFrame([d], 66).single;

    expect(out.windowFrameCount, 2);
  });

  test('lock and ready trigger after stability window', () {
    final engine = DetectionStabilityEngine(
      labels: const ['a'],
      config: const StabilityConfig(
        detectConfMin: 0.0,
        stabilityWindowFramesM: 3,
        lockWinCount: 2,
        hysteresisFrames: 1,
        readyConfMin: 0.5,
        readyMinAgeMs: 0,
      ),
    );

    final Detection d = Detection(
      box: Rect.fromLTWH(0, 0, 1, 1),
      confidence: 0.9,
      classId: 0,
      label: 'a',
    );

    engine.processFrame([d], 0);
    engine.processFrame([d], 33);
    final StableTrack out = engine.processFrame([d], 66).single;

    expect(out.lockedClassId, 0);
    expect(out.isReadyToCapture, true);
  });

  test('ambiguous flag set when margin is small', () {
    final engine = DetectionStabilityEngine(
      labels: const ['a', 'b'],
      config: const StabilityConfig(
        detectConfMin: 0.0,
        stabilityWindowFramesM: 2,
        lockWinCount: 1,
        readyConfMin: 0.0,
        readyMinAgeMs: 0,
      ),
    );

    engine.processFrame(
      [
        Detection(
          box: Rect.fromLTWH(0, 0, 1, 1),
          confidence: 0.6,
          classId: 0,
          label: 'a',
        ),
      ],
      0,
    );
    final StableTrack out = engine.processFrame(
      [
        Detection(
          box: Rect.fromLTWH(0, 0, 1, 1),
          confidence: 0.55,
          classId: 1,
          label: 'b',
        ),
      ],
      33,
    ).single;

    expect(out.isAmbiguous, true);
    expect(out.top2Label, 'b');
  });
}
