import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/map_tile_cache_service.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final MapTileCacheService _tileCacheService = MapTileCacheService.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final MapController _mapController = MapController();
  final Uuid _uuid = const Uuid();

  bool _loading = true;
  bool _locationEnabled = false;
  bool _tileCachingEnabled = true;
  Map<String, String> _speciesNames = {};
  TileProvider? _tileProvider;
  List<Observation> _observationsCache = const [];
  MapFocusRequest? _pendingFocus;
  MapPickLocationArgs? _pickArgs;
  LatLng? _pickedLocation;
  LatLng? _temporaryFocusLocation;
  bool _allowMapWithoutLocation = false;
  bool _mapReady = false;
  bool _handledInitialArgs = false;
  AnimationController? _mapAnimationController;
  late final VoidCallback _settingsListener;

  @override
  void initState() {
    super.initState();
    _settingsListener = _handleSettingsChanged;
    _settingsService.settingsNotifier.addListener(_settingsListener);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialArgs) {
      return;
    }
    _handledInitialArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is MapFocusRequest) {
      _pendingFocus = args;
      _allowMapWithoutLocation = true;
    } else if (args is MapPickLocationArgs) {
      _pickArgs = args;
      _allowMapWithoutLocation = true;
      final double? lat = args.initialLat;
      final double? lon = args.initialLon;
      if (lat != null && lon != null) {
        _pickedLocation = LatLng(lat, lon);
      }
    }
  }

  @override
  void dispose() {
    _settingsService.settingsNotifier.removeListener(_settingsListener);
    _mapAnimationController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _tileCacheService.ensureInitialized();
    final settings = await _settingsService.loadSettings();
    final species = await _speciesRepository.loadSpecies();
    final names = {for (final item in species) item.id: item.displayName};
    if (!mounted) return;
    setState(() {
      _locationEnabled = settings.locationTaggingEnabled;
      _tileCachingEnabled = settings.mapTileCachingEnabled;
      _speciesNames = names;
      _tileProvider =
          _tileCacheService.tileProvider(cachingEnabled: _tileCachingEnabled);
      _loading = false;
    });
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    final settings = _settingsService.settingsNotifier.value;
    final bool cachingChanged =
        settings.mapTileCachingEnabled != _tileCachingEnabled;
    final bool locationChanged =
        settings.locationTaggingEnabled != _locationEnabled;

    if (!cachingChanged && !locationChanged) {
      return;
    }

    setState(() {
      _locationEnabled = settings.locationTaggingEnabled;
      _tileCachingEnabled = settings.mapTileCachingEnabled;
      if (cachingChanged) {
        _tileProvider =
            _tileCacheService.tileProvider(cachingEnabled: _tileCachingEnabled);
      }
    });
  }

  void focusOnObservation(
    String id,
    double lat,
    double lon, {
    double zoom = 15,
  }) {
    handleFocusRequest(
      MapFocusRequest(
        observationId: id,
        lat: lat,
        lon: lon,
        zoom: zoom,
      ),
    );
  }

  void focusOnLocation(
    double lat,
    double lon, {
    double zoom = 15,
    String? label,
  }) {
    handleFocusRequest(
      MapFocusRequest(
        observationId: null,
        lat: lat,
        lon: lon,
        zoom: zoom,
        label: label,
      ),
    );
  }

  void handleFocusRequest(MapFocusRequest request) {
    _allowMapWithoutLocation = true;
    _pendingFocus = request;
    if (mounted) {
      setState(() {});
    }
    _maybeHandlePendingFocus();
  }

  void _maybeHandlePendingFocus() {
    if (!_mapReady) {
      return;
    }
    final request = _pendingFocus;
    if (request == null) {
      return;
    }
    _pendingFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _performFocus(request);
    });
  }

  Future<void> _performFocus(MapFocusRequest request) async {
    await _animateTo(
      LatLng(request.lat, request.lon),
      request.zoom,
    );
    final String? observationId = request.observationId;
    if (observationId != null) {
      _temporaryFocusLocation = null;
      Observation? target;
      for (final observation in _observationsCache) {
        if (observation.id == observationId) {
          target = observation;
          break;
        }
      }
      if (target != null && mounted) {
        _showObservationSheet(target);
      }
      return;
    }
    _temporaryFocusLocation = LatLng(request.lat, request.lon);
    if (mounted) {
      _showLocationSheet(
        request.lat,
        request.lon,
        label: request.label,
      );
    }
  }

  Future<void> _animateTo(LatLng target, double zoom) async {
    _mapAnimationController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _mapAnimationController = controller;
    final CurvedAnimation curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );
    final LatLng start = _mapController.camera.center;
    final double startZoom = _mapController.camera.zoom;

    controller.addListener(() {
      final double t = curve.value;
      final double lat = lerpDouble(start.latitude, target.latitude, t) ??
          target.latitude;
      final double lon = lerpDouble(start.longitude, target.longitude, t) ??
          target.longitude;
      final double currentZoom = lerpDouble(startZoom, zoom, t) ?? zoom;
      _mapController.move(LatLng(lat, lon), currentZoom);
    });

    await controller.forward();
    if (_mapAnimationController == controller) {
      _mapAnimationController = null;
    }
    controller.dispose();
  }

  List<Marker> _buildMarkers(
    List<Observation> observations, {
    bool interactive = true,
  }) {
    return observations.map((observation) {
      final location = observation.location!;
      return Marker(
        width: 44,
        height: 44,
        point: LatLng(location.latitude, location.longitude),
        child: GestureDetector(
          onTap: interactive ? () => _showObservationSheet(observation) : null,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFF8FBFA1),
            size: 38,
          ),
        ),
      );
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

  void _openObservation(Observation observation) {
    Navigator.of(context).pushNamed(
      '/detection-result',
      arguments: DetectionResultArgs(
        observationId: observation.id,
        lockedLabel: _displayNameFor(observation),
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
        isLichen: observation.isLichen ?? false,
        isSavedView: true,
      ),
    );
  }

  Future<void> _openExternalMaps(Observation observation) async {
    final location = observation.location;
    if (location == null) return;
    final lat = location.latitude;
    final lon = location.longitude;
    final label = Uri.encodeComponent(_displayNameFor(observation));

    final Uri platformUri = Platform.isIOS
        ? Uri.parse('http://maps.apple.com/?ll=$lat,$lon&q=$label')
        : Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)');
    final Uri fallback = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon',
    );

    final bool launched = await _tryLaunch(platformUri);
    if (!launched) {
      await _tryLaunch(fallback);
    }
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      final result =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!result) {
        _showMessage('Unable to open external maps.');
      }
      return result;
    } catch (_) {
      _showMessage('No map app available for this action.');
      return false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openNoteEditor({
    String? noteId,
    String? observationId,
    LocationRef? location,
  }) {
    Navigator.of(context).pushNamed(
      '/field-note-editor',
      arguments: FieldNoteEditorArgs(
        noteId: noteId,
        prelinkedObservationId: observationId,
        prelinkedLocation: location,
      ),
    );
  }

  List<FieldNote> _notesNearLocation(
    List<FieldNote> notes,
    double lat,
    double lon, {
    double radiusMeters = 80,
  }) {
    const distance = Distance();
    final target = LatLng(lat, lon);
    return notes.where((note) {
      for (final location in note.links.locations) {
        final meters = distance(
          target,
          LatLng(location.lat, location.lon),
        );
        if (meters <= radiusMeters) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Widget _noteList(List<FieldNote> notes) {
    if (notes.isEmpty) {
      return const Text(
        'No field notes yet.',
        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
      );
    }
    return Column(
      children: notes.map((note) {
        final title = note.title.trim().isEmpty ? 'Untitled note' : note.title;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
          ),
          subtitle: Text(
            formatDateTime(note.updatedAt),
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11.5),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.white70,
            size: 18,
          ),
          onTap: () => _openNoteEditor(noteId: note.id),
        );
      }).toList(),
    );
  }

  void _showLocationSheet(
    double lat,
    double lon, {
    String? label,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        final String labelText = (label ?? '').trim().isEmpty
            ? 'Pinned location'
            : label!.trim();
        final locationRef = LocationRef(
          id: _uuid.v4(),
          lat: lat,
          lon: lon,
          label: label,
          accuracyMeters: null,
          capturedAt: DateTime.now(),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Notes at this location',
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
                    final notes = snapshot.data ?? const <FieldNote>[];
                    final nearby = _notesNearLocation(notes, lat, lon);
                    return _noteList(nearby);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openNoteEditor(location: locationRef);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8FBFA1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Add note here'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _temporaryFocusLocation = null;
      });
    });
  }

  void _showObservationSheet(Observation observation) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        final name = _displayNameFor(observation);
        final confidence = observation.confidence;
        final color = _confidenceColor(confidence);
        final photoPath = observation.photoPath;
        final hasImage = photoPath != null && File(photoPath).existsSync();
        final notes = (observation.notes ?? '').trim();
        final hasNotes = notes.isNotEmpty;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatDateTime(observation.timestamp),
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        'Confidence ${formatConfidence(confidence)}',
                        style: TextStyle(
                          color: color,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 150,
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
                const SizedBox(height: 12),
                Text(
                  'Notes',
                  style: const TextStyle(
                    color: Color(0xFFE7F3E7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasNotes ? notes : 'No notes recorded.',
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
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
                    final allNotes = snapshot.data ?? const <FieldNote>[];
                    final observationNotes = allNotes
                        .where((note) => note.links.observationIds
                            .contains(observation.id))
                        .toList();
                    final double? lat = observation.latitude;
                    final double? lon = observation.longitude;
                    final List<FieldNote> locationNotes =
                        (lat != null && lon != null)
                            ? _notesNearLocation(allNotes, lat, lon)
                            : const <FieldNote>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Linked to this observation',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _noteList(observationNotes),
                        const SizedBox(height: 10),
                        const Text(
                          'Notes at this location',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _noteList(locationNotes),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openNoteEditor(
                                    observationId: observation.id,
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side:
                                      const BorderSide(color: Colors.white54),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text('Add note for observation'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (lat == null || lon == null)
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        _openNoteEditor(
                                          location: LocationRef(
                                            id: _uuid.v4(),
                                            lat: lat,
                                            lon: lon,
                                            label: observation.locationLabel,
                                            accuracyMeters:
                                                observation.accuracyMeters,
                                            capturedAt:
                                                observation.capturedAt ??
                                                DateTime.now(),
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8FBFA1),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text('Add note here'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openExternalMaps(observation);
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open in maps'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openObservation(observation);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FBFA1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('View observation'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);
    final bool pickMode = _pickArgs != null;

    if (_loading) {
      _mapReady = false;
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool showLocationDisabled =
        !_locationEnabled && !pickMode && !_allowMapWithoutLocation;

    if (showLocationDisabled) {
      _mapReady = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pickMode ? (_pickArgs?.title ?? 'Pick location') : 'Observation Map',
        ),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: pickMode
            ? [
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]
            : null,
      ),
      body: showLocationDisabled
          ? ForestBackground(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              includeTopSafeArea: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Location tagging is disabled.',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enable it in Settings to map observations.',
                      style: TextStyle(color: accentTextColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/settings');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Open Settings'),
                    ),
                  ],
                ),
              ),
            )
          : StreamBuilder<List<Observation>>(
              stream: _observationRepository.watchObservationsWithLocation(),
              builder: (context, snapshot) {
                final observations = snapshot.data ?? const <Observation>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    observations.isEmpty &&
                    !pickMode) {
                  _mapReady = false;
                  return const Center(child: CircularProgressIndicator());
                }
                if (observations.isEmpty && !pickMode) {
                  _mapReady = false;
                  return ForestBackground(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    includeTopSafeArea: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'No mapped observations yet.',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Save an observation with a location to see it here.',
                            style: TextStyle(color: accentTextColor),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final ordered = [...observations];
                ordered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                _observationsCache = ordered;
                final markers = _buildMarkers(
                  ordered,
                  interactive: !pickMode,
                );
                final Observation? first =
                    ordered.isEmpty ? null : ordered.first;
                final ObservationLocation? firstLocation = first?.location;
                final double? pickLat = _pickArgs?.initialLat;
                final double? pickLon = _pickArgs?.initialLon;
                final LatLng center = (pickLat != null && pickLon != null)
                    ? LatLng(pickLat, pickLon)
                    : (firstLocation == null
                        ? const LatLng(-25.2744, 133.7751)
                        : LatLng(firstLocation.latitude, firstLocation.longitude));

                _mapReady = true;
                _maybeHandlePendingFocus();

                final List<Marker> overlayMarkers = [...markers];
                final LatLng? picked = _pickedLocation;
                if (picked != null) {
                  overlayMarkers.add(
                    Marker(
                      width: 42,
                      height: 42,
                      point: picked,
                      child: const Icon(
                        Icons.place,
                        color: Color(0xFFFFC857),
                        size: 36,
                      ),
                    ),
                  );
                }
                final LatLng? tempFocus = _temporaryFocusLocation;
                if (tempFocus != null) {
                  overlayMarkers.add(
                    Marker(
                      width: 42,
                      height: 42,
                      point: tempFocus,
                      child: const Icon(
                        Icons.place,
                        color: Color(0xFF7CD39A),
                        size: 36,
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: pickMode ? 10.0 : 6.0,
                        backgroundColor: const Color(0xFF0F2A20),
                        onTap: pickMode
                            ? (tapPosition, latlng) {
                                setState(() {
                                  _pickedLocation = latlng;
                                });
                              }
                            : null,
                      ),
                      mapController: _mapController,
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          // Responsible caching only: no bulk download. Respect
                          // OSM Tile Usage Policy https://operations.osmfoundation.org/policies/tiles/
                          userAgentPackageName: 'realtime_detection_app',
                          tileProvider: _tileProvider ?? NetworkTileProvider(),
                        ),
                        MarkerLayer(markers: overlayMarkers),
                      ],
                    ),
                    if (pickMode)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F4E3D)
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tap the map to drop a pin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _pickedLocation == null
                                    ? 'No location selected'
                                    : '${_pickedLocation!.latitude.toStringAsFixed(4)}, ${_pickedLocation!.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _pickedLocation == null
                                      ? null
                                      : () {
                                          final selected = _pickedLocation!;
                                          Navigator.of(context).pop(
                                            MapPickResult(
                                              lat: selected.latitude,
                                              lon: selected.longitude,
                                              label: null,
                                            ),
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF8FBFA1),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('Use this location'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
