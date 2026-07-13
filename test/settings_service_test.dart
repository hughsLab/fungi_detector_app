import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/services/settings_service.dart';

void main() {
  test('settings default public map sharing on', () {
    final settings = AppSettings.defaults();

    expect(settings.shareObservationsOnPublicMap, isTrue);
    expect(settings.showUsernameOnPublicObservations, isTrue);
  });

  test('settings sharing toggles serialize and restore', () {
    final settings = AppSettings.defaults().copyWith(
      shareObservationsOnPublicMap: false,
      showUsernameOnPublicObservations: false,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.shareObservationsOnPublicMap, isFalse);
    expect(restored.showUsernameOnPublicObservations, isFalse);
  });

  test('legacy settings default to public sharing', () {
    final restored = AppSettings.fromJson({
      'confidenceThreshold': 0.7,
      'locationTaggingEnabled': true,
    });

    expect(restored.shareObservationsOnPublicMap, isTrue);
    expect(restored.showUsernameOnPublicObservations, isTrue);
  });
}
