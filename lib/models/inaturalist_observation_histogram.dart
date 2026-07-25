class INaturalistObservationHistogram {
  final int taxonId;
  final Map<int, int> observationsByMonth;
  final Map<int, int> observationsByYear;
  final DateTime fetchedAt;
  final DateTime expiresAt;

  const INaturalistObservationHistogram({
    required this.taxonId,
    required this.observationsByMonth,
    required this.observationsByYear,
    required this.fetchedAt,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'cacheFormatVersion': 1,
    'taxonId': taxonId,
    'observationsByMonth': observationsByMonth.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
    'observationsByYear': observationsByYear.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
    'fetchedAt': fetchedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory INaturalistObservationHistogram.fromJson(
    Map<String, dynamic> json,
  ) {
    return INaturalistObservationHistogram(
      taxonId: _asInt(json['taxonId']) ?? 0,
      observationsByMonth: _parseCountMap(json['observationsByMonth']),
      observationsByYear: _parseCountMap(json['observationsByYear']),
      fetchedAt:
          DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

Map<int, int> _parseCountMap(dynamic value) {
  if (value is! Map) return const {};
  final result = <int, int>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    final count = _asInt(entry.value);
    if (key != null && count != null && count >= 0) result[key] = count;
  }
  return result;
}

int? _asInt(dynamic value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '');
