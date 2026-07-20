import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';
import 'package:realtime_detection_app/repositories/observation_repository.dart';

void main() {
  test('observation repository is local-first and queues cloud sync', () {
    final source = File(
      'lib/repositories/observation_repository.dart',
    ).readAsStringSync();

    expect(source, contains('observations.json'));
    expect(source, contains('path_provider'));
    expect(source, contains('enqueueObservationUpsert'));
    expect(source, contains('pending_cloud_sync'));
    expect(source, contains('watchObservationChanges'));
    expect(source, contains('_observationStreamController.add'));
  });

  test('saved observations screen listens for repository changes', () {
    final source = File(
      'lib/screens/observations_screen.dart',
    ).readAsStringSync();

    expect(source, contains('.watchObservationChanges()'));
    expect(source, contains('_handleObservationChanges'));
    expect(source, contains('_observationSubscription?.cancel()'));
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

  test('offline and online observations share the same cloud queue', () {
    final repositorySource = File(
      'lib/repositories/observation_repository.dart',
    ).readAsStringSync();
    final syncSource = File(
      'lib/services/sync_manager.dart',
    ).readAsStringSync();

    expect(repositorySource, contains('enqueueObservationUpsert(observation)'));
    expect(syncSource, contains('Observation.fromJson(payload)'));
    expect(syncSource, isNot(contains("onlineIdentification == true")));
    expect(syncSource, isNot(contains("detectionSource == 'offline_model'")));
  });

  test('every observation requires a photo and uploads it to storage', () {
    final localSource = File(
      'lib/repositories/observation_repository.dart',
    ).readAsStringSync();
    final firebaseSource = File(
      'lib/repositories/firebase_observation_repository.dart',
    ).readAsStringSync();
    final manualSaveSource = File(
      'lib/screens/save_observation_screen.dart',
    ).readAsStringSync();
    final firebaseConfig = File('firebase.json').readAsStringSync();
    final storageRules = File('storage.rules').readAsStringSync();

    expect(localSource, contains('_hasSavedPhoto(observation)'));
    expect(manualSaveSource, contains('ImageSource.camera'));
    expect(manualSaveSource, contains('ImageSource.gallery'));
    expect(firebaseSource, contains('await ref.putFile('));
    expect(firebaseSource, contains('cloud_photo_failed'));
    expect(firebaseConfig, contains('"rules": "storage.rules"'));
    expect(storageRules, contains('request.auth.uid == uid'));
  });

  test('sync completion preserves mutations queued during an active sync', () {
    final source = File('lib/services/sync_manager.dart').readAsStringSync();

    expect(source, contains('completeAttempt('));
    expect(source, contains('new mutations arrived during sync'));
    expect(source, isNot(contains('_queueStore.replace(remaining)')));
  });

  test('visible map observations merge Firebase and local pins', () {
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
      local: [
        _observation(
          id: 'local-pin',
          createdAt: DateTime.utc(2026, 7, 7, 8),
          latitude: -43.1,
          longitude: 147.1,
        ),
      ],
    );

    expect(merged.map((observation) => observation.id), [
      'public-pin',
      'my-pin',
      'local-pin',
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

  test('map uses fungi markers coloured by species rarity', () {
    final source = File('lib/screens/map_screen.dart').readAsStringSync();

    expect(source, contains('_FungiMapMarker('));
    expect(source, contains('_rarityColor(rarity.level)'));
    expect(source, contains("'Fungi rarity'"));
    expect(source, isNot(contains('Icons.location_on,')));
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
