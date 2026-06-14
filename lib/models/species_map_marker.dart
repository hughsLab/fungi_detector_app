class SpeciesMapMarker {
  final String label;
  final double latitude;
  final double longitude;
  final String source;
  final String? note;

  const SpeciesMapMarker({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.note,
  });
}
