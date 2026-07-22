import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inaturalist_taxon.dart';

abstract class INaturalistCacheStore {
  Future<INaturalistTaxonMatch?> read(String normalizedScientificName);
  Future<void> write(INaturalistTaxonMatch value);
}

class INaturalistCacheRepository implements INaturalistCacheStore {
  INaturalistCacheRepository._();

  static final INaturalistCacheRepository instance =
      INaturalistCacheRepository._();

  static const _namePrefix = 'inat_taxon:';
  static const _idPrefix = 'inat_taxon_id:';

  @override
  Future<INaturalistTaxonMatch?> read(String normalizedScientificName) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_namePrefix$normalizedScientificName');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return INaturalistTaxonMatch.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(INaturalistTaxonMatch value) async {
    if (value.status == INaturalistMatchStatus.unavailable) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(value.toJson());
    await preferences.setString(
      '$_namePrefix${normalizeINaturalistName(value.requestName)}',
      encoded,
    );
    final taxonId = value.taxonId;
    if (taxonId != null) {
      await preferences.setString('$_idPrefix$taxonId', encoded);
    }
  }
}

String normalizeINaturalistName(String value) => value
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

class MemoryINaturalistCacheStore implements INaturalistCacheStore {
  final Map<String, INaturalistTaxonMatch> values = {};

  @override
  Future<INaturalistTaxonMatch?> read(String normalizedScientificName) async =>
      values[normalizedScientificName];

  @override
  Future<void> write(INaturalistTaxonMatch value) async {
    values[normalizeINaturalistName(value.requestName)] = value;
  }
}

