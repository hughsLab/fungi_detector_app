import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/inaturalist_taxon.dart';
import 'package:realtime_detection_app/repositories/inaturalist_cache_repository.dart';
import 'package:realtime_detection_app/repositories/species_repository.dart';
import 'package:realtime_detection_app/screens/species_library_screen.dart';
import 'package:realtime_detection_app/services/inaturalist_rate_limiter.dart';
import 'package:realtime_detection_app/services/inaturalist_service.dart';

void main() {
  testWidgets('offline matches continue into licensed online fungal results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(SpeciesRepository.instance.loadSpecies);
    await tester.pumpWidget(
      MaterialApp(
        home: SpeciesLibraryScreen(
          iNaturalistService: _FakeLibraryService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const Key('fungi-library-search')),
      'Amanita',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Offline field guide'), findsOneWidget);
    expect(find.text('Online library continuation'), findsOneWidget);
    expect(find.text('Amanita muscaria'), findsWidgets);
    expect(find.text('Amanita exampleii'), findsOneWidget);
    expect(find.textContaining('CC-BY'), findsWidgets);
  });
}

class _FakeLibraryService extends INaturalistService {
  _FakeLibraryService()
    : super(
        cache: MemoryINaturalistCacheStore(),
        histogramCache: MemoryINaturalistHistogramCacheStore(),
        librarySearchCache: MemoryINaturalistLibrarySearchCacheStore(),
        rateLimiter: INaturalistRateLimiter(minimumInterval: Duration.zero),
      );

  @override
  Future<List<INaturalistTaxonMatch>> searchFungalTaxa(
    String query, {
    int limit = 30,
  }) async {
    final now = DateTime(2026);
    INaturalistTaxonMatch taxon(int id, String name, String commonName) =>
        INaturalistTaxonMatch(
          status: INaturalistMatchStatus.matched,
          requestName: query,
          taxonId: id,
          acceptedScientificName: name,
          matchedName: name,
          preferredCommonName: commonName,
          rank: 'species',
          iconicTaxonName: 'Fungi',
          isActive: true,
          extinct: false,
          photoUrl:
              'https://inaturalist-open-data.s3.amazonaws.com/photos/$id/medium.jpg',
          photoAttribution: '(c) Example, CC BY',
          photoLicense: 'cc-by',
          taxonUrl: 'https://www.inaturalist.org/taxa/$id',
          globalObservationCount: 10,
          regionalObservationCount: null,
          conservationStatus: null,
          conservationStatusAuthority: null,
          conservationStatusPlace: null,
          fetchedAt: now,
          expiresAt: DateTime(2027),
        );
    return [
      taxon(1, 'Amanita muscaria', 'Fly Agaric'),
      taxon(2, 'Amanita exampleii', 'Example Amanita'),
    ];
  }
}
