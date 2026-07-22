import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/inaturalist_taxon.dart';
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
      'results': [
        taxon(name: 'Accepted fungus', matchedTerm: 'Old fungus'),
      ],
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

  test('parses aggregate count and collapses concurrent duplicate lookups', () async {
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
          return {'results': [taxon()]};
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
  });
}

