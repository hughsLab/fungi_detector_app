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
                            return _SpeciesLibraryTile(
                              species: species,
                              onTap: () => _openDetail(species),
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

class _SpeciesLibraryTile extends StatelessWidget {
  final Species species;
  final VoidCallback onTap;

  const _SpeciesLibraryTile({
    required this.species,
    required this.onTap,
  });

  String _valueOrPlaceholder(
    String? value, {
    String placeholder = 'Not listed',
  }) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? placeholder : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    final scientificName = _valueOrPlaceholder(
      species.scientificName,
      placeholder: 'Unknown',
    );
    final colloquialName = _valueOrPlaceholder(
      (species.colloquialName?.trim().isNotEmpty ?? false)
          ? species.colloquialName
          : species.commonName,
    );
    final description = species.shortDescription?.trim() ?? '';
    final thumbnailPath = species.thumbnailAssetPath?.trim() ?? '';

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (thumbnailPath.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    thumbnailPath,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: Colors.white.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.local_florist,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scientific Name: $scientificName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        'Colloquial Name: $colloquialName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: accentTextColor,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: accentTextColor,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Colors.white70,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
