import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CountryPositionResolver = Future<CountryCoordinates?> Function();
typedef CountryReverseGeocoder = Future<String?> Function(
  double latitude,
  double longitude,
);

class CountryCoordinates {
  final double latitude;
  final double longitude;

  const CountryCoordinates({
    required this.latitude,
    required this.longitude,
  });
}

class CountryLocationService {
  CountryLocationService({
    Future<SharedPreferences> Function()? preferencesProvider,
    CountryPositionResolver? positionResolver,
    CountryReverseGeocoder? reverseGeocoder,
  })  : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance,
        _positionResolver = positionResolver,
        _reverseGeocoder = reverseGeocoder;

  CountryLocationService._default()
      : _preferencesProvider = SharedPreferences.getInstance,
        _positionResolver = null,
        _reverseGeocoder = null;

  static final CountryLocationService instance =
      CountryLocationService._default();

  static const String fallbackCountry = 'Australia';
  static const String cachedCountryKey = 'cached_country_name';

  static const String _locationPromptedKey =
      'country_location_permission_prompted';
  static const String _checkedAtKey = 'cached_country_checked_at';
  static const Duration _refreshInterval = Duration(hours: 24);

  final Future<SharedPreferences> Function() _preferencesProvider;
  final CountryPositionResolver? _positionResolver;
  final CountryReverseGeocoder? _reverseGeocoder;

  Future<String> getCachedCountryOrFallback() async {
    final prefs = await _preferencesProvider();
    return _cachedCountry(prefs) ?? fallbackCountry;
  }

  Future<String> getCurrentCountryOrFallback() async {
    final prefs = await _preferencesProvider();
    final cachedCountry = _cachedCountry(prefs);
    if (cachedCountry != null && !_refreshDue(prefs)) {
      return cachedCountry;
    }

    final detectedCountry = await _detectCountry(prefs);
    await prefs.setString(_checkedAtKey, DateTime.now().toIso8601String());

    if (detectedCountry != null) {
      await prefs.setString(cachedCountryKey, detectedCountry);
      return detectedCountry;
    }

    return cachedCountry ?? fallbackCountry;
  }

  Future<String?> _detectCountry(SharedPreferences prefs) async {
    try {
      final coordinates = _positionResolver == null
          ? await _resolveDevicePosition(prefs)
          : await _positionResolver();
      if (coordinates == null) {
        return null;
      }

      final country = _reverseGeocoder == null
          ? await _reverseGeocodeCountry(
              coordinates.latitude,
              coordinates.longitude,
            )
          : await _reverseGeocoder(
              coordinates.latitude,
              coordinates.longitude,
            );
      return _cleanCountry(country);
    } catch (_) {
      return null;
    }
  }

  Future<CountryCoordinates?> _resolveDevicePosition(
    SharedPreferences prefs,
  ) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final alreadyPrompted = prefs.getBool(_locationPromptedKey) ?? false;
      if (alreadyPrompted) {
        return null;
      }
      await prefs.setBool(_locationPromptedKey, true);
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 6));
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      return null;
    }

    final latitude = _normalizeLatitude(position.latitude);
    final longitude = _normalizeLongitude(position.longitude);
    if (latitude == null || longitude == null) {
      return null;
    }

    return CountryCoordinates(latitude: latitude, longitude: longitude);
  }

  Future<String?> _reverseGeocodeCountry(
    double latitude,
    double longitude,
  ) async {
    final placemarks = await placemarkFromCoordinates(
      latitude,
      longitude,
    ).timeout(const Duration(seconds: 6));
    for (final placemark in placemarks) {
      final country = _cleanCountry(placemark.country);
      if (country != null) {
        return country;
      }
    }
    return null;
  }

  String? _cachedCountry(SharedPreferences prefs) {
    return _cleanCountry(prefs.getString(cachedCountryKey));
  }

  bool _refreshDue(SharedPreferences prefs) {
    final checkedAtRaw = prefs.getString(_checkedAtKey);
    final checkedAt =
        checkedAtRaw == null ? null : DateTime.tryParse(checkedAtRaw);
    if (checkedAt == null) {
      return true;
    }
    return DateTime.now().difference(checkedAt) >= _refreshInterval;
  }

  String? _cleanCountry(String? value) {
    final country = value?.trim();
    if (country == null || country.isEmpty) {
      return null;
    }
    return country;
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
  var longitude = value;
  while (longitude < -180.0) {
    longitude += 360.0;
  }
  while (longitude > 180.0) {
    longitude -= 360.0;
  }
  return longitude;
}
