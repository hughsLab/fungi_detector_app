import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/species.dart';

class SpeciesRepository {
  SpeciesRepository._();

  static final SpeciesRepository instance = SpeciesRepository._();

  List<Species>? _cache;
  Map<String, Species>? _byModelClassCache;
  Map<String, Species>? _byScientificNameCache;
  Map<String, Species>? _byCanonicalNameCache;

  static const String model1Id = 'model_1';
  static const String model2Id = 'model_2';

  Future<List<Species>> loadSpecies() async {
    if (_cache != null) {
      return _cache!;
    }
    final _TasColloquialMaps tasColloquial = await _loadTasColloquialMaps();
    final List<Species> model1Species = await _loadSpeciesFromAsset(
      assetPath: 'assets/data/species.json',
      fallbackAssetPath: 'assets/data/species_tas.json',
      modelId: model1Id,
      namespaceIds: false,
      colloquialFallback: tasColloquial,
    );
    final List<Species> model2Species = await _loadSpeciesFromAsset(
      assetPath: 'assets/data/species_model2_136_app_form.json',
      modelId: model2Id,
      namespaceIds: true,
      colloquialFallback: tasColloquial,
    );
    _cache = <Species>[...model1Species, ...model2Species];
    _byModelClassCache = {
      for (final item in _cache!)
        if (item.modelId != null && item.sourceClassId != null)
          _modelClassKey(item.modelId!, item.sourceClassId!): item,
    };
    _byScientificNameCache = _buildNameCache(
      _cache!,
      (species) => species.scientificName,
    );
    _byCanonicalNameCache = _buildNameCache(
      _cache!,
      (species) => species.canonicalName,
    );
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

  Future<Species?> getByModelClass(String? modelId, int? sourceClassId) async {
    if (modelId == null || sourceClassId == null) {
      return null;
    }
    await loadSpecies();
    return _byModelClassCache?[_modelClassKey(modelId, sourceClassId)];
  }

  Future<Species?> getByScientificName(String name) async {
    final normalized = _normalizeForLookup(name);
    if (normalized.isEmpty) {
      return null;
    }
    await loadSpecies();
    return _byScientificNameCache?[normalized] ??
        _byCanonicalNameCache?[normalized];
  }

  Future<Species?> matchSpecies({
    String? speciesId,
    String? modelId,
    int? sourceClassId,
    String? scientificName,
    String? label,
  }) async {
    final species = await loadSpecies();
    final Species? byModelClass = await getByModelClass(modelId, sourceClassId);
    if (byModelClass != null) {
      return byModelClass;
    }

    final String normalizedId = speciesId?.trim() ?? '';
    if (normalizedId.isNotEmpty) {
      for (final item in species) {
        if (item.id == normalizedId) {
          return item;
        }
      }
    }

    final Species? byScientificName =
        await getByScientificName(scientificName ?? '');
    if (byScientificName != null) {
      return byScientificName;
    }

    return getByScientificName(label ?? '');
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

  String _modelClassKey(String modelId, int sourceClassId) {
    return '$modelId:$sourceClassId';
  }

  Map<String, Species> _buildNameCache(
    List<Species> species,
    String? Function(Species species) nameFor,
  ) {
    final map = <String, Species>{};
    for (final item in species) {
      final normalized = _normalizeForLookup(nameFor(item));
      if (normalized.isNotEmpty && !map.containsKey(normalized)) {
        map[normalized] = item;
      }
    }
    return map;
  }

  Future<List<Species>> _loadSpeciesFromAsset({
    required String assetPath,
    String? fallbackAssetPath,
    required String modelId,
    required bool namespaceIds,
    required _TasColloquialMaps colloquialFallback,
  }) async {
    String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (_) {
      if (fallbackAssetPath == null) {
        rethrow;
      }
      raw = await rootBundle.loadString(fallbackAssetPath);
    }
    final data = _decodeCards(raw);
    return data.whereType<Map<String, dynamic>>().map((item) {
      final Map<String, dynamic> enriched = Map<String, dynamic>.from(item);
      final String rawId = (enriched['id'] ??
                  enriched['speciesId'] ??
                  enriched['species_id'])
              ?.toString()
              .trim() ??
          '';
      final int? sourceClassId = int.tryParse(rawId);
      if (namespaceIds && rawId.isNotEmpty) {
        enriched['id'] = '$modelId:$rawId';
      }
      enriched['modelId'] = modelId;
      if (sourceClassId != null) {
        enriched['sourceClassId'] = sourceClassId;
      }
      _applyColloquialFallback(enriched, rawId, colloquialFallback);
      return Species.fromJson(enriched);
    }).toList();
  }

  List<dynamic> _decodeCards(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    if (decoded is Map<String, dynamic> && decoded['cards'] is List<dynamic>) {
      return decoded['cards'] as List<dynamic>;
    }
    throw FormatException('Unexpected species data format');
  }

  void _applyColloquialFallback(
    Map<String, dynamic> enriched,
    String rawId,
    _TasColloquialMaps fallback,
  ) {
    final String existingColloquial =
        enriched['colloquialName']?.toString().trim() ?? '';
    if (existingColloquial.isNotEmpty) {
      return;
    }
    final String normalizedScientific = _normalizeForLookup(
      enriched['scientificName']?.toString(),
    );
    final String? fallbackValue =
        (rawId.isNotEmpty ? fallback.byId[rawId] : null) ??
            fallback.byScientificName[normalizedScientific];
    if (fallbackValue != null && fallbackValue.trim().isNotEmpty) {
      enriched['colloquialName'] = fallbackValue.trim();
    }
  }

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
