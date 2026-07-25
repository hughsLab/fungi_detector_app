import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/repositories/species_repository.dart';
import 'package:realtime_detection_app/screens/species_library_screen.dart';

void main() {
  testWidgets('fungi library opens with a scrollable offline catalogue', (
    tester,
  ) async {
    await tester.runAsync(SpeciesRepository.instance.loadSpecies);
    await tester.pumpWidget(const MaterialApp(home: SpeciesLibraryScreen()));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('fungi-scroll-list'));
    expect(list, findsOneWidget);
    expect(find.text('Browse fungi'), findsOneWidget);
    expect(find.textContaining('offline species'), findsOneWidget);
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);

    await tester.fling(list, const Offset(0, -1200), 1800);
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
  });
}
