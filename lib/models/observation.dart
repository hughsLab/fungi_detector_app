enum ObservationLocationSource { deviceGps, exifGps, none }

class Observation {
  final String id;
  final String speciesId;
  final int? classIndex;
  final String? modelId;
  final String? modelDisplayName;
  final int? sourceClassId;
  final String label;
  final String? colloquialName;
  final double? confidence;
  final double? rawConfidence;
  final double? calibratedConfidence;
  final double? finalScore;
  final String? top2Label;
  final double? top2Confidence;
  final String? top2ModelId;
  final String? top2ModelDisplayName;
  final int? top2SourceClassId;
  final double? top1VoteRatio;
  final int? windowFrameCount;
  final int? windowDurationMs;
  final int? stabilityWinCount;
  final int? stabilityWindowSize;
  final bool? isLichen;
  final DateTime createdAt;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final ObservationLocationSource locationSource;
  final String? locationLabel;
  final String? notes;

  const Observation({
    required this.id,
    required this.speciesId,
    required this.classIndex,
    this.modelId,
    this.modelDisplayName,
    this.sourceClassId,
    required this.label,
    this.colloquialName,
    required this.confidence,
    this.rawConfidence,
    this.calibratedConfidence,
    this.finalScore,
    this.top2Label,
    this.top2Confidence,
    this.top2ModelId,
    this.top2ModelDisplayName,
    this.top2SourceClassId,
    this.top1VoteRatio,
    this.windowFrameCount,
    this.windowDurationMs,
    this.stabilityWinCount,
    this.stabilityWindowSize,
    this.isLichen,
    required this.createdAt,
    required this.photoPath,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.capturedAt,
    this.locationSource = ObservationLocationSource.none,
    this.locationLabel,
    this.notes,
  });

  String get speciesName => label;
  double? get lat => latitude;
  double? get lon => longitude;
  DateTime get timestamp => createdAt;

  ObservationLocation? get location {
    final lat = latitude;
    final lon = longitude;
    if (lat == null || lon == null) {
      return null;
    }
    return ObservationLocation(
      latitude: lat,
      longitude: lon,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt,
    );
  }

