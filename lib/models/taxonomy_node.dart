class TaxonomyNode {
  final int? taxonId;
  final String rank;
  final String scientificName;
  final String? commonName;
  final double? rankLevel;

  const TaxonomyNode({
    required this.taxonId,
    required this.rank,
    required this.scientificName,
    required this.commonName,
    required this.rankLevel,
  });

  Map<String, dynamic> toJson() => {
    'taxonId': taxonId,
    'rank': rank,
    'scientificName': scientificName,
    'commonName': commonName,
    'rankLevel': rankLevel,
  };

  factory TaxonomyNode.fromJson(Map<String, dynamic> json) => TaxonomyNode(
    taxonId: _asInt(json['taxonId']),
    rank: json['rank']?.toString() ?? '',
    scientificName: json['scientificName']?.toString() ?? '',
    commonName: json['commonName']?.toString(),
    rankLevel: _asDouble(json['rankLevel']),
  );
}

int? _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

double? _asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
