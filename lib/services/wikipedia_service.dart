import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/wikipedia_species_content.dart';
import '../repositories/species_enrichment_cache_repository.dart';
import '../utils/wikipedia_text_cleaner.dart';

typedef WikipediaJsonGetter =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, String> headers);

class WikipediaService {
  WikipediaService({
    WikipediaSpeciesCacheStore? cache,
    WikipediaJsonGetter? jsonGetter,
    this.baseUrl = 'https://en.wikipedia.org/w/api.php',
    this.userAgent = 'FungiApp/1.0',
    this.timeout = const Duration(seconds: 12),
  }) : _cache = cache ?? SpeciesEnrichmentCacheRepository.instance,
       _jsonGetter = jsonGetter;

  static final WikipediaService instance = WikipediaService();

  final WikipediaSpeciesCacheStore _cache;
  final WikipediaJsonGetter? _jsonGetter;
  final String baseUrl;
  final String userAgent;
  final Duration timeout;
  final Map<String, Future<WikipediaSpeciesContent>> _inFlight = {};

  Future<WikipediaSpeciesContent> findSpecies(
    String scientificName, {
    Iterable<String> synonyms = const [],
  }) {
    final requestName = scientificName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final key = normalizeWikipediaName(requestName);
    if (key.isEmpty) {
      return Future.value(
        WikipediaSpeciesContent.statusOnly(
          status: WikipediaMatchStatus.notFound,
          requestedScientificName: requestName,
          fetchedAt: DateTime.now(),
        ),
      );
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _find(requestName, key, synonyms: synonyms);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<WikipediaSpeciesContent> _find(
    String requestName,
    String key, {
    required Iterable<String> synonyms,
  }) async {
    final cached = await _cache.read(key);
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached;
    }

    final candidateNames = <String>[
      requestName,
      ...synonyms.map((value) => value.trim()),
    ].where((value) => value.isNotEmpty).toSet().toList();
    try {
      Map<String, dynamic>? pageResponse;
      String? matchedRequest;
      for (final candidate in candidateNames) {
        final response = await _queryPage(candidate);
        if (isValidWikipediaPageResponse(
          response,
          acceptedScientificName: requestName,
          knownNames: candidateNames,
        )) {
          pageResponse = response;
          matchedRequest = candidate;
          break;
        }
      }

      if (pageResponse == null) {
        final search = await _request({
          'action': 'query',
          'list': 'search',
          'srsearch': '"$requestName"',
          'srnamespace': '0',
          'srlimit': '5',
          'format': 'json',
          'formatversion': '2',
          'origin': '*',
        });
        final searchQuery = _stringMap(search['query']);
        if (!searchQuery.containsKey('search')) {
          throw const FormatException('Malformed Wikipedia search response.');
        }
        final selection = selectWikipediaSearchTitle(
          search,
          acceptedScientificName: requestName,
          knownNames: candidateNames,
        );
        if (selection.status != WikipediaMatchStatus.matched ||
            selection.title == null) {
          final result = WikipediaSpeciesContent.statusOnly(
            status: selection.status,
            requestedScientificName: requestName,
            fetchedAt: DateTime.now(),
          );
          await _cache.write(result);
          return result;
        }
        final response = await _queryPage(selection.title!);
        if (!isValidWikipediaPageResponse(
          response,
          acceptedScientificName: requestName,
          knownNames: candidateNames,
        )) {
          final result = WikipediaSpeciesContent.statusOnly(
            status: WikipediaMatchStatus.ambiguous,
            requestedScientificName: requestName,
            fetchedAt: DateTime.now(),
          );
          await _cache.write(result);
          return result;
        }
        pageResponse = response;
        matchedRequest = selection.title;
      }

      final page = _firstPage(pageResponse);
      final pageTitle = page['title']?.toString() ?? matchedRequest!;
      final description = await _loadDescription(pageTitle);
      final image = await _loadImageMetadata(page['pageimage']?.toString());
      final now = DateTime.now();
      final result = WikipediaSpeciesContent(
        status: WikipediaMatchStatus.matched,
        requestedScientificName: requestName,
        pageTitle: pageTitle,
        pageDescription: cleanWikipediaPlainText(
          page['description']?.toString() ?? '',
        ),
        summaryExtract: cleanWikipediaPlainText(
          page['extract']?.toString() ?? '',
        ),
        descriptionText: description,
        thumbnailUrl: _nestedString(page, 'thumbnail', 'source'),
        originalImageUrl: _nestedString(page, 'original', 'source'),
        articleUrl:
            page['canonicalurl']?.toString() ?? page['fullurl']?.toString(),
        imageSourceUrl: image.sourceUrl,
        imageAttribution: image.attribution,
        imageLicense: image.license,
        imageLicenseUrl: image.licenseUrl,
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      );
      await _cache.write(result);
      return result;
    } catch (_) {
      if (cached != null) return cached.copyWith(isStale: true);
      return WikipediaSpeciesContent.statusOnly(
        status: WikipediaMatchStatus.unavailable,
        requestedScientificName: requestName,
        fetchedAt: DateTime.now(),
      );
    }
  }

  Future<Map<String, dynamic>> _queryPage(String title) => _request({
    'action': 'query',
    'titles': title,
    'redirects': '1',
    'prop': 'extracts|pageimages|info|description',
    'exintro': '1',
    'explaintext': '1',
    'inprop': 'url',
    'piprop': 'thumbnail|original|name',
    'pithumbsize': '1200',
    'format': 'json',
    'formatversion': '2',
    'origin': '*',
  });

  Future<String?> _loadDescription(String pageTitle) async {
    final sectionsResponse = await _request({
      'action': 'parse',
      'page': pageTitle,
      'redirects': '1',
      'prop': 'tocdata',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
    });
    final parse = _stringMap(sectionsResponse['parse']);
    final sections =
        _stringMap(parse['tocdata'])['sections'] ?? parse['sections'];
    if (sections is! List) return null;
    final descriptionSections = sections.whereType<Map>().where((section) {
      final line = cleanWikipediaPlainText(
        section['line']?.toString() ?? '',
      ).toLowerCase();
      return line == 'description' || line == 'description and ecology';
    }).toList();
    if (descriptionSections.isEmpty) return null;
    final index = descriptionSections.first['index']?.toString();
    if (index == null || index.isEmpty) return null;

    final response = await _request({
      'action': 'parse',
      'page': pageTitle,
      'redirects': '1',
      'section': index,
      'prop': 'text',
      'disableeditsection': '1',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
    });
    final html = _stringMap(response['parse'])['text'];
    final cleaned = cleanWikipediaHtml(
      html is Map ? html['*']?.toString() ?? '' : html?.toString() ?? '',
    );
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<_WikipediaImageMetadata> _loadImageMetadata(String? imageName) async {
    final name = imageName?.trim() ?? '';
    if (name.isEmpty) return const _WikipediaImageMetadata();
    final response = await _request({
      'action': 'query',
      'titles': name.startsWith('File:') ? name : 'File:$name',
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata',
      'iiextmetadatalanguage': 'en',
      'iiextmetadatafilter':
          'Artist|Credit|LicenseShortName|LicenseUrl|UsageTerms',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
    });
    final page = _firstPage(response);
    final imageInfo = page['imageinfo'];
    if (imageInfo is! List || imageInfo.isEmpty) {
      return const _WikipediaImageMetadata();
    }
    final info = _stringMap(imageInfo.first);
    final metadata = _stringMap(info['extmetadata']);
    final artist = cleanWikipediaMetadataValue(metadata['Artist']);
    final credit = cleanWikipediaMetadataValue(metadata['Credit']);
    final license = cleanWikipediaMetadataValue(
      metadata['LicenseShortName'] ?? metadata['UsageTerms'],
    );
    return _WikipediaImageMetadata(
      sourceUrl: info['descriptionurl']?.toString(),
      attribution: [
        artist,
        credit,
      ].where((value) => value.isNotEmpty).toSet().join(' · '),
      license: license.isEmpty ? null : license,
      licenseUrl: cleanWikipediaMetadataValue(metadata['LicenseUrl']),
    );
  }

  Future<Map<String, dynamic>> _request(Map<String, String> query) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: query);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final getter = _jsonGetter ?? _httpGetJson;
        return await getter(uri, {'User-Agent': userAgent}).timeout(timeout);
      } on WikipediaHttpException catch (error) {
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
    throw lastError ?? StateError('Wikipedia request failed.');
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
        throw WikipediaHttpException(response.statusCode);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected Wikipedia response.');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

class WikipediaHttpException implements Exception {
  final int statusCode;
  const WikipediaHttpException(this.statusCode);
}

class WikipediaSearchSelection {
  final WikipediaMatchStatus status;
  final String? title;
  const WikipediaSearchSelection(this.status, this.title);
}

WikipediaSearchSelection selectWikipediaSearchTitle(
  Map<String, dynamic> response, {
  required String acceptedScientificName,
  Iterable<String> knownNames = const [],
}) {
  final validNames = {
    normalizeWikipediaName(acceptedScientificName),
    ...knownNames.map(normalizeWikipediaName),
  }..remove('');
  final query = _stringMap(response['query']);
  final rawResults = query['search'];
  if (rawResults is! List) {
    return const WikipediaSearchSelection(WikipediaMatchStatus.notFound, null);
  }
  final candidates = rawResults.whereType<Map>().where((result) {
    final title = normalizeWikipediaName(result['title']?.toString() ?? '');
    if (validNames.contains(title)) return true;
    return validNames.any(
      (name) => title.startsWith('$name ') || title.startsWith('$name ('),
    );
  }).toList();
  if (candidates.isEmpty) {
    return const WikipediaSearchSelection(WikipediaMatchStatus.notFound, null);
  }
  if (candidates.length > 1) {
    return const WikipediaSearchSelection(WikipediaMatchStatus.ambiguous, null);
  }
  return WikipediaSearchSelection(
    WikipediaMatchStatus.matched,
    candidates.single['title']?.toString(),
  );
}

bool isValidWikipediaPageResponse(
  Map<String, dynamic> response, {
  required String acceptedScientificName,
  Iterable<String> knownNames = const [],
}) {
  final page = _firstPage(response);
  if (page.isEmpty || page['missing'] == true || page['invalid'] == true) {
    return false;
  }
  final validNames = {
    normalizeWikipediaName(acceptedScientificName),
    ...knownNames.map(normalizeWikipediaName),
  }..remove('');
  final title = normalizeWikipediaName(page['title']?.toString() ?? '');
  final query = _stringMap(response['query']);
  final redirects = query['redirects'];
  final redirectMatches =
      redirects is List &&
      redirects.whereType<Map>().any((redirect) {
        final from = normalizeWikipediaName(redirect['from']?.toString() ?? '');
        final to = normalizeWikipediaName(redirect['to']?.toString() ?? '');
        return validNames.contains(from) && to == title;
      });
  final titleMatches =
      validNames.contains(title) ||
      validNames.any(
        (name) => title.startsWith('$name ') || title.startsWith('$name ('),
      ) ||
      redirectMatches;
  if (!titleMatches) return false;
  final extract = normalizeWikipediaName(page['extract']?.toString() ?? '');
  return extract.isEmpty ||
      validNames.any((name) => name.isNotEmpty && extract.contains(name)) ||
      (redirectMatches && extract.contains(title));
}

Map<String, dynamic> _firstPage(Map<String, dynamic> response) {
  final query = _stringMap(response['query']);
  final pages = query['pages'];
  if (pages is List && pages.isNotEmpty) return _stringMap(pages.first);
  if (pages is Map && pages.isNotEmpty) return _stringMap(pages.values.first);
  return const {};
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String? _nestedString(
  Map<String, dynamic> value,
  String parent,
  String child,
) => _stringMap(value[parent])[child]?.toString();

class _WikipediaImageMetadata {
  final String? sourceUrl;
  final String? attribution;
  final String? license;
  final String? licenseUrl;

  const _WikipediaImageMetadata({
    this.sourceUrl,
    this.attribution,
    this.license,
    this.licenseUrl,
  });
}
