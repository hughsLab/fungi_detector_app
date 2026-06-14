import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/repositories/species_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads model 1 and namespaced model 2 species cards', () async {
    final species = await SpeciesRepository.instance.loadSpecies();
    final model1 = await SpeciesRepository.instance.getByModelClass(
      SpeciesRepository.model1Id,
      0,
    );
    final model2 = await SpeciesRepository.instance.getByModelClass(
      SpeciesRepository.model2Id,
      0,
    );

    expect(species.length, greaterThanOrEqualTo(273));
    expect(model1?.id, '0');
    expect(model1?.scientificName, 'Aleuria aurantia');
    expect(model1?.keyFeatures, isNotEmpty);
    expect(model1?.location.global, contains('Australia'));
    expect(model1?.location.australiaStates, contains('Tasmania'));
    expect(model2?.id, 'model_2:0');
    expect(model2?.scientificName, 'Agaricus campestris');
    expect(model2?.keyFeatures, isNotEmpty);
    expect(model2?.location.global, contains('Australia'));
    expect(model2?.location.australiaStates, contains('Tasmania'));
  });

  test('stable model and class identifiers beat ambiguous species ids', () async {
    final match = await SpeciesRepository.instance.matchSpecies(
      speciesId: '0',
      modelId: SpeciesRepository.model2Id,
      sourceClassId: 0,
      label: 'field mushroom',
    );

    expect(match?.id, 'model_2:0');
    expect(match?.scientificName, 'Agaricus campestris');
    expect(match?.colloquialName, 'field mushroom');
  });

  test('display names are not used as primary species lookup keys', () async {
    final match = await SpeciesRepository.instance.matchSpecies(
      label: 'field mushroom',
    );

    expect(match, isNull);
  });

  test('matches enriched species by stable identifiers and scientific name', () async {
    final byModelClass = await SpeciesRepository.instance.matchSpecies(
      modelId: SpeciesRepository.model2Id,
      sourceClassId: 0,
      label: 'field mushroom',
    );
    final byScientificName = await SpeciesRepository.instance.matchSpecies(
      scientificName: 'Aleuria aurantia',
    );

    expect(byModelClass?.scientificName, 'Agaricus campestris');
    expect(byModelClass?.keyFeatures, isNotEmpty);
    expect(byScientificName?.scientificName, 'Aleuria aurantia');
    expect(byScientificName?.keyFeatures, isNotEmpty);
  });
}
