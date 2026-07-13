import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/mushroom_id_result.dart';
import 'package:realtime_detection_app/services/mushroom_id_observation_mapper.dart';

void main() {
  test('parses normalized mushroom.id DTO', () {
    final result = MushroomIdResult.fromJson({
      'source': 'mushroom.id',
      'onlineIdentification': true,
      'topSuggestion': {
        'scientificName': 'Amanita muscaria',
        'probability': 0.6433,
        'confidencePercent': 64.33,
        'commonNames': ['Fly agaric'],
        'edibility': 'poisonous',
        'toxicity': 'toxic if eaten',
        'rank': 'species',
        'description': 'Red cap with white warts.',
        'url': 'https://example.com/amanita',
        'taxonomy': {
          'kingdom': 'Fungi',
          'phylum': 'Basidiomycota',
          'class': 'Agaricomycetes',
          'order': 'Agaricales',
          'family': 'Amanitaceae',
          'genus': 'Amanita',
        },
        'similarImages': [
          {
            'urlSmall': 'https://example.com/small.jpg',
            'url': 'https://example.com/full.jpg',
            'similarity': 0.694,
            'citation': 'Example',
            'licenseName': 'CC BY',
          },
        ],
      },
      'alternatives': [
        {
          'scientificName': 'Amanita parcivolvata',
          'probability': 0.1589,
          'confidencePercent': 15.89,
          'commonNames': ['False fly agaric'],
          'url': 'https://example.com/alt',
        },
      ],
      'warnings': ['Do not consume fungi based on app identification.'],
      'locationFilterApplied': false,
    });

    expect(result.topSuggestion?.scientificName, 'Amanita muscaria');
    expect(result.topSuggestion?.confidencePercent, 64.33);
    expect(result.topSuggestion?.commonNames, ['Fly agaric']);
    expect(result.topSuggestion?.taxonomy['genus'], 'Amanita');
    expect(result.topSuggestion?.similarImages.first.licenseName, 'CC BY');
    expect(result.alternatives.single.scientificName, 'Amanita parcivolvata');
    expect(result.hasConfidentTopSuggestion, isTrue);
  });

  test('handles empty online suggestions', () {
    final result = MushroomIdResult.fromJson({
      'source': 'mushroom.id',
      'onlineIdentification': true,
      'topSuggestion': null,
      'alternatives': [],
    });

    expect(result.topSuggestion, isNull);
    expect(result.alternatives, isEmpty);
    expect(result.hasConfidentTopSuggestion, isFalse);
  });

  test('maps online result into observation draft', () {
    final result = MushroomIdResult.fromJson({
      'topSuggestion': {
        'scientificName': 'Amanita muscaria',
        'probability': 0.6433,
        'confidencePercent': 64.33,
        'commonNames': ['Fly agaric'],
        'edibility': 'poisonous',
        'description': 'Red cap with white warts.',
      },
      'alternatives': [
        {
          'scientificName': 'Amanita parcivolvata',
          'probability': 0.1589,
          'confidencePercent': 15.89,
        },
      ],
    });

    final draft = const MushroomIdObservationMapper().draftFromResult(result);

    expect(draft.label, 'Amanita muscaria');
    expect(draft.commonName, 'Fly agaric');
    expect(draft.confidence, 0.6433);
    expect(draft.candidates, hasLength(2));
    expect(draft.notes, contains('Do not consume fungi'));
    expect(draft.notes, contains('Edibility: poisonous'));
    expect(draft.notes, contains('Possible matches'));
  });
}
