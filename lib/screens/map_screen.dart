import 'dart:async';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/field_note.dart';
import '../models/navigation_args.dart';
import '../models/observation.dart';
import '../models/species.dart';
import '../repositories/field_notes_repository.dart';
import '../repositories/observation_repository.dart';
import '../repositories/species_repository.dart';
import '../services/auth_service.dart';
import '../services/location_capture_service.dart';
import '../services/map_tile_cache_service.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../widgets/local_image_preview.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class _ObservationRarity {
  final SpeciesRarity level;
  final bool estimated;

  const _ObservationRarity({required this.level, required this.estimated});
}

class _FungiMapMarker extends StatelessWidget {
  final Color color;
  final String semanticsLabel;

  const _FungiMapMarker({required this.color, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        label: semanticsLabel,
        button: true,
        child: CustomPaint(
          painter: _FungiMarkerPainter(color),
          size: const Size(48, 52),
        ),
      ),
    );
  }
}

class _FungiMarkerPainter extends CustomPainter {
  final Color color;

  const _FungiMarkerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = const Color(0xFF17382D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - 4),
        width: 25,
        height: 7,
      ),
      shadow,
    );

    final stem = ui.Path()
      ..moveTo(size.width * 0.42, size.height * 0.45)
      ..quadraticBezierTo(
        size.width * 0.43,
        size.height * 0.72,
        size.width * 0.34,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.96,
        size.width * 0.66,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.57,
        size.height * 0.72,
        size.width * 0.58,
        size.height * 0.45,
      )
      ..close();
    canvas.drawPath(
      stem,
      Paint()
        ..color = const Color(0xFFFFF2D1)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(stem, outline);

    final cap = ui.Path()
      ..moveTo(size.width * 0.10, size.height * 0.48)
      ..quadraticBezierTo(
        size.width * 0.16,
        size.height * 0.10,
        size.width * 0.50,
        size.height * 0.08,
      )
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.10,
        size.width * 0.90,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.57,
        size.width * 0.10,
        size.height * 0.48,
      )
      ..close();
    canvas.drawPath(
      cap,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(cap, outline);

    final spotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.34, size.height * 0.27),
      2.4,
      spotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.55, size.height * 0.18),
      2.0,
      spotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.34),
      2.3,
      spotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FungiMarkerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RarityLegend extends StatelessWidget {
  const _RarityLegend();

  static const _entries = <(String, Color)>[
    ('Common', Color(0xFF2EAD67)),
    ('Uncommon', Color(0xFF3D8FE3)),
    ('Rare', Color(0xFFFFA000)),
    ('Very rare', Color(0xFFE23D5B)),
    ('Unknown', Color(0xFF78909C)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F4E3D).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Fungi rarity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          for (final entry in _entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: entry.$2,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 0.7),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.$1,
                    style: const TextStyle(color: Colors.white, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const SizedBox(
            width: 130,
            child: Text(
              'Range estimate unless curated rarity is available.',
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 9,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final ObservationRepository _observationRepository =
      ObservationRepository.instance;
  final FieldNotesRepository _fieldNotesRepository =
      FieldNotesRepository.instance;
  final SpeciesRepository _speciesRepository = SpeciesRepository.instance;
  final MapTileCacheService _tileCacheService = MapTileCacheService.instance;
  final LocationCaptureService _locationCaptureService =
      LocationCaptureService.instance;
  final SettingsService _settingsService = SettingsService.instance;
  final Connectivity _connectivity = Connectivity();
  final MapController _mapController = MapController();
  final Uuid _uuid = const Uuid();

  bool _loading = true;
  bool _locationEnabled = false;
  bool _tileCachingEnabled = true;
  int _tileCacheLimitMb = 250;
  bool _offlineDownloading = false;
  bool _offlineCancelling = false;
  double _offlineRadiusKm = 3.0;
  OfflineDownloadUpdate? _offlineDownloadUpdate;
  Map<String, String> _speciesNames = {};
  Map<String, Species> _speciesById = {};
  Map<String, Species> _speciesByModelClass = {};
  Map<String, Species> _speciesByScientificName = {};
  TileProvider? _tileProvider;
  List<Observation> _observationsCache = const [];
  MapFocusRequest? _pendingFocus;
  MapPickLocationArgs? _pickArgs;
  LatLng? _pickedLocation;
  LatLng? _temporaryFocusLocation;
  bool _mapReady = false;
  bool _handledInitialArgs = false;
  bool _hasNetworkConnection = true;
  bool _mapTileError = false;
  AnimationController? _mapAnimationController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  late final VoidCallback _settingsListener;

  @override
  void initState() {
    super.initState();
    _settingsListener = _handleSettingsChanged;
    _settingsService.settingsNotifier.addListener(_settingsListener);
    _startConnectivityMonitor();
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
    } else if (args is MapPickLocationArgs) {
      _pickArgs = args;
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
    _connectivitySubscription?.cancel();
    _mapAnimationController?.dispose();
    super.dispose();
  }

  Future<void> _startConnectivityMonitor() async {
    try {
      _handleConnectivityResults(await _connectivity.checkConnectivity());
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityResults,
      );
    } catch (e) {
      debugPrint('MAP_CONNECTIVITY: unable to monitor network state: $e');
    }
  }

  void _handleConnectivityResults(List<ConnectivityResult> results) {
    final hasNetwork = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (_hasNetworkConnection == hasNetwork) {
      return;
    }
    if (!mounted) {
      _hasNetworkConnection = hasNetwork;
      return;
    }
    setState(() {
      _hasNetworkConnection = hasNetwork;
      if (hasNetwork) {
        _mapTileError = false;
      }
    });
  }

  Future<void> _loadData() async {
    final settings = await _settingsService.loadSettings();
    await _tileCacheService.ensureInitialized(
      cacheSoftLimitMb: settings.mapTileCacheMaxSizeMb,
      maxDatabaseSizeKiB: settings.mapTileCacheMaxSizeMb * 1024,
    );
    final species = await _speciesRepository.loadSpecies();
    final names = {for (final item in species) item.id: item.displayName};
    final speciesById = {for (final item in species) item.id: item};
    final speciesByModelClass = <String, Species>{
      for (final item in species)
        if (item.modelId != null && item.sourceClassId != null)
          _modelClassKey(item.modelId!, item.sourceClassId!): item,
    };
    final speciesByScientificName = <String, Species>{};
    for (final item in species) {
      for (final name in <String?>[
        item.scientificName,
        item.canonicalName,
        item.commonName,
        item.colloquialName,
      ]) {
        final normalized = _normalizeSpeciesName(name);
        if (normalized.isNotEmpty) {
          speciesByScientificName.putIfAbsent(normalized, () => item);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _locationEnabled = settings.locationTaggingEnabled;
      _tileCachingEnabled = settings.mapTileCachingEnabled;
      _tileCacheLimitMb = settings.mapTileCacheMaxSizeMb;
      _speciesNames = names;
      _speciesById = speciesById;
      _speciesByModelClass = speciesByModelClass;
      _speciesByScientificName = speciesByScientificName;
      _tileProvider = _tileCacheService.tileProvider(
        cachingEnabled: _tileCachingEnabled,
      );
      _loading = false;
    });
  }

  void _handleSettingsChanged() async {
    if (!mounted) return;
    final settings = _settingsService.settingsNotifier.value;
    final bool cachingChanged =
        settings.mapTileCachingEnabled != _tileCachingEnabled;
    final bool locationChanged =
        settings.locationTaggingEnabled != _locationEnabled;
    final bool cacheLimitChanged =
        settings.mapTileCacheMaxSizeMb != _tileCacheLimitMb;

    if (!cachingChanged && !locationChanged && !cacheLimitChanged) {
      return;
    }

    if (cacheLimitChanged) {
      await _tileCacheService.configureCacheLimitMb(
        settings.mapTileCacheMaxSizeMb,
      );
    }
    if (!mounted) return;
    setState(() {
      _locationEnabled = settings.locationTaggingEnabled;
      _tileCachingEnabled = settings.mapTileCachingEnabled;
      _tileCacheLimitMb = settings.mapTileCacheMaxSizeMb;
      if (cachingChanged || cacheLimitChanged) {
        _tileProvider = _tileCacheService.tileProvider(
          cachingEnabled: _tileCachingEnabled,
        );
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
      MapFocusRequest(observationId: id, lat: lat, lon: lon, zoom: zoom),
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
    await _animateTo(LatLng(request.lat, request.lon), request.zoom);
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
      _showLocationSheet(request.lat, request.lon, label: request.label);
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
      final double lat =
          ui.lerpDouble(start.latitude, target.latitude, t) ?? target.latitude;
      final double lon =
          ui.lerpDouble(start.longitude, target.longitude, t) ??
          target.longitude;
      final double currentZoom = ui.lerpDouble(startZoom, zoom, t) ?? zoom;
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
      final rarity = _rarityForObservation(observation);
      final name = _displayNameFor(observation);
      return Marker(
        width: 48,
        height: 52,
        point: LatLng(location.latitude, location.longitude),
        child: GestureDetector(
          onTap: interactive ? () => _showObservationSheet(observation) : null,
          child: _FungiMapMarker(
            color: _rarityColor(rarity.level),
            semanticsLabel: '$name, ${_rarityLabel(rarity.level)} rarity',
          ),
        ),
      );
    }).toList();
  }

  String _modelClassKey(String modelId, int sourceClassId) {
    return '$modelId:$sourceClassId';
  }

  String _normalizeSpeciesName(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  Species? _speciesForObservation(Observation observation) {
    final modelId = observation.modelId;
    final sourceClassId = observation.sourceClassId;
    if (modelId != null && sourceClassId != null) {
      final byModelClass =
          _speciesByModelClass[_modelClassKey(modelId, sourceClassId)];
      if (byModelClass != null) return byModelClass;
    }
    final byId = _speciesById[observation.speciesId];
    if (byId != null) return byId;
    for (final name in <String?>[
      observation.scientificName,
      observation.label,
      observation.commonName,
      observation.colloquialName,
    ]) {
      final species = _speciesByScientificName[_normalizeSpeciesName(name)];
      if (species != null) return species;
    }
    return null;
  }

  _ObservationRarity _rarityForObservation(Observation observation) {
    final species = _speciesForObservation(observation);
    if (species == null) {
      return const _ObservationRarity(
        level: SpeciesRarity.unknown,
        estimated: false,
      );
    }
    return _ObservationRarity(
      level: species.mapRarity,
      estimated: species.mapRarityIsEstimated,
    );
  }

  Color _rarityColor(SpeciesRarity rarity) {
    switch (rarity) {
      case SpeciesRarity.common:
        return const Color(0xFF2EAD67);
      case SpeciesRarity.uncommon:
        return const Color(0xFF3D8FE3);
      case SpeciesRarity.rare:
        return const Color(0xFFFFA000);
      case SpeciesRarity.veryRare:
        return const Color(0xFFE23D5B);
      case SpeciesRarity.unknown:
        return const Color(0xFF78909C);
    }
  }

  String _rarityLabel(SpeciesRarity rarity) {
    switch (rarity) {
      case SpeciesRarity.common:
        return 'Common';
      case SpeciesRarity.uncommon:
        return 'Uncommon';
      case SpeciesRarity.rare:
        return 'Rare';
      case SpeciesRarity.veryRare:
        return 'Very rare';
      case SpeciesRarity.unknown:
        return 'Unknown';
    }
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

  String? get _currentUid => AuthService.instance.currentState.uid;

  bool _ownsObservation(Observation observation) {
    final uid = _currentUid;
    return uid != null && uid.isNotEmpty && observation.userId == uid;
  }

  String _observerLabel(Observation observation, {required bool isOwner}) {
    final observerName = observation.observerName;
    if (observerName != null) {
      return 'Observed by $observerName';
    }
    if (isOwner) {
      return 'Observed by you';
    }
    return 'Observed by community member';
  }

  String? _observationImagePath(Observation observation) {
    final imageUrl = observation.imageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return imageUrl;
    }
    final photoPath = observation.photoPath?.trim();
    if (photoPath != null && photoPath.isNotEmpty) {
      return photoPath;
    }
    return null;
  }

  Future<void> _setObservationVisibility(
    Observation observation,
    bool isPublic,
  ) async {
    if (!_ownsObservation(observation)) {
      _showMessage('This shared observation is read-only.');
      return;
    }
    try {
      await _observationRepository.updateObservationDetails(
        observation.id,
        isPublic: isPublic,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showMessage('Could not update sharing: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    _showMessage(
      isPublic ? 'Observation shared.' : 'Observation made private.',
    );
  }

  void _openObservation(Observation observation) {
    Navigator.of(context).pushNamed(
      '/detection-result',
      arguments: DetectionResultArgs(
        observationId: observation.id,
        lockedLabel: _displayNameFor(observation),
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
        isLichen: observation.isLichen ?? false,
        isSavedView: true,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleMapTileError(
    TileImage tile,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (!mounted || _mapTileError) {
      return;
    }
    debugPrint('MAP_TILE: tile load failed for ${tile.coordinates}: $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace, label: 'MAP_TILE');
    }
    setState(() {
      _mapTileError = true;
    });
  }

  Widget _emptyMapOverlay() {
    return Positioned(
      left: 16,
      right: 84,
      top: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1F4E3D).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No mapped observations yet.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Public shared observations and your saved locations will appear here.',
                style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offlineMapUnavailableOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: _offlineDownloading || _offlineDownloadUpdate != null ? 96 : 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF4E2B1F).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            'Map unavailable offline. Connect to the internet or download a small offline region first.',
            style: TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      ),
    );
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
        final meters = distance(target, LatLng(location.lat, location.lon));
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

  void _showLocationSheet(double lat, double lon, {String? label}) {
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
        final notes = (observation.notes ?? '').trim();
        final hasNotes = notes.isNotEmpty;
        final isOwner = _ownsObservation(observation);
        final observerLabel = _observerLabel(observation, isOwner: isOwner);
        final imagePath = _observationImagePath(observation);
        final rarity = _rarityForObservation(observation);
        final rarityColor = _rarityColor(rarity.level);
        final raritySuffix = rarity.estimated ? ' (range estimate)' : '';

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
                    fontStyle: FontStyle.italic,
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
                const SizedBox(height: 6),
                Text(
                  observerLabel,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isOwner) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Text(
                      'Shared public observation - read-only',
                      style: TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: rarityColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: rarityColor.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        '${_rarityLabel(rarity.level)}$raritySuffix',
                        style: TextStyle(
                          color: rarityColor,
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
                  child: LocalImagePreview(
                    path: imagePath,
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
                if (isOwner) ...[
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
                          .where(
                            (note) => note.links.observationIds.contains(
                              observation.id,
                            ),
                          )
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
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _setObservationVisibility(
                        observation,
                        !observation.isPublic,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        observation.isPublic
                            ? 'Make observation private'
                            : 'Share observation publicly',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
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
                      child: const Text('Back to observation card'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openOfflineActionsSheet() async {
    double selectedRadiusKm = _offlineRadiusKm;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F4E3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool canDownload =
                !_offlineDownloading &&
                _hasNetworkConnection &&
                _tileCacheService.isAvailable;
            final bool hasSavedObservationLocations = _observationsCache.any(
              (observation) => observation.location != null,
            );
            final bool canDownloadSavedObservations =
                canDownload && hasSavedObservationLocations;
            final String? disabledReason = !_hasNetworkConnection
                ? 'Offline downloads need an internet connection.'
                : (!_tileCacheService.isAvailable
                      ? 'Offline map storage is not available on this device.'
                      : null);
            final String? savedObservationsDisabledReason =
                disabledReason ??
                (hasSavedObservationLocations
                    ? null
                    : 'No saved observation locations are available yet.');
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Offline map download',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cache cap: $_tileCacheLimitMb MB',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Region radius',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<double>(
                      value: selectedRadiusKm,
                      dropdownColor: const Color(0xFF1F4E3D),
                      items: const [
                        DropdownMenuItem(
                          value: 2,
                          child: Text(
                            '2 km',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text(
                            '3 km',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text(
                            '5 km',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedRadiusKm = value;
                        });
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canDownload
                            ? () {
                                Navigator.of(context).pop();
                                _offlineRadiusKm = selectedRadiusKm;
                                _startDownloadAroundCurrentLocation(
                                  radiusKm: selectedRadiusKm,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.my_location),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FBFA1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                        label: const Text('Download around current GPS'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: canDownloadSavedObservations
                            ? () {
                                Navigator.of(context).pop();
                                _offlineRadiusKm = selectedRadiusKm;
                                _startDownloadAroundObservations(
                                  radiusKm: selectedRadiusKm,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.pin_drop),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                        label: const Text('Download around saved observations'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Uses OpenStreetMap tiles; keep download regions modest.',
                      style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                    ),
                    if (disabledReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        disabledReason,
                        style: const TextStyle(
                          color: Color(0xFFFFD1C1),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (savedObservationsDisabledReason != null &&
                        savedObservationsDisabledReason != disabledReason) ...[
                      const SizedBox(height: 4),
                      Text(
                        savedObservationsDisabledReason,
                        style: const TextStyle(
                          color: Color(0xFFFFD1C1),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startDownloadAroundCurrentLocation({
    required double radiusKm,
  }) async {
    if (!await _canStartOfflineDownload()) {
      return;
    }
    final captured = await _locationCaptureService.captureForObservation();
    if (captured == null) {
      _showMessage(
        _locationCaptureService.lastErrorMessage ??
            'Unable to get current location for offline download.',
      );
      return;
    }
    await _runOfflineDownload([
      OfflineDownloadRegionRequest(
        label: 'Current location',
        center: LatLng(captured.latitude, captured.longitude),
        radiusKm: radiusKm,
      ),
    ]);
  }

  Future<void> _startDownloadAroundObservations({
    required double radiusKm,
  }) async {
    if (!await _canStartOfflineDownload()) {
      return;
    }
    final requests = <OfflineDownloadRegionRequest>[];
    final seen = <String>{};

    for (final observation in _observationsCache) {
      final location = observation.location;
      if (location == null) {
        continue;
      }

      final key =
          '${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}';
      if (!seen.add(key)) {
        continue;
      }

      requests.add(
        OfflineDownloadRegionRequest(
          label: _displayNameFor(observation),
          center: LatLng(location.latitude, location.longitude),
          radiusKm: radiusKm,
        ),
      );

      if (requests.length >= 25) {
        break;
      }
    }

    if (requests.isEmpty) {
      _showMessage('No saved observation locations are available yet.');
      return;
    }

    await _runOfflineDownload(requests);
  }

  Future<bool> _canStartOfflineDownload() async {
    final hasNetwork = await _refreshNetworkAvailability();
    if (!hasNetwork) {
      _showMessage('Offline map downloads need an internet connection.');
      return false;
    }
    if (!_tileCacheService.isAvailable) {
      _showMessage('Offline map storage is not available on this device.');
      return false;
    }
    return true;
  }

  Future<bool> _refreshNetworkAvailability() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _handleConnectivityResults(results);
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return _hasNetworkConnection;
    }
  }

  Future<void> _runOfflineDownload(
    List<OfflineDownloadRegionRequest> requests,
  ) async {
    if (_offlineDownloading) {
      _showMessage('An offline download is already in progress.');
      return;
    }
    if (requests.isEmpty) {
      return;
    }

    setState(() {
      _offlineDownloading = true;
      _offlineCancelling = false;
      _offlineDownloadUpdate = null;
    });

    try {
      await for (final update in _tileCacheService.downloadRegions(requests)) {
        if (!mounted) return;
        setState(() {
          _offlineDownloadUpdate = update;
        });
      }
      if (!mounted) return;

      final int pruned = _offlineDownloadUpdate?.prunedTiles ?? 0;
      if (_offlineCancelling) {
        _showMessage('Offline download cancelled.');
      } else if (pruned > 0) {
        _showMessage(
          'Offline download complete. Pruned $pruned old tiles to stay within cache limit.',
        );
      } else {
        _showMessage('Offline download complete.');
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Offline download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _offlineDownloading = false;
          _offlineCancelling = false;
        });
      }
    }
  }

  Future<void> _cancelOfflineDownload() async {
    if (!_offlineDownloading || _offlineCancelling) {
      return;
    }
    setState(() {
      _offlineCancelling = true;
    });
    await _tileCacheService.cancelActiveDownload();
  }

  Widget _offlineDownloadStatusCard() {
    final update = _offlineDownloadUpdate;
    if (!_offlineDownloading && update == null) {
      return const SizedBox.shrink();
    }

    final regionProgress = update?.regionProgress;
    final double overall =
        update?.overallProgressFraction ?? (_offlineDownloading ? 0 : 1);
    final String heading = _offlineDownloading
        ? (_offlineCancelling
              ? 'Stopping offline download...'
              : 'Downloading offline tiles...')
        : (update?.isComplete ?? false)
        ? 'Offline tiles ready'
        : 'Offline download finished';
    final String regionLabel = update == null || update.totalRegions <= 0
        ? ''
        : 'Region ${update.regionIndex}/${update.totalRegions}: ${update.label}';
    final String details = regionProgress == null
        ? (update?.message ?? '')
        : '${regionProgress.attemptedTiles}/${regionProgress.maxTiles} tiles (${regionProgress.percentageProgress.toStringAsFixed(0)}%)';

    return Positioned(
      left: 14,
      right: 14,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F4E3D).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    heading,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_offlineDownloading)
                  TextButton(
                    onPressed: _offlineCancelling
                        ? null
                        : _cancelOfflineDownload,
                    child: const Text('Cancel'),
                  )
                else
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _offlineDownloadUpdate = null;
                      });
                    },
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
              ],
            ),
            if (regionLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  regionLabel,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  details,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
            LinearProgressIndicator(
              value: _offlineDownloading ? overall.clamp(0, 1) : 1,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF8FBFA1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool pickMode = _pickArgs != null;

    if (_loading) {
      _mapReady = false;
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      body: StreamBuilder<List<Observation>>(
        stream: pickMode
            ? _observationRepository.watchObservationsWithLocation()
            : _observationRepository.streamVisibleMapObservations(),
        builder: (context, snapshot) {
          final observations = snapshot.data ?? const <Observation>[];
          final ordered = [...observations];
          ordered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _observationsCache = ordered;
          final markers = _buildMarkers(ordered, interactive: !pickMode);
          final Observation? first = ordered.isEmpty ? null : ordered.first;
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
                    urlTemplate: MapTileCacheService.tileUrlTemplate,
                    userAgentPackageName:
                        MapTileCacheService.tileUserAgentPackageName,
                    tileProvider: _tileProvider ?? NetworkTileProvider(),
                    errorTileCallback: _handleMapTileError,
                  ),
                  MarkerLayer(markers: overlayMarkers),
                ],
              ),
              if (!pickMode && ordered.isEmpty) _emptyMapOverlay(),
              if (!pickMode && ordered.isNotEmpty)
                const Positioned(left: 12, top: 12, child: _RarityLegend()),
              if (!_hasNetworkConnection && _mapTileError)
                _offlineMapUnavailableOverlay(),
              if (!pickMode)
                Positioned(
                  right: 16,
                  top: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'map-offline-download',
                    onPressed: _openOfflineActionsSheet,
                    backgroundColor: const Color(
                      0xFF1F4E3D,
                    ).withValues(alpha: 0.94),
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.download_for_offline),
                  ),
                ),
              if (!pickMode) _offlineDownloadStatusCard(),
              if (pickMode)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F4E3D).withValues(alpha: 0.92),
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
                              backgroundColor: const Color(0xFF8FBFA1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
