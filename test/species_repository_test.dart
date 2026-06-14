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
    expect(model2?.id, 'model_2:0');
    expect(model2?.scientificName, 'Agaricus campestris');
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
}
