import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/inaturalist_taxon.dart';
import '../models/toxicity_level.dart';
import '../widgets/forest_background.dart';
import '../widgets/inaturalist_observation_charts.dart';
import '../widgets/toxicity_safety_section.dart';

class OnlineSpeciesDetailScreen extends StatelessWidget {
  final INaturalistTaxonMatch taxon;

  const OnlineSpeciesDetailScreen({super.key, required this.taxon});

  Future<void> _openUrl(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scientificName = taxon.acceptedScientificName ?? 'Unknown fungus';
    final commonName = taxon.preferredCommonName?.trim();
    final photoUrl = taxon.photoUrl;
    final attribution = taxon.photoAttribution?.trim() ?? '';
    final license = taxon.photoLicense?.trim() ?? '';
    final licenseUrl = _licenseUrl(license);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Species Detail'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        includeTopSafeArea: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const ColoredBox(
                              color: Color(0x22000000),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0x22000000),
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.white70,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                scientificName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (commonName != null && commonName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  commonName,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _MetadataCard(taxon: taxon),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attribution,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: licenseUrl == null
                              ? null
                              : () => _openUrl(licenseUrl),
                          icon: const Icon(Icons.copyright, size: 16),
                          label: Text(_licenseLabel(license)),
                        ),
                        TextButton.icon(
                          onPressed: taxon.taxonUrl == null
                              ? null
                              : () => _openUrl(taxon.taxonUrl),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('View on iNaturalist'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const ToxicitySafetySection(
                level: ToxicityLevel.unknown,
                summary:
                    'No matching curated application toxicity record is available.',
                source: null,
              ),
              const SizedBox(height: 12),
              INaturalistObservationCharts(
                taxonId: taxon.taxonId,
                scientificName: scientificName,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final INaturalistTaxonMatch taxon;
  const _MetadataCard({required this.taxon});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Online library record',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        if ((taxon.rank ?? '').isNotEmpty)
          Text(
            'Taxonomic rank: ${taxon.rank}',
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
        if (taxon.globalObservationCount != null)
          Text(
            'iNaturalist public observations: '
            '${taxon.globalObservationCount}',
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
        const SizedBox(height: 6),
        const Text(
          'Taxonomy, image and observation data: iNaturalist',
          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
        ),
      ],
    ),
  );
}

String _licenseLabel(String code) => switch (code.toLowerCase()) {
  'cc0' => 'CC0',
  'cc-by' => 'CC BY 4.0',
  'cc-by-sa' => 'CC BY-SA 4.0',
  'cc-by-nd' => 'CC BY-ND 4.0',
  'cc-by-nc' => 'CC BY-NC 4.0',
  'cc-by-nc-sa' => 'CC BY-NC-SA 4.0',
  'cc-by-nc-nd' => 'CC BY-NC-ND 4.0',
  _ => code.toUpperCase(),
};

String? _licenseUrl(String code) => switch (code.toLowerCase()) {
  'cc0' => 'https://creativecommons.org/publicdomain/zero/1.0/',
  'cc-by' => 'https://creativecommons.org/licenses/by/4.0/',
  'cc-by-sa' => 'https://creativecommons.org/licenses/by-sa/4.0/',
  'cc-by-nd' => 'https://creativecommons.org/licenses/by-nd/4.0/',
  'cc-by-nc' => 'https://creativecommons.org/licenses/by-nc/4.0/',
  'cc-by-nc-sa' => 'https://creativecommons.org/licenses/by-nc-sa/4.0/',
  'cc-by-nc-nd' => 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
  _ => null,
};
