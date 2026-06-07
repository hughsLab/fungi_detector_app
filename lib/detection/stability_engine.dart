import 'dart:ui';

import 'detection.dart';
import 'iou.dart';
import 'track.dart';

class StabilityConfig {
  final double detectConfMin;
  final Map<String, double> modelDetectConfMin;
  final double iouMatchThreshold;
  final int trackTtlMs;
  final int windowMs;
  final int windowFrames;
  final int stabilityWindowFramesM;
  final int lockWinCount;
  final double marginMin;
  final int hysteresisFrames;
  final double hysteresisDelta;
  final double readyConfMin;
  final int readyMinAgeMs;
  final double provisionalConfMin;
  final double stableConfMin;
  final Map<String, double> modelStableConfMin;
  final int minObservationsForStability;
  final double adaptiveHighConfMin;
  final double adaptiveMediumConfMin;
  final int adaptiveHighConfWins;
  final int adaptiveMediumConfWins;

  const StabilityConfig({
    this.detectConfMin = 0.45,
    this.modelDetectConfMin = const <String, double>{},
    this.iouMatchThreshold = 0.5,
    this.trackTtlMs = 1200,
    this.windowMs = 1500,
    this.windowFrames = 45,
    this.stabilityWindowFramesM = 5,
    this.lockWinCount = 4,
    this.marginMin = 0.08,
    this.hysteresisFrames = 5,
    this.hysteresisDelta = 0.10,
    this.readyConfMin = 0.55,
    this.readyMinAgeMs = 600,
    this.provisionalConfMin = 0.55,
    this.stableConfMin = 0.55,
    this.modelStableConfMin = const <String, double>{},
    this.minObservationsForStability = 1,
    this.adaptiveHighConfMin = 0.85,
    this.adaptiveMediumConfMin = 0.70,
    this.adaptiveHighConfWins = 2,
    this.adaptiveMediumConfWins = 3,
  });

  double detectConfMinFor(Detection detection) {
    return modelDetectConfMin[detection.modelId] ?? detectConfMin;
  }

  double stableConfMinFor(String? modelId) {
    if (modelId == null) {
      return stableConfMin;
    }
    return modelStableConfMin[modelId] ?? stableConfMin;
  }
}

class StableTrack {
  final int trackId;
  final Rect bbox;
  final String? lockedClassKey;
  final int? lockedClassId;
  final String? lockedModelId;
  final String? lockedModelDisplayName;
  final String? lockedLabel;
  final double lockedAvgConf;
  final String? top1ClassKey;
  final int? top1ClassId;
  final String? top1ModelId;
  final String? top1ModelDisplayName;
  final String? top1Label;
  final String? top2ClassKey;
  final int? top2ClassId;
  final String? top2ModelId;
  final String? top2ModelDisplayName;
  final String? top2Label;
  final double top1AvgConf;
  final double top2AvgConf;
  final double top1VoteRatio;
  final bool isAmbiguous;
  final bool isProvisional;
  final bool isStable;
  final bool isAdaptiveStable;
  final bool isReadyToCapture;
  final int windowFrameCount;
  final int windowDurationMs;
  final int stabilityWinCount;
  final int stabilityWindowSize;
  final int consecutiveTop1Wins;
  final int requiredWinsForStability;

  const StableTrack({
    required this.trackId,
    required this.bbox,
    required this.lockedClassKey,
    required this.lockedClassId,
    required this.lockedModelId,
    required this.lockedModelDisplayName,
    required this.lockedLabel,
    required this.lockedAvgConf,
    required this.top1ClassKey,
    required this.top1ClassId,
    required this.top1ModelId,
    required this.top1ModelDisplayName,
    required this.top1Label,
    required this.top2ClassKey,
    required this.top2ClassId,
    required this.top2ModelId,
    required this.top2ModelDisplayName,
    required this.top2Label,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
    required this.isAmbiguous,
    required this.isProvisional,
    required this.isStable,
    required this.isAdaptiveStable,
    required this.isReadyToCapture,
    required this.windowFrameCount,
    required this.windowDurationMs,
    required this.stabilityWinCount,
    required this.stabilityWindowSize,
    required this.consecutiveTop1Wins,
    required this.requiredWinsForStability,
  });
}

