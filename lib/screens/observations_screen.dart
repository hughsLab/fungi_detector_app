import 'dart:io';

import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

class ObservationsScreen extends StatefulWidget {
  const ObservationsScreen({super.key});

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;

  List<Observation> _observations = [];
  Map<String, String> _speciesNames = {};
  bool _loading = true;
  ObservationSort _sort = ObservationSort.date;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final observations = await _observationRepository.loadObservations();
    final species = await _speciesRepository.loadSpecies();
    final nameMap = {
      for (final item in species) item.id: item.displayName,
    };
    if (!mounted) return;

    setState(() {
      _observations = observations;
      _speciesNames = nameMap;
      _loading = false;
    });
  }

  List<Observation> get _sortedObservations {
    final list = [..._observations];
    if (_sort == ObservationSort.speciesName) {
      list.sort((a, b) {
        final nameA = _displayNameFor(a);
        final nameB = _displayNameFor(b);
        return nameA.compareTo(nameB);
      });
    } else {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    return list;
  }

  String _displayNameFor(Observation observation) {
    final label = observation.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return _speciesNames[observation.speciesId] ?? 'Unknown';
  }

  void _openDetail(Observation observation) {
    Navigator.of(context).pushNamed(
      '/species-detail',
      arguments: SpeciesDetailArgs(
        speciesId: observation.speciesId,
        observation: observation,
      ),
    );
  }

  void _openSaveObservation() {
    Navigator.of(context)
        .pushNamed('/save-observation')
        .then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Observations'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<ObservationSort>(
              value: _sort,
              dropdownColor: const Color(0xFF1F4E3D),
              iconEnabledColor: Colors.white,
              items: const [
                DropdownMenuItem(
                  value: ObservationSort.date,
                  child: Text(
                    'Sort by date',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                DropdownMenuItem(
                  value: ObservationSort.speciesName,
                  child: Text(
                    'Sort by species',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _sort = value;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSaveObservation,
        backgroundColor: const Color(0xFF8FBFA1),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _observations.isEmpty
                ? const Center(
                    child: Text(
                      'No observations saved yet.',
                      style: TextStyle(color: accentTextColor),
                    ),
                  )
                : ListView.separated(
                    itemCount: _sortedObservations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final observation = _sortedObservations[index];
                      final name = _displayNameFor(observation);
                      final photoPath = observation.photoPath;

                      return Material(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          onTap: () => _openDetail(observation),
                          leading: _ObservationThumbnail(photoPath: photoPath),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${formatDateTime(observation.timestamp)} · ${formatConfidence(observation.confidence)}',
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
    );
  }
}

class _ObservationThumbnail extends StatelessWidget {
  final String? photoPath;

  const _ObservationThumbnail({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    final hasImage = path != null && File(path).existsSync();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(path!),
                fit: BoxFit.cover,
              ),
            )
          : const Icon(
              Icons.local_florist,
              color: Colors.white70,
            ),
    );
  }
}

enum ObservationSort { date, speciesName }