  factory Observation.fromJson(Map<String, dynamic> json) {
    final locationJson = json['location'];
    ObservationLocation? location;
    if (locationJson is Map<String, dynamic>) {
      location = ObservationLocation.fromJson(locationJson);
    }

    final dynamic rawClassIndex = json['classIndex'];
    int? classIndex;
    if (rawClassIndex is int) {
      classIndex = rawClassIndex;
    } else if (rawClassIndex is num) {
      classIndex = rawClassIndex.toInt();
    } else if (rawClassIndex != null) {
      classIndex = int.tryParse(rawClassIndex.toString());
    }

    final String speciesId =
        json['speciesId']?.toString() ??
        (classIndex == null ? '' : classIndex.toString());

    final double? latitude =
        _parseDouble(json['latitude']) ??
        _parseDouble(json['lat']) ??
        location?.latitude;
    final double? longitude =
        _parseDouble(json['longitude']) ??
        _parseDouble(json['lon']) ??
        location?.longitude;
    final double? accuracyMeters =
        _parseDouble(json['accuracyMeters']) ?? location?.accuracyMeters;
    final DateTime? capturedAt =
        _parseDateTime(json['capturedAt']) ?? location?.capturedAt;
    final String? locationLabel =
        json['locationLabel']?.toString() ??
        json['location_label']?.toString();
    final ObservationLocationSource locationSource =
        _parseLocationSource(json['locationSource']) ??
        ((latitude != null && longitude != null)
            ? ObservationLocationSource.deviceGps
            : ObservationLocationSource.none);

    return Observation(
      id: json['id']?.toString() ?? '',
      speciesId: speciesId,
      classIndex: classIndex,
      modelId: json['modelId']?.toString(),
      modelDisplayName: json['modelDisplayName']?.toString(),
      sourceClassId: json['sourceClassId'] is num
          ? (json['sourceClassId'] as num).toInt()
          : int.tryParse(json['sourceClassId']?.toString() ?? ''),
      label: json['label']?.toString() ??
          json['speciesName']?.toString() ??
          '',
      colloquialName: json['colloquialName']?.toString(),
      confidence: json['confidence'] == null
          ? null
          : (json['confidence'] as num).toDouble(),
      rawConfidence: _parseDouble(json['rawConfidence']),
      calibratedConfidence: _parseDouble(json['calibratedConfidence']),
      finalScore: _parseDouble(json['finalScore']),
      top2Label: json['top2Label']?.toString(),
      top2Confidence: json['top2Confidence'] == null
          ? null
          : (json['top2Confidence'] as num).toDouble(),
      top2ModelId: json['top2ModelId']?.toString(),
      top2ModelDisplayName: json['top2ModelDisplayName']?.toString(),
      top2SourceClassId: json['top2SourceClassId'] is num
          ? (json['top2SourceClassId'] as num).toInt()
          : int.tryParse(json['top2SourceClassId']?.toString() ?? ''),
      top1VoteRatio: json['top1VoteRatio'] == null
          ? null
          : (json['top1VoteRatio'] as num).toDouble(),
      windowFrameCount: json['windowFrameCount'] is num
          ? (json['windowFrameCount'] as num).toInt()
          : null,
      windowDurationMs: json['windowDurationMs'] is num
          ? (json['windowDurationMs'] as num).toInt()
          : null,
      stabilityWinCount: json['stabilityWinCount'] is num
          ? (json['stabilityWinCount'] as num).toInt()
          : null,
      stabilityWindowSize: json['stabilityWindowSize'] is num
          ? (json['stabilityWindowSize'] as num).toInt()
          : null,
      isLichen: json['isLichen'] is bool ? json['isLichen'] as bool : null,
      createdAt:
          _parseDateTime(json['createdAt']) ??
          _parseDateTime(json['timestamp']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      photoPath: json['photoPath']?.toString(),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt,
      locationSource: locationSource,
      locationLabel: locationLabel,
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final String createdAtIso = createdAt.toIso8601String();
    return {
      'id': id,
      'speciesId': speciesId,
      'classIndex': classIndex,
      'modelId': modelId,
      'modelDisplayName': modelDisplayName,
      'sourceClassId': sourceClassId,
      'label': label,
      'colloquialName': colloquialName,
      'speciesName': speciesName,
      'confidence': confidence,
      'rawConfidence': rawConfidence,
      'calibratedConfidence': calibratedConfidence,
      'finalScore': finalScore,
      'top2Label': top2Label,
      'top2Confidence': top2Confidence,
      'top2ModelId': top2ModelId,
      'top2ModelDisplayName': top2ModelDisplayName,
      'top2SourceClassId': top2SourceClassId,
      'top1VoteRatio': top1VoteRatio,
      'windowFrameCount': windowFrameCount,
      'windowDurationMs': windowDurationMs,
      'stabilityWinCount': stabilityWinCount,
      'stabilityWindowSize': stabilityWindowSize,
      'isLichen': isLichen,
      'createdAt': createdAtIso,
      'timestamp': createdAtIso,
      'photoPath': photoPath,
      'latitude': latitude,
      'longitude': longitude,
      'lat': latitude,
      'lon': longitude,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt?.toIso8601String(),
      'locationSource': locationSource.name,
      'locationLabel': locationLabel,
      'location': location?.toJson(),
      'notes': notes,
    };
  }
}

class ObservationLocation {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;

  const ObservationLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  });

  factory ObservationLocation.fromJson(Map<String, dynamic> json) {
    return ObservationLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      capturedAt: _parseDateTime(json['capturedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt?.toIso8601String(),
    };
  }
}

double? _parseDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

ObservationLocationSource? _parseLocationSource(dynamic value) {
  if (value == null) {
    return null;
  }
  final raw = value.toString();
  for (final candidate in ObservationLocationSource.values) {
    if (candidate.name == raw) {
      return candidate;
    }
  }
  return null;
}