class DetectionStabilityEngine {
  DetectionStabilityEngine({
    required List<String> labels,
    StabilityConfig? config,
  })  : _labels = labels,
        config = config ?? const StabilityConfig();

  final List<String> _labels;
  final StabilityConfig config;
  final Map<int, Track> _tracks = {};
  int _nextTrackId = 1;

  List<StableTrack> processFrame(List<Detection> detections, int timestampMs) {
    final List<Detection> filtered = detections
        .where((d) => d.confidence >= config.detectConfMinFor(d))
        .toList(growable: false);
    final List<Detection> sorted = [...filtered]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final Set<int> assignedTrackIds = <int>{};
    final Map<int, Detection> updates = <int, Detection>{};

    for (final detection in sorted) {
      Track? bestTrack;
      double bestIou = 0.0;
      for (final track in _tracks.values) {
        if (assignedTrackIds.contains(track.id)) {
          continue;
        }
        final double score = intersectionOverUnion(detection.box, track.bbox);
        if (score > bestIou) {
          bestIou = score;
          bestTrack = track;
        }
      }

      if (bestTrack != null && bestIou >= config.iouMatchThreshold) {
        updates[bestTrack.id] = detection;
        assignedTrackIds.add(bestTrack.id);
      } else {
        final int id = _nextTrackId++;
        final Track track = Track(
          id: id,
          bbox: detection.box,
          createdAtMs: timestampMs,
          lastSeenMs: timestampMs,
        );
        _tracks[id] = track;
        updates[id] = detection;
        assignedTrackIds.add(id);
      }
    }

    for (final entry in updates.entries) {
      final Track track = _tracks[entry.key]!;
      final Detection detection = entry.value;
      track.bbox = detection.box;
      track.addSample(timestampMs, detection);
    }

    final List<int> expired = <int>[];
    final List<StableTrack> output = <StableTrack>[];

    for (final track in _tracks.values) {
      track.trimWindow(
        timestampMs,
        config.windowMs,
        config.windowFrames,
      );
      if (timestampMs - track.lastSeenMs > config.trackTtlMs) {
        expired.add(track.id);
        continue;
      }
      output.add(_buildStableTrack(track, timestampMs));
    }

    for (final id in expired) {
      _tracks.remove(id);
    }

    output.sort(
      (a, b) => (b.bbox.width * b.bbox.height)
          .compareTo(a.bbox.width * a.bbox.height),
    );
    return output;
  }

  String _labelFor(int classId) {
    if (classId >= 0 && classId < _labels.length) {
      return _labels[classId];
    }
    return 'id_$classId';
  }

