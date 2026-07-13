class MushroomIdResult {
  final String source;
  final bool onlineIdentification;
  final MushroomIdSuggestion? topSuggestion;
  final List<MushroomIdSuggestion> alternatives;
  final List<String> warnings;
  final bool? regionSupported;
  final bool locationFilterApplied;

  const MushroomIdResult({
    required this.source,
    required this.onlineIdentification,
    required this.topSuggestion,
    this.alternatives = const <MushroomIdSuggestion>[],
    this.warnings = const <String>[],
    this.regionSupported,
    this.locationFilterApplied = false,
  });

  factory MushroomIdResult.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = _parseProviderSuggestionList(
      _readProviderSuggestions(json),
    );
    final parsedTopSuggestion = _parseSuggestion(json['topSuggestion']);
    final parsedAlternatives = _parseSuggestionList(json['alternatives']);
    return MushroomIdResult(
      source: json['source']?.toString() ?? 'mushroom.id',
      onlineIdentification: json['onlineIdentification'] is bool
          ? json['onlineIdentification'] as bool
          : true,
      topSuggestion: parsedTopSuggestion ??
          (rawSuggestions.isEmpty ? null : rawSuggestions.first),
      alternatives: parsedAlternatives.isNotEmpty || rawSuggestions.isEmpty
          ? parsedAlternatives
          : rawSuggestions.skip(1).take(4).toList(growable: false),
      warnings: _parseStringList(json['warnings']),
      regionSupported: json['regionSupported'] is bool
          ? json['regionSupported'] as bool
          : null,
      locationFilterApplied: json['locationFilterApplied'] is bool
          ? json['locationFilterApplied'] as bool
          : false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'onlineIdentification': onlineIdentification,
      'topSuggestion': topSuggestion?.toJson(),
      'alternatives': alternatives.map((item) => item.toJson()).toList(),
      'warnings': warnings,
      'regionSupported': regionSupported,
      'locationFilterApplied': locationFilterApplied,
    };
  }

  bool get hasConfidentTopSuggestion =>
      (topSuggestion?.probability ?? 0.0) >= 0.20;
}

class MushroomIdSuggestion {
  final String scientificName;
  final double probability;
  final double confidencePercent;
  final List<String> commonNames;
  final String? edibility;
  final String? toxicity;
  final String? rank;
  final String? description;
  final String? url;
  final Map<String, String> taxonomy;
  final List<MushroomIdSimilarImage> similarImages;

  const MushroomIdSuggestion({
    required this.scientificName,
    required this.probability,
    required this.confidencePercent,
    this.commonNames = const <String>[],
    this.edibility,
    this.toxicity,
    this.rank,
    this.description,
    this.url,
    this.taxonomy = const <String, String>{},
    this.similarImages = const <MushroomIdSimilarImage>[],
  });

  factory MushroomIdSuggestion.fromJson(Map<String, dynamic> json) {
    final details = _parseDynamicMap(json['details']);
    final probability = _parseDouble(json['probability']) ?? 0.0;
    return MushroomIdSuggestion(
      scientificName: json['scientificName']?.toString() ??
          json['name']?.toString() ??
          details['scientific_name']?.toString() ??
          details['scientificName']?.toString() ??
          '',
      probability: probability,
      confidencePercent: _parseDouble(json['confidencePercent']) ??
          (probability * 100.0),
      commonNames: _parseStringList(
        json['commonNames'] ?? json['common_names'] ?? details['common_names'],
      ),
      edibility: _nonEmpty(json['edibility'] ?? details['edibility']),
      toxicity: _nonEmpty(json['toxicity'] ?? details['toxicity']),
      rank: _nonEmpty(json['rank'] ?? details['rank']),
      description: _descriptionText(json['description'] ?? details['description']),
      url: _nonEmpty(json['url'] ?? details['url']),
      taxonomy: _parseStringMap(json['taxonomy'] ?? details['taxonomy']),
      similarImages: _parseSimilarImages(
        json['similarImages'] ?? json['similar_images'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scientificName': scientificName,
      'probability': probability,
      'confidencePercent': confidencePercent,
      'commonNames': commonNames,
      'edibility': edibility,
      'toxicity': toxicity,
      'rank': rank,
      'description': description,
      'url': url,
      'taxonomy': taxonomy,
      'similarImages': similarImages.map((item) => item.toJson()).toList(),
    };
  }

  Map<String, dynamic> toCompactJson() => toJson();
}

class MushroomIdSimilarImage {
  final String? urlSmall;
  final String? url;
  final double? similarity;
  final String? citation;
  final String? licenseName;

  const MushroomIdSimilarImage({
    this.urlSmall,
    this.url,
    this.similarity,
    this.citation,
    this.licenseName,
  });

  factory MushroomIdSimilarImage.fromJson(Map<String, dynamic> json) {
    return MushroomIdSimilarImage(
      urlSmall: _nonEmpty(json['urlSmall'] ?? json['url_small']),
      url: _nonEmpty(json['url']),
      similarity: _parseDouble(json['similarity']),
      citation: _nonEmpty(json['citation']),
      licenseName: _nonEmpty(json['licenseName'] ?? json['license_name']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'urlSmall': urlSmall,
      'url': url,
      'similarity': similarity,
      'citation': citation,
      'licenseName': licenseName,
    };
  }
}

dynamic _readProviderSuggestions(Map<String, dynamic> json) {
  final result = _parseDynamicMap(json['result']);
  final resultClassification = _parseDynamicMap(result['classification']);
  final classification = _parseDynamicMap(json['classification']);
  return resultClassification['suggestions'] ??
      classification['suggestions'] ??
      json['suggestions'];
}

List<MushroomIdSuggestion> _parseProviderSuggestionList(dynamic value) {
  if (value is! List) {
    return const <MushroomIdSuggestion>[];
  }
  return value
      .map(_parseSuggestion)
      .whereType<MushroomIdSuggestion>()
      .toList(growable: false);
}

MushroomIdSuggestion? _parseSuggestion(dynamic value) {
  if (value is Map<String, dynamic>) {
    final suggestion = MushroomIdSuggestion.fromJson(value);
    return suggestion.scientificName.trim().isEmpty ? null : suggestion;
  }
  if (value is Map) {
    final suggestion = MushroomIdSuggestion.fromJson(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
    return suggestion.scientificName.trim().isEmpty ? null : suggestion;
  }
  return null;
}

Map<String, dynamic> _parseDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<MushroomIdSuggestion> _parseSuggestionList(dynamic value) {
  if (value is! List) {
    return const <MushroomIdSuggestion>[];
  }
  return value
      .map(_parseSuggestion)
      .whereType<MushroomIdSuggestion>()
      .toList(growable: false);
}

List<MushroomIdSimilarImage> _parseSimilarImages(dynamic value) {
  if (value is! List) {
    return const <MushroomIdSimilarImage>[];
  }
  final images = <MushroomIdSimilarImage>[];
  for (final item in value) {
    if (item is Map<String, dynamic>) {
      images.add(MushroomIdSimilarImage.fromJson(item));
    } else if (item is Map) {
      images.add(
        MushroomIdSimilarImage.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
  }
  return images;
}

List<String> _parseStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _parseStringMap(dynamic value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  final output = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    final val = entry.value?.toString().trim() ?? '';
    if (key.isNotEmpty && val.isNotEmpty) {
      output[key] = val;
    }
  }
  return output;
}

double? _parseDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

String? _descriptionText(dynamic value) {
  if (value is Map) {
    return _nonEmpty(value['value'] ?? value['text']);
  }
  return _nonEmpty(value);
}

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
