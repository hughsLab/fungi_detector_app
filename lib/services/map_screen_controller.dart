import '../models/observation.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/settings_service.dart';

class MapScreenData {
  final bool locationTaggingEnabled;
  final bool mapTileCachingEnabled;
  final List<Observation> observations;
  final Map<String, String> speciesNames;

  const MapScreenData({
    required this.locationTaggingEnabled,
    required this.mapTileCachingEnabled,
    required this.observations,
    required this.speciesNames,
  });
}

class MapScreenController {
  final ObservationRepository _observationRepository;
  final SpeciesRepository _speciesRepository;
  final SettingsService _settingsService;

  MapScreenController({
    ObservationRepository? observationRepository,
    SpeciesRepository? speciesRepository,
    SettingsService? settingsService,
  })  : _observationRepository =
            observationRepository ?? ObservationRepository.instance,
        _speciesRepository = speciesRepository ?? SpeciesRepository.instance,
        _settingsService = settingsService ?? SettingsService.instance;

  Future<MapScreenData> load() async {
    final settings = await _settingsService.loadSettings();
    final observations = await _observationRepository.getAllWithLocation();
    final species = await _speciesRepository.loadSpecies();
    final names = {for (final item in species) item.id: item.displayName};

    return MapScreenData(
      locationTaggingEnabled: settings.locationTaggingEnabled,
      mapTileCachingEnabled: settings.mapTileCachingEnabled,
      observations: observations,
      speciesNames: names,
    );
  }
}
