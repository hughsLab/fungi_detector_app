enum ObservationLocationSource { deviceGps, exifGps, none }

class ObservationCandidate {
  final String label;
  final double confidence;
  final int? classIndex;
  final String? speciesId;
  final String? modelId;
  final String? modelDisplayName;
  final int? sourceClassId;
  final double? rawConfidence;
  final double? calibratedConfidence;
  final double? finalScore;

  const ObservationCandidate({
    required this.label,
    required this.confidence,
    this.classIndex,
    this.speciesId,
    this.modelId,
    this.modelDisplayName,
    this.sourceClassId,
    this.rawConfidence,
    this.calibratedConfidence,
    this.finalScore,
  });

  factory ObservationCandidate.fromJson(Map<String, dynamic> json) {
    return ObservationCandidate(
      label: json['label']?.toString() ?? '',
      confidence: _parseDouble(json['confidence']) ?? 0.0,
      classIndex: _parseInt(json['classIndex']),
      speciesId: json['speciesId']?.toString(),
      modelId: json['modelId']?.toString(),
      modelDisplayName: json['modelDisplayName']?.toString(),
      sourceClassId: _parseInt(json['sourceClassId']),
      rawConfidence: _parseDouble(json['rawConfidence']),
      calibratedConfidence: _parseDouble(json['calibratedConfidence']),
      finalScore: _parseDouble(json['finalScore']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'confidence': confidence,
      'classIndex': classIndex,
      'speciesId': speciesId,
      'modelId': modelId,
      'modelDisplayName': modelDisplayName,
      'sourceClassId': sourceClassId,
      'rawConfidence': rawConfidence,
      'calibratedConfidence': calibratedConfidence,
      'finalScore': finalScore,
    };
  }
}

class Observation {
  final String id;
  final String? userId;
  final String? ownerUsername;
  final String? ownerDisplayName;
  final String speciesId;
  final int? classIndex;
  final String? modelId;
  final String? modelDisplayName;
  final int? sourceClassId;
  final String label;
  final String? scientificName;
  final String? commonName;
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
  final List<ObservationCandidate> candidates;
  final double? top1VoteRatio;
  final int? windowFrameCount;
  final int? windowDurationMs;
  final int? stabilityWinCount;
  final int? stabilityWindowSize;
  final bool? isLichen;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? photoPath;
  final String? imageStoragePath;
  final String? imageUrl;
  final String? thumbnailStoragePath;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final ObservationLocationSource locationSource;
  final String? locationLabel;
  final String? country;
  final String? region;
  final String? notes;
  final List<String> fieldNoteIds;
  final String? detectionSource;
  final String? identificationSource;
  final bool? onlineIdentification;
  final String? onlineProvider;
  final String? onlineScientificName;
  final List<String> onlineCommonNames;
  final double? onlineConfidence;
  final double? onlineConfidencePercent;
  final String? onlineEdibility;
  final String? onlineToxicity;
  final String? onlineDescription;
  final String? onlineUrl;
  final Map<String, dynamic>? onlineTaxonomy;
  final List<Map<String, dynamic>> onlineAlternatives;
  final List<Map<String, dynamic>> onlineSimilarImages;
  final List<String> identificationWarnings;
  final bool? regionSupported;
  final bool? locationFilterApplied;
  final bool isPublic;
  final double? publicLat;
  final double? publicLng;
  final String? syncStatus;

  const Observation({
    required this.id,
    this.userId,
    this.ownerUsername,
    this.ownerDisplayName,
    required this.speciesId,
    required this.classIndex,
    this.modelId,
    this.modelDisplayName,
    this.sourceClassId,
    required this.label,
    this.scientificName,
    this.commonName,
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
    this.candidates = const <ObservationCandidate>[],
    this.top1VoteRatio,
    this.windowFrameCount,
    this.windowDurationMs,
    this.stabilityWinCount,
    this.stabilityWindowSize,
    this.isLichen,
    required this.createdAt,
    this.updatedAt,
    required this.photoPath,
    this.imageStoragePath,
    this.imageUrl,
    this.thumbnailStoragePath,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.capturedAt,
    this.locationSource = ObservationLocationSource.none,
    this.locationLabel,
    this.country,
    this.region,
    this.notes,
    this.fieldNoteIds = const <String>[],
    this.detectionSource,
    this.identificationSource,
    this.onlineIdentification,
    this.onlineProvider,
    this.onlineScientificName,
    this.onlineCommonNames = const <String>[],
    this.onlineConfidence,
    this.onlineConfidencePercent,
    this.onlineEdibility,
    this.onlineToxicity,
    this.onlineDescription,
    this.onlineUrl,
    this.onlineTaxonomy,
    this.onlineAlternatives = const <Map<String, dynamic>>[],
    this.onlineSimilarImages = const <Map<String, dynamic>>[],
    this.identificationWarnings = const <String>[],
    this.regionSupported,
    this.locationFilterApplied,
    this.isPublic = false,
    this.publicLat,
    this.publicLng,
    this.syncStatus,
  });

