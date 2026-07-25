import 'taxonomy_node.dart';

enum INaturalistMatchStatus { matched, ambiguous, notFound, unavailable }

class INaturalistTaxonMatch {
  final INaturalistMatchStatus status;
  final String requestName;
  final int? taxonId;
  final String? acceptedScientificName;
  final String? matchedName;
  final String? preferredCommonName;
  final String? rank;
  final String? iconicTaxonName;
  final bool? isActive;
  final bool? extinct;
  final String? photoUrl;
  final String? photoAttribution;
  final String? photoLicense;
  final String? taxonUrl;
  final int? globalObservationCount;
  final int? regionalObservationCount;
  final String? conservationStatus;
  final String? conservationStatusAuthority;
  final String? conservationStatusPlace;
  final List<TaxonomyNode> taxonomy;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final bool isStale;

  const INaturalistTaxonMatch({
    required this.status,
    required this.requestName,
    required this.taxonId,
    required this.acceptedScientificName,
    required this.matchedName,
    required this.preferredCommonName,
    required this.rank,
    required this.iconicTaxonName,
    required this.isActive,
    required this.extinct,
    required this.photoUrl,
    required this.photoAttribution,
    required this.photoLicense,
    required this.taxonUrl,
    required this.globalObservationCount,
    required this.regionalObservationCount,
    required this.conservationStatus,
    required this.conservationStatusAuthority,
    required this.conservationStatusPlace,
    this.taxonomy = const [],
    required this.fetchedAt,
    required this.expiresAt,
    this.isStale = false,
  });

  factory INaturalistTaxonMatch.statusOnly({
    required INaturalistMatchStatus status,
    required String requestName,
    required DateTime fetchedAt,
  }) => INaturalistTaxonMatch(
    status: status,
    requestName: requestName,
    taxonId: null,
    acceptedScientificName: null,
    matchedName: null,
    preferredCommonName: null,
    rank: null,
    iconicTaxonName: null,
    isActive: null,
    extinct: null,
    photoUrl: null,
    photoAttribution: null,
    photoLicense: null,
    taxonUrl: null,
    globalObservationCount: null,
    regionalObservationCount: null,
    conservationStatus: null,
    conservationStatusAuthority: null,
    conservationStatusPlace: null,
    taxonomy: const [],
    fetchedAt: fetchedAt,
    expiresAt: fetchedAt.add(const Duration(days: 1)),
  );

  INaturalistTaxonMatch copyWith({
    int? globalObservationCount,
    int? regionalObservationCount,
    String? conservationStatus,
    String? conservationStatusAuthority,
    String? conservationStatusPlace,
    List<TaxonomyNode>? taxonomy,
    DateTime? fetchedAt,
    DateTime? expiresAt,
    bool? isStale,
  }) => INaturalistTaxonMatch(
    status: status,
    requestName: requestName,
    taxonId: taxonId,
    acceptedScientificName: acceptedScientificName,
    matchedName: matchedName,
    preferredCommonName: preferredCommonName,
    rank: rank,
    iconicTaxonName: iconicTaxonName,
    isActive: isActive,
    extinct: extinct,
    photoUrl: photoUrl,
    photoAttribution: photoAttribution,
    photoLicense: photoLicense,
    taxonUrl: taxonUrl,
    globalObservationCount:
        globalObservationCount ?? this.globalObservationCount,
    regionalObservationCount:
        regionalObservationCount ?? this.regionalObservationCount,
    conservationStatus: conservationStatus ?? this.conservationStatus,
    conservationStatusAuthority:
        conservationStatusAuthority ?? this.conservationStatusAuthority,
    conservationStatusPlace:
        conservationStatusPlace ?? this.conservationStatusPlace,
    taxonomy: taxonomy ?? this.taxonomy,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    isStale: isStale ?? this.isStale,
  );

  Map<String, dynamic> toJson() => {
    'cacheFormatVersion': 1,
    'status': status.name,
    'requestName': requestName,
    'taxonId': taxonId,
    'acceptedScientificName': acceptedScientificName,
    'matchedName': matchedName,
    'preferredCommonName': preferredCommonName,
    'rank': rank,
    'iconicTaxonName': iconicTaxonName,
    'isActive': isActive,
    'extinct': extinct,
    'photoUrl': photoUrl,
    'photoAttribution': photoAttribution,
    'photoLicense': photoLicense,
    'taxonUrl': taxonUrl,
    'globalObservationCount': globalObservationCount,
    'regionalObservationCount': regionalObservationCount,
    'conservationStatus': conservationStatus,
    'conservationStatusAuthority': conservationStatusAuthority,
    'conservationStatusPlace': conservationStatusPlace,
    'taxonomy': taxonomy.map((node) => node.toJson()).toList(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory INaturalistTaxonMatch.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    final status = INaturalistMatchStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => INaturalistMatchStatus.unavailable,
    );
    final fetchedAt =
        DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return INaturalistTaxonMatch(
      status: status,
      requestName: json['requestName']?.toString() ?? '',
      taxonId: _int(json['taxonId']),
      acceptedScientificName: json['acceptedScientificName']?.toString(),
      matchedName: json['matchedName']?.toString(),
      preferredCommonName: json['preferredCommonName']?.toString(),
      rank: json['rank']?.toString(),
      iconicTaxonName: json['iconicTaxonName']?.toString(),
      isActive: json['isActive'] is bool ? json['isActive'] as bool : null,
      extinct: json['extinct'] is bool ? json['extinct'] as bool : null,
      photoUrl: json['photoUrl']?.toString(),
      photoAttribution: json['photoAttribution']?.toString(),
      photoLicense: json['photoLicense']?.toString(),
      taxonUrl: json['taxonUrl']?.toString(),
      globalObservationCount: _int(json['globalObservationCount']),
      regionalObservationCount: _int(json['regionalObservationCount']),
      conservationStatus: json['conservationStatus']?.toString(),
      conservationStatusAuthority: json['conservationStatusAuthority']
          ?.toString(),
      conservationStatusPlace: json['conservationStatusPlace']?.toString(),
      taxonomy: (json['taxonomy'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => TaxonomyNode.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((node) => node.scientificName.trim().isNotEmpty)
          .toList(),
      fetchedAt: fetchedAt,
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ?? fetchedAt,
    );
  }
}

int? _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
