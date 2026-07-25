import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/wikipedia_species_content.dart';
import 'package:realtime_detection_app/repositories/species_enrichment_cache_repository.dart';
import 'package:realtime_detection_app/services/wikipedia_service.dart';
import 'package:realtime_detection_app/utils/wikipedia_text_cleaner.dart';

void main() {
  Map<String, dynamic> pageResponse({
    String title = 'Coprinus comatus',
    String? extract = 'Coprinus comatus is a species of fungus.',
    bool missing = false,
    String? pageImage,
    List<Map<String, dynamic>> redirects = const [],
  }) => {
    'query': {
      if (redirects.isNotEmpty) 'redirects': redirects,
      'pages': [
        {
          if (!missing) 'pageid': 1,
          if (missing) 'missing': true,
          'title': title,
          if (extract != null) 'extract': extract,
          'description': 'species of fungus',
          'canonicalurl': 'https://en.wikipedia.org/wiki/Coprinus_comatus',
          if (pageImage != null) 'pageimage': pageImage,
        },
      ],
    },
  };

  Map<String, dynamic> noSections() => {
    'parse': {'sections': <dynamic>[]},
  };

  WikipediaService serviceFor(
    Future<Map<String, dynamic>> Function(Uri uri) handler, {
    MemoryWikipediaSpeciesCacheStore? cache,
  }) => WikipediaService(
    cache: cache ?? MemoryWikipediaSpeciesCacheStore(),
    jsonGetter: (uri, headers) => handler(uri),
    timeout: const Duration(milliseconds: 100),
  );

  test('matches an exact scientific-name article', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['action'] == 'parse') return noSections();
      return pageResponse();
    });
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.status, WikipediaMatchStatus.matched);
    expect(result.pageTitle, 'Coprinus comatus');
    expect(result.summaryExtract, contains('species of fungus'));
  });

  test('accepts an exact scientific-name redirect', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['action'] == 'parse') return noSections();
      return pageResponse(
        title: 'Coprinellus comatus',
        extract: 'Coprinellus comatus is a fungus.',
        redirects: [
          {'from': 'Coprinus comatus', 'to': 'Coprinellus comatus'},
        ],
      );
    });
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.status, WikipediaMatchStatus.matched);
    expect(result.pageTitle, 'Coprinellus comatus');
  });

  test('tries an exact known scientific synonym', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['action'] == 'parse') return noSections();
      final title = uri.queryParameters['titles'];
      if (title == 'Old fungus') {
        return pageResponse(title: title!, missing: true);
      }
      return pageResponse(
        title: 'Accepted fungus',
        extract: 'Old fungus is now known as Accepted fungus.',
      );
    });
    final result = await service.findSpecies(
      'Old fungus',
      synonyms: const ['Accepted fungus'],
    );
    expect(result.status, WikipediaMatchStatus.matched);
    expect(result.pageTitle, 'Accepted fungus');
  });

  test('rejects an unrelated search result', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['list'] == 'search') {
        return {
          'query': {
            'search': [
              {'title': 'Coprinus domesticus'},
            ],
          },
        };
      }
      return pageResponse(title: 'Coprinus comatus', missing: true);
    });
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.status, WikipediaMatchStatus.notFound);
  });

  test('marks multiple validated search titles ambiguous', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['list'] == 'search') {
        return {
          'query': {
            'search': [
              {'title': 'Coprinus comatus (fungus)'},
              {'title': 'Coprinus comatus (name)'},
            ],
          },
        };
      }
      return pageResponse(title: 'Coprinus comatus', missing: true);
    });
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.status, WikipediaMatchStatus.ambiguous);
  });

  test('returns not found when no exact result exists', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['list'] == 'search') {
        return {
          'query': {'search': <dynamic>[]},
        };
      }
      return pageResponse(title: 'Missing fungus', missing: true);
    });
    final result = await service.findSpecies('Missing fungus');
    expect(result.status, WikipediaMatchStatus.notFound);
  });

  test(
    'keeps matched content when description and image are missing',
    () async {
      final service = serviceFor((uri) async {
        if (uri.queryParameters['action'] == 'parse') return noSections();
        return pageResponse();
      });
      final result = await service.findSpecies('Coprinus comatus');
      expect(result.status, WikipediaMatchStatus.matched);
      expect(result.descriptionText, isNull);
      expect(result.thumbnailUrl, isNull);
      expect(result.imageAttribution, isNull);
    },
  );

  test('cleans Description HTML and retains image attribution', () async {
    final service = serviceFor((uri) async {
      if (uri.queryParameters['action'] == 'parse' &&
          uri.queryParameters['prop'] == 'tocdata') {
        return {
          'parse': {
            'tocdata': {
              'sections': [
                {'line': 'Description', 'index': '1'},
              ],
            },
          },
        };
      }
      if (uri.queryParameters['action'] == 'parse') {
        return {
          'parse': {
            'text':
                '<p>White cap<sup class="reference">[1]</sup>.</p>'
                '<script>bad()</script><p>Dark gills &amp; stem.</p>',
          },
        };
      }
      if ((uri.queryParameters['titles'] ?? '').startsWith('File:')) {
        return {
          'query': {
            'pages': [
              {
                'title': 'File:Fungus.jpg',
                'imageinfo': [
                  {
                    'descriptionurl':
                        'https://commons.wikimedia.org/wiki/File:Fungus.jpg',
                    'extmetadata': {
                      'Artist': {'value': '<b>Example creator</b>'},
                      'LicenseShortName': {'value': 'CC BY-SA 4.0'},
                    },
                  },
                ],
              },
            ],
          },
        };
      }
      return pageResponse(pageImage: 'Fungus.jpg');
    });
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.descriptionText, 'White cap.\n\nDark gills & stem.');
    expect(result.imageAttribution, 'Example creator');
    expect(result.imageLicense, 'CC BY-SA 4.0');
  });

  test(
    'malformed response is unavailable and is not cached as not found',
    () async {
      final cache = MemoryWikipediaSpeciesCacheStore();
      final service = serviceFor(
        (uri) async => <String, dynamic>{},
        cache: cache,
      );
      final result = await service.findSpecies('Coprinus comatus');
      expect(result.status, WikipediaMatchStatus.unavailable);
      expect(cache.values, isEmpty);
    },
  );

  test('network failure returns unavailable without throwing', () async {
    final service = serviceFor(
      (uri) async => throw const SocketException('offline'),
    );
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.status, WikipediaMatchStatus.unavailable);
  });

  test('returns a fresh cached response without a network call', () async {
    final cache = MemoryWikipediaSpeciesCacheStore();
    final now = DateTime.now();
    await cache.write(
      WikipediaSpeciesContent(
        status: WikipediaMatchStatus.matched,
        requestedScientificName: 'Coprinus comatus',
        pageTitle: 'Coprinus comatus',
        pageDescription: null,
        summaryExtract: 'Cached summary',
        descriptionText: null,
        thumbnailUrl: null,
        originalImageUrl: null,
        articleUrl: null,
        imageSourceUrl: null,
        imageAttribution: null,
        imageLicense: null,
        imageLicenseUrl: null,
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 2)),
      ),
    );
    final service = serviceFor(
      (uri) async => throw StateError('network should not be called'),
      cache: cache,
    );
    final result = await service.findSpecies('Coprinus comatus');
    expect(result.summaryExtract, 'Cached summary');
  });

  test('plain and HTML cleaning removes citations and unsafe elements', () {
    expect(
      cleanWikipediaPlainText('One [1]  two.\n\n\nThree [citation needed]'),
      'One two.\n\nThree',
    );
    expect(
      cleanWikipediaHtml('<p>Useful &amp; clean.</p><style>bad</style>'),
      'Useful & clean.',
    );
  });
}
