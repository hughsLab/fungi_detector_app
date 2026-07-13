import 'observation.dart';
import 'field_note.dart';
import 'mushroom_id_result.dart';

enum SpeciesDetailSource {
  speciesLibrary,
  detectionResult,
  existingObservation,
}

class SpeciesDetailArgs {
  final String speciesId;
  final Observation? observation;
  final String? comparePrimaryLabel;
  final String? compareSecondaryLabel;
  final SpeciesDetailSource source;

  const SpeciesDetailArgs({
    required this.speciesId,
    this.observation,
    this.comparePrimaryLabel,
    this.compareSecondaryLabel,
    this.source = SpeciesDetailSource.speciesLibrary,
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
  final String? modelId;
  final String? modelDisplayName;
  final int? sourceClassId;
  final double? rawConfidence;
  final double? calibratedConfidence;
  final double? finalScore;
  final String? top2ModelId;
  final String? top2ModelDisplayName;
  final int? top2SourceClassId;
  final List<ObservationCandidate> candidates;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final bool isLichen;
  final bool isSavedView;
  final bool isConfirmed;

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
    this.modelId,
    this.modelDisplayName,
    this.sourceClassId,
    this.rawConfidence,
    this.calibratedConfidence,
    this.finalScore,
    this.top2ModelId,
    this.top2ModelDisplayName,
    this.top2SourceClassId,
    this.candidates = const <ObservationCandidate>[],
    this.photoPath,
    this.latitude,
    this.longitude,
    this.locationLabel,
    required this.isLichen,
    this.isSavedView = false,
    this.isConfirmed = true,
  });
}

class OnlineIdentificationResultArgs {
  final MushroomIdResult result;
  final String photoPath;
  final String? country;
  final String? region;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final String? locationLabel;

  const OnlineIdentificationResultArgs({
    required this.result,
    required this.photoPath,
    this.country,
    this.region,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.capturedAt,
    this.locationLabel,
  });
}
