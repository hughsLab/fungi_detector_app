import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';
import 'package:realtime_detection_app/repositories/observation_repository.dart';

void main() {
  test('observation repository does not use internal JSON storage', () {
    final source = File(
      'lib/repositories/observation_repository.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('observations.json')));
    expect(source, isNot(contains('path_provider')));
    expect(source, isNot(contains('dart:convert')));
  });

  test('firebase public map feed uses top-level observations collection', () {
    final source = File(
      'lib/repositories/firebase_observation_repository.dart',
    ).readAsStringSync();

    expect(source, contains("_firestore.collection('observations')"));
    expect(source, contains("where('isPublic', isEqualTo: true)"));
    expect(source, contains("'ownerUid': userId"));
    expect(source, contains("'isPublic': observation.isPublic"));
    expect(source, isNot(contains("collection('users')")));
    expect(source, isNot(contains("users/\$uid/observations")));
  });

  test('new observation saves use settings public sharing value', () {
    final manualSaveSource = File(
      'lib/screens/save_observation_screen.dart',
    ).readAsStringSync();
    final offlineSaveSource = File(
      'lib/screens/detection_result_screen.dart',
    ).readAsStringSync();
    final onlineSaveSource = File(
      'lib/screens/online_identification_result_screen.dart',
    ).readAsStringSync();

    expect(
      manualSaveSource,
      contains('isPublic: settings.shareObservationsOnPublicMap'),
    );
    expect(
      offlineSaveSource,
      contains('isPublic: settings.shareObservationsOnPublicMap'),
    );
    expect(
      onlineSaveSource,
      contains('isPublic: settings.shareObservationsOnPublicMap'),
    );
  });

  test('visible map observations use Firebase pins only', () {
    final publicPinned = _observation(
      id: 'public-pin',
      createdAt: DateTime.utc(2026, 7, 7, 10),
      latitude: -41.4545,
      longitude: 145.9707,
      isPublic: true,
      ownerUsername: 'field_user',
    );
    final myPinned = _observation(
      id: 'my-pin',
      createdAt: DateTime.utc(2026, 7, 7, 9),
      latitude: -42.8821,
      longitude: 147.3272,
      ownerUsername: 'me',
    );

    final merged = ObservationRepository.mergeFirebaseMapObservationLists(
      public: [publicPinned],
      mine: [myPinned],
    );

    expect(merged.map((observation) => observation.id), [
      'public-pin',
      'my-pin',
    ]);
    expect(merged.first.ownerUsername, 'field_user');
  });

  test('visible map observations include pins without photos', () {
    final publicPinned = _observation(
      id: 'public-pin-no-photo',
      createdAt: DateTime.utc(2026, 7, 7, 10),
      latitude: -41.4545,
      longitude: 145.9707,
      isPublic: true,
    );

    final merged = ObservationRepository.mergeFirebaseMapObservationLists(
      public: [publicPinned],
      mine: const <Observation>[],
    );

    expect(merged, hasLength(1));
    expect(merged.single.photoPath, isNull);
    expect(merged.single.location, isNotNull);
  });

  test('visible map observations keep the newest duplicate by id', () {
    final olderPublic = _observation(
      id: 'same-pin',
      createdAt: DateTime.utc(2026, 7, 7, 9),
      updatedAt: DateTime.utc(2026, 7, 7, 9),
      latitude: -42.8821,
      longitude: 147.3272,
      label: 'Older local',
    );
    final newerCloud = _observation(
      id: 'same-pin',
      createdAt: DateTime.utc(2026, 7, 7, 9),
      updatedAt: DateTime.utc(2026, 7, 7, 10),
      latitude: -42.8821,
      longitude: 147.3272,
      label: 'Newer cloud',
    );

    final merged = ObservationRepository.mergeFirebaseMapObservationLists(
      public: [olderPublic],
      mine: [newerCloud],
    );

    expect(merged, hasLength(1));
    expect(merged.single.label, 'Newer cloud');
  });
}

Observation _observation({
  required String id,
  required DateTime createdAt,
  DateTime? updatedAt,
  double? latitude,
  double? longitude,
  bool isPublic = false,
  String label = 'Agaricus campestris',
  String? ownerUsername,
}) {
  return Observation(
    id: id,
    userId: ownerUsername == null ? null : 'user-$ownerUsername',
    ownerUsername: ownerUsername,
    speciesId: 'model_2:0',
    classIndex: 0,
    label: label,
    confidence: 0.8,
    createdAt: createdAt,
    updatedAt: updatedAt,
    photoPath: null,
    latitude: latitude,
    longitude: longitude,
    isPublic: isPublic,
  );
}
