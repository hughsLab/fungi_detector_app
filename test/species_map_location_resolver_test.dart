import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_detection_app/models/species.dart';
import 'package:realtime_detection_app/services/species_map_location_resolver.dart';

void main() {
  const resolver = SpeciesMapLocationResolver();

  test('returns Australian state markers from location state records', () {
    final markers = resolver.resolveMarkersFromLocation(
      const SpeciesLocation(
        global: <String>['Australia'],
        australiaStates: <String>[
          'Tasmania',
          'Victoria',
          'New South Wales',
        ],
        regionalNotes: <String>[],
      ),
    );

    expect(
      markers.map((marker) => marker.label),
      containsAll(<String>['Tasmania', 'Victoria', 'New South Wales']),
    );
    expect(markers.firstWhere((marker) => marker.label == 'Tasmania').latitude,
        -42.0409);
  });

  test('skips broad Australia marker when state markers are available', () {
    final markers = resolver.resolveMarkersFromLocation(
      const SpeciesLocation(
        global: <String>['Australia', 'New Zealand'],
        australiaStates: <String>['Tasmania'],
        regionalNotes: <String>[],
      ),
    );

    expect(markers.map((marker) => marker.label), contains('Tasmania'));
    expect(markers.map((marker) => marker.label), contains('New Zealand'));
    expect(markers.map((marker) => marker.label), isNot(contains('Australia')));
  });

  test('returns broad global markers from location global records', () {
    final markers = resolver.resolveMarkersFromLocation(
      const SpeciesLocation(
        global: <String>['New Zealand', 'Europe', 'North America'],
        australiaStates: <String>[],
        regionalNotes: <String>[],
      ),
    );

    expect(
      markers.map((marker) => marker.label),
      containsAll(<String>['New Zealand', 'Europe', 'North America']),
    );
    expect(
      markers.every((marker) => marker.source == 'global'),
      isTrue,
    );
  });

  test('deduplicates repeated locations and keeps unknown strings harmless', () {
    final markers = resolver.resolveMarkersFromLocation(
      const SpeciesLocation(
        global: <String>['Europe', 'Europe', 'Atlantis'],
        australiaStates: <String>['Tasmania', 'Tasmania', 'Unknown State'],
        regionalNotes: <String>[],
      ),
    );

    expect(
      markers.where((marker) => marker.label == 'Europe'),
      hasLength(1),
    );
    expect(
      markers.where((marker) => marker.label == 'Tasmania'),
      hasLength(1),
    );
  });
}
