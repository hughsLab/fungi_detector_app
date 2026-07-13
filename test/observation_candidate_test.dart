import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';

void main() {
  test('observation candidates round-trip through json', () {
    final observation = Observation(
      id: 'obs-1',
      ownerUsername: 'field_user',
      ownerDisplayName: 'Field User',
      speciesId: 'model_2:0',
      classIndex: 0,
      modelId: 'model_2',
      modelDisplayName: 'Model 2',
      sourceClassId: 0,
      label: 'Agaricus campestris',
      confidence: 0.70,
      top2Label: 'Agaricus xanthodermus',
      top2Confidence: 0.63,
      top2ModelId: 'model_1',
      top2ModelDisplayName: 'Model 1',
      top2SourceClassId: 12,
      candidates: const <ObservationCandidate>[
        ObservationCandidate(
          label: 'Agaricus campestris',
          confidence: 0.70,
          classIndex: 0,
          speciesId: 'model_2:0',
          modelId: 'model_2',
          modelDisplayName: 'Model 2',
          sourceClassId: 0,
        ),
        ObservationCandidate(
          label: 'Agaricus xanthodermus',
          confidence: 0.63,
          classIndex: 12,
          modelId: 'model_1',
          modelDisplayName: 'Model 1',
          sourceClassId: 12,
        ),
        ObservationCandidate(
          label: 'Leucopaxillus eucalyptorum',
          confidence: 0.48,
          classIndex: 34,
          modelId: 'merged',
          modelDisplayName: 'Merged',
          sourceClassId: 34,
        ),
      ],
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 9),
      photoPath: null,
      imageStoragePath: 'users/user-1/observations/obs-1/photo.jpg',
      imageUrl: 'https://example.com/photo.jpg',
      detectionSource: 'offline_model',
      identificationSource: 'offline',
      isPublic: false,
      syncStatus: 'synced',
    );

    final restored = Observation.fromJson(observation.toJson());

    expect(restored.candidates, hasLength(3));
    expect(restored.candidates[0].label, 'Agaricus campestris');
    expect(restored.candidates[1].modelDisplayName, 'Model 1');
    expect(restored.candidates[2].confidence, 0.48);
    expect(
      restored.imageStoragePath,
      'users/user-1/observations/obs-1/photo.jpg',
    );
    expect(restored.imageUrl, 'https://example.com/photo.jpg');
    expect(restored.detectionSource, 'offline_model');
    expect(restored.identificationSource, 'offline');
    expect(restored.ownerUsername, 'field_user');
    expect(restored.ownerDisplayName, 'Field User');
    expect(restored.syncStatus, 'synced');
  });

  test('legacy observation without candidates still parses', () {
    final restored = Observation.fromJson({
      'id': 'legacy',
      'speciesId': '1',
      'classIndex': 1,
      'label': 'Amanita muscaria',
      'confidence': 0.82,
      'createdAt': '2026-06-08T00:00:00.000Z',
    });

    expect(restored.label, 'Amanita muscaria');
    expect(restored.candidates, isEmpty);
    expect(restored.onlineIdentification, isNull);
    expect(restored.onlineAlternatives, isEmpty);
  });

  test('observation json preserves public visibility', () {
    final observation = Observation(
      id: 'public-json',
      speciesId: '1',
      classIndex: 1,
      label: 'Amanita muscaria',
      confidence: 0.82,
      createdAt: DateTime.utc(2026, 7, 8),
      photoPath: null,
      latitude: -42.8821,
      longitude: 147.3272,
      isPublic: true,
    );

    final json = observation.toJson();
    final restored = Observation.fromJson(json);

    expect(json['isPublic'], isTrue);
    expect(restored.isPublic, isTrue);
    expect(restored.location, isNotNull);
  });

  test('legacy detection source maps to identification source', () {
    final restored = Observation.fromJson({
      'id': 'legacy-offline',
      'speciesId': '1',
      'classIndex': 1,
      'label': 'Amanita muscaria',
      'createdAt': '2026-06-08T00:00:00.000Z',
      'detectionSource': 'offline_model',
    });

    expect(restored.identificationSource, 'offline');
  });

  test('firebase observedAt timestamp is used when createdAt is absent', () {
    final restored = Observation.fromJson({
      'id': 'firebase-only-time',
      'speciesId': '1',
      'classIndex': 1,
      'label': 'Amanita muscaria',
      'observedAt': '2026-07-07T10:30:00.000Z',
    });

    expect(restored.createdAt, DateTime.utc(2026, 7, 7, 10, 30));
  });

  test('firebase username aliases parse into owner fields', () {
    final restored = Observation.fromJson({
      'id': 'firebase-user',
      'speciesId': '1',
      'classIndex': 1,
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'username': 'field_user',
      'displayName': 'Field User',
    });

    expect(restored.ownerUsername, 'field_user');
    expect(restored.ownerDisplayName, 'Field User');
  });

  test('firebase nested latitude and longitude parse into location', () {
    final restored = Observation.fromJson({
      'id': 'nested-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'location': {
        'latitude': -42.8821,
        'longitude': 147.3272,
      },
    });

    expect(restored.location?.latitude, -42.8821);
    expect(restored.location?.longitude, 147.3272);
  });

  test('firebase flat latitude and lng parse into location', () {
    final restored = Observation.fromJson({
      'id': 'flat-lng-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'latitude': '-41.4545',
      'lng': '145.9707',
    });

    expect(restored.location?.latitude, -41.4545);
    expect(restored.location?.longitude, 145.9707);
  });

  test('firebase nested lat and lng parse into location', () {
    final restored = Observation.fromJson({
      'id': 'nested-lat-lng-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'location': {
        'lat': -35.2809,
        'lng': 149.13,
      },
    });

    expect(restored.location?.latitude, -35.2809);
    expect(restored.location?.longitude, 149.13);
  });

  test('firebase GeoPoint-like location parses into location', () {
    final restored = Observation.fromJson({
      'id': 'geopoint-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'location': _FakeGeoPoint(-37.8136, 144.9631),
    });

    expect(restored.location?.latitude, -37.8136);
    expect(restored.location?.longitude, 144.9631);
  });

  test('firebase public coordinates can provide map location', () {
    final restored = Observation.fromJson({
      'id': 'public-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'publicLat': -34.9285,
      'publicLng': 138.6007,
      'isPublic': true,
    });

    expect(restored.location?.latitude, -34.9285);
    expect(restored.location?.longitude, 138.6007);
  });

  test('invalid firebase coordinates do not create map location', () {
    final restored = Observation.fromJson({
      'id': 'invalid-location',
      'speciesId': '1',
      'label': 'Amanita muscaria',
      'createdAt': '2026-07-07T10:30:00.000Z',
      'latitude': 120,
      'longitude': 240,
    });

    expect(restored.location, isNull);
  });
}

class _FakeGeoPoint {
  final double latitude;
  final double longitude;

  const _FakeGeoPoint(this.latitude, this.longitude);
}
