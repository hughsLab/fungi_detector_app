enum WikipediaMatchStatus { matched, ambiguous, notFound, unavailable }

class WikipediaSpeciesContent {
  final WikipediaMatchStatus status;
  final String requestedScientificName;
  final String? pageTitle;
  final String? pageDescription;
  final String? summaryExtract;
  final String? descriptionText;
  final String? thumbnailUrl;
  final String? originalImageUrl;
  final String? articleUrl;
  final String? imageSourceUrl;
  final String? imageAttribution;
  final String? imageLicense;
  final String? imageLicenseUrl;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final bool isStale;

  const WikipediaSpeciesContent({
    required this.status,
    required this.requestedScientificName,
    required this.pageTitle,
    required this.pageDescription,
    required this.summaryExtract,
    required this.descriptionText,
    required this.thumbnailUrl,
    required this.originalImageUrl,
    required this.articleUrl,
    required this.imageSourceUrl,
    required this.imageAttribution,
    required this.imageLicense,
    required this.imageLicenseUrl,
    required this.fetchedAt,
    required this.expiresAt,
    this.isStale = false,
  });

  factory WikipediaSpeciesContent.statusOnly({
    required WikipediaMatchStatus status,
    required String requestedScientificName,
    required DateTime fetchedAt,
  }) => WikipediaSpeciesContent(
    status: status,
    requestedScientificName: requestedScientificName,
    pageTitle: null,
    pageDescription: null,
    summaryExtract: null,
    descriptionText: null,
    thumbnailUrl: null,
    originalImageUrl: null,
    articleUrl: null,
    imageSourceUrl: null,
    imageAttribution: null,
    imageLicense: null,
    imageLicenseUrl: null,
    fetchedAt: fetchedAt,
    expiresAt: fetchedAt.add(const Duration(days: 1)),
  );

  WikipediaSpeciesContent copyWith({bool? isStale}) => WikipediaSpeciesContent(
    status: status,
    requestedScientificName: requestedScientificName,
    pageTitle: pageTitle,
    pageDescription: pageDescription,
    summaryExtract: summaryExtract,
    descriptionText: descriptionText,
    thumbnailUrl: thumbnailUrl,
    originalImageUrl: originalImageUrl,
    articleUrl: articleUrl,
    imageSourceUrl: imageSourceUrl,
    imageAttribution: imageAttribution,
    imageLicense: imageLicense,
    imageLicenseUrl: imageLicenseUrl,
    fetchedAt: fetchedAt,
    expiresAt: expiresAt,
    isStale: isStale ?? this.isStale,
  );

  Map<String, dynamic> toJson() => {
    'cacheFormatVersion': 1,
    'status': status.name,
    'requestedScientificName': requestedScientificName,
    'pageTitle': pageTitle,
    'pageDescription': pageDescription,
    'summaryExtract': summaryExtract,
    'descriptionText': descriptionText,
    'thumbnailUrl': thumbnailUrl,
    'originalImageUrl': originalImageUrl,
    'articleUrl': articleUrl,
    'imageSourceUrl': imageSourceUrl,
    'imageAttribution': imageAttribution,
    'imageLicense': imageLicense,
    'imageLicenseUrl': imageLicenseUrl,
    'fetchedAt': fetchedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory WikipediaSpeciesContent.fromJson(Map<String, dynamic> json) {
    final fetchedAt =
        DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return WikipediaSpeciesContent(
      status: WikipediaMatchStatus.values.firstWhere(
        (value) => value.name == json['status']?.toString(),
        orElse: () => WikipediaMatchStatus.unavailable,
      ),
      requestedScientificName:
          json['requestedScientificName']?.toString() ?? '',
      pageTitle: json['pageTitle']?.toString(),
      pageDescription: json['pageDescription']?.toString(),
      summaryExtract: json['summaryExtract']?.toString(),
      descriptionText: json['descriptionText']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      originalImageUrl: json['originalImageUrl']?.toString(),
      articleUrl: json['articleUrl']?.toString(),
      imageSourceUrl: json['imageSourceUrl']?.toString(),
      imageAttribution: json['imageAttribution']?.toString(),
      imageLicense: json['imageLicense']?.toString(),
      imageLicenseUrl: json['imageLicenseUrl']?.toString(),
      fetchedAt: fetchedAt,
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ?? fetchedAt,
    );
  }
}
