import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';
import '../widgets/key_features_section.dart';
import '../widgets/local_image_preview.dart';

class ObservationsScreen extends StatefulWidget {
  final ValueChanged<MapFocusRequest>? onMapFocusRequest;

  const ObservationsScreen({super.key, this.onMapFocusRequest});

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Observation> _observations = [];
  Map<String, String> _speciesNames = {};
  Map<String, Species> _speciesById = {};
  Map<String, Species> _speciesByModelClass = {};
  Map<String, String> _speciesIdByScientificName = {};
  Map<String, String> _tasColloquialById = {};
  Map<String, String> _tasColloquialByScientificName = {};
  Set<String> _lichenSpeciesIds = <String>{};
  Set<String> _lichenNames = <String>{};
  List<Observation> _visibleObservations = const [];
  bool _loading = true;
  bool _locationTaggingEnabled = false;
  ObservationSort _sort = ObservationSort.date;
  double _minConfidence = 0.0;
  String _searchQuery = '';
  late final VoidCallback _settingsListener;
  StreamSubscription<List<Observation>>? _observationSubscription;

  @override
  void initState() {
    super.initState();
    _settingsListener = _handleSettingsChanged;
    _settingsService.settingsNotifier.addListener(_settingsListener);
    _observationSubscription = _observationRepository
        .watchObservationChanges()
        .listen(_handleObservationChanges);
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _observationSubscription?.cancel();
    _searchController.dispose();
    _settingsService.settingsNotifier.removeListener(_settingsListener);
    super.dispose();
  }

  void _handleObservationChanges(List<Observation> observations) {
    if (!mounted) return;
    setState(() {
      _observations = observations;
      _visibleObservations = _buildVisibleObservations(
        observations: observations,
      );
      _loading = false;
    });
  }

