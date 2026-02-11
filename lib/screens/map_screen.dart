import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/map_tile_cache_service.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../widgets/forest_background.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final MapTileCacheService _tileCacheService = MapTileCacheService.instance;
  final SettingsService _settingsService = SettingsService.instance;

  bool _loading = true;
  bool _locationEnabled = false;
  bool _tileCachingEnabled = true;
  Map<String, String> _speciesNames = {};
  TileProvider? _tileProvider;
  late final VoidCallback _settingsListener;

  @override
  void initState() {
    super.initState();
    _settingsListener = _handleSettingsChanged;
    _settingsService.settingsNotifier.addListener(_settingsListener);
    _loadData();
  }

  @override
  void dispose() {
    _settingsService.settingsNotifier.removeListener(_settingsListener);
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

  List<Marker> _buildMarkers(List<Observation> observations) {
    return observations.map((observation) {
      final location = observation.location!;
      return Marker(
        width: 44,
        height: 44,
        point: LatLng(location.latitude, location.longitude),
        child: GestureDetector(
          onTap: () => _showObservationSheet(observation),
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

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool showLocationDisabled = !_locationEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Observation Map'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
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
                    observations.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (observations.isEmpty) {
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
                final markers = _buildMarkers(ordered);
                final Observation first = ordered.first;
                final ObservationLocation? firstLocation = first.location;
                final LatLng center = firstLocation == null
                    ? const LatLng(-25.2744, 133.7751)
                    : LatLng(firstLocation.latitude, firstLocation.longitude);

                return FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 6.0,
                    backgroundColor: const Color(0xFF0F2A20),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      // Responsible caching only: no bulk download. Respect
                      // OSM Tile Usage Policy https://operations.osmfoundation.org/policies/tiles/
                      userAgentPackageName: 'realtime_detection_app',
                      tileProvider: _tileProvider ?? NetworkTileProvider(),
                    ),
                    MarkerLayer(markers: markers),
                  ],
                );
              },
            ),
    );
  }
}
