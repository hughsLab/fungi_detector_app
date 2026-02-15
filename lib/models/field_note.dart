enum NoteAttachmentType { image, file }

class NoteAttachment {
  final String id;
  final NoteAttachmentType type;
  final String filePath;
  final String? thumbnailPath;
  final DateTime createdAt;

  const NoteAttachment({
    required this.id,
    required this.type,
    required this.filePath,
    required this.thumbnailPath,
    required this.createdAt,
  });

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    final String? rawType = json['type']?.toString();
    final NoteAttachmentType parsedType = NoteAttachmentType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => NoteAttachmentType.file,
    );
    return NoteAttachment(
      id: json['id']?.toString() ?? '',
      type: parsedType,
      filePath: json['filePath']?.toString() ?? '',
      thumbnailPath: json['thumbnailPath']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'filePath': filePath,
      'thumbnailPath': thumbnailPath,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class LocationRef {
  final String id;
  final double lat;
  final double lon;
  final String? label;
  final double? accuracyMeters;
  final DateTime capturedAt;

  const LocationRef({
    required this.id,
    required this.lat,
    required this.lon,
    required this.label,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  factory LocationRef.fromJson(Map<String, dynamic> json) {
    return LocationRef(
      id: json['id']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      label: json['label']?.toString(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      capturedAt:
          DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': lat,
      'lon': lon,
      'label': label,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }
}

class NoteLinks {
  final List<String> observationIds;
  final List<String> speciesIds;
  final List<LocationRef> locations;

  const NoteLinks({
    required this.observationIds,
    required this.speciesIds,
    required this.locations,
  });

  factory NoteLinks.empty() {
    return const NoteLinks(
      observationIds: [],
      speciesIds: [],
      locations: [],
    );
  }

  factory NoteLinks.fromJson(Map<String, dynamic> json) {
    final observations =
        (json['observationIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final species =
        (json['speciesIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final locations =
        (json['locations'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(LocationRef.fromJson)
            .toList();
    return NoteLinks(
      observationIds: observations,
      speciesIds: species,
      locations: locations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'observationIds': observationIds,
      'speciesIds': speciesIds,
      'locations': locations.map((item) => item.toJson()).toList(),
    };
  }

  NoteLinks copyWith({
    List<String>? observationIds,
    List<String>? speciesIds,
    List<LocationRef>? locations,
  }) {
    return NoteLinks(
      observationIds: observationIds ?? this.observationIds,
      speciesIds: speciesIds ?? this.speciesIds,
      locations: locations ?? this.locations,
    );
  }
}

class FieldNote {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final List<NoteAttachment> attachments;
  final NoteLinks links;
  final bool isPinned;
  final bool isArchived;

  const FieldNote({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.attachments,
    required this.links,
    required this.isPinned,
    required this.isArchived,
  });

  factory FieldNote.fromJson(Map<String, dynamic> json) {
    return FieldNote(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      attachments:
          (json['attachments'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(NoteAttachment.fromJson)
              .toList(),
      links: json['links'] is Map<String, dynamic>
          ? NoteLinks.fromJson(json['links'] as Map<String, dynamic>)
          : NoteLinks.empty(),
      isPinned: json['isPinned'] == true,
      isArchived: json['isArchived'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'tags': tags,
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'links': links.toJson(),
      'isPinned': isPinned,
      'isArchived': isArchived,
    };
  }

  FieldNote copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    List<NoteAttachment>? attachments,
    NoteLinks? links,
    bool? isPinned,
    bool? isArchived,
  }) {
    return FieldNote(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      attachments: attachments ?? this.attachments,
      links: links ?? this.links,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
