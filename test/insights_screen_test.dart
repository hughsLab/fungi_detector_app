import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/observation.dart';
import 'package:realtime_detection_app/models/species.dart';
import 'package:realtime_detection_app/models/toxicity_level.dart';
import 'package:realtime_detection_app/screens/insights_screen.dart';
import 'package:realtime_detection_app/screens/home_screen.dart';

void main() {
  testWidgets('Insights navigation item appears directly after Map', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeExploreMenu(
            twoColumns: false,
            observationCount: 0,
            onTapObservations: () {},
            onTapLibrary: () {},
            onTapMap: () {},
            onTapInsights: () {},
            onTapNotes: () {},
          ),
        ),
      ),
    );
    final mapY = tester
        .getTopLeft(find.byKey(const Key('home-map-menu-item')))
        .dy;
    final insightsY = tester
        .getTopLeft(find.byKey(const Key('home-insights-menu-item')))
        .dy;
    final notesY = tester
        .getTopLeft(find.byKey(const Key('home-notes-menu-item')))
        .dy;
    expect(find.text('Insights'), findsOneWidget);
    expect(insightsY, greaterThan(mapY));
    expect(notesY, greaterThan(insightsY));
  });

  testWidgets('shows loading and empty states', (tester) async {
    final completer = Completer<List<Observation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(
          personalLoader: () => completer.future,
          speciesLoader: () async => const [],
        ),
      ),
    );
    expect(find.byKey(const Key('insights-loading')), findsOneWidget);
    completer.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No insights yet'), findsOneWidget);
  });

  testWidgets('shows a non-destructive error with retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(
          personalLoader: () => Future.error(StateError('failed')),
          speciesLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Insights could not be loaded'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'renders summary, species controls, list, and poisonous warning',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final species = Species.fromJson({
        'id': '1',
        'scientificName': 'Amanita example',
        'commonName': 'Example cap',
      });
      final observation = Observation(
        id: '1',
        speciesId: '1',
        classIndex: null,
        label: 'Example cap',
        confidence: .82,
        createdAt: DateTime(2026, 7, 20),
        photoPath: null,
        detectionSource: 'online_mushroom_id',
        identificationSource: 'online_mushroom_id',
        onlineIdentification: true,
        toxicityLevel: ToxicityLevel.poisonous,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InsightsScreen(
            personalLoader: () async => [observation],
            speciesLoader: () async => [species],
            now: () => DateTime(2026, 7, 21),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total observations'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('insights-species-search')),
        700,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Detections by Species'), findsOneWidget);
      expect(find.byKey(const Key('insights-species-search')), findsOneWidget);
      expect(find.byKey(const Key('insights-sort')), findsOneWidget);
      expect(find.text('Example cap'), findsWidgets);
      expect(
        find.byTooltip('Poisonous or potentially poisonous'),
        findsOneWidget,
      );
    },
  );

  testWidgets('search filters the species detection list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final species = [
      Species.fromJson({
        'id': '1',
        'scientificName': 'Amanita one',
        'commonName': 'First cap',
      }),
      Species.fromJson({
        'id': '2',
        'scientificName': 'Boletus two',
        'commonName': 'Second cap',
      }),
    ];
    final observations = [
      _observation('1', '1', 'First cap'),
      _observation('2', '2', 'Second cap'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(
          personalLoader: () async => observations,
          speciesLoader: () async => species,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('insights-species-search')),
      700,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('insights-species-search')),
      'boletus',
    );
    await tester.pump();
    expect(find.text('Second cap'), findsWidgets);
    expect(find.text('First cap'), findsNothing);
  });

  testWidgets('presents observations as a personal fungi profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final species = Species.fromJson({
      'id': '1',
      'scientificName': 'Amanita example',
      'commonName': 'Example cap',
      'taxonomy': {'phylum': 'Basidiomycota', 'family': 'Amanitaceae'},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(
          personalLoader: () async => [_observation('1', '1', 'Example cap')],
          speciesLoader: () async => [species],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fungi-profile-hero')), findsOneWidget);
    expect(find.text('My fungi profile'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('When I find fungi'), findsOneWidget);
    expect(find.byKey(const Key('fungi-observation-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Observation _observation(String id, String speciesId, String label) =>
    Observation(
      id: id,
      speciesId: speciesId,
      classIndex: null,
      label: label,
      confidence: .7,
      createdAt: DateTime(2026, 7, 1),
      photoPath: null,
      detectionSource: 'offline_model',
      identificationSource: 'offline',
    );
