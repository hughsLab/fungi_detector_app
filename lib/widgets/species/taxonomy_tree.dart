import 'package:flutter/material.dart';

import '../../models/inaturalist_taxon.dart';
import '../../models/taxonomy_node.dart';
import 'species_name_text.dart';

class INaturalistTaxonomySection extends StatelessWidget {
  const INaturalistTaxonomySection({super.key, required this.future});

  final Future<INaturalistTaxonMatch> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<INaturalistTaxonMatch>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SectionCard(
            title: 'Taxonomy',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(minHeight: 2),
                SizedBox(height: 8),
                Text(
                  'Loading iNaturalist taxonomy…',
                  key: Key('taxonomy-loading'),
                  style: TextStyle(color: Color(0xCCFFFFFF)),
                ),
              ],
            ),
          );
        }
        final taxon = snapshot.data;
        if (taxon == null ||
            taxon.status != INaturalistMatchStatus.matched ||
            taxon.taxonomy.isEmpty) {
          return const _SectionCard(
            title: 'Taxonomy',
            child: Text(
              'Taxonomy information is currently unavailable.',
              style: TextStyle(color: Color(0xCCFFFFFF)),
            ),
          );
        }
        return _SectionCard(
          title: 'Taxonomy',
          child: TaxonomyTree(nodes: taxon.taxonomy),
        );
      },
    );
  }
}

class INaturalistObservationInformation extends StatelessWidget {
  const INaturalistObservationInformation({super.key, required this.future});

  final Future<INaturalistTaxonMatch> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<INaturalistTaxonMatch>(
      future: future,
      builder: (context, snapshot) {
        final taxon = snapshot.data;
        return _SectionCard(
          title: 'Observation information',
          child: snapshot.connectionState != ConnectionState.done
              ? const LinearProgressIndicator(minHeight: 2)
              : taxon == null || taxon.status != INaturalistMatchStatus.matched
              ? const Text(
                  'iNaturalist observation information is currently unavailable.',
                  style: TextStyle(color: Color(0xCCFFFFFF)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'iNaturalist public observations: '
                      '${taxon.globalObservationCount?.toString() ?? 'Not available'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Public observation counts show reporting frequency on '
                      'iNaturalist and do not necessarily indicate biological rarity.',
                      style: TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if ((taxon.conservationStatus ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Source classification: ${taxon.conservationStatus}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      if ((taxon.conservationStatusAuthority ?? '')
                          .trim()
                          .isNotEmpty)
                        Text(
                          'Authority: ${taxon.conservationStatusAuthority}',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      if ((taxon.conservationStatusPlace ?? '')
                          .trim()
                          .isNotEmpty)
                        Text(
                          'Region: ${taxon.conservationStatusPlace}',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                    ],
                    if (taxon.isStale) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Showing previously saved species information.',
                        style: TextStyle(
                          color: Color(0xFFFFE8A3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class TaxonomyTree extends StatelessWidget {
  const TaxonomyTree({super.key, required this.nodes});

  final List<TaxonomyNode> nodes;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < nodes.length; index++)
        _TaxonomyRow(node: nodes[index], depth: index),
    ],
  );
}

class _TaxonomyRow extends StatelessWidget {
  const _TaxonomyRow({required this.node, required this.depth});

  final TaxonomyNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final commonName = node.commonName?.trim() ?? '';
    final showCommon =
        commonName.isNotEmpty &&
        commonName.toLowerCase() != node.scientificName.toLowerCase();
    return Padding(
      key: ValueKey('taxonomy-${node.rank}-${node.scientificName}'),
      padding: EdgeInsets.only(
        left: (depth * 11).clamp(0, 88).toDouble(),
        bottom: 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              depth == 0
                  ? Icons.account_tree_outlined
                  : Icons.subdirectory_arrow_right,
              color: const Color(0xFF8FBFA1),
              size: 17,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showCommon)
                  Text(
                    commonName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                Text(
                  node.scientificName,
                  style: SpeciesNameText.italic(
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _rankLabel(node.rank),
                  style: const TextStyle(
                    color: Color(0xAAFFFFFF),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _rankLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Taxon';
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        child,
      ],
    ),
  );
}
