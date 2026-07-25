import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/inaturalist_taxon.dart';
import 'package:realtime_detection_app/models/taxonomy_node.dart';
import 'package:realtime_detection_app/repositories/inaturalist_cache_repository.dart';
import 'package:realtime_detection_app/services/inaturalist_rate_limiter.dart';
import 'package:realtime_detection_app/services/inaturalist_service.dart';

void main() {
  Map<String, dynamic> taxon({
    int id = 1,
    String name = 'Amanita muscaria',
    String matchedTerm = 'Amanita muscaria',
    String rank = 'species',
    String iconic = 'Fungi',
  }) => {
    'id': id,
    'name': name,
    'matched_term': matchedTerm,
    'rank': rank,
    'iconic_taxon_name': iconic,
    'is_active': true,
    'observations_count': 42,
  };

  test('selects exact fungal scientific-name match case-insensitively', () {
    final match = selectConservativeTaxonMatch('amanita MUSCARIA', {
      'results': [taxon()],
    });
    expect(match.status, INaturalistMatchStatus.matched);
    expect(match.taxonId, 1);
    expect(match.globalObservationCount, 42);
  });

  test('accepts an exact synonym matched term and keeps accepted name', () {
    final match = selectConservativeTaxonMatch('Old fungus', {
      'results': [taxon(name: 'Accepted fungus', matchedTerm: 'Old fungus')],
    });
    expect(match.status, INaturalistMatchStatus.matched);
    expect(match.acceptedScientificName, 'Accepted fungus');
  });

  test('rejects genus result for a species query and non-fungi result', () {
    final genus = selectConservativeTaxonMatch('Amanita muscaria', {
      'results': [taxon(name: 'Amanita', rank: 'genus')],
    });
    final plant = selectConservativeTaxonMatch('Amanita muscaria', {
      'results': [taxon(iconic: 'Plantae')],
    });
    expect(genus.status, INaturalistMatchStatus.notFound);
    expect(plant.status, INaturalistMatchStatus.notFound);
  });

  test('marks multiple exact candidates ambiguous', () {
    final match = selectConservativeTaxonMatch('Amanita muscaria', {
      'results': [taxon(id: 1), taxon(id: 2)],
    });
    expect(match.status, INaturalistMatchStatus.ambiguous);
  });

  test(
    'parses aggregate count and collapses concurrent duplicate lookups',
    () async {
      var searchCalls = 0;
      final gate = Completer<void>();
      final service = INaturalistService(
        cache: MemoryINaturalistCacheStore(),
        rateLimiter: INaturalistRateLimiter(minimumInterval: Duration.zero),
        jsonGetter: (uri, headers) async {
          expect(headers['User-Agent'], startsWith('FungiApp/'));
          if (uri.path.endsWith('/taxa')) {
            searchCalls++;
            await gate.future;
            return {
              'results': [taxon()],
            };
          }
          if (uri.path.endsWith('/taxa/1')) {
            return {
              'results': [taxon()],
            };
          }
          expect(uri.queryParameters['per_page'], '0');
          return {'total_results': 99, 'results': []};
        },
      );
      final first = service.findTaxonByScientificName('Amanita muscaria');
      final second = service.findTaxonByScientificName(' Amanita   muscaria ');
      gate.complete();
      final values = await Future.wait([first, second]);
      expect(searchCalls, 1);
      expect(values.first.globalObservationCount, 99);
      expect(values.last.taxonId, 1);
    },
  );

  test('parses and sorts complete ancestry from kingdom to species', () {
    final nodes = parseINaturalistTaxonomy({
      'id': 4,
      'name': 'Amanita muscaria',
      'rank': 'species',
      'rank_level': 10,
      'preferred_common_name': 'Fly agaric',
      'ancestors': [
        {'id': 3, 'name': 'Amanita', 'rank': 'genus', 'rank_level': 20},
        {'id': 1, 'name': 'Fungi', 'rank': 'kingdom', 'rank_level': 70},
        {'id': 2, 'name': 'Amanitaceae', 'rank': 'family', 'rank_level': 30},
      ],
    });
    expect(nodes.map((node) => node.rank), [
      'kingdom',
      'family',
      'genus',
      'species',
    ]);
    expect(nodes.last.commonName, 'Fly agaric');
  });

  test('taxonomy tolerates missing ranks and malformed ancestry entries', () {
    final nodes = parseINaturalistTaxonomy({
      'id': 3,
      'name': 'Amanita muscaria',
      'rank': 'species',
      'ancestors': [
        {'id': 1, 'name': 'Fungi', 'rank': 'kingdom'},
        {'broken': true},
        'not a taxon',
        {'id': 2, 'name': 'Amanita', 'rank': 'genus'},
      ],
    });
    expect(nodes.map((node) => node.rank), ['kingdom', 'genus', 'species']);
  });

  test('exact detail rejects non-fungi and genus-level species matches', () {
    final plant = parseExactINaturalistTaxonDetails('Amanita muscaria', {
      ...taxon(iconic: 'Plantae'),
      'ancestors': const [],
    });
    final genus = parseExactINaturalistTaxonDetails('Amanita muscaria', {
      ...taxon(name: 'Amanita', rank: 'genus'),
      'ancestors': [
        {'id': 99, 'name': 'Fungi', 'rank': 'kingdom'},
      ],
    });
    expect(plant.status, INaturalistMatchStatus.notFound);
    expect(genus.status, INaturalistMatchStatus.notFound);
  });

  test('fresh cached taxonomy avoids another API call', () async {
    final cache = MemoryINaturalistCacheStore();
    final now = DateTime.now();
    await cache.write(
      INaturalistTaxonMatch(
        status: INaturalistMatchStatus.matched,
        requestName: 'Amanita muscaria',
        taxonId: 1,
        acceptedScientificName: 'Amanita muscaria',
        matchedName: 'Amanita muscaria',
        preferredCommonName: 'Fly agaric',
        rank: 'species',
        iconicTaxonName: 'Fungi',
        isActive: true,
        extinct: false,
        photoUrl: null,
        photoAttribution: null,
        photoLicense: null,
        taxonUrl: null,
        globalObservationCount: 12,
        regionalObservationCount: null,
        conservationStatus: null,
        conservationStatusAuthority: null,
        conservationStatusPlace: null,
        taxonomy: const [
          TaxonomyNode(
            taxonId: 99,
            rank: 'kingdom',
            scientificName: 'Fungi',
            commonName: null,
            rankLevel: 70,
          ),
        ],
        fetchedAt: now,
        expiresAt: now.add(const Duration(days: 2)),
      ),
    );
    final service = INaturalistService(
      cache: cache,
      rateLimiter: INaturalistRateLimiter(minimumInterval: Duration.zero),
      jsonGetter: (uri, headers) async =>
          throw StateError('network should not be called'),
    );
    final result = await service.findTaxonByScientificName('Amanita muscaria');
    expect(result.taxonomy.single.scientificName, 'Fungi');
  });

  test('parses month-of-year and dated year histogram keys', () {
    expect(
      parseINaturalistHistogramCounts({
        'results': {
          'month_of_year': {'1': 12, '10': 45},
        },
      }, interval: 'month_of_year'),
      {1: 12, 10: 45},
    );
    expect(
      parseINaturalistHistogramCounts({
        'results': {
          'year': {'2024-01-01': 80, '2025-01-01': 95},
        },
      }, interval: 'year'),
      {2024: 80, 2025: 95},
    );
  });

  test('online library keeps only fungal species with reusable clear photos', () {
    Map<String, dynamic> result({
      required int id,
      String iconic = 'Fungi',
      String rank = 'species',
      String? license = 'cc-by',
      int width = 800,
      bool includeDimensions = true,
    }) => {
      'id': id,
      'name': 'Fungus $id',
      'rank': rank,
      'iconic_taxon_name': iconic,
      'is_active': true,
      'default_photo': {
        'license_code': license,
        'attribution': '(c) Example photographer, CC BY',
        'medium_url':
            'https://inaturalist-open-data.s3.amazonaws.com/photos/$id/medium.jpg',
        if (includeDimensions)
          'original_dimensions': {'width': width, 'height': 600},
      },
    };
    final matches = parseLicensedFungalTaxa({
      'results': [
        result(id: 1),
        result(id: 2, iconic: 'Plantae'),
        result(id: 3, rank: 'genus'),
        result(id: 4, license: null),
        result(id: 5, width: 120),
        result(id: 6, license: 'cc-by-nc'),
        result(id: 7, license: 'cc-by-nd'),
        result(id: 8, includeDimensions: false),
      ],
    }, requestName: 'fungus');
    expect(matches.map((item) => item.taxonId), [1]);
    expect(matches.single.photoLicense, 'cc-by');
    expect(matches.single.photoAttribution, isNotEmpty);
  });
}
