import 'package:flutter/services.dart';
import 'package:geocoder_offline/geocoder_offline.dart';

import 'settings_service.dart';

class LocationLabelService {
  LocationLabelService._();

  static final LocationLabelService instance = LocationLabelService._();

  static const String _datasetAssetPath = 'assets/data/au_localities.csv';
  static const double _nearThresholdKm = 25.0;

  GeocodeData? _geocodeData;
  bool _loadAttempted = false;

  Future<String?> labelFor({
    required double latitude,
    required double longitude,
    required LocationLabelMode mode,
  }) async {
    if (latitude.isNaN || longitude.isNaN) {
      return null;
    }

    if (mode == LocationLabelMode.coordinates) {
      return _formatCoordinates(latitude, longitude);
    }

    final GeocodeData? geocodeData = await _loadGeocodeData();
    if (geocodeData == null) {
      return _formatCoordinates(latitude, longitude);
    }

    final List<LocationResult> results = geocodeData.search(
      latitude,
      longitude,
    );
    if (results.isEmpty) {
      return _formatCoordinates(latitude, longitude);
    }

    final LocationResult best = results.first;
    final String name = (best.location.featureName ?? '').trim();
    if (name.isEmpty) {
      return _formatCoordinates(latitude, longitude);
    }

    final String state = (best.location.state ?? '').trim();
    final String baseLabel = state.isEmpty ? name : '$name $state';
    final double distanceKm = GeocodeData.calculateDistance(
      latitude,
      longitude,
      best.location.latitude ?? latitude,
      best.location.longitude ?? longitude,
    );
    if (distanceKm > _nearThresholdKm) {
      return 'Near $baseLabel';
    }
    return baseLabel;
  }

  Future<GeocodeData?> _loadGeocodeData() async {
    if (_geocodeData != null) {
      return _geocodeData;
    }
    if (_loadAttempted) {
      return null;
    }
    _loadAttempted = true;
    try {
      final String raw = await rootBundle.loadString(_datasetAssetPath);
      if (raw.trim().isEmpty) {
        return null;
      }
      _geocodeData = GeocodeData(
        raw,
        'LOCALITY',
        'STATE',
        'LAT',
        'LON',
      );
      return _geocodeData;
    } catch (_) {
      return null;
    }
  }

  String _formatCoordinates(double latitude, double longitude) {
    final String lat = latitude.toStringAsFixed(2);
    final String lon = longitude.toStringAsFixed(2);
    return 'Lat $lat, Lon $lon';
  }
}
