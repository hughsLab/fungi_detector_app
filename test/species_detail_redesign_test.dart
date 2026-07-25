import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/inaturalist_observation_histogram.dart';
import 'package:realtime_detection_app/models/inaturalist_taxon.dart';
import 'package:realtime_detection_app/models/navigation_args.dart';
import 'package:realtime_detection_app/models/taxonomy_node.dart';
import 'package:realtime_detection_app/models/wikipedia_species_content.dart';
import 'package:realtime_detection_app/repositories/inaturalist_cache_repository.dart';
import 'package:realtime_detection_app/repositories/species_enrichment_cache_repository.dart';
import 'package:realtime_detection_app/repositories/species_repository.dart';
import 'package:realtime_detection_app/screens/species_detail_screen.dart';
import 'package:realtime_detection_app/services/inaturalist_rate_limiter.dart';
import 'package:realtime_detection_app/services/inaturalist_service.dart';
import 'package:realtime_detection_app/services/wikipedia_service.dart';

void main() {
  late INaturalistTaxonMatch taxon;
  late WikipediaSpeciesContent wikipedia;

  setUp(() {
    final now = DateTime.now();
    taxon = INaturalistTaxonMatch(
      status: INaturalistMatchStatus.matched,
      requestName: 'Aleuria aurantia',
      taxonId: 5258678,
      acceptedScientificName: 'Aleuria aurantia',
      matchedName: 'Aleuria aurantia',
      preferredCommonName: 'Orange peel fungus',
      rank: 'species',
      iconicTaxonName: 'Fungi',
      isActive: true,
      extinct: false,
      photoUrl: null,
      photoAttribution: null,
      photoLicense: null,
      taxonUrl: 'https://www.inaturalist.org/taxa/5258678',
      globalObservationCount: 1200,
      regionalObservationCount: null,
      conservationStatus: 'S3',
      conservationStatusAuthority: 'Example authority',
      conservationStatusPlace: 'Example region',
      taxonomy: const [
        TaxonomyNode(
          taxonId: 1,
          rank: 'kingdom',
          scientificName: 'Fungi',
          commonName: null,
          rankLevel: 70,
        ),
        TaxonomyNode(
          taxonId: 2,
          rank: 'phylum',
          scientificName: 'Ascomycota',
          commonName: 'Sac fungi',
          rankLevel: 60,
        ),
        TaxonomyNode(
          taxonId: 5258678,
          rank: 'species',
          scientificName: 'Aleuria aurantia',
          commonName: 'Orange peel fungus',
          rankLevel: 10,
        ),
      ],
      fetchedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
    );
    wikipedia = WikipediaSpeciesContent(
      status: WikipediaMatchStatus.matched,
      requestedScientificName: 'Aleuria aurantia',
      pageTitle: 'Aleuria aurantia',
      pageDescription: 'species of fungus',
      summaryExtract:
          'Aleuria aurantia is a bright orange cup fungus found on bare soil.',
      descriptionText: List.filled(
        80,
        'The fruiting body is cup-shaped and orange.',
      ).join(' '),
      thumbnailUrl: null,
      originalImageUrl: null,
      articleUrl: 'https://en.wikipedia.org/wiki/Aleuria_aurantia',
      imageSourceUrl: null,
      imageAttribution: 'Example creator',
      imageLicense: 'CC BY-SA 4.0',
      imageLicenseUrl: null,
      fetchedAt: now,
      expiresAt: now.add(const Duration(days: 30)),
    );
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    Future<WikipediaSpeciesContent>? wikipediaFuture,
    Future<INaturalistTaxonMatch>? taxonFuture,
  }) async {
    await tester.runAsync(SpeciesRepository.instance.loadSpecies);
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/detail',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: RouteSettings(
            name: '/detail',
            arguments: const SpeciesDetailArgs(speciesId: '0'),
          ),
          builder: (_) => SpeciesDetailScreen(
            iNaturalistService: _FakeINaturalistService(
              taxonFuture ?? Future.value(taxon),
            ),
            wikipediaService: _FakeWikipediaService(
              wikipediaFuture ?? Future.value(wikipedia),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('detail uses italic names and moves safety below enrichment', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.text('Toxicity and Safety'), findsNothing);
    final scientific = tester.widget<Text>(find.text('Aleuria aurantia').first);
    final common = tester.widget<Text>(find.text('orange peel fungus'));
    expect(scientific.style?.fontStyle, FontStyle.italic);
    expect(common.style?.fontStyle, FontStyle.italic);

    expect(find.text('Reference image'), findsOneWidget);
    expect(find.text('About this species'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Taxonomy'), findsOneWidget);
    expect(find.byKey(const Key('compact-safety-section')), findsOneWidget);
    expect(find.byKey(const Key('data-attribution-section')), findsOneWidget);

    final safetyY = tester
        .getTopLeft(find.byKey(const Key('compact-safety-section')))
        .dy;
    final taxonomyY = tester.getTopLeft(find.text('Taxonomy')).dy;
    expect(safetyY, greaterThan(taxonomyY));
  });

  testWidgets('Description expands and taxonomy names are italic', (
    tester,
  ) async {
    await pumpDetail(tester);

    final taxonomyName = tester.widget<Text>(find.text('Ascomycota'));
    expect(taxonomyName.style?.fontStyle, FontStyle.italic);
    expect(find.text('Show more'), findsOneWidget);
    await tester.ensureVisible(find.text('Show more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('Wikipedia and taxonomy show independent loading states', (
    tester,
  ) async {
    final wikipediaCompleter = Completer<WikipediaSpeciesContent>();
    final taxonCompleter = Completer<INaturalistTaxonMatch>();
    await pumpDetail(
      tester,
      wikipediaFuture: wikipediaCompleter.future,
      taxonFuture: taxonCompleter.future,
    );

    expect(find.byKey(const Key('wikipedia-loading')), findsOneWidget);
    expect(find.byKey(const Key('taxonomy-loading')), findsOneWidget);
  });

  testWidgets('partial Wikipedia failure does not hide taxonomy', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpDetail(
      tester,
      wikipediaFuture: Future.value(
        WikipediaSpeciesContent.statusOnly(
          status: WikipediaMatchStatus.unavailable,
          requestedScientificName: 'Aleuria aurantia',
          fetchedAt: now,
        ),
      ),
    );

    expect(
      find.text('Wikipedia information is currently unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Ascomycota'), findsOneWidget);
  });
}

class _FakeWikipediaService extends WikipediaService {
  _FakeWikipediaService(this.result)
    : super(
        cache: MemoryWikipediaSpeciesCacheStore(),
        jsonGetter: (uri, headers) async => const {},
      );

  final Future<WikipediaSpeciesContent> result;

  @override
  Future<WikipediaSpeciesContent> findSpecies(
    String scientificName, {
    Iterable<String> synonyms = const [],
  }) => result;
}

class _FakeINaturalistService extends INaturalistService {
  _FakeINaturalistService(this.result)
    : super(
        cache: MemoryINaturalistCacheStore(),
        histogramCache: MemoryINaturalistHistogramCacheStore(),
        librarySearchCache: MemoryINaturalistLibrarySearchCacheStore(),
        rateLimiter: INaturalistRateLimiter(minimumInterval: Duration.zero),
      );

  final Future<INaturalistTaxonMatch> result;

  @override
  Future<INaturalistTaxonMatch> findTaxonByScientificName(
    String scientificName, {
    String? placeId,
    int? storedTaxonId,
    Iterable<String> synonyms = const [],
  }) => result;

  @override
  Future<INaturalistObservationHistogram?> getObservationHistogramForTaxon(
    int taxonId,
  ) async => null;
}