  StableTrack _buildStableTrack(Track track, int timestampMs) {
    final _AggregateResult aggregate = _aggregateWindow(track);
    final String? top1ClassKey = aggregate.top1ClassKey;

    if (top1ClassKey != null) {
      track.pushWinner(top1ClassKey, config.stabilityWindowFramesM);
    }

    final int stabilityWindowFilled = track.lastMFrameWinners.length;
    final int top1WinCount = top1ClassKey == null
        ? 0
        : track.lastMFrameWinners
            .where((id) => id == top1ClassKey)
            .length;
    final bool hasFullStabilityWindow =
        stabilityWindowFilled >= config.stabilityWindowFramesM;
    final bool hasEnoughObservations = aggregate.top1Count >=
        config.minObservationsForStability;
    final bool stableConfidence = aggregate.top1AvgConf >=
        config.stableConfMinFor(aggregate.top1?.modelId);
    final bool normalStable = hasFullStabilityWindow &&
        top1ClassKey != null &&
        top1WinCount >= config.lockWinCount &&
        hasEnoughObservations &&
        stableConfidence;
    final int consecutiveTop1Wins = top1ClassKey == null
        ? 0
        : _consecutiveWinnerStreak(track, top1ClassKey);
    final int? adaptiveRequiredWins = _adaptiveWinRequirement(
      aggregate.top1AvgConf,
    );
    final bool adaptiveStable = top1ClassKey != null &&
        adaptiveRequiredWins != null &&
        consecutiveTop1Wins >= adaptiveRequiredWins &&
        hasEnoughObservations &&
        stableConfidence;
    final bool stable = normalStable || adaptiveStable;

    final bool ambiguous = top1ClassKey != null &&
        aggregate.top2ClassKey != null &&
        (aggregate.top1AvgConf - aggregate.top2AvgConf) < config.marginMin;
    final bool provisional =
        top1ClassKey != null && aggregate.top1AvgConf >= config.provisionalConfMin;

    _applyLocking(
      track,
      aggregate.top1,
      aggregate.top1AvgConf,
      stable,
      timestampMs,
    );

    final bool ready = stable &&
        aggregate.top1AvgConf >= config.readyConfMin &&
        (timestampMs - track.createdAtMs) >= config.readyMinAgeMs;

    final int windowFrameCount = track.window.length;
    final int windowDurationMs = windowFrameCount == 0
        ? 0
        : timestampMs - track.window.first.timestampMs;

    return StableTrack(
      trackId: track.id,
      bbox: track.bbox,
      lockedClassKey: track.lockedClassKey,
      lockedClassId: track.lockedClassId,
      lockedModelId: track.lockedModelId,
      lockedModelDisplayName: track.lockedModelDisplayName,
      lockedLabel: track.lockedLabel ??
          (track.lockedClassId == null ? null : _labelFor(track.lockedClassId!)),
      lockedAvgConf: track.lockedAvgConf,
      top1ClassKey: aggregate.top1ClassKey,
      top1ClassId: aggregate.top1?.sourceClassId,
      top1ModelId: aggregate.top1?.modelId,
      top1ModelDisplayName: aggregate.top1?.modelDisplayName,
      top1Label: aggregate.top1?.label ??
          (aggregate.top1?.sourceClassId == null
              ? null
              : _labelFor(aggregate.top1!.sourceClassId)),
      top2ClassKey: aggregate.top2ClassKey,
      top2ClassId: aggregate.top2?.sourceClassId,
      top2ModelId: aggregate.top2?.modelId,
      top2ModelDisplayName: aggregate.top2?.modelDisplayName,
      top2Label: aggregate.top2?.label ??
          (aggregate.top2?.sourceClassId == null
              ? null
              : _labelFor(aggregate.top2!.sourceClassId)),
      top1AvgConf: aggregate.top1AvgConf,
      top2AvgConf: aggregate.top2AvgConf,
      top1VoteRatio: aggregate.top1VoteRatio,
      isAmbiguous: ambiguous,
      isProvisional: provisional,
      isStable: stable,
      isAdaptiveStable: adaptiveStable && !normalStable,
      isReadyToCapture: ready,
      windowFrameCount: windowFrameCount,
      windowDurationMs: windowDurationMs,
      stabilityWinCount: top1WinCount,
      stabilityWindowSize: config.stabilityWindowFramesM,
      consecutiveTop1Wins: consecutiveTop1Wins,
      requiredWinsForStability: adaptiveRequiredWins ?? config.lockWinCount,
    );
  }

  int _consecutiveWinnerStreak(Track track, String classKey) {
    int streak = 0;
    for (final winner in track.lastMFrameWinners.toList().reversed) {
      if (winner != classKey) {
        break;
      }
      streak += 1;
    }
    return streak;
  }

  int? _adaptiveWinRequirement(double avgConfidence) {
    if (avgConfidence >= config.adaptiveHighConfMin) {
      return config.adaptiveHighConfWins;
    }
    if (avgConfidence >= config.adaptiveMediumConfMin) {
      return config.adaptiveMediumConfWins;
    }
    return null;
  }

  void _applyLocking(
    Track track,
    _AggregateClass? top1,
    double top1AvgConf,
    bool stable,
    int timestampMs,
  ) {
    final String? top1ClassKey = top1?.classKey;
    if (top1ClassKey == null || top1 == null) {
      track.candidateClassKey = null;
      track.consecutiveWinsForCandidate = 0;
      return;
    }

    if (track.lockedClassKey == null) {
      if (stable) {
        _lockTo(track, top1, top1AvgConf, timestampMs);
      }
      return;
    }

    if (track.lockedClassKey == top1ClassKey) {
      track.candidateClassKey = null;
      track.consecutiveWinsForCandidate = 0;
      track.lockedAvgConf = top1AvgConf;
      return;
    }

    if (track.candidateClassKey == top1ClassKey) {
      track.consecutiveWinsForCandidate += 1;
    } else {
      track.candidateClassKey = top1ClassKey;
      track.consecutiveWinsForCandidate = 1;
    }

    final bool canSwitchByStable = stable &&
        track.consecutiveWinsForCandidate >= config.hysteresisFrames;
    final bool canSwitchByDelta =
        track.consecutiveWinsForCandidate >= config.hysteresisFrames &&
            top1AvgConf >= track.lockedAvgConf + config.hysteresisDelta;

    if (canSwitchByStable || canSwitchByDelta) {
      _lockTo(track, top1, top1AvgConf, timestampMs);
    }
  }

