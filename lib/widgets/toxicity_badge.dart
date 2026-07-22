import 'package:flutter/material.dart';

import '../models/toxicity_level.dart';

class ToxicityBadge extends StatelessWidget {
  const ToxicityBadge({super.key, required this.level, this.compact = false});

  final ToxicityLevel level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dangerous = level.isDangerous;
    final color = dangerous ? const Color(0xFFFF8A80) : Colors.white70;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dangerous ? Icons.warning_amber_rounded : Icons.help_outline,
            color: color,
            size: compact ? 13 : 15,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              level.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

