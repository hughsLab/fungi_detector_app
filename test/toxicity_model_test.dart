import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';
import 'package:realtime_detection_app/models/species.dart';
import 'package:realtime_detection_app/models/toxicity_level.dart';
import 'package:realtime_detection_app/services/toxicity_resolver.dart';

void main() {
  test('legacy poisonous true migrates but false never becomes edible', () {
    expect(
      Observation.fromJson({
        'id': '1',
        'label': 'Fungus',
        'createdAt': '2026-01-01T00:00:00Z',
        'isPoisonous': true,
      }).toxicityLevel,
      ToxicityLevel.poisonous,
    );
    expect(
      Observation.fromJson({
        'id': '2',
        'label': 'Fungus',
        'createdAt': '2026-01-01T00:00:00Z',
        'isPoisonous': false,
      }).toxicityLevel,
      ToxicityLevel.notKnown,
    );
  });

  test('unknown toxicity and iNaturalist enrichment round-trip safely', () {
    final observation = Observation(
      id: '1',
      speciesId: 'fungus',
      classIndex: null,
      label: 'Fungus',
      confidence: .8,
      createdAt: DateTime.utc(2026),
      photoPath: 'photo.jpg',
      iNaturalistTaxonId: 123,
      iNaturalistGlobalObservationCount: 456,
      toxicityLevel: ToxicityLevel.unknown,
    );
    final restored = Observation.fromJson(observation.toJson());
    expect(restored.toxicityLevel, ToxicityLevel.unknown);
    expect(restored.iNaturalistTaxonId, 123);
    expect(restored.iNaturalistGlobalObservationCount, 456);
  });

  test('resolver accepts scientific names and synonyms but not common names', () {
    final species = Species.fromJson({
      'id': 'curated-1',
      'scientificName': 'Accepted fungus',
      'canonicalName': 'Old fungus',
      'commonName': 'Red cap',
      'toxicityLevel': 'deadly',
      'toxicitySource': 'Curated field guide',
    });
    final resolver = ToxicityResolver();
    expect(
      resolver
          .resolveFromSpecies(
            [species],
            acceptedScientificName: 'accepted FUNGUS',
          )
          .level,
      ToxicityLevel.deadly,
    );
    expect(
      resolver
          .resolveFromSpecies([species], scientificName: 'Old fungus')
          .level,
      ToxicityLevel.deadly,
    );
    expect(
      resolver
          .resolveFromSpecies([species], scientificName: 'Red cap')
          .level,
      ToxicityLevel.unknown,
    );
  });
}
