import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/inaturalist_taxon.dart';
import '../models/inaturalist_observation_histogram.dart';
import '../models/taxonomy_node.dart';
import '../repositories/inaturalist_cache_repository.dart';
import 'inaturalist_rate_limiter.dart';

typedef INaturalistJsonGetter =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, String> headers);

class INaturalistService {
  INaturalistService({
    INaturalistCacheStore? cache,
    INaturalistRateLimiter? rateLimiter,
    INaturalistHistogramCacheStore? histogramCache,
    INaturalistLibrarySearchCacheStore? librarySearchCache,
    INaturalistJsonGetter? jsonGetter,
    this.baseUrl = 'https://api.inaturalist.org/v1',
    this.userAgent = 'FungiApp/1.0',
    this.timeout = const Duration(seconds: 12),
  }) : _cache = cache ?? INaturalistCacheRepository.instance,
       _rateLimiter = rateLimiter ?? INaturalistRateLimiter(),
       _histogramCache =
           histogramCache ?? INaturalistHistogramCacheRepository.instance,
       _librarySearchCache =
           librarySearchCache ??
           INaturalistLibrarySearchCacheRepository.instance,
       _jsonGetter = jsonGetter;

  static final INaturalistService instance = INaturalistService();

  final INaturalistCacheStore _cache;
  final INaturalistRateLimiter _rateLimiter;
  final INaturalistHistogramCacheStore _histogramCache;
  final INaturalistLibrarySearchCacheStore _librarySearchCache;
  final INaturalistJsonGetter? _jsonGetter;
  final String baseUrl;
  final String userAgent;
  final Duration timeout;
  final Map<String, Future<INaturalistTaxonMatch>> _inFlight = {};
  final Map<int, Future<INaturalistObservationHistogram?>> _histogramInFlight =
      {};
  final Map<String, Future<List<INaturalistTaxonMatch>>> _searchInFlight = {};

  Future<INaturalistTaxonMatch> findTaxonByScientificName(
    String scientificName, {
    String? placeId,
    int? storedTaxonId,
    Iterable<String> synonyms = const [],
  }) {
    final requestName = cleanScientificName(scientificName);
    final key = normalizeINaturalistName(requestName);
    if (key.isEmpty) {
      return Future.value(
        INaturalistTaxonMatch.statusOnly(
          status: INaturalistMatchStatus.notFound,
          requestName: requestName,
          fetchedAt: DateTime.now(),
        ),
      );
    }
    final requestKey = '$key:${storedTaxonId ?? ''}:${placeId ?? ''}';
    final existing = _inFlight[requestKey];
    if (existing != null) return existing;
    final future = _find(
      requestName,
      key,
      placeId: placeId,
      storedTaxonId: storedTaxonId,
      synonyms: synonyms,
    );
    _inFlight[requestKey] = future;
    return future.whenComplete(() => _inFlight.remove(requestKey));
  }

