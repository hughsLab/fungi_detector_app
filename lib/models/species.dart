import 'toxicity_level.dart';

enum SpeciesRarity { common, uncommon, rare, veryRare, unknown }

class Species {
  final String id;
  final String? modelId;
  final int? sourceClassId;
  final String scientificName;
  final String? canonicalName;
  final String? authority;
  final String? commonName;
  final String? colloquialName;
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
  final SpeciesLocation location;
  final String? habitat;
  final String? season;
  final String? edibilityWarning;
  final String? sourceTaxonomy;
  final String? sourceDescription;
  final String? thumbnailAssetPath;
  final SpeciesRarity rarity;
  final ToxicityLevel toxicityLevel;
  final String? toxicitySummary;
  final String? toxicitySource;
  final String? toxicitySourceUrl;
  final DateTime? toxicityVerifiedAt;
  final int? iNaturalistTaxonId;
  final String? iNaturalistPreferredCommonName;
  final String? iNaturalistPhotoUrl;
  final String? iNaturalistPhotoAttribution;
  final String? iNaturalistPhotoLicense;
  final int? iNaturalistGlobalObservationCount;
  final String? conservationStatus;
  final String? conservationStatusAuthority;
  final String? conservationStatusPlace;
  final DateTime? iNaturalistDataUpdatedAt;

  const Species({
    required this.id,
    required this.modelId,
    required this.sourceClassId,
    required this.scientificName,
    required this.canonicalName,
    required this.authority,
    required this.commonName,
    required this.colloquialName,
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
    required this.location,
    required this.habitat,
    required this.season,
    required this.edibilityWarning,
    required this.sourceTaxonomy,
    required this.sourceDescription,
    required this.thumbnailAssetPath,
    this.rarity = SpeciesRarity.unknown,
    this.toxicityLevel = ToxicityLevel.unknown,
    this.toxicitySummary,
    this.toxicitySource,
    this.toxicitySourceUrl,
    this.toxicityVerifiedAt,
    this.iNaturalistTaxonId,
    this.iNaturalistPreferredCommonName,
    this.iNaturalistPhotoUrl,
    this.iNaturalistPhotoAttribution,
    this.iNaturalistPhotoLicense,
    this.iNaturalistGlobalObservationCount,
    this.conservationStatus,
    this.conservationStatusAuthority,
    this.conservationStatusPlace,
    this.iNaturalistDataUpdatedAt,
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

    final location = SpeciesLocation.fromJson(json['location']);

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
      modelId: json['modelId']?.toString(),
      sourceClassId: json['sourceClassId'] is num
          ? (json['sourceClassId'] as num).toInt()
          : int.tryParse(json['sourceClassId']?.toString() ?? ''),
      scientificName: json['scientificName']?.toString() ?? '',
      canonicalName:
          json['canonicalName']?.toString() ?? taxonomySpecies,
      authority: json['authority']?.toString(),
      commonName: json['commonName']?.toString(),
      colloquialName: json['colloquialName']?.toString(),
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
      location: location,
      habitat: json['habitat']?.toString(),
      season: json['season']?.toString(),
      edibilityWarning: json['edibilityWarning']?.toString(),
      sourceTaxonomy: sourceTaxonomy,
      sourceDescription: sourceDescription,
      thumbnailAssetPath:
          json['thumbnailAssetPath']?.toString() ?? json['imageAsset']?.toString(),
      rarity: _parseSpeciesRarity(
        json['rarity'] ?? json['rarityStatus'] ?? json['rarity_status'],
      ),
      toxicityLevel: parseToxicityLevel(
        json['toxicityLevel'],
        legacyIsPoisonous: json['isPoisonous'] is bool
            ? json['isPoisonous'] as bool
            : null,
      ),
      toxicitySummary: json['toxicitySummary']?.toString(),
      toxicitySource: json['toxicitySource']?.toString(),
      toxicitySourceUrl: json['toxicitySourceUrl']?.toString(),
      toxicityVerifiedAt: DateTime.tryParse(
        json['toxicityVerifiedAt']?.toString() ?? '',
      ),
      iNaturalistTaxonId: _parseInt(json['iNaturalistTaxonId']),
      iNaturalistPreferredCommonName:
          json['iNaturalistPreferredCommonName']?.toString(),
      iNaturalistPhotoUrl: json['iNaturalistPhotoUrl']?.toString(),
      iNaturalistPhotoAttribution:
          json['iNaturalistPhotoAttribution']?.toString(),
      iNaturalistPhotoLicense:
          json['iNaturalistPhotoLicense']?.toString(),
      iNaturalistGlobalObservationCount:
          _parseInt(json['iNaturalistGlobalObservationCount']),
      conservationStatus: json['conservationStatus']?.toString(),
      conservationStatusAuthority:
          json['conservationStatusAuthority']?.toString(),
      conservationStatusPlace: json['conservationStatusPlace']?.toString(),
      iNaturalistDataUpdatedAt: DateTime.tryParse(
        json['iNaturalistDataUpdatedAt']?.toString() ?? '',
      ),
    );
  }

  SpeciesRarity get mapRarity {
    if (rarity != SpeciesRarity.unknown) {
      return rarity;
    }
    final rangeScore = <String>{
      ...location.global.map((value) => value.trim().toLowerCase()),
      ...location.australiaStates.map((value) => value.trim().toLowerCase()),
    }.where((value) => value.isNotEmpty).length;
    if (rangeScore == 0) return SpeciesRarity.unknown;
    if (rangeScore <= 4) return SpeciesRarity.veryRare;
    if (rangeScore <= 7) return SpeciesRarity.rare;
    if (rangeScore <= 11) return SpeciesRarity.uncommon;
    return SpeciesRarity.common;
  }

  bool get mapRarityIsEstimated => rarity == SpeciesRarity.unknown;

  String get displayName {
    final common = commonName;
    if (common == null || common.isEmpty) {
      return scientificName;
    }
    return '$scientificName ($common)';
  }

  String get taxonomyPath {
    return <String?>[
      taxonomyKingdom,
      taxonomyPhylum,
      taxonomyClass,
      taxonomyOrder,
      taxonomyFamily,
      taxonomyGenus,
      taxonomySpecies,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' > ');
  }
}

int? _parseInt(dynamic value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '');

SpeciesRarity _parseSpeciesRarity(dynamic value) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ');
  switch (normalized) {
    case 'common':
      return SpeciesRarity.common;
    case 'uncommon':
      return SpeciesRarity.uncommon;
    case 'rare':
      return SpeciesRarity.rare;
    case 'very rare':
    case 'extremely rare':
      return SpeciesRarity.veryRare;
    default:
      return SpeciesRarity.unknown;
  }
}

class SpeciesLocation {
  final List<String> global;
  final List<String> australiaStates;
  final List<String> regionalNotes;

  const SpeciesLocation({
    required this.global,
    required this.australiaStates,
    required this.regionalNotes,
  });

  factory SpeciesLocation.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const SpeciesLocation(
        global: <String>[],
        australiaStates: <String>[],
        regionalNotes: <String>[],
      );
    }
    final australia = json['australia'];
    final List<String> states = australia is Map<String, dynamic>
        ? (australia['states'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList()
        : const <String>[];
    return SpeciesLocation(
      global: (json['global'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      australiaStates: states,
      regionalNotes: (json['regionalNotes'] as List<dynamic>? ??
              const <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }

  bool get isEmpty =>
      global.isEmpty && australiaStates.isEmpty && regionalNotes.isEmpty;
}
