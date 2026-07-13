import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/services/country_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns Australia when no cached or detected country is available',
      () async {
    final service = CountryLocationService(
      positionResolver: () async => null,
      reverseGeocoder: (_, _) async => null,
    );

    expect(
      await service.getCurrentCountryOrFallback(),
      CountryLocationService.fallbackCountry,
    );
  });

  test('returns cached country before detecting a fresh value', () async {
    SharedPreferences.setMockInitialValues({
      CountryLocationService.cachedCountryKey: 'New Zealand',
    });
    final service = CountryLocationService(
      positionResolver: () async => const CountryCoordinates(
        latitude: -42.8821,
        longitude: 147.3272,
      ),
      reverseGeocoder: (_, _) async => 'Australia',
    );

    expect(await service.getCachedCountryOrFallback(), 'New Zealand');
    expect(await service.getCurrentCountryOrFallback(), 'Australia');
  });

  test('stores detected country in local preferences', () async {
    final service = CountryLocationService(
      positionResolver: () async => const CountryCoordinates(
        latitude: -42.8821,
        longitude: 147.3272,
      ),
      reverseGeocoder: (_, _) async => 'Australia',
    );

    expect(await service.getCurrentCountryOrFallback(), 'Australia');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(CountryLocationService.cachedCountryKey),
      'Australia',
    );
  });
}
