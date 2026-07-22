import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/insight_statistics.dart';
import 'package:realtime_detection_app/models/observation.dart';
import 'package:realtime_detection_app/models/species.dart';
import 'package:realtime_detection_app/models/toxicity_level.dart';
import 'package:realtime_detection_app/services/insights_service.dart';

void main() {
  const service = InsightsService();
  final now = DateTime(2026, 7, 21, 12);

  test('zero observations produces empty, available statistics', () {
    final result = service.calculate(
      observations: const [],
      species: const [],
      now: now,
    );
    expect(result.totalObservations, 0);
    expect(result.totalDetections, 0);
    expect(result.species, isEmpty);
    expect(result.averageConfidence, isNull);
  });

  test('groups species, prevents duplicate IDs, and calculates confidence', () {
    final species = _species(
      id: '1',
      scientific: 'Amanita muscaria',
      common: 'Fly agaric',
    );
    final observations = [
      _observation(
        id: 'a',
        speciesId: '1',
        label: 'Fly agaric',
        confidence: .8,
        createdAt: DateTime(2026, 7, 1),
        source: 'offline_model',
      ),
      _observation(
        id: 'b',
        speciesId: '1',
        label: 'Fly agaric',
        confidence: .6,
        createdAt: DateTime(2026, 7, 2),
        source: 'online_mushroom_id',
        online: true,
      ),
      _observation(
        id: 'a',
        speciesId: '1',
        label: 'Fly agaric',
        confidence: .9,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 3),
        source: 'offline_model',
      ),
    ];
    final result = service.calculate(
      observations: observations,
      species: [species],
      now: now,
    );
    expect(result.totalObservations, 2);
    expect(result.totalDetections, 2);
    expect(result.uniqueSpecies, 1);
    expect(result.species.single.detectionCount, 2);
    expect(result.species.single.source, DetectionSourceCategory.both);
    expect(result.species.single.averageConfidence, closeTo(.75, .0001));
    expect(result.species.single.highestConfidence, .9);
    expect(result.highConfidenceDetections, 1);
    expect(result.mediumConfidenceDetections, 1);
  });

  test('keeps biological rarity independent from user frequency', () {
    final rare = _species(
      id: 'rare',
      scientific: 'Rare fungus',
      rarity: 'rare',
    );
    final unknown = _species(id: 'unknown', scientific: 'Unknown rarity');
    final result = service.calculate(
      observations: [
        _observation(id: '1', speciesId: 'rare', label: 'Rare fungus'),
        _observation(id: '2', speciesId: 'unknown', label: 'Unknown rarity'),
        _observation(id: '3', speciesId: 'unknown', label: 'Unknown rarity'),
      ],
      species: [rare, unknown],
      now: now,
    );
    expect(result.raritySpeciesCounts[SpeciesRarity.rare], 1);
    expect(result.raritySpeciesCounts[SpeciesRarity.unknown], 1);
    expect(result.rareObservations, 1);
    expect(
      result.species.firstWhere((item) => item.key == 'unknown').rarity,
      SpeciesRarity.unknown,
    );
  });

  test(
    'uses explicit toxicity only and preserves missing toxicity as unknown',
    () {
      final species = _species(id: '1', scientific: 'Amanita example');
      final result = service.calculate(
        observations: [
          _observation(
            id: '1',
            speciesId: '1',
            label: 'Amanita example',
            toxicity: 'poisonous',
          ),
          _observation(id: '2', speciesId: '1', label: 'Amanita example'),
        ],
        species: [species],
        now: now,
      );
      expect(result.poisonousSpecies, 1);
      expect(result.poisonousObservations, 1);
      expect(result.species.single.toxicity, ToxicityCategory.poisonous);

      final unknownResult = service.calculate(
        observations: [
          _observation(id: '3', speciesId: '1', label: 'Amanita example'),
        ],
        species: [species],
        now: now,
      );
      expect(unknownResult.poisonousSpecies, 0);
      expect(unknownResult.toxicitySpeciesCounts[ToxicityCategory.unknown], 1);
    },
  );

  test(
    'calculates sources, dates, pending sync, location, and unidentified',
    () {
      final known = _species(id: '1', scientific: 'Known fungus');
      final result = service.calculate(
        observations: [
          _observation(
            id: '1',
            speciesId: '1',
            label: 'Known fungus',
            source: 'offline_model',
            confidence: .8,
            top2: .5,
            createdAt: DateTime(2026, 7, 21),
            latitude: -42,
            longitude: 147,
            country: 'Australia',
            region: 'Tasmania',
            syncStatus: 'pending_cloud_sync',
          ),
          _observation(
            id: '2',
            speciesId: '1',
            label: 'Known fungus',
            source: 'online_mushroom_id',
            online: true,
            confidence: .4,
            createdAt: DateTime(2026, 6, 1),
            latitude: 999,
            longitude: 999,
          ),
          _observation(
            id: '3',
            speciesId: '',
            label: 'Unknown',
            createdAt: DateTime(2026, 6, 2),
          ),
        ],
        species: [known],
        now: now,
      );
      expect(result.onlineDetections, 1);
      expect(result.offlineDetections, 1);
      expect(result.unidentifiedObservations, 1);
      expect(result.pendingCloudSync, 1);
      expect(result.observationsWithCoordinates, 1);
      expect(result.observationsWithoutCoordinates, 2);
      expect(result.countryCounts['Australia'], 1);
      expect(result.regionCounts['Tasmania'], 1);
      expect(result.averagePrimarySecondaryGap, closeTo(.3, .0001));
      expect(result.observationsLast7Days, 1);
      expect(result.observationsByMonth, {'2026-06': 2, '2026-07': 1});
    },
  );

  test('filters personal and public observations without mutating input', () {
    final species = _species(id: '1', scientific: 'Known fungus');
    final observations = [
      _observation(
        id: 'mine',
        userId: 'me',
        speciesId: '1',
        label: 'Known fungus',
        isPublic: false,
      ),
      _observation(
        id: 'theirs',
        userId: 'them',
        speciesId: '1',
        label: 'Known fungus',
        isPublic: true,
      ),
    ];
    final personal = service.calculate(
      observations: observations,
      species: [species],
      userId: 'me',
      now: now,
    );
    final global = service.calculate(
      observations: observations,
      species: [species],
      publicOnly: true,
      now: now,
    );
    expect(personal.totalObservations, 1);
    expect(global.totalObservations, 1);
    expect(observations, hasLength(2));
  });

  test('old observation records tolerate missing and string fields', () {
    final observation = Observation.fromJson({
      'id': 'old',
      'label': 'Old fungus',
      'confidence': '0.65',
      'top2Confidence': '0.2',
      'timestamp': '2026-07-01T00:00:00.000',
    });
    final result = service.calculate(
      observations: [observation],
      species: const [],
      now: now,
    );
    expect(result.totalObservations, 1);
    expect(result.totalDetections, 1);
    expect(result.averageConfidence, .65);
  });
}

Species _species({
  required String id,
  required String scientific,
  String? common,
  String? rarity,
}) => Species.fromJson({
  'id': id,
  'scientificName': scientific,
  'commonName': common,
  if (rarity != null) 'rarity': rarity,
});

Observation _observation({
  required String id,
  required String speciesId,
  required String label,
  String? userId,
  double? confidence,
  double? top2,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? source,
  bool? online,
  String? toxicity,
  double? latitude,
  double? longitude,
  String? country,
  String? region,
  String? syncStatus,
  bool isPublic = false,
}) => Observation(
  id: id,
  userId: userId,
  speciesId: speciesId,
  classIndex: null,
  label: label,
  confidence: confidence,
  top2Confidence: top2,
  createdAt: createdAt ?? DateTime(2026, 7, 1),
  updatedAt: updatedAt,
  photoPath: null,
  detectionSource: source,
  identificationSource: source,
  onlineIdentification: online,
  toxicityLevel: toxicity == null
      ? ToxicityLevel.unknown
      : parseToxicityLevel(toxicity),
  latitude: latitude,
  longitude: longitude,
  country: country,
  region: region,
  syncStatus: syncStatus,
  isPublic: isPublic,
);
