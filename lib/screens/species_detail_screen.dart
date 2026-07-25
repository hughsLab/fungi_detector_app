import 'package:flutter/material.dart';

import '../models/field_note.dart';
import '../models/inaturalist_taxon.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../models/wikipedia_species_content.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/species_repository.dart';
import '../services/species_map_location_resolver.dart';
import '../services/inaturalist_service.dart';
import '../services/wikipedia_service.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';
import '../widgets/global_distribution_map_preview.dart';
import '../widgets/key_features_section.dart';
import '../widgets/inaturalist_observation_charts.dart';
import '../widgets/species/compact_safety_section.dart';
import '../widgets/species/data_attribution_section.dart';
import '../widgets/species/species_name_text.dart';
import '../widgets/species/taxonomy_tree.dart';
import '../widgets/species/wikipedia_species_section.dart';

class SpeciesDetailScreen extends StatefulWidget {
  const SpeciesDetailScreen({
    super.key,
    this.speciesRepository,
    this.iNaturalistService,
    this.wikipediaService,
  });

  final SpeciesRepository? speciesRepository;
  final INaturalistService? iNaturalistService;
  final WikipediaService? wikipediaService;

  @override
  State<SpeciesDetailScreen> createState() => _SpeciesDetailScreenState();
}

class _SpeciesDetailScreenState extends State<SpeciesDetailScreen> {
  SpeciesRepository get _repository =>
      widget.speciesRepository ?? SpeciesRepository.instance;
  INaturalistService get _iNaturalistService =>
      widget.iNaturalistService ?? INaturalistService.instance;
  WikipediaService get _wikipediaService =>
      widget.wikipediaService ?? WikipediaService.instance;
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;
  SpeciesDetailArgs? _args;
  Future<_SpeciesDetailData>? _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) {
      return;
    }
    final args =
        ModalRoute.of(context)?.settings.arguments as SpeciesDetailArgs?;
    if (args != null) {
      _args = args;
      _dataFuture = _loadData(args.speciesId);
    }
  }

  Future<_SpeciesDetailData> _loadData(String id) async {
    final species = await _repository.getById(id);
    final all = await _repository.loadSpecies();
    final similar = <Species>[];
    if (species != null) {
      for (final similarId in species.similarSpeciesIds) {
        final match = all.where((item) => item.id == similarId);
        if (match.isNotEmpty) {
          similar.add(match.first);
        }
      }
    }
    final iNaturalistFuture = species == null
        ? null
        : _iNaturalistService.findTaxonByScientificName(
            species.scientificName,
            storedTaxonId: species.iNaturalistTaxonId,
            synonyms: [
              if ((species.canonicalName ?? '').trim().isNotEmpty)
                species.canonicalName!,
            ],
          );
    final wikipediaFuture = species == null
        ? null
        : _wikipediaService.findSpecies(
            species.scientificName,
            synonyms: [
              if ((species.canonicalName ?? '').trim().isNotEmpty)
                species.canonicalName!,
            ],
          );
    return _SpeciesDetailData(
      species: species,
      similar: similar,
      iNaturalistFuture: iNaturalistFuture,
      wikipediaFuture: wikipediaFuture,
    );
  }

  void _openSaveObservation(String speciesId) {
    Navigator.of(context).pushNamed(
      '/save-observation',
      arguments: SaveObservationArgs(preselectedSpeciesId: speciesId),
    );
  }

  void _returnToObservationCard() {
    Navigator.of(context).pop();
  }

  String? _extractEcologicalRole(Species species) {
    final description = (species.shortDescription ?? '').toLowerCase();
    if (description.contains('mycorrh')) {
      return 'Mycorrhizal';
    }
    if (description.contains('saprotroph') ||
        description.contains('saprobe') ||
        description.contains('saprotrophic')) {
      return 'Saprotrophic';
    }
    if (description.contains('parasit')) {
      return 'Parasitic';
    }
    if (description.contains('lichen')) {
      return 'Lichenized';
    }
    if (description.contains('symbio')) {
      return 'Symbiotic';
    }
    return null;
  }

  Set<int> _parseSeasonalityMonths(String season) {
    final normalized = season.toLowerCase();
    final Map<String, int> months = const {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };

    final Set<int> found = {};
    for (final entry in months.entries) {
      if (normalized.contains(entry.key)) {
        found.add(entry.value);
      }
    }

    if (found.isNotEmpty) {
      return found;
    }
    if (normalized.contains('summer')) {
      return {12, 1, 2};
    }
    if (normalized.contains('autumn') || normalized.contains('fall')) {
      return {3, 4, 5};
    }
    if (normalized.contains('winter')) {
      return {6, 7, 8};
    }
    if (normalized.contains('spring')) {
      return {9, 10, 11};
    }
    return {};
  }

  String _normalizeLabel(String value) {
    return value.trim().toLowerCase();
  }

  Widget _fieldNotesPanel(String speciesId) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Field Notes',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/field-note-editor',
                    arguments: FieldNoteEditorArgs(
                      prelinkedSpeciesId: speciesId,
                    ),
                  );
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          StreamBuilder<List<FieldNote>>(
            stream: _fieldNotesRepository.watchAllNotes(),
            builder: (context, snapshot) {
              final notes = (snapshot.data ?? const <FieldNote>[])
                  .where((note) => note.links.speciesIds.contains(speciesId))
                  .toList();
              if (notes.isEmpty) {
                return const Text(
                  'No notes linked to this species yet.',
                  style: TextStyle(color: Color(0xCCFFFFFF)),
                );
              }
              return Column(
                children: notes.map((note) {
                  final title = note.title.trim().isEmpty
                      ? 'Untitled note'
                      : note.title;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      formatDateTime(note.updatedAt),
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/field-note-editor',
                        arguments: FieldNoteEditorArgs(noteId: note.id),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }

  Widget _similarChip(String label, {bool highlight = false}) {
    final Color border = highlight
        ? const Color(0xFF7CD39A)
        : Colors.white.withValues(alpha: 0.2);
    final Color background = highlight
        ? const Color(0xFF7CD39A).withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.12);
    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
        ),
      ),
      backgroundColor: background,
      side: BorderSide(color: border),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Species Detail'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: _dataFuture == null
            ? const Center(child: CircularProgressIndicator())
            : FutureBuilder<_SpeciesDetailData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data?.species == null) {
                    return const Center(
                      child: Text(
                        'Species not found.',
                        style: TextStyle(color: accentTextColor),
                      ),
                    );
                  }

                  final data = snapshot.data!;
                  final species = data.species!;
                  final similarSpecies = data.similar;
                  final observation = _args?.observation;
                  final String? comparePrimaryLabel = _args?.comparePrimaryLabel
                      ?.trim();
                  final String? compareSecondaryLabel = _args
                      ?.compareSecondaryLabel
                      ?.trim();
                  final String? compareSecondaryNormalized =
                      compareSecondaryLabel == null ||
                          compareSecondaryLabel.isEmpty
                      ? null
                      : _normalizeLabel(compareSecondaryLabel);
                  final bool isCompareFlow = compareSecondaryNormalized != null;
                  final bool fromExistingObservation =
                      _args?.source == SpeciesDetailSource.existingObservation;
                  final similarNames = species.similarSpeciesNames
                      .where((name) => name.trim().isNotEmpty)
                      .toList();
                  final List<String> similarLabels = similarSpecies.isNotEmpty
                      ? similarSpecies.map((item) => item.displayName).toList()
                      : similarNames;
                  final Set<String> similarNormalized = similarLabels
                      .map((label) => _normalizeLabel(label))
                      .toSet();
                  final List<Widget> similarChips = [
                    ...similarLabels.map((label) {
                      final bool highlight =
                          compareSecondaryNormalized != null &&
                          _normalizeLabel(label) == compareSecondaryNormalized;
                      return _similarChip(label, highlight: highlight);
                    }),
                    if (isCompareFlow &&
                        compareSecondaryLabel != null &&
                        !similarNormalized.contains(compareSecondaryNormalized))
                      _similarChip(compareSecondaryLabel, highlight: true),
                  ];
                  final bool hasSimilar = similarChips.isNotEmpty;
                  final description = species.shortDescription?.trim() ?? '';
                  final habitat = species.habitat?.trim() ?? '';
                  final season = species.season?.trim() ?? '';
                  final Set<int> seasonMonths = season.isEmpty
                      ? {}
                      : _parseSeasonalityMonths(season);
                  final String? ecologicalRole = _extractEcologicalRole(
                    species,
                  );
                  final distributionNote = species.distributionNote.trim();
                  final location = species.location;
                  final distributionMarkers = SpeciesMapLocationResolver
                      .instance
                      .resolveMarkers(species);
                  final edibilityWarning =
                      species.edibilityWarning?.trim() ?? '';
                  final String colloquialName =
                      (species.colloquialName?.trim().isNotEmpty ?? false)
                      ? species.colloquialName!.trim()
                      : ((species.commonName?.trim().isNotEmpty ?? false)
                            ? species.commonName!.trim()
                            : 'Not listed');

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SpeciesNameText(
                          scientificName: species.scientificName,
                          commonName: colloquialName == 'Not listed'
                              ? null
                              : colloquialName,
                        ),
                        if (species.authority != null &&
                            species.authority!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Authority: ${species.authority}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: accentTextColor,
                              ),
                            ),
                          ),
                        if (isCompareFlow && compareSecondaryLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _CompareSummaryCard(
                              primaryLabel:
                                  comparePrimaryLabel ?? species.scientificName,
                              secondaryLabel: compareSecondaryLabel,
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (data.wikipediaFuture != null)
                          WikipediaSpeciesSection(
                            future: data.wikipediaFuture!,
                            localImageAssetPath: species.thumbnailAssetPath,
                          ),
                        const SizedBox(height: 16),
                        if (data.iNaturalistFuture != null)
                          INaturalistTaxonomySection(
                            future: data.iNaturalistFuture!,
                          ),
                        const SizedBox(height: 16),
                        if (data.iNaturalistFuture != null)
                          INaturalistObservationInformation(
                            future: data.iNaturalistFuture!,
                          ),
                        if (observation != null) ...[
                          const SizedBox(height: 16),
                          _ObservationSummaryCard(observation: observation),
                        ],
                        const SizedBox(height: 16),
                        INaturalistObservationCharts(
                          taxonId: species.iNaturalistTaxonId,
                          scientificName: species.scientificName,
                          service: _iNaturalistService,
                        ),
                        const SizedBox(height: 16),
                        CompactSafetySection(
                          level: species.toxicityLevel,
                          summary: species.toxicitySummary,
                          source: species.toxicitySource,
                          edibilityWarning: edibilityWarning,
                        ),
                        const SizedBox(height: 16),
                        if (data.wikipediaFuture != null)
                          DataAttributionSection(
                            wikipediaFuture: data.wikipediaFuture!,
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'Field Guide+',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (description.isNotEmpty) ...[
                                _sectionTitle('Local guide overview'),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              KeyFeaturesSection(features: species.keyFeatures),
                              if (habitat.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _sectionTitle('Habitat'),
                                const SizedBox(height: 6),
                                Text(
                                  habitat,
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              if (ecologicalRole != null) ...[
                                const SizedBox(height: 12),
                                _sectionTitle('Ecological Role'),
                                const SizedBox(height: 6),
                                Text(
                                  ecologicalRole,
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              if (season.isNotEmpty ||
                                  seasonMonths.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _sectionTitle('Seasonality'),
                                const SizedBox(height: 6),
                                if (season.isNotEmpty)
                                  Text(
                                    season,
                                    style: const TextStyle(
                                      color: accentTextColor,
                                      height: 1.4,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                _SeasonalityStrip(activeMonths: seasonMonths),
                              ],
                              const SizedBox(height: 12),
                              _sectionTitle('Similar Species'),
                              if (isCompareFlow &&
                                  compareSecondaryLabel != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Comparing with $compareSecondaryLabel. Review key features and habitat differences.',
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              !hasSimilar
                                  ? const Text(
                                      'No similar species listed.',
                                      style: TextStyle(color: accentTextColor),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: similarChips,
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Distribution',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        distributionNote.isEmpty
                            ? const Text(
                                'No distribution notes listed.',
                                style: TextStyle(color: accentTextColor),
                              )
                            : Text(
                                distributionNote,
                                style: const TextStyle(
                                  color: accentTextColor,
                                  height: 1.4,
                                ),
                              ),
                        if (!location.isEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle('Location'),
                                if (location.global.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _LocationLine(
                                    label: 'Global',
                                    value: location.global.join(', '),
                                  ),
                                ],
                                if (location.australiaStates.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _LocationLine(
                                    label: 'Australia',
                                    value: location.australiaStates.join(', '),
                                  ),
                                ],
                                if (location.regionalNotes.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _BulletList(
                                    items: location.regionalNotes,
                                    emptyText: 'No regional notes listed.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        GlobalDistributionMapPreview(
                          scientificName: species.scientificName,
                          canonicalName: species.canonicalName,
                          speciesId: species.id,
                          modelId: species.modelId,
                          sourceClassId: species.sourceClassId,
                          observationLatitude: observation?.latitude,
                          observationLongitude: observation?.longitude,
                          markers: distributionMarkers,
                          emptyText:
                              'Location data not available for this species.',
                        ),
                        const SizedBox(height: 16),
                        _fieldNotesPanel(species.id),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: fromExistingObservation
                                ? _returnToObservationCard
                                : () => _openSaveObservation(species.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8FBFA1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              fromExistingObservation
                                  ? 'Back to Observation Card'
                                  : 'Save Observation',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SpeciesDetailData {
  final Species? species;
  final List<Species> similar;
  final Future<INaturalistTaxonMatch>? iNaturalistFuture;
  final Future<WikipediaSpeciesContent>? wikipediaFuture;

  const _SpeciesDetailData({
    required this.species,
    required this.similar,
    required this.iNaturalistFuture,
    required this.wikipediaFuture,
  });
}

class _SeasonalityStrip extends StatelessWidget {
  final Set<int> activeMonths;

  const _SeasonalityStrip({required this.activeMonths});

  @override
  Widget build(BuildContext context) {
    const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (index) {
        final month = index + 1;
        final bool active = activeMonths.contains(month);
        final Color color = active
            ? const Color(0xFF7CD39A)
            : Colors.white.withValues(alpha: 0.3);
        return Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF7CD39A).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Text(
            labels[index],
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }),
    );
  }
}

class _CompareSummaryCard extends StatelessWidget {
  final String primaryLabel;
  final String secondaryLabel;

  const _CompareSummaryCard({
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compare Similar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _CompareChipRow(
            label: 'Primary',
            value: primaryLabel,
            color: const Color(0xFF7CD39A),
          ),
          const SizedBox(height: 6),
          _CompareChipRow(
            label: 'Secondary',
            value: secondaryLabel,
            color: const Color(0xFFFFC857),
          ),
        ],
      ),
    );
  }
}

class _CompareChipRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CompareChipRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  final String emptyText;

  const _BulletList({
    required this.items,
    this.emptyText = 'No identifying features listed.',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(emptyText, style: const TextStyle(color: Color(0xCCFFFFFF)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LocationLine extends StatelessWidget {
  final String label;
  final String value;

  const _LocationLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Color(0xCCFFFFFF), height: 1.35),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ObservationSummaryCard extends StatelessWidget {
  final Observation observation;

  const _ObservationSummaryCard({required this.observation});

  @override
  Widget build(BuildContext context) {
    final location = observation.location;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Observation details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Observed: ${formatDateTime(observation.timestamp)}',
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 4),
          Text(
            'User: ${observation.observerName ?? 'Unknown user'}',
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 4),
          Text(
            'Confidence: ${formatConfidence(observation.confidence)}',
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
          if (location != null) ...[
            const SizedBox(height: 4),
            Text(
              'Location: ${location.latitude.toStringAsFixed(3)}, ${location.longitude.toStringAsFixed(3)}',
              style: const TextStyle(color: Color(0xCCFFFFFF)),
            ),
          ],
          if (observation.notes != null && observation.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Notes: ${observation.notes}',
              style: const TextStyle(color: Color(0xCCFFFFFF)),
            ),
          ],
        ],
      ),
    );
  }
}
