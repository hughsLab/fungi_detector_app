import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/species.dart';

class SpeciesRepository {
  SpeciesRepository._();

  static final SpeciesRepository instance = SpeciesRepository._();

  List<Species>? _cache;

  Future<List<Species>> loadSpecies() async {
    if (_cache != null) {
      return _cache!;
    }
    final raw = await rootBundle.loadString('assets/data/species_tas.json');
    final data = jsonDecode(raw) as List<dynamic>;
    _cache = data
        .whereType<Map<String, dynamic>>()
        .map((item) => Species.fromJson(item))
        .toList();
    return _cache!;
  }

  Future<Species?> getById(String id) async {
    final species = await loadSpecies();
    try {
      return species.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Species>> search(String query) async {
    final species = await loadSpecies();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return species;
    }
    return species.where((item) {
      final common = item.commonName?.toLowerCase() ?? '';
      return item.scientificName.toLowerCase().contains(normalized) ||
          common.contains(normalized);
    }).toList();
  }
}
