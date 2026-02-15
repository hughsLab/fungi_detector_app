import 'observation.dart';
import 'field_note.dart';

class SpeciesDetailArgs {
  final String speciesId;
  final Observation? observation;
  final String? comparePrimaryLabel;
  final String? compareSecondaryLabel;

  const SpeciesDetailArgs({
    required this.speciesId,
    this.observation,
    this.comparePrimaryLabel,
    this.compareSecondaryLabel,
  });
}

class SaveObservationArgs {
  final String? preselectedSpeciesId;

  const SaveObservationArgs({this.preselectedSpeciesId});
}

class MapFocusRequest {
  final String? observationId;
  final double lat;
  final double lon;
  final double zoom;
  final String? label;

  const MapFocusRequest({
    required this.observationId,
    required this.lat,
    required this.lon,
    this.zoom = 15,
    this.label,
  });
}

class MapPickLocationArgs {
  final double? initialLat;
  final double? initialLon;
  final String? title;

  const MapPickLocationArgs({this.initialLat, this.initialLon, this.title});
}

class MapPickResult {
  final double lat;
  final double lon;
  final String? label;

  const MapPickResult({
    required this.lat,
    required this.lon,
    this.label,
  });
}

class FieldNoteEditorArgs {
  final String? noteId;
  final String? prelinkedObservationId;
  final String? prelinkedSpeciesId;
  final LocationRef? prelinkedLocation;

  const FieldNoteEditorArgs({
    this.noteId,
    this.prelinkedObservationId,
    this.prelinkedSpeciesId,
    this.prelinkedLocation,
  });
}

class DisclaimerArgs {
  final String? nextRoute;
  final bool allowBack;

  const DisclaimerArgs({this.nextRoute, this.allowBack = true});
}

class DetectionResultArgs {
  final String? observationId;
  final String lockedLabel;
  final String? top2Label;
  final int? top2ClassIndex;
  final double top1AvgConf;
  final double? top2AvgConf;
  final double top1VoteRatio;
  final int windowFrameCount;
  final int windowDurationMs;
  final int stabilityWinCount;
  final int stabilityWindowSize;
  final DateTime timestamp;
  final String? speciesId;
  final int? classIndex;
  final String? photoPath;
  final bool isLichen;
  final bool isSavedView;

  const DetectionResultArgs({
    required this.observationId,
    required this.lockedLabel,
    required this.top2Label,
    this.top2ClassIndex,
    required this.top1AvgConf,
    required this.top2AvgConf,
    required this.top1VoteRatio,
    required this.windowFrameCount,
    required this.windowDurationMs,
    required this.stabilityWinCount,
    required this.stabilityWindowSize,
    required this.timestamp,
    required this.speciesId,
    required this.classIndex,
    this.photoPath,
    required this.isLichen,
    this.isSavedView = false,
  });
}
