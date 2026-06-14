import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/widgets/key_features_section.dart';

void main() {
  testWidgets('renders key identifying features as compact bullets',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KeyFeaturesSection(
            features: [
              'Bright orange cup-shaped fruiting bodies.',
              'Usually lacks a distinct stem.',
            ],
          ),
        ),
      ),
    );

    expect(find.text('Key Identifying Features'), findsOneWidget);
    expect(
      find.text('Bright orange cup-shaped fruiting bodies.'),
      findsOneWidget,
    );
    expect(find.text('Usually lacks a distinct stem.'), findsOneWidget);
    expect(find.text('No identifying features listed.'), findsNothing);
  });

  testWidgets('renders fallback when no features are available', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KeyFeaturesSection(features: <String>[]),
        ),
      ),
    );

    expect(find.text('Key Identifying Features'), findsOneWidget);
    expect(find.text('No identifying features listed.'), findsOneWidget);
  });
}
