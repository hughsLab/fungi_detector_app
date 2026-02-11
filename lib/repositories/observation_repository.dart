import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/observation.dart';

abstract class ObservationsRepository {
  Future<void> saveObservation(Observation observation);
  Stream<List<Observation>> watchObservationsWithLocation();
  Future<List<Observation>> getObservationsWithLocation();
}

class ObservationRepository implements ObservationsRepository {
  ObservationRepository._();

  static final ObservationRepository instance = ObservationRepository._();
  final StreamController<List<Observation>> _locationStreamController =
      StreamController<List<Observation>>.broadcast();

  Future<File> _getFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/observations.json');
  }

  Future<List<Observation>> loadObservations() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return [];
    }
    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map((item) => Observation.fromJson(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveObservations(List<Observation> observations) async {
    final file = await _getFile();
    final data = observations.map((item) => item.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
    await _emitLocationUpdate(observations);
  }

  @override
  Future<void> saveObservation(Observation observation) async {
    final observations = await loadObservations();
    observations.add(observation);
    await saveObservations(observations);
  }

  Future<void> addObservation(Observation observation) async {
    await saveObservation(observation);
  }

  Future<void> clearObservations() async {
    final file = await _getFile();
    if (await file.exists()) {
      await file.writeAsString('[]');
    }
    await _emitLocationUpdate(const []);
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
    yield await getObservationsWithLocation();
    yield* _locationStreamController.stream;
  }

  Future<void> _emitLocationUpdate([
    List<Observation>? observations,
  ]) async {
    final list = observations ?? await loadObservations();
    final withLocation = list.where((item) => item.location != null).toList();
    if (!_locationStreamController.isClosed) {
      _locationStreamController.add(withLocation);
    }
  }
}
