import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

class MapTileCacheService {
  MapTileCacheService._();

  static final MapTileCacheService instance = MapTileCacheService._();

  static const String _storeName = 'osm_map_tiles';
  final FMTCStore _store = const FMTCStore(_storeName);

  Future<void>? _initFuture;
  bool _available = false;
  FMTCTileProvider? _tileProvider;

  bool get isAvailable => _available;

  Future<void> ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    try {
      await FMTCObjectBoxBackend().initialise();
      final ready = await _store.manage.ready;
      if (!ready) {
        await _store.manage.create();
      }
      _tileProvider = _store.getTileProvider();
      _available = true;
    } catch (e, st) {
      // If tile caching fails to initialize, fall back to network tiles only.
      debugPrint('MAP_CACHE: Failed to initialize tile cache: $e');
      debugPrintStack(stackTrace: st, label: 'MAP_CACHE');
      _available = false;
    }
  }

  TileProvider tileProvider({required bool cachingEnabled}) {
    if (!cachingEnabled || !_available) {
      return NetworkTileProvider();
    }
    return _tileProvider ?? _store.getTileProvider();
  }

  Future<int?> getCacheSizeBytes() async {
    if (!_available) {
      return 0;
    }
    final ready = await _store.manage.ready;
    if (!ready) {
      return 0;
    }
    final sizeKiB = await _store.stats.size;
    return (sizeKiB * 1024).round();
  }

  Future<void> clearCache() async {
    if (!_available) {
      return;
    }
    final ready = await _store.manage.ready;
    if (!ready) {
      return;
    }
    await _store.manage.reset();
  }
}
