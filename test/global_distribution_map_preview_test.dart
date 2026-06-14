import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/species_map_marker.dart';
import 'package:realtime_detection_app/widgets/global_distribution_map_preview.dart';

void main() {
  testWidgets('shows fallback text when no markers are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlobalDistributionMapPreview(),
        ),
      ),
    );

    expect(
      find.text('Location data not available for this species.'),
      findsOneWidget,
    );
  });

  testWidgets('shows presence note and marker label after tapping a marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlobalDistributionMapPreview(
            markers: <SpeciesMapMarker>[
              SpeciesMapMarker(
                label: 'Tasmania',
                latitude: -42.0409,
                longitude: 146.8087,
                source: 'australia.states',
                note: 'Presence record / regional location',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Presence markers are approximate and do not imply abundance.'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.location_on));
    await tester.pump();

    expect(find.text('Tasmania'), findsOneWidget);
    expect(find.text('Presence record / regional location'), findsOneWidget);
  });
}
