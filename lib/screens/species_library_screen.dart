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
              'Tasmania-only offline field guide',
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
                            final descriptor = species.keyFeatures.isNotEmpty
                                ? species.keyFeatures.first
                                : 'Tap to view details';
                            return Material(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                onTap: () => _openDetail(species),
                                title: Text(
                                  species.scientificName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  species.commonName == null ||
                                          species.commonName!.isEmpty
                                      ? descriptor
                                      : '${species.commonName} · $descriptor',
                                  style: const TextStyle(
                                    color: accentTextColor,
                                    fontSize: 12.5,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white70,
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
