class Species {
  final String id;
  final String scientificName;
  final String? authority;
  final String? commonName;
  final String? shortDescription;
  final String? taxonomyKingdom;
  final String? taxonomyPhylum;
  final String? taxonomyClass;
  final String? taxonomyOrder;
  final String? taxonomyFamily;
  final String? taxonomyGenus;
  final String? taxonomySpecies;
  final List<String> keyFeatures;
  final List<String> similarSpeciesIds;
  final List<String> similarSpeciesNames;
  final String distributionNote;
  final String? distributionCountry;
  final List<String> distributionStates;
  final String? habitat;
  final String? season;
  final String? edibilityWarning;
  final String? sourceTaxonomy;
  final String? sourceDescription;
  final String? thumbnailAssetPath;

  const Species({
    required this.id,
    required this.scientificName,
    required this.authority,
    required this.commonName,
    required this.shortDescription,
    required this.taxonomyKingdom,
    required this.taxonomyPhylum,
    required this.taxonomyClass,
    required this.taxonomyOrder,
    required this.taxonomyFamily,
    required this.taxonomyGenus,
    required this.taxonomySpecies,
    required this.keyFeatures,
    required this.similarSpeciesIds,
    required this.similarSpeciesNames,
    required this.distributionNote,
    required this.distributionCountry,
    required this.distributionStates,
    required this.habitat,
    required this.season,
    required this.edibilityWarning,
    required this.sourceTaxonomy,
    required this.sourceDescription,
    required this.thumbnailAssetPath,
  });

  factory Species.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['speciesId'] ?? json['species_id'];
    final keyFeatures =
        (json['keyFeatures'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final similarSpeciesIds =
        (json['similarSpeciesIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();
    final similarSpeciesNames =
        (json['similarSpecies'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList();

    final distribution = json['distribution'];
    String? distributionCountry;
    List<String> distributionStates = const <String>[];
    String? distributionNote;
    if (distribution is Map<String, dynamic>) {
      distributionCountry = distribution['country']?.toString();
      distributionStates = (distribution['states'] as List<dynamic>? ??
              const <dynamic>[])
          .map((item) => item.toString())
          .toList();
      distributionNote = distribution['note']?.toString();
    }

    String? computedNote =
        json['distributionNote']?.toString() ?? distributionNote;
    if (computedNote == null || computedNote.trim().isEmpty) {
      final pieces = <String>[];
      if (distributionCountry != null && distributionCountry.isNotEmpty) {
        pieces.add(distributionCountry);
      }
      if (distributionStates.isNotEmpty) {
        pieces.add(distributionStates.join(', '));
      }
      if (pieces.isNotEmpty) {
        computedNote = pieces.join(' — ');
      }
    }

    final taxonomy = json['taxonomy'];
    String? taxonomyKingdom;
    String? taxonomyPhylum;
    String? taxonomyClass;
    String? taxonomyOrder;
    String? taxonomyFamily;
    String? taxonomyGenus;
    String? taxonomySpecies;
    if (taxonomy is Map<String, dynamic>) {
      taxonomyKingdom = taxonomy['kingdom']?.toString();
      taxonomyPhylum = taxonomy['phylum']?.toString();
      taxonomyClass = taxonomy['class']?.toString();
      taxonomyOrder = taxonomy['order']?.toString();
      taxonomyFamily = taxonomy['family']?.toString();
      taxonomyGenus = taxonomy['genus']?.toString();
      taxonomySpecies = taxonomy['species']?.toString();
    }

    final sources = json['sources'];
    String? sourceTaxonomy;
    String? sourceDescription;
    if (sources is Map<String, dynamic>) {
      sourceTaxonomy = sources['taxonomy']?.toString();
      sourceDescription = sources['description']?.toString();
    }

    return Species(
      id: rawId?.toString() ?? '',
      scientificName: json['scientificName']?.toString() ?? '',
      authority: json['authority']?.toString(),
      commonName: json['commonName']?.toString(),
      shortDescription: json['shortDescription']?.toString() ??
          json['description']?.toString(),
      taxonomyKingdom: taxonomyKingdom,
      taxonomyPhylum: taxonomyPhylum,
      taxonomyClass: taxonomyClass,
      taxonomyOrder: taxonomyOrder,
      taxonomyFamily: taxonomyFamily,
      taxonomyGenus: taxonomyGenus,
      taxonomySpecies: taxonomySpecies,
      keyFeatures: keyFeatures,
      similarSpeciesIds: similarSpeciesIds,
      similarSpeciesNames: similarSpeciesNames,
      distributionNote: computedNote ?? '',
      distributionCountry: distributionCountry,
      distributionStates: distributionStates,
      habitat: json['habitat']?.toString(),
      season: json['season']?.toString(),
      edibilityWarning: json['edibilityWarning']?.toString(),
      sourceTaxonomy: sourceTaxonomy,
      sourceDescription: sourceDescription,
      thumbnailAssetPath:
          json['thumbnailAssetPath']?.toString() ?? json['imageAsset']?.toString(),
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
