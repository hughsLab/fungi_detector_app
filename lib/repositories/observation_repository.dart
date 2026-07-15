import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/observation.dart';
import '../services/auth_service.dart';
import '../services/sync_manager.dart';
import 'firebase_observation_repository.dart';

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
  final StreamController<List<Observation>> _locationStreamController =
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
    await _emitLocationUpdate(observations);
  }

  Future<List<Observation>> loadObservations({bool includeCloud = true}) async {
    final local = await _loadLocalObservations();
    if (!includeCloud || !AuthService.instance.currentState.isOnline) {
      return local;
    }

    try {
      final cloud = await _firebaseRepository.loadCurrentUserObservations();
      final merged = _mergeById(local, cloud);
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
    final observations = await _loadLocalObservations();
    final updated = _mergeById(observations, <Observation>[
      observation.copyWith(syncStatus: 'pending_cloud_sync'),
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
