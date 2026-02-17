import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_tile_caching/src/backend/backend_access.dart'; // ignore: implementation_imports
import 'package:latlong2/latlong.dart';

class OfflineDownloadRegionRequest {
  final String label;
  final LatLng center;
  final double radiusKm;
  final int minZoom;
  final int maxZoom;

  const OfflineDownloadRegionRequest({
    required this.label,
    required this.center,
    this.radiusKm = 3.0,
    this.minZoom = 11,
    this.maxZoom = 16,
  });
}

class OfflineDownloadUpdate {
  final int regionIndex;
  final int totalRegions;
  final String label;
  final int estimatedTilesInRegion;
  final DownloadProgress? regionProgress;
  final bool isComplete;
  final String? message;
  final int prunedTiles;

  const OfflineDownloadUpdate({
    required this.regionIndex,
    required this.totalRegions,
    required this.label,
    required this.estimatedTilesInRegion,
    required this.regionProgress,
    required this.isComplete,
    this.message,
    this.prunedTiles = 0,
  });

  double get overallProgressFraction {
    if (totalRegions <= 0) {
      return 1;
    }
    if (isComplete) {
      return 1;
    }
    final regionFraction = (regionProgress?.percentageProgress ?? 0) / 100;
    final completedRegions = max(0, regionIndex - 1);
    return ((completedRegions + regionFraction.clamp(0, 1)) / totalRegions)
        .clamp(0, 1);
  }
}

class MapTileCacheService {
  MapTileCacheService._();

  static final MapTileCacheService instance = MapTileCacheService._();

  static const String storeName = 'osm_map_tiles';
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String tileUserAgentPackageName = 'realtime_detection_app';

  static const String _downloadInstanceId = 'offline-region-prefetch';
  static const int _defaultEstimatedTileSizeBytes = 24 * 1024;

  final FMTCStore _store = const FMTCStore(storeName);
  int _softCacheLimitMb = 250;
  int _maxDatabaseSizeKiB = 250 * 1024;
  int _maxStoreLength = 0;

  Future<void>? _initFuture;
  bool _available = false;
  FMTCTileProvider? _tileProvider;

  bool get isAvailable => _available;
  int get softCacheLimitMb => _softCacheLimitMb;

  Future<void> ensureInitialized({
    int? cacheSoftLimitMb,
    int? maxDatabaseSizeKiB,
  }) async {
    if (cacheSoftLimitMb != null) {
      _softCacheLimitMb = cacheSoftLimitMb;
    }
    if (maxDatabaseSizeKiB != null) {
      _maxDatabaseSizeKiB = maxDatabaseSizeKiB;
    }

    _initFuture ??= _initialize();
    await _initFuture!;

    if (_available) {
      await _refreshProviderSettings();
    }
  }