  Future<INaturalistTaxonMatch> _find(
    String requestName,
    String key, {
    String? placeId,
    int? storedTaxonId,
    required Iterable<String> synonyms,
  }) async {
    final cached =
        await _cache.read(key) ??
        (storedTaxonId == null ? null : await _cache.readById(storedTaxonId));
    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now()) &&
        (cached.status != INaturalistMatchStatus.matched ||
            cached.taxonomy.isNotEmpty)) {
      return cached;
    }
    try {
      INaturalistTaxonMatch selected;
      Map<String, dynamic> details;
      if (storedTaxonId != null) {
        final detailJson = await _request('/taxa/$storedTaxonId', const {});
        details = _firstMap(detailJson['results']);
        selected = parseExactINaturalistTaxonDetails(
          requestName,
          details,
          knownSynonyms: synonyms,
          allowStoredIdMatch: true,
        );
      } else {
        final search = await _request('/taxa', {
          'q': requestName,
          'per_page': '10',
        });
        selected = selectConservativeTaxonMatch(
          requestName,
          search,
          knownSynonyms: synonyms,
        );
        details = const {};
      }
      if (selected.status != INaturalistMatchStatus.matched ||
          selected.taxonId == null) {
        await _cache.write(selected);
        return selected;
      }

      if (details.isEmpty) {
        final detailJson = await _request(
          '/taxa/${selected.taxonId}',
          const {},
        );
        details = _firstMap(detailJson['results']);
        selected = parseExactINaturalistTaxonDetails(
          requestName,
          details,
          knownSynonyms: synonyms,
        );
        if (selected.status != INaturalistMatchStatus.matched) {
          await _cache.write(selected);
          return selected;
        }
      }
      final conservation = _conservationFrom(details);
      final globalCount = await getObservationCountForTaxon(selected.taxonId!);
      final regionalCount = placeId == null || placeId.trim().isEmpty
          ? null
          : await getObservationCountForTaxon(
              selected.taxonId!,
              placeId: placeId,
            );
      final now = DateTime.now();
      final enriched = selected.copyWith(
        globalObservationCount: globalCount,
        regionalObservationCount: regionalCount,
        conservationStatus: conservation.$1,
        conservationStatusAuthority: conservation.$2,
        conservationStatusPlace: conservation.$3,
        taxonomy: parseINaturalistTaxonomy(details),
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await _cache.write(enriched);
      return enriched;
    } catch (_) {
      if (cached != null) return cached.copyWith(isStale: true);
      return INaturalistTaxonMatch.statusOnly(
        status: INaturalistMatchStatus.unavailable,
        requestName: requestName,
        fetchedAt: DateTime.now(),
      );
    }
  }

  Future<int?> getObservationCountForTaxon(
    int taxonId, {
    String? placeId,
  }) async {
    final response = await _request('/observations', {
      'taxon_id': '$taxonId',
      'per_page': '0',
      if (placeId != null && placeId.trim().isNotEmpty)
        'place_id': placeId.trim(),
    });
    return _asInt(response['total_results']);
  }

  Future<INaturalistObservationHistogram?> getObservationHistogramForTaxon(
    int taxonId,
  ) {
    final existing = _histogramInFlight[taxonId];
    if (existing != null) return existing;
    final future = _loadObservationHistogram(taxonId);
    _histogramInFlight[taxonId] = future;
    return future.whenComplete(() => _histogramInFlight.remove(taxonId));
  }

  Future<List<INaturalistTaxonMatch>> searchFungalTaxa(
    String query, {
    int limit = 30,
  }) {
    final normalized = normalizeINaturalistName(query);
    if (normalized.length < 2) return Future.value(const []);
    final existing = _searchInFlight[normalized];
    if (existing != null) return existing;
    final future = _searchFungalTaxa(normalized, limit: limit);
    _searchInFlight[normalized] = future;
    return future.whenComplete(() => _searchInFlight.remove(normalized));
  }

  Future<List<INaturalistTaxonMatch>> _searchFungalTaxa(
    String query, {
    required int limit,
  }) async {
    final cached = await _librarySearchCache.readSearch(query);
    if (cached != null) return cached;
    final response = await _request('/taxa/autocomplete', {
      'q': query,
      'taxon_id': '47170',
      'per_page': '${limit.clamp(1, 50)}',
    });
    final values = parseLicensedFungalTaxa(response, requestName: query);
    await _librarySearchCache.writeSearch(query, values);
    return values;
  }

  Future<INaturalistObservationHistogram?> _loadObservationHistogram(
    int taxonId,
  ) async {
    final cached = await _histogramCache.readHistogram(taxonId);
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached;
    }
    try {
      final seasonal = await _request('/observations/histogram', {
        'taxon_id': '$taxonId',
        'date_field': 'observed',
        'interval': 'month_of_year',
      });
      final history = await _request('/observations/histogram', {
        'taxon_id': '$taxonId',
        'date_field': 'observed',
        'interval': 'year',
      });
      final now = DateTime.now();
      final result = INaturalistObservationHistogram(
        taxonId: taxonId,
        observationsByMonth: parseINaturalistHistogramCounts(
          seasonal,
          interval: 'month_of_year',
        ),
        observationsByYear: parseINaturalistHistogramCounts(
          history,
          interval: 'year',
        ),
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );
      await _histogramCache.writeHistogram(result);
      return result;
    } catch (_) {
      return cached;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      await _rateLimiter.waitForTurn();
      try {
        final getter = _jsonGetter ?? _httpGetJson;
        return await getter(uri, {'User-Agent': userAgent}).timeout(timeout);
      } on INaturalistHttpException catch (error) {
        lastError = error;
        if (error.statusCode != 429 && error.statusCode < 500) rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on FormatException {
        rethrow;
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(milliseconds: 400 * pow(2, attempt).toInt()),
        );
      }
    }
    throw lastError ?? StateError('iNaturalist request failed.');
  }

  Future<Map<String, dynamic>> _httpGetJson(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw INaturalistHttpException(response.statusCode);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected iNaturalist response.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

class INaturalistHttpException implements Exception {
  final int statusCode;
  const INaturalistHttpException(this.statusCode);
  @override
  String toString() => 'iNaturalist HTTP $statusCode';
}

String cleanScientificName(String value) {
  var cleaned = value
      .replaceAll(RegExp(r'\(?\s*\d+(?:\.\d+)?\s*%\s*\)?'), ' ')
      .replaceAll(
        RegExp(
          r'^(scientific name|species|result)\s*:\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final parts = cleaned.split(' ');
  if (parts.length > 2 &&
      RegExp(r'^[A-Z][a-z-]+$').hasMatch(parts[0]) &&
      RegExp(r'^[a-z][a-z-]+$').hasMatch(parts[1])) {
    cleaned = '${parts[0]} ${parts[1]}';
  }
  return cleaned;
}

INaturalistTaxonMatch selectConservativeTaxonMatch(
  String requestName,
  Map<String, dynamic> response, {
  Iterable<String> knownSynonyms = const [],
}) {
  final now = DateTime.now();
  final normalized = normalizeINaturalistName(cleanScientificName(requestName));
  final speciesQuery = normalized.split(' ').length >= 2;
  final acceptedNames = {
    normalized,
    ...knownSynonyms.map(
      (name) => normalizeINaturalistName(cleanScientificName(name)),
    ),
  }..remove('');
  const speciesRanks = {'species', 'subspecies', 'variety', 'form', 'hybrid'};
  final results = response['results'] is List
      ? (response['results'] as List)
            .whereType<Map>()
            .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
            .where(
              (item) =>
                  item['iconic_taxon_name']?.toString().toLowerCase() ==
                  'fungi',
            )
            .where(
              (item) =>
                  !speciesQuery ||
                  speciesRanks.contains(item['rank']?.toString().toLowerCase()),
            )
            .toList()
      : <Map<String, dynamic>>[];
  final exact = results.where((item) {
    final accepted = normalizeINaturalistName(item['name']?.toString() ?? '');
    final matched = normalizeINaturalistName(
      item['matched_term']?.toString() ?? '',
    );
    return acceptedNames.contains(accepted) || acceptedNames.contains(matched);
  }).toList();
  if (exact.length != 1) {
    return INaturalistTaxonMatch.statusOnly(
      status: exact.length > 1
          ? INaturalistMatchStatus.ambiguous
          : INaturalistMatchStatus.notFound,
      requestName: requestName,
      fetchedAt: now,
    );
  }
  final taxon = exact.single;
  final photo = taxon['default_photo'] is Map
      ? (taxon['default_photo'] as Map).map((k, v) => MapEntry(k.toString(), v))
      : const <String, dynamic>{};
  final id = _asInt(taxon['id']);
  return INaturalistTaxonMatch(
    status: INaturalistMatchStatus.matched,
    requestName: requestName,
    taxonId: id,
    acceptedScientificName: taxon['name']?.toString(),
    matchedName: taxon['matched_term']?.toString(),
    preferredCommonName: taxon['preferred_common_name']?.toString(),
    rank: taxon['rank']?.toString(),
    iconicTaxonName: taxon['iconic_taxon_name']?.toString(),
    isActive: taxon['is_active'] is bool ? taxon['is_active'] as bool : null,
    extinct: taxon['extinct'] is bool ? taxon['extinct'] as bool : null,
    photoUrl: photo['medium_url']?.toString() ?? photo['url']?.toString(),
    photoAttribution: photo['attribution']?.toString(),
    photoLicense: photo['license_code']?.toString(),
    taxonUrl: id == null ? null : 'https://www.inaturalist.org/taxa/$id',
    globalObservationCount: _asInt(taxon['observations_count']),
    regionalObservationCount: null,
    conservationStatus: null,
    conservationStatusAuthority: null,
    conservationStatusPlace: null,
    fetchedAt: now,
    expiresAt: now.add(const Duration(days: 30)),
  );
}

INaturalistTaxonMatch parseExactINaturalistTaxonDetails(
  String requestName,
  Map<String, dynamic> taxon, {
  Iterable<String> knownSynonyms = const [],
  bool allowStoredIdMatch = false,
}) {
  final now = DateTime.now();
  final normalized = normalizeINaturalistName(cleanScientificName(requestName));
  final speciesQuery = normalized.split(' ').length >= 2;
  final acceptedNames = {
    normalized,
    ...knownSynonyms.map(
      (name) => normalizeINaturalistName(cleanScientificName(name)),
    ),
  }..remove('');
  final taxonomy = parseINaturalistTaxonomy(taxon);
  final isFungus =
      taxon['iconic_taxon_name']?.toString().toLowerCase() == 'fungi' ||
      taxonomy.any(
        (node) =>
            node.rank.toLowerCase() == 'kingdom' &&
            normalizeINaturalistName(node.scientificName) == 'fungi',
      );
  const speciesRanks = {'species', 'subspecies', 'variety', 'form', 'hybrid'};
  final rank = taxon['rank']?.toString().toLowerCase() ?? '';
  final accepted = normalizeINaturalistName(taxon['name']?.toString() ?? '');
  final exactName = acceptedNames.contains(accepted);
  if (!isFungus ||
      (speciesQuery && !speciesRanks.contains(rank)) ||
      (!allowStoredIdMatch && !exactName)) {
    return INaturalistTaxonMatch.statusOnly(
      status: INaturalistMatchStatus.notFound,
      requestName: requestName,
      fetchedAt: now,
    );
  }

  final photo = _stringMap(taxon['default_photo']);
  final id = _asInt(taxon['id']);
  return INaturalistTaxonMatch(
    status: INaturalistMatchStatus.matched,
    requestName: requestName,
    taxonId: id,
    acceptedScientificName: taxon['name']?.toString(),
    matchedName: exactName ? requestName : null,
    preferredCommonName: taxon['preferred_common_name']?.toString(),
    rank: taxon['rank']?.toString(),
    iconicTaxonName: taxon['iconic_taxon_name']?.toString(),
    isActive: taxon['is_active'] is bool ? taxon['is_active'] as bool : null,
    extinct: taxon['extinct'] is bool ? taxon['extinct'] as bool : null,
    photoUrl: photo['medium_url']?.toString() ?? photo['url']?.toString(),
    photoAttribution: photo['attribution']?.toString(),
    photoLicense: photo['license_code']?.toString(),
    taxonUrl: id == null ? null : 'https://www.inaturalist.org/taxa/$id',
    globalObservationCount: _asInt(taxon['observations_count']),
    regionalObservationCount: null,
    conservationStatus: null,
    conservationStatusAuthority: null,
    conservationStatusPlace: null,
    taxonomy: taxonomy,
    fetchedAt: now,
    expiresAt: now.add(const Duration(days: 30)),
  );
}

List<TaxonomyNode> parseINaturalistTaxonomy(Map<String, dynamic> taxon) {
  final rawNodes = <Map<String, dynamic>>[];
  final ancestors = taxon['ancestors'];
  if (ancestors is List) {
    for (final item in ancestors.whereType<Map>()) {
      rawNodes.add(item.map((key, value) => MapEntry(key.toString(), value)));
    }
  }
  if (taxon.isNotEmpty) rawNodes.add(taxon);

  final seen = <int>{};
  final nodes = <TaxonomyNode>[];
  for (final item in rawNodes) {
    final id = _asInt(item['id']);
    final scientificName = item['name']?.toString().trim() ?? '';
    final rank = item['rank']?.toString().trim() ?? '';
    if (scientificName.isEmpty || rank.isEmpty) continue;
    if (id != null && !seen.add(id)) continue;
    nodes.add(
      TaxonomyNode(
        taxonId: id,
        rank: rank,
        scientificName: scientificName,
        commonName: item['preferred_common_name']?.toString(),
        rankLevel: _asDouble(item['rank_level']),
      ),
    );
  }
  nodes.sort((a, b) {
    final aLevel = a.rankLevel ?? _fallbackRankLevel(a.rank);
    final bLevel = b.rankLevel ?? _fallbackRankLevel(b.rank);
    return bLevel.compareTo(aLevel);
  });
  return nodes;
}

Map<String, dynamic> _firstMap(dynamic value) {
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const {};
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

(String?, String?, String?) _conservationFrom(Map<String, dynamic> taxon) {
  Map<String, dynamic> status = const {};
  final primary = taxon['conservation_status'];
  if (primary is Map && primary.isNotEmpty) {
    status = primary.map((key, value) => MapEntry(key.toString(), value));
  } else if (taxon['conservation_statuses'] is List) {
    final list = taxon['conservation_statuses'] as List;
    if (list.isNotEmpty && list.first is Map) {
      status = (list.first as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
  }
  if (status.isEmpty) return (null, null, null);
  final place = status['place'] is Map
      ? (status['place'] as Map)['display_name']?.toString() ??
            (status['place'] as Map)['name']?.toString()
      : null;
  return (
    status['status_name']?.toString() ?? status['status']?.toString(),
    status['authority']?.toString(),
    place,
  );
}

int? _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

double? _asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

double _fallbackRankLevel(String rank) => switch (rank.toLowerCase()) {
  'kingdom' => 70,
  'phylum' => 60,
  'subphylum' => 57,
  'class' => 50,
  'subclass' => 47,
  'order' => 40,
  'suborder' => 37,
  'family' => 30,
  'subfamily' => 27,
  'tribe' => 25,
  'genus' => 20,
  'subgenus' => 17,
  'species' => 10,
  'subspecies' => 5,
  'variety' => 5,
  'form' => 5,
  _ => 0,
};

Map<int, int> parseINaturalistHistogramCounts(
  Map<String, dynamic> response, {
  required String interval,
}) {
  final results = response['results'];
  if (results is! Map) return const {};
  final raw = results[interval];
  if (raw is! Map) return const {};
  final counts = <int, int>{};
  for (final entry in raw.entries) {
    final keyText = entry.key.toString();
    final key = interval == 'year'
        ? DateTime.tryParse(keyText)?.year ?? int.tryParse(keyText)
        : int.tryParse(keyText);
    final count = _asInt(entry.value);
    if (key != null && count != null && count >= 0) counts[key] = count;
  }
  return counts;
}

List<INaturalistTaxonMatch> parseLicensedFungalTaxa(
  Map<String, dynamic> response, {
  required String requestName,
}) {
  final rawResults = response['results'];
  if (rawResults is! List) return const [];
  const acceptedRanks = {'species', 'subspecies', 'variety', 'form', 'hybrid'};
  const reusableLicenses = {'cc0', 'cc-by', 'cc-by-sa'};
  final now = DateTime.now();
  final matches = <INaturalistTaxonMatch>[];
  final seenTaxa = <int>{};
  for (final raw in rawResults.whereType<Map>()) {
    final taxon = raw.map((key, value) => MapEntry(key.toString(), value));
    if (taxon['iconic_taxon_name']?.toString().toLowerCase() != 'fungi' ||
        taxon['is_active'] != true ||
        !acceptedRanks.contains(taxon['rank']?.toString().toLowerCase())) {
      continue;
    }
    final id = _asInt(taxon['id']);
    if (id == null || !seenTaxa.add(id)) continue;
    final rawPhoto = taxon['default_photo'];
    if (rawPhoto is! Map) continue;
    final photo = rawPhoto.map((key, value) => MapEntry(key.toString(), value));
    final license = photo['license_code']?.toString().toLowerCase();
    final attribution = photo['attribution']?.toString().trim() ?? '';
    final photoUrl =
        photo['medium_url']?.toString() ?? photo['url']?.toString();
    final dimensions = photo['original_dimensions'];
    final width = dimensions is Map ? _asInt(dimensions['width']) : null;
    final height = dimensions is Map ? _asInt(dimensions['height']) : null;
    if (license == null ||
        !reusableLicenses.contains(license) ||
        attribution.isEmpty ||
        !_isTrustedINaturalistPhotoUrl(photoUrl) ||
        width == null ||
        width < 300 ||
        height == null ||
        height < 300) {
      continue;
    }
    matches.add(
      INaturalistTaxonMatch(
        status: INaturalistMatchStatus.matched,
        requestName: requestName,
        taxonId: id,
        acceptedScientificName: taxon['name']?.toString(),
        matchedName: taxon['matched_term']?.toString(),
        preferredCommonName: taxon['preferred_common_name']?.toString(),
        rank: taxon['rank']?.toString(),
        iconicTaxonName: taxon['iconic_taxon_name']?.toString(),
        isActive: taxon['is_active'] is bool
            ? taxon['is_active'] as bool
            : null,
        extinct: taxon['extinct'] is bool ? taxon['extinct'] as bool : null,
        photoUrl: photoUrl,
        photoAttribution: attribution,
        photoLicense: license,
        taxonUrl: 'https://www.inaturalist.org/taxa/$id',
        globalObservationCount: _asInt(taxon['observations_count']),
        regionalObservationCount: null,
        conservationStatus: null,
        conservationStatusAuthority: null,
        conservationStatusPlace: null,
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );
  }
  return matches;
}

bool _isTrustedINaturalistPhotoUrl(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'inaturalist-open-data.s3.amazonaws.com' ||
      host == 'static.inaturalist.org' ||
      host.endsWith('.inaturalist-open-data.s3.amazonaws.com');
}
