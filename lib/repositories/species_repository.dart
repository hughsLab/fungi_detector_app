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
    String raw;
    try {
      raw = await rootBundle.loadString('assets/data/species.json');
    } catch (_) {
      raw = await rootBundle.loadString('assets/data/species_tas.json');
    }
    final decoded = jsonDecode(raw);
    final List<dynamic> data;
    if (decoded is List<dynamic>) {
      data = decoded;
    } else if (decoded is Map<String, dynamic> &&
        decoded['cards'] is List<dynamic>) {
      data = decoded['cards'] as List<dynamic>;
    } else {
      throw FormatException('Unexpected species data format');
    }
    final _TasColloquialMaps tasColloquial = await _loadTasColloquialMaps();
    _cache = data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final Map<String, dynamic> enriched = Map<String, dynamic>.from(item);
          final String existingColloquial =
              enriched['colloquialName']?.toString().trim() ?? '';
          if (existingColloquial.isEmpty) {
            final String id = (enriched['id'] ??
                        enriched['speciesId'] ??
                        enriched['species_id'])
                    ?.toString()
                    .trim() ??
                '';
            final String normalizedScientific = _normalizeForLookup(
              enriched['scientificName']?.toString(),
            );
            final String? fallback = (id.isNotEmpty ? tasColloquial.byId[id] : null) ??
                tasColloquial.byScientificName[normalizedScientific];
            if (fallback != null && fallback.trim().isNotEmpty) {
              enriched['colloquialName'] = fallback.trim();
            }
          }
          return Species.fromJson(enriched);
        })
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
      final colloquial = item.colloquialName?.toLowerCase() ?? '';
      return item.scientificName.toLowerCase().contains(normalized) ||
          common.contains(normalized) ||
          colloquial.contains(normalized);
    }).toList();
  }

  String _normalizeForLookup(String? value) => value?.trim().toLowerCase() ?? '';

  Future<_TasColloquialMaps> _loadTasColloquialMaps() async {
    try {
      final String raw = await rootBundle.loadString('assets/data/species_tas.json');
      final dynamic decoded = jsonDecode(raw);
      final List<dynamic> cards = (decoded is Map<String, dynamic> &&
              decoded['cards'] is List<dynamic>)
          ? decoded['cards'] as List<dynamic>
          : const <dynamic>[];

      final Map<String, String> byId = <String, String>{};
      final Map<String, String> byScientificName = <String, String>{};
      for (final dynamic item in cards) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final String colloquial = item['colloquialName']?.toString().trim() ?? '';
        if (colloquial.isEmpty) {
          continue;
        }
        final String id = item['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          byId[id] = colloquial;
        }
        final String normalizedScientific = _normalizeForLookup(
          item['scientificName']?.toString(),
        );
        if (normalizedScientific.isNotEmpty &&
            !byScientificName.containsKey(normalizedScientific)) {
          byScientificName[normalizedScientific] = colloquial;
        }
      }
      return _TasColloquialMaps(byId: byId, byScientificName: byScientificName);
    } catch (_) {
      return const _TasColloquialMaps(
        byId: <String, String>{},
        byScientificName: <String, String>{},
      );
    }
  }
}

class _TasColloquialMaps {
  final Map<String, String> byId;
  final Map<String, String> byScientificName;

  const _TasColloquialMaps({
    required this.byId,
    required this.byScientificName,
  });
}
