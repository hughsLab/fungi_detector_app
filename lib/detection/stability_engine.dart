import 'dart:ui';

import 'detection.dart';
import 'iou.dart';
import 'track.dart';

class StabilityConfig {
  final double detectConfMin;
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

  const StabilityConfig({
    this.detectConfMin = 0.45,
    this.iouMatchThreshold = 0.5,
    this.trackTtlMs = 700,
    this.windowMs = 1500,
    this.windowFrames = 45,
    this.stabilityWindowFramesM = 5,
    this.lockWinCount = 4,
    this.marginMin = 0.08,
    this.hysteresisFrames = 5,
    this.hysteresisDelta = 0.10,
    this.readyConfMin = 0.55,
    this.readyMinAgeMs = 600,
  });
}

class StableTrack {
  final int trackId;
  final Rect bbox;
  final int? lockedClassId;
  final String? lockedLabel;
  final double lockedAvgConf;
  final int? top1ClassId;
  final String? top1Label;
  final int? top2ClassId;
  final String? top2Label;
  final double top1AvgConf;
  final double top2AvgConf;
  final double top1VoteRatio;
  final bool isAmbiguous;
  final bool isStable;
  final bool isReadyToCapture;
  final int windowFrameCount;
  final int windowDurationMs;
  final int stabilityWinCount;
  final int stabilityWindowSize;

  const StableTrack({
    required this.trackId,
    required this.bbox,
    required this.lockedClassId,
    required this.lockedLabel,
    required this.lockedAvgConf,
    required this.top1ClassId,
    required this.top1Label,
    required this.top2ClassId,
    required this.top2Label,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
    required this.isAmbiguous,
    required this.isStable,
    required this.isReadyToCapture,
    required this.windowFrameCount,
    required this.windowDurationMs,
    required this.stabilityWinCount,
    required this.stabilityWindowSize,
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
        .where((d) => d.confidence >= config.detectConfMin)
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
      track.addSample(
        timestampMs,
        detection.classId,
        detection.confidence,
      );
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
    final int? top1ClassId = aggregate.top1ClassId;

    if (top1ClassId != null) {
      track.pushWinner(top1ClassId, config.stabilityWindowFramesM);
    }

    final int stabilityWindowFilled = track.lastMFrameWinners.length;
    final int top1WinCount = top1ClassId == null
        ? 0
        : track.lastMFrameWinners
            .where((id) => id == top1ClassId)
            .length;
    final bool hasFullStabilityWindow =
        stabilityWindowFilled >= config.stabilityWindowFramesM;
    final bool stable = hasFullStabilityWindow &&
        top1ClassId != null &&
        top1WinCount >= config.lockWinCount;

    final bool ambiguous = top1ClassId != null &&
        aggregate.top2ClassId != null &&
        (aggregate.top1AvgConf - aggregate.top2AvgConf) < config.marginMin;

    _applyLocking(
      track,
      top1ClassId,
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
      lockedClassId: track.lockedClassId,
      lockedLabel: track.lockedClassId == null
          ? null
          : _labelFor(track.lockedClassId!),
      lockedAvgConf: track.lockedAvgConf,
      top1ClassId: top1ClassId,
      top1Label: top1ClassId == null ? null : _labelFor(top1ClassId),
      top2ClassId: aggregate.top2ClassId,
      top2Label: aggregate.top2ClassId == null
          ? null
          : _labelFor(aggregate.top2ClassId!),
      top1AvgConf: aggregate.top1AvgConf,
      top2AvgConf: aggregate.top2AvgConf,
      top1VoteRatio: aggregate.top1VoteRatio,
      isAmbiguous: ambiguous,
      isStable: stable,
      isReadyToCapture: ready,
      windowFrameCount: windowFrameCount,
      windowDurationMs: windowDurationMs,
      stabilityWinCount: top1WinCount,
      stabilityWindowSize: config.stabilityWindowFramesM,
    );
  }

  void _applyLocking(
    Track track,
    int? top1ClassId,
    double top1AvgConf,
    bool stable,
    int timestampMs,
  ) {
    if (top1ClassId == null) {
      track.candidateClassId = null;
      track.consecutiveWinsForCandidate = 0;
      return;
    }

    if (track.lockedClassId == null) {
      if (stable) {
        _lockTo(track, top1ClassId, top1AvgConf, timestampMs);
      }
      return;
    }

    if (track.lockedClassId == top1ClassId) {
      track.candidateClassId = null;
      track.consecutiveWinsForCandidate = 0;
      track.lockedAvgConf = top1AvgConf;
      return;
    }

    if (track.candidateClassId == top1ClassId) {
      track.consecutiveWinsForCandidate += 1;
    } else {
      track.candidateClassId = top1ClassId;
      track.consecutiveWinsForCandidate = 1;
    }

    final bool canSwitchByStable = stable &&
        track.consecutiveWinsForCandidate >= config.hysteresisFrames;
    final bool canSwitchByDelta =
        track.consecutiveWinsForCandidate >= config.hysteresisFrames &&
            top1AvgConf >= track.lockedAvgConf + config.hysteresisDelta;

    if (canSwitchByStable || canSwitchByDelta) {
      _lockTo(track, top1ClassId, top1AvgConf, timestampMs);
    }
  }

  void _lockTo(
    Track track,
    int classId,
    double avgConf,
    int timestampMs,
  ) {
    track.lockedClassId = classId;
    track.lockedSinceMs = timestampMs;
    track.lockedAvgConf = avgConf;
    track.candidateClassId = null;
    track.consecutiveWinsForCandidate = 0;
  }

  _AggregateResult _aggregateWindow(Track track) {
    if (track.window.isEmpty) {
      return const _AggregateResult.empty();
    }

    final Map<int, double> scores = <int, double>{};
    final Map<int, int> counts = <int, int>{};
    for (final sample in track.window) {
      scores[sample.classId] =
          (scores[sample.classId] ?? 0) + sample.confidence;
      counts[sample.classId] = (counts[sample.classId] ?? 0) + 1;
    }

    final List<MapEntry<int, double>> ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final int top1ClassId = ranked.first.key;
    final double top1Score = ranked.first.value;
    final int top1Count = counts[top1ClassId] ?? 0;
    final double top1AvgConf =
        top1Count == 0 ? 0.0 : top1Score / top1Count;

    int? top2ClassId;
    double top2Score = 0.0;
    double top2AvgConf = 0.0;
    if (ranked.length > 1) {
      top2ClassId = ranked[1].key;
      top2Score = ranked[1].value;
      final int top2Count = counts[top2ClassId] ?? 0;
      top2AvgConf = top2Count == 0 ? 0.0 : top2Score / top2Count;
    }

    final int totalFrames = track.window.length;
    final double top1VoteRatio =
        totalFrames == 0 ? 0.0 : top1Count / totalFrames;

    return _AggregateResult(
      top1ClassId: top1ClassId,
      top2ClassId: top2ClassId,
      top1AvgConf: top1AvgConf,
      top2AvgConf: top2AvgConf,
      top1VoteRatio: top1VoteRatio,
    );
  }
}

class _AggregateResult {
  final int? top1ClassId;
  final int? top2ClassId;
  final double top1AvgConf;
  final double top2AvgConf;
  final double top1VoteRatio;

  const _AggregateResult({
    required this.top1ClassId,
    required this.top2ClassId,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
  });

  const _AggregateResult.empty()
      : top1ClassId = null,
        top2ClassId = null,
        top1AvgConf = 0.0,
        top2AvgConf = 0.0,
        top1VoteRatio = 0.0;
}
