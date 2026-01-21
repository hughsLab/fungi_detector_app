import 'observation.dart';

class SpeciesDetailArgs {
  final String speciesId;
  final Observation? observation;

  const SpeciesDetailArgs({
    required this.speciesId,
    this.observation,
  });
}

class SaveObservationArgs {
  final String? preselectedSpeciesId;

  const SaveObservationArgs({this.preselectedSpeciesId});
}

class DisclaimerArgs {
  final String? nextRoute;
  final bool allowBack;

  const DisclaimerArgs({
    this.nextRoute,
    this.allowBack = true,
  });
}

class DetectionResultArgs {
  final String lockedLabel;
  final String? top2Label;
  final double top1AvgConf;
  final double? top2AvgConf;
  final double top1VoteRatio;
  final int windowFrameCount;
  final int windowDurationMs;
  final int stabilityWinCount;
  final int stabilityWindowSize;
  final DateTime timestamp;
  final String? speciesId;

  const DetectionResultArgs({
    required this.lockedLabel,
    required this.top2Label,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
    required this.windowFrameCount,
    required this.windowDurationMs,
    required this.stabilityWinCount,
    required this.stabilityWindowSize,
    required this.timestamp,
    required this.speciesId,
  });
}
