import 'dart:io';

import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
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
  final TextEditingController _searchController = TextEditingController();

  List<Observation> _observations = [];
  Map<String, String> _speciesNames = {};
  Set<String> _lichenSpeciesIds = <String>{};
  Set<String> _lichenNames = <String>{};
  bool _loading = true;
  ObservationSort _sort = ObservationSort.date;
  double _minConfidence = 0.0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final observations = await _observationRepository.loadObservations();
    final species = await _speciesRepository.loadSpecies();
    final nameMap = {for (final item in species) item.id: item.displayName};
    final lichenSpeciesIds = <String>{};
    final lichenNames = <String>{};
    for (final item in species) {
      if (_isLichenSpecies(item)) {
        lichenSpeciesIds.add(item.id);
        final scientific = item.scientificName.trim().toLowerCase();
        if (scientific.isNotEmpty) {
          lichenNames.add(scientific);
        }
        final common = (item.commonName ?? '').trim().toLowerCase();
        if (common.isNotEmpty) {
          lichenNames.add(common);
        }
      }
    }
    if (!mounted) return;

    setState(() {
      _observations = observations;
      _speciesNames = nameMap;
      _lichenSpeciesIds = lichenSpeciesIds;
      _lichenNames = lichenNames;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
    });
  }

  bool _isLichenSpecies(Species species) {
    final String taxonomyClass = (species.taxonomyClass ?? '')
        .trim()
        .toLowerCase();
    if (taxonomyClass == 'lecanoromycetes') {
      return true;
    }
    final String combined = [
      species.commonName,
      species.shortDescription,
      species.taxonomyOrder,
      species.taxonomyFamily,
    ].whereType<String>().join(' ').toLowerCase();
    return combined.contains('lichen');
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

  List<Observation> get _filteredObservations {
    final query = _searchQuery.trim().toLowerCase();
    return _sortedObservations.where((observation) {
      final confidence = observation.confidence ?? 0.0;
      if (confidence < _minConfidence) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final name = _displayNameFor(observation).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  String _displayNameFor(Observation observation) {
    final label = observation.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return _speciesNames[observation.speciesId] ?? 'Unknown';
  }

  Color _confidenceColor(double? confidence) {
    final value = confidence ?? 0.0;
    if (value >= 0.8) {
      return const Color(0xFF7CD39A);
    }
    if (value >= 0.6) {
      return const Color(0xFFFFC857);
    }
    return Colors.white70;
  }

  void _openDetail(Observation observation) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _ObservationDetailSheet(
          observation: observation,
          displayName: _displayNameFor(observation),
          confidenceColor: _confidenceColor(observation.confidence),
          onViewFull: () {
            Navigator.of(context).pop();
            _openFullDetail(observation);
          },
        );
      },
    );
  }

  void _openFullDetail(Observation observation) {
    final String label = _displayNameFor(observation);
    final String normalizedLabel = label.trim().toLowerCase();
    final bool isLichen =
        observation.isLichen ??
        _lichenSpeciesIds.contains(observation.speciesId) ||
            _lichenNames.contains(normalizedLabel);
    Navigator.of(context).pushNamed(
      '/detection-result',
      arguments: DetectionResultArgs(
        lockedLabel: label,
        top2Label: observation.top2Label,
        top1AvgConf: observation.confidence ?? 0.0,
        top2AvgConf: observation.top2Confidence,
        top1VoteRatio: observation.top1VoteRatio ?? 0.0,
        windowFrameCount: observation.windowFrameCount ?? 0,
        windowDurationMs: observation.windowDurationMs ?? 0,
        stabilityWinCount: observation.stabilityWinCount ?? 0,
        stabilityWindowSize: observation.stabilityWindowSize ?? 0,
        timestamp: observation.timestamp,
        speciesId: observation.speciesId.trim().isEmpty
            ? null
            : observation.speciesId,
        classIndex: observation.classIndex,
        photoPath: observation.photoPath,
        isLichen: isLichen,
        isSavedView: true,
      ),
    );
  }

  void _openSaveObservation() {
    Navigator.of(
      context,
    ).pushNamed('/save-observation').then((_) => _loadData());
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
            : Column(
                children: [
                  _ObservationFilterRow(
                    searchController: _searchController,
                    minConfidence: _minConfidence,
                    onConfidenceChanged: (value) {
                      setState(() {
                        _minConfidence = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _observations.isEmpty
                        ? const Center(
                            child: Text(
                              'No observations saved yet.',
                              style: TextStyle(color: accentTextColor),
                            ),
                          )
                        : _filteredObservations.isEmpty
                        ? const Center(
                            child: Text(
                              'No observations match your filters.',
                              style: TextStyle(color: accentTextColor),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredObservations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final observation = _filteredObservations[index];
                              final name = _displayNameFor(observation);
                              return _ObservationCard(
                                observation: observation,
                                displayName: name,
                                confidenceColor: _confidenceColor(
                                  observation.confidence,
                                ),
                                onTap: () => _openDetail(observation),
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

class _ObservationFilterRow extends StatelessWidget {
  final TextEditingController searchController;
  final double minConfidence;
  final ValueChanged<double> onConfidenceChanged;

  const _ObservationFilterRow({
    required this.searchController,
    required this.minConfidence,
    required this.onConfidenceChanged,
  });

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search by species label',
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
        const SizedBox(height: 10),
        Text(
          'Min confidence: ${(minConfidence * 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: accentTextColor, fontSize: 12.5),
        ),
        Slider(
          value: minConfidence,
          min: 0,
          max: 1,
          divisions: 20,
          activeColor: const Color(0xFF8FBFA1),
          inactiveColor: Colors.white24,
          onChanged: onConfidenceChanged,
        ),
      ],
    );
  }
}

class _ObservationCard extends StatelessWidget {
  final Observation observation;
  final String displayName;
  final Color confidenceColor;
  final VoidCallback onTap;

  const _ObservationCard({
    required this.observation,
    required this.displayName,
    required this.confidenceColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photoPath = observation.photoPath;
    final hasImage = photoPath != null && File(photoPath).existsSync();
    final hasLocation = observation.location != null;

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
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(photoPath), fit: BoxFit.cover),
                      )
                    : const Icon(Icons.local_florist, color: Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(observation.timestamp),
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: confidenceColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: confidenceColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      formatConfidence(observation.confidence),
                      style: TextStyle(
                        color: confidenceColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFF8FBFA1),
                      size: 18,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObservationDetailSheet extends StatelessWidget {
  final Observation observation;
  final String displayName;
  final Color confidenceColor;
  final VoidCallback onViewFull;

  const _ObservationDetailSheet({
    required this.observation,
    required this.displayName,
    required this.confidenceColor,
    required this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    final location = observation.location;
    final top2Label = observation.top2Label?.trim();
    final top2Confidence = observation.top2Confidence;
    final bool hasTop2 = top2Label != null && top2Label.isNotEmpty;
    final String top2Value = top2Confidence == null
        ? 'Not recorded'
        : '${(top2Confidence * 100).toStringAsFixed(1)}%';
    final double? voteRatio = observation.top1VoteRatio;
    final String votePercent = voteRatio == null
        ? 'Not recorded'
        : '${(voteRatio * 100).toStringAsFixed(1)}%';
    final int windowFrames = observation.windowFrameCount ?? 0;
    final int windowMs = observation.windowDurationMs ?? 0;
    final String windowDuration = windowMs == 0
        ? 'Not recorded'
        : '${(windowMs / 1000).toStringAsFixed(1)}s';
    final int stabilityWins = observation.stabilityWinCount ?? 0;
    final int stabilityWindow = observation.stabilityWindowSize ?? 0;

    final photoPath = observation.photoPath;
    final hasImage = photoPath != null && File(photoPath).existsSync();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatDateTime(observation.timestamp),
              style: const TextStyle(
                color: accentTextColor,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(photoPath!), fit: BoxFit.cover),
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white70,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            _ObservationDetailRow(
              label: 'Primary Confidence',
              value: formatConfidence(observation.confidence),
              valueColor: confidenceColor,
            ),
            if (hasTop2)
              _ObservationDetailRow(
                label: 'Secondary Candidate',
                value: '$top2Label - $top2Value',
              ),
            const SizedBox(height: 8),
            _ObservationDetailRow(
              label: 'Vote ratio',
              value: votePercent,
            ),
            _ObservationDetailRow(
              label: 'Stability window',
              value: stabilityWindow == 0
                  ? 'Not recorded'
                  : '$stabilityWins/$stabilityWindow frames',
            ),
            _ObservationDetailRow(
              label: 'Window duration',
              value: windowDuration,
            ),
            if (location != null)
              _ObservationDetailRow(
                label: 'Location',
                value:
                    '${location.latitude.toStringAsFixed(3)}, ${location.longitude.toStringAsFixed(3)}',
              ),
            if (observation.notes != null &&
                observation.notes!.trim().isNotEmpty)
              _ObservationDetailRow(
                label: 'Notes',
                value: observation.notes!.trim(),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onViewFull,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8FBFA1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('View Full Detail'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservationDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ObservationDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFE7F3E7),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? const Color(0xCCFFFFFF),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum ObservationSort { date, speciesName }
