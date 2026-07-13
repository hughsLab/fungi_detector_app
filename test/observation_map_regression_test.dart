import 'dart:io';

import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/services/map_tile_cache_service.dart';

void main() {
  test('map tile cache provider is online-first with cached fallback', () {
    final settings = MapTileCacheService.buildOnlineFirstTileProviderSettings(
      maxStoreLength: 120,
    );

    expect(settings.behavior, CacheBehavior.onlineFirst);
    expect(settings.cachedValidDuration, Duration.zero);
    expect(settings.maxStoreLength, 120);
  });

  test('main Android manifest allows online map tile requests', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET" />'),
    );
  });
}
