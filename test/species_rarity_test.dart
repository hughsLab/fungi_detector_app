import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/species.dart';

void main() {
  test('explicit rarity takes precedence over range estimate', () {
    final species = _species(
      rarity: 'very_rare',
      globalRegions: const <String>['Australia', 'Europe', 'Asia'],
      australianStates: const <String>[
        'Tasmania',
        'Victoria',
        'New South Wales',
      ],
    );

    expect(species.mapRarity, SpeciesRarity.veryRare);
    expect(species.mapRarityIsEstimated, isFalse);
  });

  test('documented range provides rarity estimate when status is absent', () {
    expect(
      _species(
        globalRegions: const <String>['Australia'],
        australianStates: const <String>['Tasmania', 'Victoria'],
      ).mapRarity,
      SpeciesRarity.veryRare,
    );
    expect(
      _species(
        globalRegions: const <String>['Australia', 'New Zealand', 'Europe'],
        australianStates: const <String>['Tasmania', 'Victoria', 'NSW'],
      ).mapRarity,
      SpeciesRarity.rare,
    );
    expect(
      _species(
        globalRegions: const <String>['Australia', 'Europe', 'Asia', 'Africa'],
        australianStates: const <String>[
          'Tasmania',
          'Victoria',
          'NSW',
          'Queensland',
          'South Australia',
        ],
      ).mapRarity,
      SpeciesRarity.uncommon,
    );
  });

  test('missing rarity and range remain unknown', () {
    final species = _species();

    expect(species.mapRarity, SpeciesRarity.unknown);
    expect(species.mapRarityIsEstimated, isTrue);
  });
}

Species _species({
  String? rarity,
  List<String> globalRegions = const <String>[],
  List<String> australianStates = const <String>[],
}) {
  return Species.fromJson(<String, dynamic>{
    'id': 'test-species',
    'scientificName': 'Testus fungalis',
    if (rarity != null) 'rarity': rarity,
    'location': <String, dynamic>{
      'global': globalRegions,
      'australia': <String, dynamic>{'states': australianStates},
    },
  });
}
