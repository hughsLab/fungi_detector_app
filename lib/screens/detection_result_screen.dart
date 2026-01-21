import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../widgets/forest_background.dart';

class DetectionResultScreen extends StatelessWidget {
  const DetectionResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as DetectionResultArgs?;

    if (args == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1F4E3D),
        body: Center(
          child: Text(
            'No capture details available.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final String top1Percent =
        '${(args.top1AvgConf * 100).toStringAsFixed(1)}%';
    final String votePercent =
        '${(args.top1VoteRatio * 100).toStringAsFixed(1)}%';
    final String durationSeconds =
        (args.windowDurationMs / 1000).toStringAsFixed(1);
    final String capturedAt = _formatTimestamp(args.timestamp);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Result'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        includeTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Stable detection captured',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF8FBFA1).withValues(alpha: 0.85),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    args.lockedLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (args.top2Label != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Also possible: ${args.top2Label}',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Avg confidence: $top1Percent',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vote ratio: $votePercent',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stable for ${args.stabilityWinCount}/${args.stabilityWindowSize} frames over ${durationSeconds}s',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Captured at $capturedAt',
                    style: const TextStyle(
                      color: Color(0xAAFFFFFF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (args.speciesId != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/species-detail',
                      arguments: SpeciesDetailArgs(speciesId: args.speciesId!),
                    );
                  },
                  icon: const Icon(Icons.nature),
                  label: const Text('Open species profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FBFA1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Back to detection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  final String year = local.year.toString().padLeft(4, '0');
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  final String second = local.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}
