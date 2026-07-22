import '../models/insight_statistics.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../models/toxicity_level.dart';

class InsightsService {
  const InsightsService();

  InsightStatistics calculate({
    required Iterable<Observation> observations,
    required Iterable<Species> species,
    DateTime? now,
    String? userId,
    bool publicOnly = false,
    bool isLimitedSnapshot = false,
  }) {
    final current = now ?? DateTime.now();
    final deduplicated = <String, Observation>{};
    var anonymousIndex = 0;
    for (final observation in observations) {
      if (userId != null && observation.userId != userId) continue;
      if (publicOnly && !observation.isPublic) continue;
      final id = observation.id.trim();
      final key = id.isEmpty ? '__anonymous_${anonymousIndex++}' : id;
      final existing = deduplicated[key];
      if (existing == null ||
          _updatedAt(observation).isAfter(_updatedAt(existing))) {
        deduplicated[key] = observation;
      }
    }
    final items = deduplicated.values.toList(growable: false);
    final matcher = _SpeciesMatcher(species);
    final groups = <String, _SpeciesAccumulator>{};
    final unidentified = <Observation>[];
    final countryCounts = <String, int>{};
    final regionCounts = <String, int>{};
    final monthCounts = <String, int>{};
    final weekdayCounts = <String, int>{};
    final mappedLocations = <String>{};
    final confidenceValues = <double>[];
    final onlineConfidenceValues = <double>[];
    final offlineConfidenceValues = <double>[];
    final confidenceGaps = <double>[];
    var online = 0;
    var offline = 0;
    var unknownSource = 0;
    var pending = 0;
    var withCoordinates = 0;
    var highConfidence = 0;
    var mediumConfidence = 0;
    var lowConfidence = 0;

    for (final observation in items) {
      final matchedSpecies = matcher.match(observation);
      final identity = _identityFor(observation, matchedSpecies);
      if (identity == null) {
        unidentified.add(observation);
      } else {
        groups
            .putIfAbsent(
              identity.key,
              () => _SpeciesAccumulator(identity: identity),
            )
            .add(observation);
      }

      final source = _sourceFor(observation);
      if (identity != null) {
        if (source == DetectionSourceCategory.online) {
          online++;
        } else if (source == DetectionSourceCategory.offline) {
          offline++;
        } else {
          unknownSource++;
        }
      }
      if (_isPending(observation.syncStatus)) pending++;

      final confidence = _confidenceFor(observation);
      if (confidence != null && identity != null) {
        confidenceValues.add(confidence);
        if (source == DetectionSourceCategory.online) {
          onlineConfidenceValues.add(confidence);
        } else if (source == DetectionSourceCategory.offline) {
          offlineConfidenceValues.add(confidence);
        }
        // These boundaries match the existing scan engine's stable (0.55)
        // and adaptive-medium (0.70) confidence thresholds.
        if (confidence >= 0.70) {
          highConfidence++;
        } else if (confidence >= 0.55) {
          mediumConfidence++;
        } else {
          lowConfidence++;
        }
        final second = _normalizeConfidence(observation.top2Confidence);
        if (second != null && confidence >= second) {
          confidenceGaps.add(confidence - second);
        }
      }

      final month = _monthKey(observation.createdAt);
      monthCounts[month] = (monthCounts[month] ?? 0) + 1;
      final weekday = _weekdayName(observation.createdAt.weekday);
      weekdayCounts[weekday] = (weekdayCounts[weekday] ?? 0) + 1;
      final country = _cleanLabel(observation.country);
      if (country != null) {
        countryCounts[country] = (countryCounts[country] ?? 0) + 1;
      }
      final region = _cleanLabel(observation.region);
      if (region != null) {
        regionCounts[region] = (regionCounts[region] ?? 0) + 1;
      }
      final location = observation.location;
      if (location != null) {
        withCoordinates++;
        // Rounded to about 1 km. Exact private coordinates never leave the
        // statistics layer or appear in the UI.
        mappedLocations.add(
          '${location.latitude.toStringAsFixed(2)},${location.longitude.toStringAsFixed(2)}',
        );
      }
    }

    final totalDetections = groups.values.fold<int>(
      0,
      (sum, group) => sum + group.observations.length,
    );
    final speciesInsights =
        groups.values
            .map((group) => group.build(totalDetections: totalDetections))
            .toList()
          ..sort((a, b) {
            final count = b.detectionCount.compareTo(a.detectionCount);
            return count != 0
                ? count
                : a.scientificName.compareTo(b.scientificName);
          });

    final rareSpecies = speciesInsights
        .where(
          (item) =>
              item.rarity == SpeciesRarity.rare ||
              item.rarity == SpeciesRarity.veryRare,
        )
        .toList();
    final poisonousSpecies = speciesInsights
        .where(
          (item) =>
              item.toxicity == ToxicityCategory.deadly ||
              item.toxicity == ToxicityCategory.poisonous ||
              item.toxicity == ToxicityCategory.potentiallyPoisonous,
        )
        .toList();
    final poisonousObservations = groups.values
        .expand((entry) => entry.observations)
        .where((observation) {
          final toxicity = _toxicityFor(observation);
          return toxicity == ToxicityCategory.deadly ||
              toxicity == ToxicityCategory.poisonous ||
              toxicity == ToxicityCategory.potentiallyPoisonous;
        })
        .toList();
    final poisonousByMonth = <String, int>{};
    for (final observation in poisonousObservations) {
      final key = _monthKey(observation.createdAt);
      poisonousByMonth[key] = (poisonousByMonth[key] ?? 0) + 1;
    }

    final startOfToday = DateTime(current.year, current.month, current.day);
    final startOfMonth = DateTime(current.year, current.month);
    final firstDetectionBySpecies = <String, DateTime>{};
    for (final entry in groups.entries) {
      final dates =
          entry.value.observations.map((item) => item.createdAt).toList()
            ..sort();
      firstDetectionBySpecies[entry.key] = dates.first;
    }
    final firstTimeDetections = groups.length;
    final repeatDetections = totalDetections - firstTimeDetections;

    final rarityCounts = {for (final value in SpeciesRarity.values) value: 0};
    final toxicityCounts = {
      for (final value in ToxicityCategory.values) value: 0,
    };
    final toxicityObservationCounts = {
      for (final value in ToxicityCategory.values) value: 0,
    };
    for (final observation in items) {
      final category = _toxicityFor(observation);
      toxicityObservationCounts[category] =
          (toxicityObservationCounts[category] ?? 0) + 1;
    }
    for (final item in speciesInsights) {
      rarityCounts[item.rarity] = (rarityCounts[item.rarity] ?? 0) + 1;
      toxicityCounts[item.toxicity] = (toxicityCounts[item.toxicity] ?? 0) + 1;
    }

    final highest = [...speciesInsights]
      ..sort(
        (a, b) =>
            (b.highestConfidence ?? -1).compareTo(a.highestConfidence ?? -1),
      );
    final poisonousSorted = [...poisonousSpecies]
      ..sort((a, b) => b.detectionCount.compareTo(a.detectionCount));
    final publiclyCounted = speciesInsights
        .where((item) => item.iNaturalistGlobalObservationCount != null)
        .toList()
      ..sort(
        (a, b) => b.iNaturalistGlobalObservationCount!.compareTo(
          a.iNaturalistGlobalObservationCount!,
        ),
      );
    final conservationCounts = <String, int>{};
    for (final item in speciesInsights) {
      final status = item.conservationStatus?.trim();
      if (status != null && status.isNotEmpty) {
        conservationCounts[status] = (conservationCounts[status] ?? 0) + 1;
      }
    }
    final matchedINaturalist = speciesInsights
        .where((item) => item.iNaturalistGlobalObservationCount != null)
        .length;
    final staleINaturalist = items.where((item) {
      final updated = item.iNaturalistDataUpdatedAt;
      return updated != null &&
          current.difference(updated) > const Duration(days: 7);
    }).length;

    return InsightStatistics(
      totalObservations: items.length,
      totalDetections: totalDetections,
      uniqueSpecies: groups.length,
      unidentifiedObservations: unidentified.length,
      onlineDetections: online,
      offlineDetections: offline,
      unknownSourceDetections: unknownSource,
      pendingCloudSync: pending,
      poisonousObservations: poisonousObservations.length,
      poisonousSpecies: poisonousSpecies.length,
      rareObservations: rareSpecies.fold(
        0,
        (sum, item) => sum + item.savedObservationCount,
      ),
      observationsWithCoordinates: withCoordinates,
      observationsWithoutCoordinates: items.length - withCoordinates,
      uniqueMappedLocations: mappedLocations.length,
      observationsLast7Days: _countSince(
        items,
        startOfToday.subtract(const Duration(days: 6)),
        current,
      ),
      observationsLast30Days: _countSince(
        items,
        startOfToday.subtract(const Duration(days: 29)),
        current,
      ),
      newSpeciesThisMonth: firstDetectionBySpecies.values
          .where(
            (date) => !date.isBefore(startOfMonth) && !date.isAfter(current),
          )
          .length,
      firstTimeDetections: firstTimeDetections,
      repeatDetections: repeatDetections,
      highConfidenceDetections: highConfidence,
      mediumConfidenceDetections: mediumConfidence,
      lowConfidenceDetections: lowConfidence,
      averageConfidence: _average(confidenceValues),
      averageOnlineConfidence: _average(onlineConfidenceValues),
      averageOfflineConfidence: _average(offlineConfidenceValues),
      averagePrimarySecondaryGap: _average(confidenceGaps),
      lowestSavedConfidence: confidenceValues.isEmpty
          ? null
          : confidenceValues.reduce((a, b) => a < b ? a : b),
      highestConfidenceDetection:
          highest.isEmpty || highest.first.highestConfidence == null
          ? null
          : highest.first,
      mostDetectedPoisonousSpecies: poisonousSorted.isEmpty
          ? null
          : poisonousSorted.first,
      mostRecentPoisonousDetection: poisonousObservations.isEmpty
          ? null
          : poisonousObservations
                .map((item) => item.createdAt)
                .reduce((a, b) => a.isAfter(b) ? a : b),
      mostActiveMonth: _maxKey(monthCounts),
      mostActiveWeekday: _maxKey(weekdayCounts),
      averageObservationsPerActiveMonth: monthCounts.isEmpty
          ? null
          : items.length / monthCounts.length,
      mostActiveLocation: _maxKey(regionCounts) ?? _maxKey(countryCounts),
      raritySpeciesCounts: rarityCounts,
      toxicitySpeciesCounts: toxicityCounts,
      toxicityObservationCounts: toxicityObservationCounts,
      iNaturalistMatchedSpecies: matchedINaturalist,
      iNaturalistUnmatchedSpecies: speciesInsights.length - matchedINaturalist,
      staleINaturalistRecords: staleINaturalist,
      mostPubliclyObservedSpecies:
          publiclyCounted.isEmpty ? null : publiclyCounted.first,
      leastPubliclyObservedSpecies:
          publiclyCounted.isEmpty ? null : publiclyCounted.last,
      conservationStatusCounts: conservationCounts,
      observationsByMonth: _sortedMap(monthCounts),
      poisonousByMonth: _sortedMap(poisonousByMonth),
      observationsByWeekday: weekdayCounts,
      countryCounts: _rankedMap(countryCounts),
      regionCounts: _rankedMap(regionCounts),
      species: speciesInsights,
      rareSpecies: rareSpecies,
      poisonousSpeciesList: poisonousSorted,
      isLimitedSnapshot: isLimitedSnapshot,
    );
  }

