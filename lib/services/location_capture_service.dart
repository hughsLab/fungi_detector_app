import 'dart:async';

import 'package:geolocator/geolocator.dart';

class CapturedLocation {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime capturedAt;

  const CapturedLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });
}

class LocationCaptureService {
  LocationCaptureService._();

  static final LocationCaptureService instance = LocationCaptureService._();

  String? _lastErrorMessage;
  String? get lastErrorMessage => _lastErrorMessage;

  Future<CapturedLocation?> captureForObservation({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _lastErrorMessage = null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _lastErrorMessage =
          'Location services are disabled. Enable GPS to tag this observation.';
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _lastErrorMessage =
          'Location permission denied. Observation saved without location.';
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      _lastErrorMessage =
          'Location permission is permanently denied. Enable it in system settings.';
      return null;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(timeout);
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      _lastErrorMessage =
          'Unable to determine location right now. Try again with a clearer sky view.';
      return null;
    }

    final double? latitude = _normalizeLatitude(position.latitude);
    final double? longitude = _normalizeLongitude(position.longitude);
    if (latitude == null || longitude == null) {
      _lastErrorMessage = 'Invalid GPS coordinates received.';
      return null;
    }

    return CapturedLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp ?? DateTime.now(),
    );
  }
}

double? _normalizeLatitude(double value) {
  if (value.isNaN || value.isInfinite) {
    return null;
  }
  return value.clamp(-90.0, 90.0);
}

double? _normalizeLongitude(double value) {
  if (value.isNaN || value.isInfinite) {
    return null;
  }
  double longitude = value;
  while (longitude < -180.0) {
    longitude += 360.0;
  }
  while (longitude > 180.0) {
    longitude -= 360.0;
  }
  return longitude;
}
