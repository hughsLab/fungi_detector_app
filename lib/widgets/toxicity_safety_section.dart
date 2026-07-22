import 'package:flutter/material.dart';

import '../models/toxicity_level.dart';
import 'toxicity_badge.dart';

const fungusSafetyDisclaimer =
    'Never consume a fungus based only on an application identification. '
    'Fungi can be misidentified, and toxicity can vary by species, specimen, '
    'preparation and individual reaction. Seek advice from a qualified local expert.';

const dangerousFungusWarning =
    'Potentially dangerous fungus. Avoid handling unnecessarily and keep away '
    'from children and animals.';

class ToxicitySafetySection extends StatelessWidget {
  const ToxicitySafetySection({
    super.key,
    required this.level,
    this.summary,
    this.source,
  });

  final ToxicityLevel level;
  final String? summary;
  final String? source;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toxicity and Safety',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ToxicityBadge(level: level),
          if ((summary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary!.trim(),
              style: const TextStyle(color: Color(0xCCFFFFFF), height: 1.4),
            ),
          ],
          if ((source ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Curated source: ${source!.trim()}',
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
            ),
          ],
          if (level.isDangerous) ...[
            const SizedBox(height: 8),
            const Text(
              dangerousFungusWarning,
              style: TextStyle(color: Color(0xFFFFCDD2), height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            fungusSafetyDisclaimer,
            style: TextStyle(color: Color(0xCCFFFFFF), height: 1.4),
          ),
        ],
      ),
    );
  }
}
