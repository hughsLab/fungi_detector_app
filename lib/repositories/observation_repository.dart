import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/observation.dart';
import '../services/settings_service.dart';
import 'firebase_observation_repository.dart';
import 'user_profile_repository.dart';

abstract class ObservationsRepository {
  Future<void> saveObservation(Observation observation);
  Stream<List<Observation>> streamPublicObservations({int limit = 300});
  Stream<List<Observation>> streamMyObservations({int limit = 300});
  Stream<List<Observation>> streamVisibleMapObservations({int limit = 300});
  Stream<List<Observation>> watchObservationsWithLocation();
  Future<List<Observation>> getObservationsWithLocation();
}

class ObservationRepository implements ObservationsRepository {
  ObservationRepository._();

  static final ObservationRepository instance = ObservationRepository._();
  final FirebaseObservationRepository _firebaseRepository =
      FirebaseObservationRepository.instance;
  final UserProfileRepository _userProfileRepository =
      UserProfileRepository.instance;
  final SettingsService _settingsService = SettingsService.instance;

  Future<List<Observation>> loadObservations({bool includeCloud = true}) async {
    if (!includeCloud) {
      return const <Observation>[];
    }

    try {
      return await _firebaseRepository.loadCurrentUserObservations();
    } catch (e, st) {
      debugPrint('FIREBASE_OBSERVATION: cloud load failed: $e');
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
      return const <Observation>[];
    }
  }

  @override
  Stream<List<Observation>> streamPublicObservations({int limit = 300}) {
    return _firebaseRepository.streamPublicObservations(limit: limit).map(
          (items) => items.where((item) => item.location != null).toList(),
        );
  }

  @override
  Stream<List<Observation>> streamMyObservations({int limit = 300}) {
    return _firebaseRepository.streamMyObservations(limit: limit);
  }

  @override
  Stream<List<Observation>> streamVisibleMapObservations({int limit = 300}) {
    late final StreamController<List<Observation>> controller;
    StreamSubscription<List<Observation>>? publicSubscription;
    StreamSubscription<List<Observation>>? mySubscription;
    var publicObservations = const <Observation>[];
    var myObservations = const <Observation>[];

    void emitMerged() {
      if (!controller.isClosed) {
        controller.add(
          mergeFirebaseMapObservationLists(
            public: publicObservations,
            mine: myObservations,
          ),
        );
      }
    }

    controller = StreamController<List<Observation>>(
      onListen: () {
        publicSubscription = streamPublicObservations(limit: limit).listen(
          (items) {
            publicObservations = items;
            emitMerged();
          },
          onError: controller.addError,
        );
        mySubscription = streamMyObservations(limit: limit).listen(
          (items) {
            myObservations = items;
            emitMerged();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await publicSubscription?.cancel();
        await mySubscription?.cancel();
      },
    );

    return controller.stream;
  }

  @visibleForTesting
  static List<Observation> mergeFirebaseMapObservationLists({
    required List<Observation> public,
    required List<Observation> mine,
  }) {
    final byId = <String, Observation>{};

    void addIfMapped(Observation observation) {
      if (observation.location == null) {
        return;
      }
      final existing = byId[observation.id];
      if (existing == null) {
        byId[observation.id] = observation;
        return;
      }
      final existingUpdated = existing.updatedAt ?? existing.createdAt;
      final incomingUpdated = observation.updatedAt ?? observation.createdAt;
      if (incomingUpdated.isAfter(existingUpdated)) {
        byId[observation.id] = observation;
      }
    }

    for (final observation in public) {
      addIfMapped(observation);
    }
    for (final observation in mine) {
      addIfMapped(observation);
    }

    final merged = byId.values.toList();
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  @override
  Future<void> saveObservation(Observation observation) async {
    final preparedObservation = await _withAllowedPublicVisibility(observation);
    final cloudResult = await _firebaseRepository.saveObservation(
      preparedObservation,
    );
    if (cloudResult.saved) {
      return;
    }

    if (cloudResult.status == FirebaseObservationSaveStatus.skippedNoUser) {
      throw StateError('Sign in before saving Firebase observations.');
    }

    throw cloudResult.error ?? StateError('Firebase observation save failed.');
  }

  Future<void> addObservation(Observation observation) async {
    await saveObservation(observation);
  }

  Future<void> clearObservations() async {
    debugPrint(
      'FIREBASE_OBSERVATION: clearObservations skipped; observations are '
      'Firebase-only and local JSON storage is no longer used.',
    );
  }

  Future<void> updateObservationDetails(
    String observationId, {
    String? notes,
    String? locationLabel,
    bool? isPublic,
    double? publicLat,
    double? publicLng,
  }) async {
    try {
      await _firebaseRepository.updateObservationDetails(
        observationId,
        notes: notes,
        locationLabel: locationLabel,
        isPublic: isPublic,
        publicLat: publicLat,
        publicLng: publicLng,
      );
    } catch (e, st) {
      debugPrint('FIREBASE_OBSERVATION: cloud update failed: $e');
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
    }
  }

  Future<void> deleteObservation(
    String observationId, {
    bool deleteCloudPhoto = true,
  }) async {
    try {
      await _firebaseRepository.deleteObservation(
        observationId,
        deletePhoto: deleteCloudPhoto,
      );
    } catch (e, st) {
      debugPrint('FIREBASE_OBSERVATION: cloud delete failed: $e');
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
    }
  }

  @override
  Future<List<Observation>> getObservationsWithLocation() async {
    final observations = await loadObservations();
    return observations.where((item) => item.location != null).toList();
  }

  Future<List<Observation>> getAllWithLocation() async {
    return getObservationsWithLocation();
  }

  @override
  Stream<List<Observation>> watchObservationsWithLocation() async* {
    yield* streamMyObservations().map(
      (items) => items.where((item) => item.location != null).toList(),
    );
  }

  Future<Observation> _withAllowedPublicVisibility(
    Observation observation,
  ) async {
    if (!observation.isPublic) {
      return observation;
    }
    try {
      final settings = await _settingsService.loadSettings();
      final profile = settings.showUsernameOnPublicObservations
          ? await _userProfileRepository.ensureUserProfile()
          : null;
      if (settings.showUsernameOnPublicObservations &&
          profile?.hasUsername == true) {
        return observation.copyWith(
          ownerUsername: profile?.username,
          ownerDisplayName: profile?.displayName,
        );
      }
    } catch (e, st) {
      debugPrint('FIREBASE_OBSERVATION: username check failed: $e');
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
    }
    return observation;
  }
}
