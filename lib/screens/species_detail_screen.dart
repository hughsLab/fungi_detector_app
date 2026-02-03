import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/species_repository.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

class SpeciesDetailScreen extends StatefulWidget {
  const SpeciesDetailScreen({super.key});

  @override
  State<SpeciesDetailScreen> createState() => _SpeciesDetailScreenState();
}

class _SpeciesDetailScreenState extends State<SpeciesDetailScreen> {
  final SpeciesRepository _repository = SpeciesRepository.instance;
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
    return _SpeciesDetailData(species: species, similar: similar);
  }

  void _openSaveObservation(String speciesId) {
    Navigator.of(context).pushNamed(
      '/save-observation',
      arguments: SaveObservationArgs(preselectedSpeciesId: speciesId),
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

                  final species = snapshot.data!.species!;
                  final similarSpecies = snapshot.data!.similar;
                  final observation = _args?.observation;
                  final similarNames = species.similarSpeciesNames;
                  final hasSimilar =
                      similarSpecies.isNotEmpty || similarNames.isNotEmpty;
                  final List<Widget> similarChips = [
                    ...similarSpecies.map(
                      (item) => Chip(
                        label: Text(
                          item.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    if (similarSpecies.isEmpty)
                      ...similarNames.map(
                        (name) => Chip(
                          label: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                            ),
                          ),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                  ];
                  final description = species.shortDescription?.trim() ?? '';
                  final habitat = species.habitat?.trim() ?? '';
                  final season = species.season?.trim() ?? '';
                  final distributionNote = species.distributionNote.trim();
                  final edibilityWarning = species.edibilityWarning?.trim() ?? '';

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          species.scientificName,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (species.commonName != null &&
                            species.commonName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              species.commonName!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: accentTextColor,
                              ),
                            ),
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
                        const SizedBox(height: 16),
                        if (observation != null)
                          _ObservationSummaryCard(observation: observation),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: const TextStyle(
                              color: accentTextColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text(
                          'Key identifying features',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _BulletList(items: species.keyFeatures),
                        if (habitat.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Habitat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            habitat,
                            style: const TextStyle(
                              color: accentTextColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (season.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Season',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            season,
                            style: const TextStyle(
                              color: accentTextColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text(
                          'Similar species',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 24),
                        Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                            ),
                            collapsedBackgroundColor:
                                Colors.white.withValues(alpha: 0.06),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            collapsedShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            title: const Text(
                              'Safety disclaimer',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (edibilityWarning.isNotEmpty) ...[
                                      Text(
                                        edibilityWarning,
                                        style:
                                            const TextStyle(color: Colors.white),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    const Text(
                                      'Do not consume based on app results.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'AI identification is probabilistic.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Always consult experts before handling or eating.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Edibility or toxicity cannot be confirmed by this app.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _openSaveObservation(species.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8FBFA1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'Save Observation',
                              style: TextStyle(
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

  const _SpeciesDetailData({
    required this.species,
    required this.similar,
  });
}

class _BulletList extends StatelessWidget {
  final List<String> items;

  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No identifying features listed.',
        style: TextStyle(color: Color(0xCCFFFFFF)),
      );
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
                  const Text(
                    '• ',
                    style: TextStyle(color: Colors.white),
                  ),
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
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Observed: ${formatDateTime(observation.timestamp)}',
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
              'Location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
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
