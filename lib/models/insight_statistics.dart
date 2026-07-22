import 'species.dart';

enum InsightScope { personal, global }

enum DetectionSourceCategory { offline, online, both, unknown }

enum ToxicityCategory {
  deadly,
  poisonous,
  potentiallyPoisonous,
  causesGastrointestinalIllness,
  psychoactive,
  notKnownPoisonous,
  unknown,
}

enum SpeciesInsightSort {
  mostDetected,
  leastDetected,
  mostRecent,
  highestConfidence,
  rareSpecies,
  poisonousSpecies,
  alphabetical,
}

class SpeciesInsight {
  final String key;
  final String commonName;
  final String scientificName;
  final String? thumbnailAssetPath;
  final int detectionCount;
  final int savedObservationCount;
  final double percentage;
  final DateTime lastDetectedAt;
  final DetectionSourceCategory source;
  final double? averageConfidence;
  final double? highestConfidence;
  final SpeciesRarity rarity;
  final ToxicityCategory toxicity;
  final int? iNaturalistGlobalObservationCount;
  final String? conservationStatus;

  const SpeciesInsight({
    required this.key,
    required this.commonName,
    required this.scientificName,
    required this.thumbnailAssetPath,
    required this.detectionCount,
    required this.savedObservationCount,
    required this.percentage,
    required this.lastDetectedAt,
    required this.source,
    required this.averageConfidence,
    required this.highestConfidence,
    required this.rarity,
    required this.toxicity,
    required this.iNaturalistGlobalObservationCount,
    required this.conservationStatus,
  });
}

class InsightStatistics {
  final int totalObservations;
  final int totalDetections;
  final int uniqueSpecies;
  final int unidentifiedObservations;
  final int onlineDetections;
  final int offlineDetections;
  final int unknownSourceDetections;
  final int pendingCloudSync;
  final int poisonousObservations;
  final int poisonousSpecies;
  final int rareObservations;
  final int observationsWithCoordinates;
  final int observationsWithoutCoordinates;
  final int uniqueMappedLocations;
  final int observationsLast7Days;
  final int observationsLast30Days;
  final int newSpeciesThisMonth;
  final int firstTimeDetections;
  final int repeatDetections;
  final int highConfidenceDetections;
  final int mediumConfidenceDetections;
  final int lowConfidenceDetections;
  final double? averageConfidence;
  final double? averageOnlineConfidence;
  final double? averageOfflineConfidence;
  final double? averagePrimarySecondaryGap;
  final double? lowestSavedConfidence;
  final SpeciesInsight? highestConfidenceDetection;
  final SpeciesInsight? mostDetectedPoisonousSpecies;
  final DateTime? mostRecentPoisonousDetection;
  final String? mostActiveMonth;
  final String? mostActiveWeekday;
  final double? averageObservationsPerActiveMonth;
  final String? mostActiveLocation;
  final Map<SpeciesRarity, int> raritySpeciesCounts;
  final Map<ToxicityCategory, int> toxicitySpeciesCounts;
  final Map<ToxicityCategory, int> toxicityObservationCounts;
  final int iNaturalistMatchedSpecies;
  final int iNaturalistUnmatchedSpecies;
  final int staleINaturalistRecords;
  final SpeciesInsight? mostPubliclyObservedSpecies;
  final SpeciesInsight? leastPubliclyObservedSpecies;
  final Map<String, int> conservationStatusCounts;
  final Map<String, int> observationsByMonth;
  final Map<String, int> poisonousByMonth;
  final Map<String, int> observationsByWeekday;
  final Map<String, int> countryCounts;
  final Map<String, int> regionCounts;
  final List<SpeciesInsight> species;
  final List<SpeciesInsight> rareSpecies;
  final List<SpeciesInsight> poisonousSpeciesList;
  final bool isLimitedSnapshot;

  InsightStatistics({
    required this.totalObservations,
    required this.totalDetections,
    required this.uniqueSpecies,
    required this.unidentifiedObservations,
    required this.onlineDetections,
    required this.offlineDetections,
    required this.unknownSourceDetections,
    required this.pendingCloudSync,
    required this.poisonousObservations,
    required this.poisonousSpecies,
    required this.rareObservations,
    required this.observationsWithCoordinates,
    required this.observationsWithoutCoordinates,
    required this.uniqueMappedLocations,
    required this.observationsLast7Days,
    required this.observationsLast30Days,
    required this.newSpeciesThisMonth,
    required this.firstTimeDetections,
    required this.repeatDetections,
    required this.highConfidenceDetections,
    required this.mediumConfidenceDetections,
    required this.lowConfidenceDetections,
    required this.averageConfidence,
    required this.averageOnlineConfidence,
    required this.averageOfflineConfidence,
    required this.averagePrimarySecondaryGap,
    required this.lowestSavedConfidence,
    required this.highestConfidenceDetection,
    required this.mostDetectedPoisonousSpecies,
    required this.mostRecentPoisonousDetection,
    required this.mostActiveMonth,
    required this.mostActiveWeekday,
    required this.averageObservationsPerActiveMonth,
    required this.mostActiveLocation,
    required Map<SpeciesRarity, int> raritySpeciesCounts,
    required Map<ToxicityCategory, int> toxicitySpeciesCounts,
    required Map<ToxicityCategory, int> toxicityObservationCounts,
    required this.iNaturalistMatchedSpecies,
    required this.iNaturalistUnmatchedSpecies,
    required this.staleINaturalistRecords,
    required this.mostPubliclyObservedSpecies,
    required this.leastPubliclyObservedSpecies,
    required Map<String, int> conservationStatusCounts,
    required Map<String, int> observationsByMonth,
    required Map<String, int> poisonousByMonth,
    required Map<String, int> observationsByWeekday,
    required Map<String, int> countryCounts,
    required Map<String, int> regionCounts,
    required List<SpeciesInsight> species,
    required List<SpeciesInsight> rareSpecies,
    required List<SpeciesInsight> poisonousSpeciesList,
    this.isLimitedSnapshot = false,
  }) : raritySpeciesCounts = Map.unmodifiable(raritySpeciesCounts),
       toxicitySpeciesCounts = Map.unmodifiable(toxicitySpeciesCounts),
       toxicityObservationCounts = Map.unmodifiable(toxicityObservationCounts),
       conservationStatusCounts = Map.unmodifiable(conservationStatusCounts),
       observationsByMonth = Map.unmodifiable(observationsByMonth),
       poisonousByMonth = Map.unmodifiable(poisonousByMonth),
       observationsByWeekday = Map.unmodifiable(observationsByWeekday),
       countryCounts = Map.unmodifiable(countryCounts),
       regionCounts = Map.unmodifiable(regionCounts),
       species = List.unmodifiable(species),
       rareSpecies = List.unmodifiable(rareSpecies),
       poisonousSpeciesList = List.unmodifiable(poisonousSpeciesList);
}
