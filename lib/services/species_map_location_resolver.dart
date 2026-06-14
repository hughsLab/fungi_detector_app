import '../models/species.dart';
import '../models/species_map_marker.dart';

class SpeciesMapLocationResolver {
  const SpeciesMapLocationResolver();

  static const SpeciesMapLocationResolver instance =
      SpeciesMapLocationResolver();

  List<SpeciesMapMarker> resolveMarkers(Species species) {
    return resolveMarkersFromLocation(species.location);
  }

  List<SpeciesMapMarker> resolveMarkersFromLocation(SpeciesLocation location) {
    final markers = <SpeciesMapMarker>[];
    final addedKeys = <String>{};
    final hasAustralianStateMarkers = location.australiaStates.any(
      (state) => _locationFor(state) != null,
    );

    for (final state in location.australiaStates) {
      final lookup = _locationFor(state);
      if (lookup == null) {
        continue;
      }
      _addMarker(
        markers: markers,
        addedKeys: addedKeys,
        lookup: lookup,
        source: 'australia.states',
      );
    }

    for (final region in location.global) {
      if (hasAustralianStateMarkers && _normalize(region) == 'australia') {
        continue;
      }
      final lookup = _locationFor(region);
      if (lookup == null) {
        continue;
      }
      _addMarker(
        markers: markers,
        addedKeys: addedKeys,
        lookup: lookup,
        source: 'global',
      );
    }

    return List.unmodifiable(markers);
  }

  void _addMarker({
    required List<SpeciesMapMarker> markers,
    required Set<String> addedKeys,
    required _LookupLocation lookup,
    required String source,
  }) {
    final key = '${_normalize(lookup.label)}:'
        '${lookup.latitude.toStringAsFixed(3)}:'
        '${lookup.longitude.toStringAsFixed(3)}';
    if (!addedKeys.add(key)) {
      return;
    }
    markers.add(
      SpeciesMapMarker(
        label: lookup.label,
        latitude: lookup.latitude,
        longitude: lookup.longitude,
        source: source,
        note: 'Presence record / regional location',
      ),
    );
  }

  static _LookupLocation? _locationFor(String value) {
    return _locationLookup[_normalize(value)];
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _LookupLocation {
  final String label;
  final double latitude;
  final double longitude;

  const _LookupLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
  });
}

const Map<String, _LookupLocation> _locationLookup = {
  'australia': _LookupLocation(
    label: 'Australia',
    latitude: -25.2744,
    longitude: 133.7751,
  ),
  'tasmania': _LookupLocation(
    label: 'Tasmania',
    latitude: -42.0409,
    longitude: 146.8087,
  ),
  'victoria': _LookupLocation(
    label: 'Victoria',
    latitude: -37.4713,
    longitude: 144.7852,
  ),
  'new south wales': _LookupLocation(
    label: 'New South Wales',
    latitude: -31.2532,
    longitude: 146.9211,
  ),
  'nsw': _LookupLocation(
    label: 'New South Wales',
    latitude: -31.2532,
    longitude: 146.9211,
  ),
  'queensland': _LookupLocation(
    label: 'Queensland',
    latitude: -20.9176,
    longitude: 142.7028,
  ),
  'south australia': _LookupLocation(
    label: 'South Australia',
    latitude: -30.0002,
    longitude: 136.2092,
  ),
  'western australia': _LookupLocation(
    label: 'Western Australia',
    latitude: -27.6728,
    longitude: 121.6283,
  ),
  'northern territory': _LookupLocation(
    label: 'Northern Territory',
    latitude: -19.4914,
    longitude: 132.5510,
  ),
  'australian capital territory': _LookupLocation(
    label: 'Australian Capital Territory',
    latitude: -35.4735,
    longitude: 149.0124,
  ),
  'act': _LookupLocation(
    label: 'Australian Capital Territory',
    latitude: -35.4735,
    longitude: 149.0124,
  ),
  'new zealand': _LookupLocation(
    label: 'New Zealand',
    latitude: -40.9006,
    longitude: 174.8860,
  ),
  'europe': _LookupLocation(
    label: 'Europe',
    latitude: 54.5260,
    longitude: 15.2551,
  ),
  'north america': _LookupLocation(
    label: 'North America',
    latitude: 54.5260,
    longitude: -105.2551,
  ),
  'south america': _LookupLocation(
    label: 'South America',
    latitude: -8.7832,
    longitude: -55.4915,
  ),
  'asia': _LookupLocation(
    label: 'Asia',
    latitude: 34.0479,
    longitude: 100.6197,
  ),
  'africa': _LookupLocation(
    label: 'Africa',
    latitude: -8.7832,
    longitude: 34.5085,
  ),
  'united kingdom': _LookupLocation(
    label: 'United Kingdom',
    latitude: 55.3781,
    longitude: -3.4360,
  ),
  'uk': _LookupLocation(
    label: 'United Kingdom',
    latitude: 55.3781,
    longitude: -3.4360,
  ),
  'united states': _LookupLocation(
    label: 'United States',
    latitude: 39.8283,
    longitude: -98.5795,
  ),
  'usa': _LookupLocation(
    label: 'United States',
    latitude: 39.8283,
    longitude: -98.5795,
  ),
  'canada': _LookupLocation(
    label: 'Canada',
    latitude: 56.1304,
    longitude: -106.3468,
  ),
  'chile': _LookupLocation(
    label: 'Chile',
    latitude: -35.6751,
    longitude: -71.5430,
  ),
  'new caledonia': _LookupLocation(
    label: 'New Caledonia',
    latitude: -20.9043,
    longitude: 165.6180,
  ),
  'oceania': _LookupLocation(
    label: 'Oceania',
    latitude: -22.7359,
    longitude: 140.0188,
  ),
  'europe and asia': _LookupLocation(
    label: 'Europe and Asia',
    latitude: 48.0,
    longitude: 60.0,
  ),
};