  void _lockTo(
    Track track,
    _AggregateClass winner,
    double avgConf,
    int timestampMs,
  ) {
    track.lockedClassKey = winner.classKey;
    track.lockedClassId = winner.sourceClassId;
    track.lockedModelId = winner.modelId;
    track.lockedModelDisplayName = winner.modelDisplayName;
    track.lockedLabel = winner.label;
    track.lockedSinceMs = timestampMs;
    track.lockedAvgConf = avgConf;
    track.candidateClassKey = null;
    track.consecutiveWinsForCandidate = 0;
  }

  _AggregateResult _aggregateWindow(Track track) {
    if (track.window.isEmpty) {
      return const _AggregateResult.empty();
    }

    final Map<String, double> scores = <String, double>{};
    final Map<String, int> counts = <String, int>{};
    final Map<String, DetectionSample> representatives =
        <String, DetectionSample>{};
    for (final sample in track.window) {
      scores[sample.classKey] =
          (scores[sample.classKey] ?? 0) + sample.finalScore;
      counts[sample.classKey] = (counts[sample.classKey] ?? 0) + 1;
      representatives[sample.classKey] = sample;
    }

    final List<MapEntry<String, double>> ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final String top1ClassKey = ranked.first.key;
    final double top1Score = ranked.first.value;
    final int top1Count = counts[top1ClassKey] ?? 0;
    final double top1AvgConf =
        top1Count == 0 ? 0.0 : top1Score / top1Count;
    final DetectionSample? top1Sample = representatives[top1ClassKey];

    String? top2ClassKey;
    double top2Score = 0.0;
    double top2AvgConf = 0.0;
    DetectionSample? top2Sample;
    if (ranked.length > 1) {
      top2ClassKey = ranked[1].key;
      top2Score = ranked[1].value;
      final int top2Count = counts[top2ClassKey] ?? 0;
      top2AvgConf = top2Count == 0 ? 0.0 : top2Score / top2Count;
      top2Sample = representatives[top2ClassKey];
    }

    final int totalFrames = track.window.length;
    final double top1VoteRatio =
        totalFrames == 0 ? 0.0 : top1Count / totalFrames;

    return _AggregateResult(
      top1: top1Sample == null
          ? null
          : _AggregateClass.fromSample(top1Sample),
      top2: top2Sample == null
          ? null
          : _AggregateClass.fromSample(top2Sample),
      top1AvgConf: top1AvgConf,
      top2AvgConf: top2AvgConf,
      top1VoteRatio: top1VoteRatio,
      top1Count: top1Count,
    );
  }
}

class _AggregateResult {
  final _AggregateClass? top1;
  final _AggregateClass? top2;
  final double top1AvgConf;
  final double top2AvgConf;
  final double top1VoteRatio;
  final int top1Count;

  const _AggregateResult({
    required this.top1,
    required this.top2,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
    required this.top1Count,
  });

  const _AggregateResult.empty()
      : top1 = null,
        top2 = null,
        top1AvgConf = 0.0,
        top2AvgConf = 0.0,
        top1VoteRatio = 0.0,
        top1Count = 0;

  String? get top1ClassKey => top1?.classKey;
  String? get top2ClassKey => top2?.classKey;
}

class _AggregateClass {
  final String classKey;
  final int sourceClassId;
  final String modelId;
  final String modelDisplayName;
  final String label;

  const _AggregateClass({
    required this.classKey,
    required this.sourceClassId,
    required this.modelId,
    required this.modelDisplayName,
    required this.label,
  });

  factory _AggregateClass.fromSample(DetectionSample sample) {
    return _AggregateClass(
      classKey: sample.classKey,
      sourceClassId: sample.sourceClassId,
      modelId: sample.modelId,
      modelDisplayName: sample.modelDisplayName,
      label: sample.label,
    );
  }
}