  static DateTime _updatedAt(Observation item) =>
      item.updatedAt ?? item.createdAt;

  static int _countSince(
    List<Observation> items,
    DateTime start,
    DateTime end,
  ) => items
      .where(
        (item) =>
            !item.createdAt.isBefore(start) && !item.createdAt.isAfter(end),
      )
      .length;

  static String? _cleanLabel(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  static String _weekdayName(int value) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][value - 1];

  static String? _maxKey(Map<String, int> values) {
    if (values.isEmpty) return null;
    return values.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static Map<String, int> _sortedMap(Map<String, int> values) =>
      Map.fromEntries(
        values.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );

  static Map<String, int> _rankedMap(Map<String, int> values) =>
      Map.fromEntries(
        values.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

  static double? _average(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}

class _SpeciesMatcher {
  final Map<String, Species> byId = {};
  final Map<String, Species> byModelClass = {};
  final Map<String, Species> byName = {};

  _SpeciesMatcher(Iterable<Species> species) {
    for (final item in species) {
      byId[item.id] = item;
      if (item.modelId != null && item.sourceClassId != null) {
        byModelClass['${item.modelId}:${item.sourceClassId}'] = item;
      }
      for (final name in [
        item.scientificName,
        item.canonicalName,
        item.commonName,
        item.colloquialName,
      ]) {
        final key = _normalize(name);
        if (key.isNotEmpty) byName.putIfAbsent(key, () => item);
      }
    }
  }

  Species? match(Observation observation) {
    if (observation.modelId != null && observation.sourceClassId != null) {
      final match =
          byModelClass['${observation.modelId}:${observation.sourceClassId}'];
      if (match != null) return match;
    }
    final id = observation.speciesId.trim();
    if (id.isNotEmpty && byId[id] != null) return byId[id];
    for (final name in [
      observation.scientificName,
      observation.onlineScientificName,
      observation.label,
      observation.commonName,
    ]) {
      final match = byName[_normalize(name)];
      if (match != null) return match;
    }
    return null;
  }
}

class _SpeciesIdentity {
  final String key;
  final Species? species;
  final String commonName;
  final String scientificName;

  const _SpeciesIdentity({
    required this.key,
    required this.species,
    required this.commonName,
    required this.scientificName,
  });
}

_SpeciesIdentity? _identityFor(Observation observation, Species? species) {
  if (species != null) {
    return _SpeciesIdentity(
      key: species.id,
      species: species,
      commonName:
          _firstNonEmpty([species.colloquialName, species.commonName]) ??
          'No common name',
      scientificName: species.scientificName,
    );
  }
  final scientific = _firstNonEmpty([
    observation.scientificName,
    observation.onlineScientificName,
  ]);
  final label = _firstNonEmpty([
    observation.label,
    observation.commonName,
    observation.colloquialName,
  ]);
  final candidate = scientific ?? label;
  if (candidate == null || _isUnknown(candidate)) return null;
  return _SpeciesIdentity(
    key: observation.speciesId.trim().isNotEmpty
        ? 'observation:${observation.speciesId.trim().toLowerCase()}'
        : 'name:${_normalize(candidate)}',
    species: null,
    commonName:
        _firstNonEmpty([
          observation.commonName,
          observation.colloquialName,
          label,
        ]) ??
        'No common name',
    scientificName: scientific ?? label ?? candidate,
  );
}

class _SpeciesAccumulator {
  final _SpeciesIdentity identity;
  final List<Observation> observations = [];

  _SpeciesAccumulator({required this.identity});

  void add(Observation observation) => observations.add(observation);

  SpeciesInsight build({required int totalDetections}) {
    final confidences = observations
        .map(_confidenceFor)
        .whereType<double>()
        .toList();
    final sources = observations.map(_sourceFor).toSet();
    final hasOnline = sources.contains(DetectionSourceCategory.online);
    final hasOffline = sources.contains(DetectionSourceCategory.offline);
    final source = hasOnline && hasOffline
        ? DetectionSourceCategory.both
        : hasOnline
        ? DetectionSourceCategory.online
        : hasOffline
        ? DetectionSourceCategory.offline
        : DetectionSourceCategory.unknown;
    final toxicityValues = observations.map(_toxicityFor).toSet();
    final toxicity = toxicityValues.contains(ToxicityCategory.poisonous)
        ? ToxicityCategory.poisonous
        : toxicityValues.contains(ToxicityCategory.deadly)
        ? ToxicityCategory.deadly
        : toxicityValues.contains(ToxicityCategory.potentiallyPoisonous)
        ? ToxicityCategory.potentiallyPoisonous
        : toxicityValues.contains(ToxicityCategory.notKnownPoisonous)
        ? ToxicityCategory.notKnownPoisonous
        : ToxicityCategory.unknown;
    return SpeciesInsight(
      key: identity.key,
      commonName: identity.commonName,
      scientificName: identity.scientificName,
      thumbnailAssetPath: identity.species?.thumbnailAssetPath,
      detectionCount: observations.length,
      savedObservationCount: observations.length,
      percentage: totalDetections == 0
          ? 0
          : observations.length * 100 / totalDetections,
      lastDetectedAt: observations
          .map((item) => item.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      source: source,
      averageConfidence: InsightsService._average(confidences),
      highestConfidence: confidences.isEmpty
          ? null
          : confidences.reduce((a, b) => a > b ? a : b),
      rarity: identity.species?.rarity ?? SpeciesRarity.unknown,
      toxicity: toxicity,
      iNaturalistGlobalObservationCount: observations
          .map((item) => item.iNaturalistGlobalObservationCount)
          .whereType<int>()
          .firstOrNull,
      conservationStatus: observations
          .map((item) => item.conservationStatus?.trim())
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .firstOrNull,
    );
  }
}

DetectionSourceCategory _sourceFor(Observation observation) {
  final source =
      '${observation.detectionSource ?? ''} ${observation.identificationSource ?? ''}'
          .toLowerCase();
  if (observation.onlineIdentification == true || source.contains('online')) {
    return DetectionSourceCategory.online;
  }
  if (source.contains('offline')) return DetectionSourceCategory.offline;
  return DetectionSourceCategory.unknown;
}

ToxicityCategory _toxicityFor(Observation observation) {
  return switch (observation.toxicityLevel) {
    ToxicityLevel.deadly => ToxicityCategory.deadly,
    ToxicityLevel.poisonous => ToxicityCategory.poisonous,
    ToxicityLevel.potentiallyPoisonous =>
      ToxicityCategory.potentiallyPoisonous,
    ToxicityLevel.causesGastrointestinalIllness =>
      ToxicityCategory.causesGastrointestinalIllness,
    ToxicityLevel.psychoactive => ToxicityCategory.psychoactive,
    ToxicityLevel.notKnown => ToxicityCategory.notKnownPoisonous,
    ToxicityLevel.unknown => ToxicityCategory.unknown,
  };
}

double? _confidenceFor(Observation observation) => _normalizeConfidence(
  observation.finalScore ??
      observation.calibratedConfidence ??
      observation.confidence ??
      observation.onlineConfidence ??
      observation.onlineConfidencePercent,
);

double? _normalizeConfidence(double? value) {
  if (value == null || !value.isFinite || value < 0) return null;
  final normalized = value > 1 && value <= 100 ? value / 100 : value;
  return normalized <= 1 ? normalized : null;
}

bool _isPending(String? status) {
  final value = status?.trim().toLowerCase() ?? '';
  return value == 'pending_cloud_sync' ||
      value == 'pending' ||
      value == 'queued';
}

String _normalize(String? value) =>
    value?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ?? '';

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final cleaned = value?.trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;
  }
  return null;
}

bool _isUnknown(String value) {
  final normalized = _normalize(value);
  return normalized.isEmpty ||
      normalized == 'unknown' ||
      normalized == 'unidentified' ||
      normalized == 'unknown fungus' ||
      normalized == 'fungus';
}
