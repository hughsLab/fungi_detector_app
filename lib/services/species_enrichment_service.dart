import '../models/inaturalist_taxon.dart';
import '../models/species.dart';
import '../models/toxicity_level.dart';
import 'inaturalist_service.dart';
import 'toxicity_resolver.dart';

class SpeciesEnrichmentResult {
  final Species? localSpecies;
  final INaturalistTaxonMatch iNaturalist;
  final ToxicityLevel toxicityLevel;
  final String? toxicitySummary;
  final String? toxicitySource;
  final String? toxicitySourceUrl;

  const SpeciesEnrichmentResult({
    required this.localSpecies,
    required this.iNaturalist,
    required this.toxicityLevel,
    required this.toxicitySummary,
    required this.toxicitySource,
    required this.toxicitySourceUrl,
  });
}

class SpeciesEnrichmentService {
  SpeciesEnrichmentService({
    INaturalistService? iNaturalistService,
    ToxicityResolver? toxicityResolver,
  }) : _iNaturalistService =
           iNaturalistService ?? INaturalistService.instance,
       _toxicityResolver = toxicityResolver ?? ToxicityResolver();

  static final SpeciesEnrichmentService instance = SpeciesEnrichmentService();

  final INaturalistService _iNaturalistService;
  final ToxicityResolver _toxicityResolver;

  Future<SpeciesEnrichmentResult> enrich(
    String scientificName, {
    String? speciesId,
    String? placeId,
  }) async {
    final taxon = await _iNaturalistService.findTaxonByScientificName(
      scientificName,
      placeId: placeId,
    );
    final toxicity = await _toxicityResolver.resolve(
      speciesId: speciesId,
      iNaturalistTaxonId: taxon.taxonId,
      acceptedScientificName: taxon.acceptedScientificName,
      scientificName: scientificName,
    );
    return SpeciesEnrichmentResult(
      localSpecies: toxicity.species,
      iNaturalist: taxon,
      toxicityLevel: toxicity.level,
      toxicitySummary: toxicity.summary,
      toxicitySource: toxicity.source,
      toxicitySourceUrl: toxicity.sourceUrl,
    );
  }
}
