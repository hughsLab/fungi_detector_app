import 'package:flutter/material.dart';

import '../../models/toxicity_level.dart';
import '../toxicity_badge.dart';
import '../toxicity_safety_section.dart';

class CompactSafetySection extends StatelessWidget {
  const CompactSafetySection({
    super.key,
    required this.level,
    this.summary,
    this.source,
    this.edibilityWarning,
  });

  final ToxicityLevel level;
  final String? summary;
  final String? source;
  final String? edibilityWarning;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('compact-safety-section'),
    width: double.infinity,
    decoration: BoxDecoration(
      color: level.isDangerous
          ? const Color(0xFFFF8A80).withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: level.isDangerous
            ? const Color(0xFFFF8A80).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.12),
      ),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: const Text(
          'Safety information',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ToxicityBadge(level: level, compact: true),
          ),
        ),
        children: [
          if ((summary ?? '').trim().isNotEmpty) _SafetyText(summary!.trim()),
          if (level.isDangerous) const _SafetyText(dangerousFungusWarning),
          if ((edibilityWarning ?? '').trim().isNotEmpty)
            _SafetyText(edibilityWarning!.trim()),
          const _SafetyText(fungusSafetyDisclaimer),
          if ((source ?? '').trim().isNotEmpty)
            _SafetyText('Toxicity source: ${source!.trim()}', fontSize: 11.5),
        ],
      ),
    ),
  );
}

class _SafetyText extends StatelessWidget {
  const _SafetyText(this.text, {this.fontSize = 12.5});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xCCFFFFFF),
          fontSize: fontSize,
          height: 1.4,
        ),
      ),
    ),
  );
}
