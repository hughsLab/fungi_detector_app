import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/wikipedia_species_content.dart';

abstract class WikipediaSpeciesCacheStore {
  Future<WikipediaSpeciesContent?> read(String normalizedScientificName);
  Future<void> write(WikipediaSpeciesContent value);
}

class SpeciesEnrichmentCacheRepository implements WikipediaSpeciesCacheStore {
  SpeciesEnrichmentCacheRepository._();

  static final SpeciesEnrichmentCacheRepository instance =
      SpeciesEnrichmentCacheRepository._();

  static const _wikipediaPrefix = 'wikipedia_species:';

  @override
  Future<WikipediaSpeciesContent?> read(String normalizedScientificName) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(
      '$_wikipediaPrefix$normalizedScientificName',
    );
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? WikipediaSpeciesContent.fromJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(WikipediaSpeciesContent value) async {
    if (value.status == WikipediaMatchStatus.unavailable) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_wikipediaPrefix${normalizeWikipediaName(value.requestedScientificName)}',
      jsonEncode(value.toJson()),
    );
  }
}

class MemoryWikipediaSpeciesCacheStore implements WikipediaSpeciesCacheStore {
  final Map<String, WikipediaSpeciesContent> values = {};

  @override
  Future<WikipediaSpeciesContent?> read(
    String normalizedScientificName,
  ) async => values[normalizedScientificName];

  @override
  Future<void> write(WikipediaSpeciesContent value) async {
    if (value.status == WikipediaMatchStatus.unavailable) return;
    values[normalizeWikipediaName(value.requestedScientificName)] = value;
  }
}

String normalizeWikipediaName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
