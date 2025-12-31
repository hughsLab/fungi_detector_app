class Observation {
  final String id;
  final String speciesId;
  final String label;
  final double? confidence;
  final DateTime timestamp;
  final String? photoPath;
  final ObservationLocation? location;
  final String? notes;

  const Observation({
    required this.id,
    required this.speciesId,
    required this.label,
    required this.confidence,
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

    return Observation(
      id: json['id']?.toString() ?? '',
      speciesId: json['speciesId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      confidence:
          json['confidence'] == null ? null : (json['confidence'] as num).toDouble(),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
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
      'label': label,
      'confidence': confidence,
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

  const ObservationLocation({
    required this.latitude,
    required this.longitude,
  });

  factory ObservationLocation.fromJson(Map<String, dynamic> json) {
    return ObservationLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
