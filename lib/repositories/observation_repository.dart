import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/observation.dart';
import '../services/auth_service.dart';
import '../services/sync_manager.dart';
import 'firebase_observation_repository.dart';
import 'user_profile_repository.dart';

abstract class ObservationsRepository {
  Future<void> saveObservation(Observation observation);
  Stream<List<Observation>> watchObservationChanges();
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
  final StreamController<List<Observation>> _locationStreamController =
      StreamController<List<Observation>>.broadcast();
  final StreamController<List<Observation>> _observationStreamController =
      StreamController<List<Observation>>.broadcast();

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/observations.json');
  }

  Future<List<Observation>> _loadLocalObservations() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return <Observation>[];
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(Observation.fromJson)
          .toList();
    } catch (e, st) {
      debugPrint('LOCAL_OBSERVATION: load failed: $e');
      debugPrintStack(stackTrace: st, label: 'LOCAL_OBSERVATION');
      return <Observation>[];
    }
  }

  Future<void> _saveLocalObservations(List<Observation> observations) async {
    final file = await _getFile();
    await file.writeAsString(
      jsonEncode(observations.map((item) => item.toJson()).toList()),
    );
    if (!_observationStreamController.isClosed) {
      _observationStreamController.add(
        List<Observation>.unmodifiable(observations),
      );
    }
    await _emitLocationUpdate(observations);
  }

  @override
  Stream<List<Observation>> watchObservationChanges() {
    return _observationStreamController.stream;
  }

  Future<List<Observation>> loadObservations({bool includeCloud = true}) async {
    var local = await _loadLocalObservations();
    final localWithOwner = await _attachCurrentUserTo(local);
    if (!identical(localWithOwner, local)) {
      local = localWithOwner;
      await _saveLocalObservations(local);
    }
    if (!includeCloud || !AuthService.instance.currentState.isOnline) {
      return local;
    }

    try {
      final cloud = await _firebaseRepository.loadCurrentUserObservations();
      // A save may finish while the cloud request is in flight. Re-read the
      // device file so that refresh cannot overwrite that new observation.
      final latestLocal = await _loadLocalObservations();
      final merged = _mergeById(latestLocal, cloud);
      if (cloud.isNotEmpty) {
        await _saveLocalObservations(merged);
      }
      return merged;
    } catch (e, st) {
      debugPrint('FIREBASE_OBSERVATION: cloud load failed: $e');
      debugPrintStack(stackTrace: st, label: 'FIREBASE_OBSERVATION');
      return local;
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
    StreamSubscription<List<Observation>>? localSubscription;
    var publicObservations = const <Observation>[];
    var myObservations = const <Observation>[];
    var localObservations = const <Observation>[];

    void emitMerged() {
      if (!controller.isClosed) {
        controller.add(
          mergeFirebaseMapObservationLists(
            public: publicObservations,
            mine: myObservations,
            local: localObservations,
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
        localSubscription = watchObservationsWithLocation().listen(
          (items) {
            localObservations = items;
            emitMerged();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await publicSubscription?.cancel();
        await mySubscription?.cancel();
        await localSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  @visibleForTesting
  static List<Observation> mergeFirebaseMapObservationLists({
    required List<Observation> public,
    required List<Observation> mine,
    List<Observation> local = const <Observation>[],
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
    for (final observation in local) {
      addIfMapped(observation);
    }

    final merged = byId.values.toList();
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  @override
  Future<void> saveObservation(Observation observation) async {
    if (!await _hasSavedPhoto(observation)) {
      throw StateError('Every observation must include a saved photo.');
    }
    final file = await _getFile();
    if (kDebugMode) {
      debugPrint(
        'LOCAL_OBSERVATION: save started mode='
        '${observation.detectionSource == "offline_model" ? "offline" : "other"} '
        'id=${observation.id} label=${observation.label} '
        'detectionSource=${observation.detectionSource ?? "-"} '
        'identificationSource=${observation.identificationSource ?? "-"} '
        'hasLocation=${observation.location != null} '
        'isPublic=${observation.isPublic} cloudSyncEnabled=true path=${file.path}',
      );
    }
    final localObservation = await _attachCurrentUser(observation);
    final observations = await _loadLocalObservations();
    final updated = _mergeById(observations, <Observation>[
      localObservation.copyWith(syncStatus: 'pending_cloud_sync'),
    ]);
    await _saveLocalObservations(updated);
    if (kDebugMode) {
      debugPrint(
        'LOCAL_OBSERVATION: save succeeded id=${observation.id} '
        'count=${updated.length} syncStatus=pending_cloud_sync',
      );
    }
    final queueLength =
        await SyncManager.instance.enqueueObservationUpsert(observation);
    if (kDebugMode) {
      debugPrint(
        'LOCAL_OBSERVATION: queuedForSync=true id=${observation.id} '
        'queueLength=$queueLength',
      );
    }
  }

  Future<bool> _hasSavedPhoto(Observation observation) async {
    for (final value in <String?>[
      observation.photoPath,
      observation.imageUrl,
    ]) {
      final path = value?.trim();
      if (path == null || path.isEmpty) continue;
      if (path.startsWith('https://') || path.startsWith('http://')) {
        return true;
      }
      if (await File(path).exists()) {
        return true;
      }
    }
    return false;
  }

  Future<Observation> _attachCurrentUser(Observation observation) async {
    final observations = await _attachCurrentUserTo(<Observation>[observation]);
    return observations.single;
  }

  Future<List<Observation>> _attachCurrentUserTo(
    List<Observation> observations,
  ) async {
    if (observations.isEmpty) {
      return observations;
    }
    final uid = AuthService.instance.currentState.uid;
    if (uid == null || uid.trim().isEmpty) {
      return observations;
    }
    final ownerAlreadyAttached = observations.every(
      (observation) =>
          observation.userId != null &&
          (observation.userId != uid || observation.observerName != null),
    );
    if (ownerAlreadyAttached) {
      return observations;
    }
    try {
      final profile = await _userProfileRepository.getCurrentUserProfile();
      var changed = false;
      final updated = observations.map((observation) {
        if (observation.userId != null && observation.userId != uid) {
          return observation;
        }
        final needsUpdate = observation.userId != uid ||
            (observation.ownerUsername == null && profile?.username != null) ||
            (observation.ownerDisplayName == null &&
                profile?.displayName != null);
        if (!needsUpdate) {
          return observation;
        }
        changed = true;
        return observation.copyWith(
          userId: uid,
          ownerUsername: profile?.username,
          ownerDisplayName: profile?.displayName,
        );
      }).toList(growable: false);
      return changed ? updated : observations;
    } catch (e) {
      debugPrint('LOCAL_OBSERVATION: owner lookup failed: $e');
      var changed = false;
      final updated = observations.map((observation) {
        if (observation.userId != null) {
          return observation;
        }
        changed = true;
        return observation.copyWith(userId: uid);
      }).toList(growable: false);
      return changed ? updated : observations;
    }
  }

  Future<void> addObservation(Observation observation) async {
    await saveObservation(observation);
  }

  Future<void> clearObservations() async {
    await _saveLocalObservations(const <Observation>[]);
    await SyncManager.instance.enqueueObservationsClear();
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
    final observations = await loadObservations(includeCloud: false);
    return observations.where((item) => item.location != null).toList();
  }

  Future<List<Observation>> getAllWithLocation() async {
    return getObservationsWithLocation();
  }

  @override
  Stream<List<Observation>> watchObservationsWithLocation() async* {
    yield await getObservationsWithLocation();
    yield* _locationStreamController.stream;
  }

  List<Observation> _mergeById(
    List<Observation> existing,
    List<Observation> incoming,
  ) {
    final byId = <String, Observation>{
      for (final observation in existing) observation.id: observation,
    };
    for (final observation in incoming) {
      final current = byId[observation.id];
      final currentUpdated = current?.updatedAt ?? current?.createdAt;
      final incomingUpdated = observation.updatedAt ?? observation.createdAt;
      if (current == null ||
          currentUpdated == null ||
          !incomingUpdated.isBefore(currentUpdated)) {
        byId[observation.id] = observation;
      }
    }
    final merged = byId.values.toList();
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  Future<void> _emitLocationUpdate([List<Observation>? observations]) async {
    final list = observations ?? await _loadLocalObservations();
    if (!_locationStreamController.isClosed) {
      _locationStreamController.add(
        list.where((item) => item.location != null).toList(),
      );
    }
  }

}
