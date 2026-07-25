import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inaturalist_taxon.dart';
import '../models/inaturalist_observation_histogram.dart';

abstract class INaturalistCacheStore {
  Future<INaturalistTaxonMatch?> read(String normalizedScientificName);
  Future<INaturalistTaxonMatch?> readById(int taxonId);
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
  Future<INaturalistTaxonMatch?> readById(int taxonId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_idPrefix$taxonId');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? INaturalistTaxonMatch.fromJson(decoded)
          : null;
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

String normalizeINaturalistName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class MemoryINaturalistCacheStore implements INaturalistCacheStore {
  final Map<String, INaturalistTaxonMatch> values = {};
  final Map<int, INaturalistTaxonMatch> valuesById = {};

  @override
  Future<INaturalistTaxonMatch?> read(String normalizedScientificName) async =>
      values[normalizedScientificName];

  @override
  Future<INaturalistTaxonMatch?> readById(int taxonId) async =>
      valuesById[taxonId];

  @override
  Future<void> write(INaturalistTaxonMatch value) async {
    values[normalizeINaturalistName(value.requestName)] = value;
    if (value.taxonId != null) valuesById[value.taxonId!] = value;
  }
}

abstract class INaturalistHistogramCacheStore {
  Future<INaturalistObservationHistogram?> readHistogram(int taxonId);
  Future<void> writeHistogram(INaturalistObservationHistogram value);
}

class INaturalistHistogramCacheRepository
    implements INaturalistHistogramCacheStore {
  INaturalistHistogramCacheRepository._();

  static final INaturalistHistogramCacheRepository instance =
      INaturalistHistogramCacheRepository._();

  static const _prefix = 'inat_histogram_id:';

  @override
  Future<INaturalistObservationHistogram?> readHistogram(int taxonId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_prefix$taxonId');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? INaturalistObservationHistogram.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeHistogram(INaturalistObservationHistogram value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix${value.taxonId}',
      jsonEncode(value.toJson()),
    );
  }
}

class MemoryINaturalistHistogramCacheStore
    implements INaturalistHistogramCacheStore {
  final Map<int, INaturalistObservationHistogram> values = {};

  @override
  Future<INaturalistObservationHistogram?> readHistogram(int taxonId) async =>
      values[taxonId];

  @override
  Future<void> writeHistogram(INaturalistObservationHistogram value) async {
    values[value.taxonId] = value;
  }
}

abstract class INaturalistLibrarySearchCacheStore {
  Future<List<INaturalistTaxonMatch>?> readSearch(String normalizedQuery);
  Future<void> writeSearch(
    String normalizedQuery,
    List<INaturalistTaxonMatch> values,
  );
}

class INaturalistLibrarySearchCacheRepository
    implements INaturalistLibrarySearchCacheStore {
  INaturalistLibrarySearchCacheRepository._();

  static final INaturalistLibrarySearchCacheRepository instance =
      INaturalistLibrarySearchCacheRepository._();

  static const _prefix = 'inat_library_search:';

  @override
  Future<List<INaturalistTaxonMatch>?> readSearch(
    String normalizedQuery,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_prefix$normalizedQuery');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final values = decoded
          .whereType<Map>()
          .map(
            (item) => INaturalistTaxonMatch.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList();
      if (values.isEmpty ||
          values.any((item) => item.expiresAt.isBefore(DateTime.now()))) {
        return null;
      }
      return values;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeSearch(
    String normalizedQuery,
    List<INaturalistTaxonMatch> values,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix$normalizedQuery',
      jsonEncode(values.map((item) => item.toJson()).toList()),
    );
  }
}

class MemoryINaturalistLibrarySearchCacheStore
    implements INaturalistLibrarySearchCacheStore {
  final Map<String, List<INaturalistTaxonMatch>> values = {};

  @override
  Future<List<INaturalistTaxonMatch>?> readSearch(
    String normalizedQuery,
  ) async => values[normalizedQuery];

  @override
  Future<void> writeSearch(
    String normalizedQuery,
    List<INaturalistTaxonMatch> values,
  ) async {
    this.values[normalizedQuery] = values;
  }
}
