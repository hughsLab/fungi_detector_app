import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../models/species.dart';
import '../repositories/species_repository.dart';
import '../widgets/forest_background.dart';

class SpeciesLibraryScreen extends StatefulWidget {
  const SpeciesLibraryScreen({super.key});

  @override
  State<SpeciesLibraryScreen> createState() => _SpeciesLibraryScreenState();
}

class _SpeciesLibraryScreenState extends State<SpeciesLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SpeciesRepository _repository = SpeciesRepository.instance;

  List<Species> _species = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
    _searchController.addListener(_applySearch);
  }

  Future<void> _loadSpecies() async {
    final data = await _repository.loadSpecies();
    if (!mounted) return;
    setState(() {
      _species = data;
      _loading = false;
    });
  }

  Future<void> _applySearch() async {
    final results = await _repository.search(_searchController.text);
    if (!mounted) return;
    setState(() {
      _species = results;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(Species species) {
    Navigator.of(context).pushNamed(
      '/species-detail',
      arguments: SpeciesDetailArgs(speciesId: species.id),
    );
  }

  String _valueOrPlaceholder(String? value, {String placeholder = 'Not listed'}) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? placeholder : trimmed;
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
      ),
    );
  }

  Widget _sectionValue(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xCCFFFFFF),
        height: 1.3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Species Library'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Australia-wide offline field guide',
              style: TextStyle(
                fontSize: 14,
                color: accentTextColor,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name',
                hintStyle: const TextStyle(color: accentTextColor),
                prefixIcon: const Icon(Icons.search, color: accentTextColor),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _species.isEmpty
                      ? const Center(
                          child: Text(
                            'No species found.',
                            style: TextStyle(color: accentTextColor),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _species.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final species = _species[index];
                            final shortDescription =
                                _valueOrPlaceholder(species.shortDescription);
                            final authority =
                                _valueOrPlaceholder(species.authority);
                            final habitat = _valueOrPlaceholder(species.habitat);
                            final season = _valueOrPlaceholder(species.season);
                            final distributionNote =
                                _valueOrPlaceholder(species.distributionNote);
                            final edibilityWarning = _valueOrPlaceholder(
                              species.edibilityWarning,
                              placeholder: 'No warning provided.',
                            );
                            final taxonomyItems = <String, String>{
                              'Kingdom': species.taxonomyKingdom ?? '',
                              'Phylum': species.taxonomyPhylum ?? '',
                              'Class': species.taxonomyClass ?? '',
                              'Order': species.taxonomyOrder ?? '',
                              'Family': species.taxonomyFamily ?? '',
                              'Genus': species.taxonomyGenus ?? '',
                              'Species': species.taxonomySpecies ?? '',
                            };
                            final taxonomyChips = taxonomyItems.entries
                                .where((entry) => entry.value.trim().isNotEmpty)
                                .map(
                                  (entry) => Chip(
                                    label: Text(
                                      '${entry.key}: ${entry.value}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.12),
                                  ),
                                )
                                .toList();
                            final distributionParts = <String>[
                              if (species.distributionCountry != null &&
                                  species.distributionCountry!
                                      .trim()
                                      .isNotEmpty)
                                species.distributionCountry!.trim(),
                              if (species.distributionStates.isNotEmpty)
                                'States: ${species.distributionStates.join(', ')}',
                              if (species.distributionNote.trim().isNotEmpty)
                                species.distributionNote.trim(),
                            ];
                            final distribution = distributionParts.isEmpty
                                ? distributionNote
                                : distributionParts.join(' | ');
                            final similarNames =
                                species.similarSpeciesNames.where((name) {
                              return name.trim().isNotEmpty;
                            }).toList();
                            final similarIds =
                                species.similarSpeciesIds.where((id) {
                              return id.trim().isNotEmpty;
                            }).toList();
                            final keyFeatures = species.keyFeatures
                                .where((feature) => feature.trim().isNotEmpty)
                                .toList();
                            final sourceTaxonomy = _valueOrPlaceholder(
                              species.sourceTaxonomy,
                              placeholder: 'Not listed',
                            );
                            final sourceDescription = _valueOrPlaceholder(
                              species.sourceDescription,
                              placeholder: 'Not listed',
                            );
                            final imageAsset = _valueOrPlaceholder(
                              species.thumbnailAssetPath,
                              placeholder: 'Not listed',
                            );
                            return Material(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openDetail(species),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              species.scientificName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.white70,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _valueOrPlaceholder(species.commonName),
                                        style: const TextStyle(
                                          color: accentTextColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _sectionLabel('Authority'),
                                      const SizedBox(height: 4),
                                      _sectionValue(authority),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Description'),
                                      const SizedBox(height: 4),
                                      _sectionValue(shortDescription),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Key identifying features'),
                                      const SizedBox(height: 4),
                                      keyFeatures.isEmpty
                                          ? _sectionValue('None listed')
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: keyFeatures
                                                  .map(
                                                    (feature) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        bottom: 4,
                                                      ),
                                                      child: Text(
                                                        '- $feature',
                                                        style: const TextStyle(
                                                          color: accentTextColor,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Habitat'),
                                      const SizedBox(height: 4),
                                      _sectionValue(habitat),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Season'),
                                      const SizedBox(height: 4),
                                      _sectionValue(season),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Distribution'),
                                      const SizedBox(height: 4),
                                      _sectionValue(distribution),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Similar species'),
                                      const SizedBox(height: 4),
                                      similarNames.isEmpty && similarIds.isEmpty
                                          ? _sectionValue('None listed')
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                ...similarNames.map(
                                                  (name) => Chip(
                                                    label: Text(
                                                      name,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.12),
                                                  ),
                                                ),
                                                ...similarIds.map(
                                                  (id) => Chip(
                                                    label: Text(
                                                      id,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.12),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Taxonomy'),
                                      const SizedBox(height: 4),
                                      taxonomyChips.isEmpty
                                          ? _sectionValue('Not listed')
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: taxonomyChips,
                                            ),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Edibility warning'),
                                      const SizedBox(height: 4),
                                      _sectionValue(edibilityWarning),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Image asset'),
                                      const SizedBox(height: 4),
                                      _sectionValue(imageAsset),
                                      const SizedBox(height: 10),
                                      _sectionLabel('Sources'),
                                      const SizedBox(height: 4),
                                      _sectionValue(
                                        'Taxonomy: $sourceTaxonomy',
                                      ),
                                      const SizedBox(height: 2),
                                      _sectionValue(
                                        'Description: $sourceDescription',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
