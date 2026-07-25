import 'dart:async';

import 'package:flutter/material.dart';

import '../models/inaturalist_taxon.dart';
import '../models/navigation_args.dart';
import '../models/species.dart';
import '../models/toxicity_level.dart';
import '../repositories/species_repository.dart';
import '../services/inaturalist_service.dart';
import '../widgets/forest_background.dart';
import '../widgets/toxicity_badge.dart';
import 'online_species_detail_screen.dart';

class SpeciesLibraryScreen extends StatefulWidget {
  final SpeciesRepository? speciesRepository;
  final INaturalistService? iNaturalistService;

  const SpeciesLibraryScreen({
    super.key,
    this.speciesRepository,
    this.iNaturalistService,
  });

  @override
  State<SpeciesLibraryScreen> createState() => _SpeciesLibraryScreenState();
}

class _SpeciesLibraryScreenState extends State<SpeciesLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  SpeciesRepository get _repository =>
      widget.speciesRepository ?? SpeciesRepository.instance;
  INaturalistService get _iNaturalist =>
      widget.iNaturalistService ?? INaturalistService.instance;

  Timer? _debounce;
  List<Species> _browseSpecies = const [];
  List<_OfflineSearchResult> _offlineResults = const [];
  List<INaturalistTaxonMatch> _onlineResults = const [];
  bool _loadingSpecies = true;
  bool _searching = false;
  String? _searchError;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
    _searchController.addListener(_scheduleSearch);
  }

  Future<void> _loadSpecies() async {
    final loaded = await _repository.loadSpecies();
    if (!mounted) return;
    final byScientificName = <String, Species>{};
    for (final species in loaded) {
      final scientificName = species.scientificName.trim();
      final isFungus = species.taxonomyKingdom?.trim().toLowerCase() == 'fungi';
      if (scientificName.isEmpty || !isFungus) continue;
      byScientificName.putIfAbsent(_normalize(scientificName), () => species);
    }
    final browseSpecies = byScientificName.values.toList()
      ..sort(
        (a, b) => a.scientificName.toLowerCase().compareTo(
          b.scientificName.toLowerCase(),
        ),
      );
    setState(() {
      _browseSpecies = browseSpecies;
      _loadingSpecies = false;
    });
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    final generation = ++_searchGeneration;
    if (query.length < 2) {
      setState(() {
        _offlineResults = const [];
        _onlineResults = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => _runSearch(query, generation),
    );
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final localFuture = _repository.search(query);
      final onlineFuture = _iNaturalist.searchFungalTaxa(query);
      final local = await localFuture;
      final online = await onlineFuture;
      if (!mounted || generation != _searchGeneration) return;

      final onlineByName = <String, INaturalistTaxonMatch>{};
      for (final taxon in online) {
        for (final name in [taxon.acceptedScientificName, taxon.matchedName]) {
          final key = _normalize(name);
          if (key.isNotEmpty) onlineByName.putIfAbsent(key, () => taxon);
        }
      }

      final offline = <_OfflineSearchResult>[];
      final usedTaxonIds = <int>{};
      final usedScientificNames = <String>{};
      for (final species in local) {
        final speciesKey = _normalize(species.scientificName);
        if (!usedScientificNames.add(speciesKey)) continue;
        final photoTaxon =
            onlineByName[speciesKey] ??
            onlineByName[_normalize(species.canonicalName)];
        if (photoTaxon == null || photoTaxon.taxonId == null) continue;
        offline.add(_OfflineSearchResult(species: species, taxon: photoTaxon));
        usedTaxonIds.add(photoTaxon.taxonId!);
      }

      setState(() {
        _offlineResults = offline;
        _onlineResults = online
            .where(
              (taxon) =>
                  taxon.taxonId != null &&
                  !usedTaxonIds.contains(taxon.taxonId),
            )
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _offlineResults = const [];
        _onlineResults = const [];
        _searching = false;
        _searchError =
            'The online library is unavailable. Check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openOfflineDetail(Species species) {
    Navigator.of(context).pushNamed(
      '/species-detail',
      arguments: SpeciesDetailArgs(speciesId: species.id),
    );
  }

  void _openOnlineDetail(INaturalistTaxonMatch taxon) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineSpeciesDetailScreen(taxon: taxon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    final query = _searchController.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fungi Library'),
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
              'Browse the offline field guide or search by name',
              style: TextStyle(fontSize: 14, color: accentTextColor),
            ),
            const SizedBox(height: 6),
            const Text(
              'Online results include reusable images with full attribution.',
              style: TextStyle(fontSize: 11.5, color: accentTextColor),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('fungi-library-search'),
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search scientific or common name',
                hintStyle: const TextStyle(color: accentTextColor),
                prefixIcon: const Icon(Icons.search, color: accentTextColor),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear, color: Colors.white70),
                      ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults(query)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(String query) {
    if (_loadingSpecies) {
      return const Center(child: CircularProgressIndicator());
    }
    if (query.length < 2) {
      return _buildBrowseList(query);
    }
    if (_searching && _offlineResults.isEmpty && _onlineResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null) {
      return Center(
        child: Text(
          _searchError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xCCFFFFFF)),
        ),
      );
    }
    if (_offlineResults.isEmpty && _onlineResults.isEmpty) {
      return const Center(
        child: Text(
          'No fungal taxa with a reusable attributed image were found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xCCFFFFFF)),
        ),
      );
    }
    return ListView(
      children: [
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        if (_offlineResults.isNotEmpty) ...[
          const _SectionHeading(
            title: 'Offline field guide',
            subtitle: 'Curated application records',
          ),
          for (final result in _offlineResults) ...[
            _LibraryTaxonTile(
              taxon: result.taxon,
              species: result.species,
              sourceLabel: 'Offline guide',
              onTap: () => _openOfflineDetail(result.species),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (_onlineResults.isNotEmpty) ...[
          const _SectionHeading(
            title: 'Online library continuation',
            subtitle: 'Public iNaturalist fungal taxa',
          ),
          for (final taxon in _onlineResults) ...[
            _LibraryTaxonTile(
              taxon: taxon,
              sourceLabel: 'iNaturalist',
              onTap: () => _openOnlineDetail(taxon),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _buildBrowseList(String query) {
    final normalizedQuery = _normalize(query);
    final visibleSpecies = normalizedQuery.isEmpty
        ? _browseSpecies
        : _browseSpecies.where((species) {
            final commonName =
                species.colloquialName ?? species.commonName ?? '';
            return _normalize(
                  species.scientificName,
                ).contains(normalizedQuery) ||
                _normalize(commonName).contains(normalizedQuery);
          }).toList();

    if (visibleSpecies.isEmpty) {
      return const Center(
        child: Text(
          'No fungi found.',
          style: TextStyle(color: Color(0xCCFFFFFF)),
        ),
      );
    }

    return Scrollbar(
      child: ListView.separated(
        key: const Key('fungi-scroll-list'),
        itemCount: visibleSpecies.length + 1,
        separatorBuilder: (_, index) =>
            index == 0 ? const SizedBox(height: 2) : const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            final count = visibleSpecies.length;
            return _SectionHeading(
              title: query.isEmpty ? 'Browse fungi' : 'Local matches',
              subtitle: query.isEmpty
                  ? '$count offline species · scroll to explore'
                  : '$count match${count == 1 ? '' : 'es'} · '
                        'type one more character to search online',
            );
          }
          final species = visibleSpecies[index - 1];
          return _BrowseSpeciesTile(
            species: species,
            onTap: () => _openOfflineDetail(species),
          );
        },
      ),
    );
  }
}

class _OfflineSearchResult {
  final Species species;
  final INaturalistTaxonMatch taxon;
  const _OfflineSearchResult({required this.species, required this.taxon});
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LibraryTaxonTile extends StatelessWidget {
  final INaturalistTaxonMatch taxon;
  final Species? species;
  final String sourceLabel;
  final VoidCallback onTap;

  const _LibraryTaxonTile({
    required this.taxon,
    this.species,
    required this.sourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scientificName =
        species?.scientificName ?? taxon.acceptedScientificName ?? 'Unknown';
    final commonName =
        species?.colloquialName ??
        species?.commonName ??
        taxon.preferredCommonName ??
        'No common name listed';
    final photoUrl = taxon.photoUrl!;
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photoUrl,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          width: 88,
                          height: 88,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 88,
                    height: 88,
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scientificName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      commonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SourceBadge(label: sourceLabel),
                        ToxicityBadge(
                          level:
                              species?.toxicityLevel ?? ToxicityLevel.unknown,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${taxon.photoAttribution} · '
                      '${taxon.photoLicense?.toUpperCase()}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 9.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseSpeciesTile extends StatelessWidget {
  final Species species;
  final VoidCallback onTap;

  const _BrowseSpeciesTile({required this.species, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final commonName = species.colloquialName?.trim().isNotEmpty == true
        ? species.colloquialName!.trim()
        : species.commonName?.trim();
    final description = species.shortDescription?.trim() ?? '';

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF8FBFA1).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: const Color(0xFF8FBFA1).withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.nature_outlined,
                  color: Color(0xFFE7F3E7),
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      species.scientificName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (commonName != null && commonName.isNotEmpty)
                      Text(
                        commonName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xBFFFFFFF),
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    ToxicityBadge(level: species.toxicityLevel, compact: true),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  const _SourceBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF8FBFA1).withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF8FBFA1)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFE7F3E7),
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _normalize(String? value) =>
    value?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ?? '';
