import '../models/species.dart';
import '../models/toxicity_level.dart';
import '../repositories/species_repository.dart';

class ToxicityResolution {
  final Species? species;
  final ToxicityLevel level;
  final String? summary;
  final String? source;
  final String? sourceUrl;

  const ToxicityResolution({
    required this.species,
    required this.level,
    required this.summary,
    required this.source,
    required this.sourceUrl,
  });
}

class ToxicityResolver {
  ToxicityResolver({SpeciesRepository? speciesRepository})
    : _speciesRepository = speciesRepository ?? SpeciesRepository.instance;

  final SpeciesRepository _speciesRepository;

  Future<ToxicityResolution> resolve({
    String? speciesId,
    int? iNaturalistTaxonId,
    String? acceptedScientificName,
    String? scientificName,
  }) async {
    final all = await _speciesRepository.loadSpecies();
    return resolveFromSpecies(
      all,
      speciesId: speciesId,
      iNaturalistTaxonId: iNaturalistTaxonId,
      acceptedScientificName: acceptedScientificName,
      scientificName: scientificName,
    );
  }

  ToxicityResolution resolveFromSpecies(
    Iterable<Species> all, {
    String? speciesId,
    int? iNaturalistTaxonId,
    String? acceptedScientificName,
    String? scientificName,
  }) {
    Species? match;
    final id = speciesId?.trim() ?? '';
    if (id.isNotEmpty) {
      match = all.where((item) => item.id == id).firstOrNull;
    }
    match ??= all
        .where(
          (item) =>
              iNaturalistTaxonId != null &&
              item.iNaturalistTaxonId == iNaturalistTaxonId,
        )
        .firstOrNull;
    for (final name in [acceptedScientificName, scientificName]) {
      if (match != null || (name?.trim().isEmpty ?? true)) continue;
      final normalized = _normalize(name!);
      match = all
          .where(
            (item) =>
                _normalize(item.scientificName) == normalized ||
                _normalize(item.canonicalName ?? '') == normalized,
          )
          .firstOrNull;
    }
    return ToxicityResolution(
      species: match,
      level: match?.toxicityLevel ?? ToxicityLevel.unknown,
      summary: match?.toxicitySummary,
      source: match?.toxicitySource,
      sourceUrl: match?.toxicitySourceUrl,
    );
  }
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