  String get speciesName => label;
  double? get lat => latitude;
  double? get lon => longitude;
  DateTime get timestamp => createdAt;

  String? get observerName {
    final username = ownerUsername?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    final displayName = ownerDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return null;
  }

  ObservationLocation? get location {
    final lat = latitude;
    final lon = longitude;
    if (lat == null ||
        lon == null ||
        !_isValidLatitude(lat) ||
        !_isValidLongitude(lon)) {
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
    final location = _parseObservationLocation(json['location']);

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
        _parseLatitude(json['latitude']) ??
        _parseLatitude(json['lat']) ??
        _parseLatitude(json['publicLat']) ??
        location?.latitude;
    final double? longitude =
        _parseLongitude(json['longitude']) ??
        _parseLongitude(json['lon']) ??
        _parseLongitude(json['lng']) ??
        _parseLongitude(json['publicLng']) ??
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
      userId: json['userId']?.toString(),
      ownerUsername:
          json['ownerUsername']?.toString() ??
          json['username']?.toString() ??
          json['authorUsername']?.toString() ??
          json['userName']?.toString(),
      ownerDisplayName:
          json['ownerDisplayName']?.toString() ??
          json['displayName']?.toString() ??
          json['authorDisplayName']?.toString() ??
          json['userDisplayName']?.toString(),
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
      scientificName: json['scientificName']?.toString(),
      commonName:
          json['commonName']?.toString() ?? json['colloquialName']?.toString(),
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
      top2SourceClassId: _parseInt(json['top2SourceClassId']),
      candidates: _parseCandidates(json['candidates']),
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
          _parseDateTime(json['observedAt']) ??
          _parseDateTime(json['timestamp']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDateTime(json['updatedAt']),
      photoPath: json['photoPath']?.toString() ??
          json['localPhotoPath']?.toString() ??
          json['imageUrl']?.toString() ??
          json['downloadUrl']?.toString(),
      imageStoragePath: json['imageStoragePath']?.toString(),
      imageUrl: json['imageUrl']?.toString() ?? json['downloadUrl']?.toString(),
      thumbnailStoragePath: json['thumbnailStoragePath']?.toString(),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt,
      locationSource: locationSource,
      locationLabel: locationLabel,
      country: json['country']?.toString(),
      region: json['region']?.toString() ?? json['state']?.toString(),
      notes: json['notes']?.toString(),
      fieldNoteIds: _parseStringList(json['fieldNoteIds']),
      detectionSource: json['detectionSource']?.toString(),
      identificationSource: json['identificationSource']?.toString() ??
          _identificationSourceFromDetectionSource(
            json['detectionSource']?.toString(),
          ),
      onlineIdentification: _parseBool(json['onlineIdentification']),
      onlineProvider: json['onlineProvider']?.toString(),
      onlineScientificName: json['onlineScientificName']?.toString(),
      onlineCommonNames: _parseStringList(json['onlineCommonNames']),
      onlineConfidence: _parseDouble(json['onlineConfidence']),
      onlineConfidencePercent: _parseDouble(json['onlineConfidencePercent']),
      onlineEdibility: json['onlineEdibility']?.toString(),
      onlineToxicity: json['onlineToxicity']?.toString(),
      onlineDescription: json['onlineDescription']?.toString(),
      onlineUrl: json['onlineUrl']?.toString(),
      onlineTaxonomy: _parseDynamicMap(json['onlineTaxonomy']),
      onlineAlternatives: _parseDynamicMapList(json['onlineAlternatives']),
      onlineSimilarImages: _parseDynamicMapList(json['onlineSimilarImages']),
      identificationWarnings: _parseStringList(json['identificationWarnings']),
      regionSupported: _parseBool(json['regionSupported']),
      locationFilterApplied: _parseBool(json['locationFilterApplied']),
      isPublic: json['isPublic'] is bool ? json['isPublic'] as bool : false,
      publicLat: _parseDouble(json['publicLat']),
      publicLng: _parseDouble(json['publicLng']),
      syncStatus: json['syncStatus']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final String createdAtIso = createdAt.toIso8601String();
    return {
      'id': id,
      'userId': userId,
      'ownerUsername': ownerUsername,
      'ownerDisplayName': ownerDisplayName,
      'speciesId': speciesId,
      'classIndex': classIndex,
      'modelId': modelId,
      'modelDisplayName': modelDisplayName,
      'sourceClassId': sourceClassId,
      'label': label,
      'scientificName': scientificName,
      'commonName': commonName,
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
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
      'top1VoteRatio': top1VoteRatio,
      'windowFrameCount': windowFrameCount,
      'windowDurationMs': windowDurationMs,
      'stabilityWinCount': stabilityWinCount,
      'stabilityWindowSize': stabilityWindowSize,
      'isLichen': isLichen,
      'createdAt': createdAtIso,
      'updatedAt': updatedAt?.toIso8601String(),
      'timestamp': createdAtIso,
      'photoPath': photoPath,
      'imageStoragePath': imageStoragePath,
      'imageUrl': imageUrl,
      'downloadUrl': imageUrl,
      'thumbnailStoragePath': thumbnailStoragePath,
      'latitude': latitude,
      'longitude': longitude,
      'lat': latitude,
      'lon': longitude,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt?.toIso8601String(),
      'locationSource': locationSource.name,
      'locationLabel': locationLabel,
      'location': location?.toJson(),
      'country': country,
      'region': region,
      'notes': notes,
      'fieldNoteIds': fieldNoteIds,
      'detectionSource': detectionSource,
      'identificationSource': identificationSource,
      'onlineIdentification': onlineIdentification,
      'onlineProvider': onlineProvider,
      'onlineScientificName': onlineScientificName,
      'onlineCommonNames': onlineCommonNames,
      'onlineConfidence': onlineConfidence,
      'onlineConfidencePercent': onlineConfidencePercent,
      'onlineEdibility': onlineEdibility,
      'onlineToxicity': onlineToxicity,
      'onlineDescription': onlineDescription,
      'onlineUrl': onlineUrl,
      'onlineTaxonomy': onlineTaxonomy,
      'onlineAlternatives': onlineAlternatives,
      'onlineSimilarImages': onlineSimilarImages,
      'identificationWarnings': identificationWarnings,
      'regionSupported': regionSupported,
      'locationFilterApplied': locationFilterApplied,
      'isPublic': isPublic,
      'publicLat': publicLat,
      'publicLng': publicLng,
      'syncStatus': syncStatus,
    };
  }

  Observation copyWith({
    String? id,
    String? userId,
    String? ownerUsername,
    String? ownerDisplayName,
    String? speciesId,
    int? classIndex,
    String? modelId,
    String? modelDisplayName,
    int? sourceClassId,
    String? label,
    String? scientificName,
    String? commonName,
    String? colloquialName,
    double? confidence,
    double? rawConfidence,
    double? calibratedConfidence,
    double? finalScore,
    String? top2Label,
    double? top2Confidence,
    String? top2ModelId,
    String? top2ModelDisplayName,
    int? top2SourceClassId,
    List<ObservationCandidate>? candidates,
    double? top1VoteRatio,
    int? windowFrameCount,
    int? windowDurationMs,
    int? stabilityWinCount,
    int? stabilityWindowSize,
    bool? isLichen,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? photoPath,
    String? imageStoragePath,
    String? imageUrl,
    String? thumbnailStoragePath,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    DateTime? capturedAt,
    ObservationLocationSource? locationSource,
    String? locationLabel,
    String? country,
    String? region,
    String? notes,
    List<String>? fieldNoteIds,
    String? detectionSource,
    String? identificationSource,
    bool? onlineIdentification,
    String? onlineProvider,
    String? onlineScientificName,
    List<String>? onlineCommonNames,
    double? onlineConfidence,
    double? onlineConfidencePercent,
    String? onlineEdibility,
    String? onlineToxicity,
    String? onlineDescription,
    String? onlineUrl,
    Map<String, dynamic>? onlineTaxonomy,
    List<Map<String, dynamic>>? onlineAlternatives,
    List<Map<String, dynamic>>? onlineSimilarImages,
    List<String>? identificationWarnings,
    bool? regionSupported,
    bool? locationFilterApplied,
    bool? isPublic,
    double? publicLat,
    double? publicLng,
    String? syncStatus,
  }) {
    return Observation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
      speciesId: speciesId ?? this.speciesId,
      classIndex: classIndex ?? this.classIndex,
      modelId: modelId ?? this.modelId,
      modelDisplayName: modelDisplayName ?? this.modelDisplayName,
      sourceClassId: sourceClassId ?? this.sourceClassId,
      label: label ?? this.label,
      scientificName: scientificName ?? this.scientificName,
      commonName: commonName ?? this.commonName,
      colloquialName: colloquialName ?? this.colloquialName,
      confidence: confidence ?? this.confidence,
      rawConfidence: rawConfidence ?? this.rawConfidence,
      calibratedConfidence: calibratedConfidence ?? this.calibratedConfidence,
      finalScore: finalScore ?? this.finalScore,
      top2Label: top2Label ?? this.top2Label,
      top2Confidence: top2Confidence ?? this.top2Confidence,
      top2ModelId: top2ModelId ?? this.top2ModelId,
      top2ModelDisplayName: top2ModelDisplayName ?? this.top2ModelDisplayName,
      top2SourceClassId: top2SourceClassId ?? this.top2SourceClassId,
      candidates: candidates ?? this.candidates,
      top1VoteRatio: top1VoteRatio ?? this.top1VoteRatio,
      windowFrameCount: windowFrameCount ?? this.windowFrameCount,
      windowDurationMs: windowDurationMs ?? this.windowDurationMs,
      stabilityWinCount: stabilityWinCount ?? this.stabilityWinCount,
      stabilityWindowSize: stabilityWindowSize ?? this.stabilityWindowSize,
      isLichen: isLichen ?? this.isLichen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photoPath: photoPath ?? this.photoPath,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailStoragePath: thumbnailStoragePath ?? this.thumbnailStoragePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      capturedAt: capturedAt ?? this.capturedAt,
      locationSource: locationSource ?? this.locationSource,
      locationLabel: locationLabel ?? this.locationLabel,
      country: country ?? this.country,
      region: region ?? this.region,
      notes: notes ?? this.notes,
      fieldNoteIds: fieldNoteIds ?? this.fieldNoteIds,
      detectionSource: detectionSource ?? this.detectionSource,
      identificationSource: identificationSource ?? this.identificationSource,
      onlineIdentification: onlineIdentification ?? this.onlineIdentification,
      onlineProvider: onlineProvider ?? this.onlineProvider,
      onlineScientificName: onlineScientificName ?? this.onlineScientificName,
      onlineCommonNames: onlineCommonNames ?? this.onlineCommonNames,
      onlineConfidence: onlineConfidence ?? this.onlineConfidence,
      onlineConfidencePercent:
          onlineConfidencePercent ?? this.onlineConfidencePercent,
      onlineEdibility: onlineEdibility ?? this.onlineEdibility,
      onlineToxicity: onlineToxicity ?? this.onlineToxicity,
      onlineDescription: onlineDescription ?? this.onlineDescription,
      onlineUrl: onlineUrl ?? this.onlineUrl,
      onlineTaxonomy: onlineTaxonomy ?? this.onlineTaxonomy,
      onlineAlternatives: onlineAlternatives ?? this.onlineAlternatives,
      onlineSimilarImages: onlineSimilarImages ?? this.onlineSimilarImages,
      identificationWarnings:
          identificationWarnings ?? this.identificationWarnings,
      regionSupported: regionSupported ?? this.regionSupported,
      locationFilterApplied:
          locationFilterApplied ?? this.locationFilterApplied,
      isPublic: isPublic ?? this.isPublic,
      publicLat: publicLat ?? this.publicLat,
      publicLng: publicLng ?? this.publicLng,
      syncStatus: syncStatus ?? this.syncStatus,
    );
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
    final latitude = _parseLatitude(json['latitude']) ??
        _parseLatitude(json['lat']) ??
        0;
    final longitude = _parseLongitude(json['longitude']) ??
        _parseLongitude(json['lon']) ??
        _parseLongitude(json['lng']) ??
        0;
    return ObservationLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: _parseDouble(json['accuracyMeters']),
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

double? _parseLatitude(dynamic value) {
  final parsed = _parseDouble(value);
  if (parsed == null || !_isValidLatitude(parsed)) {
    return null;
  }
  return parsed;
}

double? _parseLongitude(dynamic value) {
  final parsed = _parseDouble(value);
  if (parsed == null || !_isValidLongitude(parsed)) {
    return null;
  }
  return parsed;
}

bool _isValidLatitude(double value) {
  return value.isFinite && value >= -90.0 && value <= 90.0;
}

bool _isValidLongitude(double value) {
  return value.isFinite && value >= -180.0 && value <= 180.0;
}

ObservationLocation? _parseObservationLocation(dynamic value) {
  if (value == null) {
    return null;
  }

  final Map<String, dynamic>? json = _parseDynamicMap(value);
  if (json != null) {
    final latitude = _parseLatitude(json['latitude']) ??
        _parseLatitude(json['lat']);
    final longitude = _parseLongitude(json['longitude']) ??
        _parseLongitude(json['lon']) ??
        _parseLongitude(json['lng']);
    if (latitude == null || longitude == null) {
      return null;
    }
    return ObservationLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: _parseDouble(json['accuracyMeters']),
      capturedAt: _parseDateTime(json['capturedAt']),
    );
  }

  final latitude = _parseLatitude(_readCoordinateProperty(value, 'latitude')) ??
      _parseLatitude(_readCoordinateProperty(value, 'lat'));
  final longitude =
      _parseLongitude(_readCoordinateProperty(value, 'longitude')) ??
          _parseLongitude(_readCoordinateProperty(value, 'lon')) ??
          _parseLongitude(_readCoordinateProperty(value, 'lng'));
  if (latitude == null || longitude == null) {
    return null;
  }
  return ObservationLocation(latitude: latitude, longitude: longitude);
}

dynamic _readCoordinateProperty(dynamic value, String propertyName) {
  try {
    switch (propertyName) {
      case 'latitude':
        return value.latitude;
      case 'longitude':
        return value.longitude;
      case 'lat':
        return value.lat;
      case 'lon':
        return value.lon;
      case 'lng':
        return value.lng;
    }
  } catch (_) {
    return null;
  }
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

List<ObservationCandidate> _parseCandidates(dynamic value) {
  if (value is! List) {
    return const <ObservationCandidate>[];
  }
  final candidates = <ObservationCandidate>[];
  for (final item in value) {
    if (item is Map<String, dynamic>) {
      candidates.add(ObservationCandidate.fromJson(item));
    } else if (item is Map) {
      candidates.add(
        ObservationCandidate.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
  }
  return candidates
      .where((candidate) =>
          candidate.label.trim().isNotEmpty &&
          candidate.confidence.isFinite)
      .toList(growable: false);
}

List<String> _parseStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic>? _parseDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<Map<String, dynamic>> _parseDynamicMapList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  final output = <Map<String, dynamic>>[];
  for (final item in value) {
    final parsed = _parseDynamicMap(item);
    if (parsed != null) {
      output.add(parsed);
    }
  }
  return output;
}

bool? _parseBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value == null) {
    return null;
  }
  final raw = value.toString().trim().toLowerCase();
  if (raw == 'true') {
    return true;
  }
  if (raw == 'false') {
    return false;
  }
  return null;
}

String? _identificationSourceFromDetectionSource(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (raw == 'offline_model') {
    return 'offline';
  }
  if (raw == 'online_mushroom_id') {
    return 'online_mushroom_id';
  }
  if (raw == 'manual') {
    return 'manual';
  }
  return raw;
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
