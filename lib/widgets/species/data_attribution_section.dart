import 'package:flutter/material.dart';

import '../../models/wikipedia_species_content.dart';

class DataAttributionSection extends StatelessWidget {
  const DataAttributionSection({super.key, required this.wikipediaFuture});

  final Future<WikipediaSpeciesContent> wikipediaFuture;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('data-attribution-section'),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: const Text(
          'Data sources and attribution',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          const _SourceLine('Species description', 'Wikipedia'),
          const _SourceLine('Reference media', 'Wikimedia Commons'),
          const _SourceLine('Taxonomy and observation data', 'iNaturalist'),
          const _SourceLine('Toxicity', 'Fungi app curated species data'),
          const _SourceLine('Local profile', 'Fungi app curated species data'),
          FutureBuilder<WikipediaSpeciesContent>(
            future: wikipediaFuture,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (value == null ||
                  value.status != WikipediaMatchStatus.matched) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((value.imageAttribution ?? '').trim().isNotEmpty)
                    _SourceLine(
                      'Image attribution',
                      value.imageAttribution!.trim(),
                    ),
                  if ((value.imageLicense ?? '').trim().isNotEmpty)
                    _SourceLine('Image licence', value.imageLicense!.trim()),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _SourceLine extends StatelessWidget {
  const _SourceLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Text.rich(
      TextSpan(
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 12,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}