  Future<void> _loadData() async {
    final observationsFuture = _observationRepository.loadObservations();
    final speciesFuture = _speciesRepository.loadSpecies();
    final settingsFuture = _settingsService.loadSettings();
    final tasColloquialFuture = _loadTasColloquialMaps();
    final observations = await observationsFuture;
    final species = await speciesFuture;
    final settings = await settingsFuture;
    final tasColloquial = await tasColloquialFuture;
    final nameMap = {for (final item in species) item.id: item.displayName};
    final speciesById = {for (final item in species) item.id: item};
    final speciesByModelClass = {
      for (final item in species)
        if (item.modelId != null && item.sourceClassId != null)
          _modelClassKey(item.modelId!, item.sourceClassId!): item,
    };
    final speciesIdByScientificName = <String, String>{};
    for (final item in species) {
      final normalized = _normalizeForLookup(item.scientificName);
      if (normalized.isNotEmpty &&
          !speciesIdByScientificName.containsKey(normalized)) {
        speciesIdByScientificName[normalized] = item.id;
      }
    }
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
      _speciesById = speciesById;
      _speciesByModelClass = speciesByModelClass;
      _speciesIdByScientificName = speciesIdByScientificName;
      _tasColloquialById = tasColloquial.byId;
      _tasColloquialByScientificName = tasColloquial.byScientificName;
      _lichenSpeciesIds = lichenSpeciesIds;
      _lichenNames = lichenNames;
      _visibleObservations = _buildVisibleObservations(
        observations: observations,
        speciesNames: nameMap,
      );
      _locationTaggingEnabled = settings.locationTaggingEnabled;
      _loading = false;
    });
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    final settings = _settingsService.settingsNotifier.value;
    if (settings.locationTaggingEnabled == _locationTaggingEnabled) {
      return;
    }
    setState(() {
      _locationTaggingEnabled = settings.locationTaggingEnabled;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      _visibleObservations = _buildVisibleObservations();
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

  List<Observation> _buildVisibleObservations({
    List<Observation>? observations,
    Map<String, String>? speciesNames,
  }) {
    final Map<String, String> names = speciesNames ?? _speciesNames;
    final List<Observation> list = [...(observations ?? _observations)];
    if (_sort == ObservationSort.speciesName) {
      list.sort((a, b) {
        final nameA = _displayNameForWithNames(a, names);
        final nameB = _displayNameForWithNames(b, names);
        return nameA.compareTo(nameB);
      });
    } else {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    final query = _searchQuery.trim().toLowerCase();
    return list.where((observation) {
      final confidence = observation.confidence ?? 0.0;
      if (confidence < _minConfidence) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final name = _displayNameForWithNames(observation, names).toLowerCase();
      return name.contains(query);
    }).toList(growable: false);
  }

  String _displayNameForWithNames(
    Observation observation,
    Map<String, String> speciesNames,
  ) {
    final label = observation.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return speciesNames[observation.speciesId] ?? 'Unknown';
  }

  String _normalizeForLookup(String? value) => value?.trim().toLowerCase() ?? '';

  String _modelClassKey(String modelId, int sourceClassId) {
    return '$modelId:$sourceClassId';
  }

  Future<_TasColloquialMaps> _loadTasColloquialMaps() async {
    try {
      final String raw = await rootBundle.loadString('assets/data/species_tas.json');
      final dynamic decoded = jsonDecode(raw);
      final List<dynamic> cards = (decoded is Map<String, dynamic> &&
              decoded['cards'] is List<dynamic>)
          ? decoded['cards'] as List<dynamic>
          : const <dynamic>[];

      final Map<String, String> byId = <String, String>{};
      final Map<String, String> byScientificName = <String, String>{};
      for (final dynamic item in cards) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String? colloquial = _cleanColloquialName(
          item['colloquialName']?.toString(),
        );
        if (colloquial == null) {
          continue;
        }
        final String id = item['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          byId[id] = colloquial;
        }
        final String scientific = item['scientificName']?.toString() ?? '';
        final String normalizedScientific = _normalizeForLookup(scientific);
        if (normalizedScientific.isNotEmpty &&
            !byScientificName.containsKey(normalizedScientific)) {
          byScientificName[normalizedScientific] = colloquial;
        }
      }
      return _TasColloquialMaps(
        byId: byId,
        byScientificName: byScientificName,
      );
    } catch (_) {
      return const _TasColloquialMaps(
        byId: <String, String>{},
        byScientificName: <String, String>{},
      );
    }
  }

  String? _cleanColloquialName(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }
    final lower = cleaned.toLowerCase();
    if (lower == 'null' || lower == 'undefined') {
      return null;
    }
    return cleaned;
  }

  Species? _speciesForObservation(Observation observation) {
    final String? modelId = observation.modelId?.trim();
    final int? sourceClassId = observation.sourceClassId ?? observation.classIndex;
    if (modelId != null && modelId.isNotEmpty && sourceClassId != null) {
      final Species? byModelClass =
          _speciesByModelClass[_modelClassKey(modelId, sourceClassId)];
      if (byModelClass != null) {
        return byModelClass;
      }
    }

    final String speciesId = observation.speciesId.trim();
    if (speciesId.isNotEmpty) {
      final Species? byId = _speciesById[speciesId];
      if (byId != null) {
        return byId;
      }
    }

    final String normalizedLabel = _normalizeForLookup(observation.label);
    if (normalizedLabel.isNotEmpty) {
      final String? lookupId = _speciesIdByScientificName[normalizedLabel];
      if (lookupId != null) {
        return _speciesById[lookupId];
      }
    }

    return null;
  }

  String _scientificNameFor(Observation observation) {
    final Species? species = _speciesForObservation(observation);
    final String speciesScientific = species?.scientificName.trim() ?? '';
    if (speciesScientific.isNotEmpty) {
      return speciesScientific;
    }
    final String label = observation.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return _speciesNames[observation.speciesId] ?? 'Unknown';
  }

  String? _getObservationColloquialName(Observation observation) {
    final String? fromObservation = _cleanColloquialName(
      observation.colloquialName,
    );
    if (fromObservation != null) {
      return fromObservation;
    }

    final Species? species = _speciesForObservation(observation);
    final String? fromSpecies = _cleanColloquialName(species?.colloquialName);
    if (fromSpecies != null) {
      return fromSpecies;
    }

    final String speciesId = observation.speciesId.trim();
    if (speciesId.isNotEmpty) {
      final String? fromTasId = _cleanColloquialName(_tasColloquialById[speciesId]);
      if (fromTasId != null) {
        return fromTasId;
      }
    }

    final String speciesScientific = species?.scientificName ?? '';
    final String scientificForLookup = speciesScientific.trim().isNotEmpty
        ? speciesScientific
        : observation.label;
    final String? fromTasScientific = _cleanColloquialName(
      _tasColloquialByScientificName[_normalizeForLookup(scientificForLookup)],
    );
    if (fromTasScientific != null) {
      return fromTasScientific;
    }

    return null;
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
        final Species? species = _speciesForObservation(observation);
        final String scientificName = _scientificNameFor(observation);
        return _ObservationDetailSheet(
          observation: observation,
          scientificName: scientificName,
          colloquialName: _getObservationColloquialName(observation),
          keyFeatures: species?.keyFeatures ?? const <String>[],
          confidenceColor: _confidenceColor(observation.confidence),
          onOpenMap: observation.location == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  _handleLocationTap(observation);
                },
          onViewFull: () {
            Navigator.of(context).pop();
            _openFullDetail(observation);
          },
        );
      },
    );
  }

  void _openFullDetail(Observation observation) {
    final String label = _scientificNameFor(observation);
    final String normalizedLabel = label.trim().toLowerCase();
    final bool isLichen =
        observation.isLichen ??
        _lichenSpeciesIds.contains(observation.speciesId) ||
            _lichenNames.contains(normalizedLabel);
    Navigator.of(context).pushNamed(
      '/detection-result',
      arguments: DetectionResultArgs(
        observationId: observation.id,
        lockedLabel: label,
        top2Label: observation.top2Label,
        top2ClassIndex: observation.top2SourceClassId,
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
        modelId: observation.modelId,
        modelDisplayName: observation.modelDisplayName,
        sourceClassId: observation.sourceClassId,
        rawConfidence: observation.rawConfidence,
        calibratedConfidence: observation.calibratedConfidence,
        finalScore: observation.finalScore,
        top2ModelId: observation.top2ModelId,
        top2ModelDisplayName: observation.top2ModelDisplayName,
        top2SourceClassId: observation.top2SourceClassId,
        candidates: observation.candidates,
        photoPath: observation.photoPath,
        latitude: observation.latitude,
        longitude: observation.longitude,
        locationLabel: observation.locationLabel,
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

  void _handleLocationTap(Observation observation) {
    final double? latitude = observation.latitude;
    final double? longitude = observation.longitude;
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No location recorded')));
      return;
    }
    final request = MapFocusRequest(
      observationId: observation.id,
      lat: latitude,
      lon: longitude,
    );
    if (widget.onMapFocusRequest != null) {
      widget.onMapFocusRequest!(request);
      return;
    }
    Navigator.of(context).pushNamed('/map', arguments: request);
  }

  String _locationTextFor(Observation observation) {
    final double? latitude = observation.latitude;
    final double? longitude = observation.longitude;
    final String? raw = observation.locationLabel?.trim();
    final String? coords = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'
        : null;

    if (raw != null && raw.isNotEmpty && coords != null) {
      return '$raw ($coords)';
    }
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    if (coords != null) {
      return coords;
    }
    return _locationTaggingEnabled
        ? 'No location recorded'
        : 'Location tagging is off';
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
                  _visibleObservations = _buildVisibleObservations();
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
                  _FieldNotesShortcut(
                    onTap: () {
                      Navigator.of(context).pushNamed('/field-notes');
                    },
                  ),
                  const SizedBox(height: 12),
                  _ObservationFilterRow(
                    searchController: _searchController,
                    minConfidence: _minConfidence,
                    onConfidenceChanged: (value) {
                      setState(() {
                        _minConfidence = value;
                        _visibleObservations = _buildVisibleObservations();
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
                        : _visibleObservations.isEmpty
                        ? const Center(
                            child: Text(
                              'No observations match your filters.',
                              style: TextStyle(color: accentTextColor),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _visibleObservations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final observation = _visibleObservations[index];
                              final scientificName = _scientificNameFor(
                                observation,
                              );
                              return _ObservationCard(
                                observation: observation,
                                scientificName: scientificName,
                                colloquialName: _getObservationColloquialName(
                                  observation,
                                ),
                                locationText: _locationTextFor(observation),
                                confidenceColor: _confidenceColor(
                                  observation.confidence,
                                ),
                                onTap: () => _openDetail(observation),
                                onMapTap: () => _handleLocationTap(observation),
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

class _FieldNotesShortcut extends StatelessWidget {
  final VoidCallback onTap;

  const _FieldNotesShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.note_alt, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Field Notes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Local notes, photos, and links',
                      style: TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
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

class _ObservationCard extends StatelessWidget {
  final Observation observation;
  final String scientificName;
  final String? colloquialName;
  final String locationText;
  final Color confidenceColor;
  final VoidCallback onTap;
  final VoidCallback onMapTap;

  const _ObservationCard({
    required this.observation,
    required this.scientificName,
    required this.colloquialName,
    required this.locationText,
    required this.confidenceColor,
    required this.onTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasLocation =
        observation.latitude != null && observation.longitude != null;
    final String colloquialDisplay =
        (colloquialName?.trim().isNotEmpty ?? false)
        ? colloquialName!.trim()
        : 'Not listed';
    final Color locationColor = hasLocation
        ? const Color(0xFFE7F3E7)
        : const Color(0xCCFFFFFF);

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
                child: LocalImagePreview(
                  path: observation.photoPath,
                  borderRadius: BorderRadius.circular(12),
                  cacheWidth: 160,
                  placeholder: const Icon(
                    Icons.local_florist,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scientific Name: $scientificName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        'Colloquial Name: $colloquialDisplay',
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'User: ${observation.observerName ?? 'Unknown user'}',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: hasLocation
                              ? const Color(0xFF8FBFA1)
                              : Colors.white38,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Tooltip(
                            message: locationText,
                            child: Text(
                              locationText,
                              style: TextStyle(
                                color: locationColor,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 28,
                          child: OutlinedButton.icon(
                            onPressed: hasLocation ? onMapTap : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: hasLocation
                                    ? Colors.white54
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                            ),
                            icon: const Icon(Icons.map, size: 14),
                            label: const Text(
                              'Map',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ),
                      ],
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
  final String scientificName;
  final String? colloquialName;
  final List<String> keyFeatures;
  final Color confidenceColor;
  final VoidCallback? onOpenMap;
  final VoidCallback onViewFull;
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;

  _ObservationDetailSheet({
    required this.observation,
    required this.scientificName,
    required this.colloquialName,
    required this.keyFeatures,
    required this.confidenceColor,
    required this.onOpenMap,
    required this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    final location = observation.location;
    final String colloquialDisplay =
        (colloquialName?.trim().isNotEmpty ?? false)
        ? colloquialName!.trim()
        : 'Not listed';
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
    final int windowMs = observation.windowDurationMs ?? 0;
    final String windowDuration = windowMs == 0
        ? 'Not recorded'
        : '${(windowMs / 1000).toStringAsFixed(1)}s';
    final int stabilityWins = observation.stabilityWinCount ?? 0;
    final int stabilityWindow = observation.stabilityWindowSize ?? 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scientific Name: $scientificName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Colloquial Name: $colloquialDisplay',
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'User: ${observation.observerName ?? 'Unknown user'}',
              style: const TextStyle(color: accentTextColor, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            Text(
              formatDateTime(observation.timestamp),
              style: const TextStyle(color: accentTextColor, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: LocalImagePreview(
                path: observation.photoPath,
                borderRadius: BorderRadius.circular(12),
                cacheWidth: 640,
                placeholder: const Center(
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.white70,
                  ),
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
            _ObservationDetailRow(label: 'Vote ratio', value: votePercent),
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
            if (onOpenMap != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map),
                  label: const Text('Open on map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
            if (observation.notes != null &&
                observation.notes!.trim().isNotEmpty)
              _ObservationDetailRow(
                label: 'Notes',
                value: observation.notes!.trim(),
              ),
            const SizedBox(height: 12),
            KeyFeaturesSection(
              features: keyFeatures,
              contained: true,
            ),
            const SizedBox(height: 12),
            const Text(
              'Field Notes',
              style: TextStyle(
                color: Color(0xFFE7F3E7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            StreamBuilder<List<FieldNote>>(
              stream: _fieldNotesRepository.watchAllNotes(),
              builder: (context, snapshot) {
                final notes = (snapshot.data ?? const <FieldNote>[])
                    .where(
                      (note) =>
                          note.links.observationIds.contains(observation.id),
                    )
                    .toList();
                if (notes.isEmpty) {
                  return const Text(
                    'No linked field notes.',
                    style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
                  );
                }
                return Column(
                  children: notes.map((note) {
                    final title = note.title.trim().isEmpty
                        ? 'Untitled note'
                        : note.title;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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
                        size: 18,
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/field-note-editor',
                    arguments: FieldNoteEditorArgs(
                      prelinkedObservationId: observation.id,
                    ),
                  );
                },
                icon: const Icon(Icons.note_add),
                label: const Text('Add note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
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

class _TasColloquialMaps {
  final Map<String, String> byId;
  final Map<String, String> byScientificName;

  const _TasColloquialMaps({
    required this.byId,
    required this.byScientificName,
  });
}
