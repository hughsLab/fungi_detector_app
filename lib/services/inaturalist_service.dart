import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/inaturalist_taxon.dart';
import '../repositories/inaturalist_cache_repository.dart';
import 'inaturalist_rate_limiter.dart';

typedef INaturalistJsonGetter = Future<Map<String, dynamic>> Function(
  Uri uri,
  Map<String, String> headers,
);

class INaturalistService {
  INaturalistService({
    INaturalistCacheStore? cache,
    INaturalistRateLimiter? rateLimiter,
    INaturalistJsonGetter? jsonGetter,
    this.baseUrl = 'https://api.inaturalist.org/v1',
    this.userAgent = 'FungiApp/1.0',
    this.timeout = const Duration(seconds: 12),
  }) : _cache = cache ?? INaturalistCacheRepository.instance,
       _rateLimiter = rateLimiter ?? INaturalistRateLimiter(),
       _jsonGetter = jsonGetter;

  static final INaturalistService instance = INaturalistService();

  final INaturalistCacheStore _cache;
  final INaturalistRateLimiter _rateLimiter;
  final INaturalistJsonGetter? _jsonGetter;
  final String baseUrl;
  final String userAgent;
  final Duration timeout;
  final Map<String, Future<INaturalistTaxonMatch>> _inFlight = {};

  Future<INaturalistTaxonMatch> findTaxonByScientificName(
    String scientificName, {
    String? placeId,
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
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _find(requestName, key, placeId: placeId);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<INaturalistTaxonMatch> _find(
    String requestName,
    String key, {
    String? placeId,
  }) async {
    final cached = await _cache.read(key);
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached;
    }
    try {
      final search = await _request(
        '/taxa',
        {'q': requestName, 'per_page': '10'},
      );
      final selected = selectConservativeTaxonMatch(requestName, search);
      if (selected.status != INaturalistMatchStatus.matched ||
          selected.taxonId == null) {
        await _cache.write(selected);
        return selected;
      }

      final detailJson = await _request('/taxa/${selected.taxonId}', const {});
      final details = _firstMap(detailJson['results']);
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
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
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
  Map<String, dynamic> response,
) {
  final now = DateTime.now();
  final normalized = normalizeINaturalistName(cleanScientificName(requestName));
  final speciesQuery = normalized.split(' ').length >= 2;
  final results = response['results'] is List
      ? (response['results'] as List)
            .whereType<Map>()
            .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
            .where(
              (item) =>
                  item['iconic_taxon_name']?.toString().toLowerCase() ==
                  'fungi',
            )
            .where((item) => !speciesQuery || item['rank'] != 'genus')
            .toList()
      : <Map<String, dynamic>>[];
  final exact = results.where((item) {
    final accepted = normalizeINaturalistName(item['name']?.toString() ?? '');
    final matched = normalizeINaturalistName(
      item['matched_term']?.toString() ?? '',
    );
    return accepted == normalized || matched == normalized;
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
      ? (taxon['default_photo'] as Map).map(
          (k, v) => MapEntry(k.toString(), v),
        )
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

Map<String, dynamic> _firstMap(dynamic value) {
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
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

int? _asInt(dynamic value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '');
