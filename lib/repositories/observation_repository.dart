import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/observation.dart';

class ObservationRepository {
  ObservationRepository._();

  static final ObservationRepository instance = ObservationRepository._();

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
  }

  Future<void> addObservation(Observation observation) async {
    final observations = await loadObservations();
    observations.add(observation);
    await saveObservations(observations);
  }

  Future<void> clearObservations() async {
    final file = await _getFile();
    if (await file.exists()) {
      await file.writeAsString('[]');
    }
  }
}