  Future<void> _initialize() async {
    try {
      await FMTCObjectBoxBackend().initialise(
        maxDatabaseSize: _maxDatabaseSizeKiB,
      );
      final ready = await _store.manage.ready;
      if (!ready) {
        await _store.manage.create();
      }
      _available = true;
      await _refreshProviderSettings();
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
    return _tileProvider ?? _buildTileProvider();
  }

  Future<void> configureCacheLimitMb(int limitMb) async {
    _softCacheLimitMb = limitMb;
    if (!_available) {
      return;
    }
    await _refreshProviderSettings();
    await pruneCacheToSoftLimit();
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

  Future<({int sizeBytes, int tileCount, int hits, int misses})>
  getCacheStats() async {
    if (!_available) {
      return (sizeBytes: 0, tileCount: 0, hits: 0, misses: 0);
    }
    final ready = await _store.manage.ready;
    if (!ready) {
      return (sizeBytes: 0, tileCount: 0, hits: 0, misses: 0);
    }
    final stats = await _store.stats.all;
    return (
      sizeBytes: (stats.size * 1024).round(),
      tileCount: stats.length,
      hits: stats.hits,
      misses: stats.misses,
    );
  }

  Future<int> pruneCacheToSoftLimit() async {
    if (!_available) {
      return 0;
    }
    final ready = await _store.manage.ready;
    if (!ready) {
      return 0;
    }

    int totalRemoved = 0;
    for (int attempts = 0; attempts < 3; attempts++) {
      final stats = await _store.stats.all;
      if (stats.length <= 0) {
        break;
      }

      final currentSizeBytes = (stats.size * 1024).round();
      final capBytes = _softCacheLimitMb * 1024 * 1024;
      if (currentSizeBytes <= capBytes) {
        break;
      }

      final avgTileBytes = max(
        1.0,
        currentSizeBytes / max(1, stats.length).toDouble(),
      );
      final tilesLimit = max(1, (capBytes / avgTileBytes).floor());

      // ignore: invalid_use_of_internal_member
      final removed = await FMTCBackendAccess.internal
          .removeOldestTilesAboveLimit(
            storeName: storeName,
            tilesLimit: tilesLimit,
          );
      totalRemoved += removed;

      if (removed == 0) {
        break;
      }
    }
    await _refreshProviderSettings();
    return totalRemoved;
  }

  Stream<OfflineDownloadUpdate> downloadRegions(
    List<OfflineDownloadRegionRequest> requests,
  ) async* {
    if (!_available) {
      throw StateError('Map tile cache is not initialized.');
    }
    if (requests.isEmpty) {
      yield const OfflineDownloadUpdate(
        regionIndex: 0,
        totalRegions: 0,
        label: 'No regions',
        estimatedTilesInRegion: 0,
        regionProgress: null,
        isComplete: true,
      );
      return;
    }

    final total = requests.length;
    for (int i = 0; i < total; i++) {
      final request = requests[i];
      final downloadable = CircleRegion(request.center, request.radiusKm)
          .toDownloadable(
            minZoom: request.minZoom,
            maxZoom: request.maxZoom,
            options: TileLayer(
              urlTemplate: tileUrlTemplate,
              userAgentPackageName: tileUserAgentPackageName,
            ),
          );

      final estimated = await _store.download.check(downloadable);
      yield OfflineDownloadUpdate(
        regionIndex: i + 1,
        totalRegions: total,
        label: request.label,
        estimatedTilesInRegion: estimated,
        regionProgress: null,
        isComplete: false,
        message: 'Preparing download...',
      );

      await for (final progress in _store.download.startForeground(
        region: downloadable,
        parallelThreads: 4,
        maxBufferLength: 120,
        skipExistingTiles: true,
        skipSeaTiles: true,
        maxReportInterval: const Duration(milliseconds: 750),
        instanceId: _downloadInstanceId,
      )) {
        yield OfflineDownloadUpdate(
          regionIndex: i + 1,
          totalRegions: total,
          label: request.label,
          estimatedTilesInRegion: estimated,
          regionProgress: progress,
          isComplete: false,
        );
      }
    }

    final pruned = await pruneCacheToSoftLimit();
    yield OfflineDownloadUpdate(
      regionIndex: total,
      totalRegions: total,
      label: requests.last.label,
      estimatedTilesInRegion: 0,
      regionProgress: null,
      isComplete: true,
      message: 'Offline region download complete.',
      prunedTiles: pruned,
    );
  }

  Future<void> cancelActiveDownload() async {
    if (!_available) {
      return;
    }
    await _store.download.cancel(instanceId: _downloadInstanceId);
  }

  Future<void> _refreshProviderSettings() async {
    _maxStoreLength = await _estimateMaxStoreLengthFromSoftLimit();
    _tileProvider = _buildTileProvider();
  }

  Future<int> _estimateMaxStoreLengthFromSoftLimit() async {
    final capBytes = _softCacheLimitMb * 1024 * 1024;
    if (capBytes <= 0) {
      return 0;
    }

    final stats = await _store.stats.all;
    final averageTileBytes = stats.length <= 0
        ? _defaultEstimatedTileSizeBytes
        : max(1, ((stats.size * 1024) / stats.length).round());

    return max(1, (capBytes / averageTileBytes).floor());
  }

  FMTCTileProvider _buildTileProvider() {
    return _store.getTileProvider(
      settings: FMTCTileProviderSettings(
        behavior: CacheBehavior.cacheFirst,
        cachedValidDuration: Duration.zero,
        maxStoreLength: _maxStoreLength,
        setInstance: false,
      ),
    );
  }
}
