class Observation {
  final String id;
  final String speciesId;
  final int? classIndex;
  final String label;
  final double? confidence;
  final String? top2Label;
  final double? top2Confidence;
  final double? top1VoteRatio;
  final int? windowFrameCount;
  final int? windowDurationMs;
  final int? stabilityWinCount;
  final int? stabilityWindowSize;
  final bool? isLichen;
  final DateTime timestamp;
  final String? photoPath;
  final ObservationLocation? location;
  final String? notes;

  const Observation({
    required this.id,
    required this.speciesId,
    required this.classIndex,
    required this.label,
    required this.confidence,
    this.top2Label,
    this.top2Confidence,
    this.top1VoteRatio,
    this.windowFrameCount,
    this.windowDurationMs,
    this.stabilityWinCount,
    this.stabilityWindowSize,
    this.isLichen,
    required this.timestamp,
    required this.photoPath,
    required this.location,
    required this.notes,
  });

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

    return Observation(
      id: json['id']?.toString() ?? '',
      speciesId: speciesId,
      classIndex: classIndex,
      label: json['label']?.toString() ?? '',
      confidence: json['confidence'] == null
          ? null
          : (json['confidence'] as num).toDouble(),
      top2Label: json['top2Label']?.toString(),
      top2Confidence: json['top2Confidence'] == null
          ? null
          : (json['top2Confidence'] as num).toDouble(),
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
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      photoPath: json['photoPath']?.toString(),
      location: location,
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'speciesId': speciesId,
      'classIndex': classIndex,
      'label': label,
      'confidence': confidence,
      'top2Label': top2Label,
      'top2Confidence': top2Confidence,
      'top1VoteRatio': top1VoteRatio,
      'windowFrameCount': windowFrameCount,
      'windowDurationMs': windowDurationMs,
      'stabilityWinCount': stabilityWinCount,
      'stabilityWindowSize': stabilityWindowSize,
      'isLichen': isLichen,
      'timestamp': timestamp.toIso8601String(),
      'photoPath': photoPath,
      'location': location?.toJson(),
      'notes': notes,
    };
  }
}

class ObservationLocation {
  final double latitude;
  final double longitude;

  const ObservationLocation({required this.latitude, required this.longitude});

  factory ObservationLocation.fromJson(Map<String, dynamic> json) {
    return ObservationLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'latitude': latitude, 'longitude': longitude};
  }
}
