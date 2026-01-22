class Species {
  final String id;
  final String scientificName;
  final String? commonName;
  final List<String> keyFeatures;
  final List<String> similarSpeciesIds;
  final String distributionNote;
  final String? thumbnailAssetPath;

  const Species({
    required this.id,
    required this.scientificName,
    required this.commonName,
    required this.keyFeatures,
    required this.similarSpeciesIds,
    required this.distributionNote,
    required this.thumbnailAssetPath,
  });

  factory Species.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['speciesId'] ?? json['species_id'];
    final keyFeatures =
        (json['keyFeatures'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final similarSpecies =
        (json['similarSpeciesIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();

    return Species(
      id: rawId?.toString() ?? '',
      scientificName: json['scientificName']?.toString() ?? '',
      commonName: json['commonName']?.toString(),
      keyFeatures: keyFeatures,
      similarSpeciesIds: similarSpecies,
      distributionNote: json['distributionNote']?.toString() ?? '',
      thumbnailAssetPath: json['thumbnailAssetPath']?.toString(),
    );
  }

  String get displayName {
    final common = commonName;
    if (common == null || common.isEmpty) {
      return scientificName;
    }
    return '$scientificName ($common)';
  }
}
