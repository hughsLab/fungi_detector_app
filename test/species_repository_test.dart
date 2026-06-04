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
}
