import 'package:flutter/material.dart';

import '../widgets/forest_background.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About / Credits'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        includeTopSafeArea: false,
        child: ListView(
          children: const [
            Text(
              'Australian Fungi Identifier',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Offline identification support for Australian fungi using on-device AI.',
              style: TextStyle(
                color: accentTextColor,
                height: 1.4,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'AI disclaimer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'AI results are probabilistic and should never be used for edibility decisions.',
              style: TextStyle(color: accentTextColor, height: 1.4),
            ),
            SizedBox(height: 20),
            Text(
              'Dataset sources (placeholder)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Curated Australian fungi references and offline datasets will be listed here.',
              style: TextStyle(color: accentTextColor, height: 1.4),
            ),
            SizedBox(height: 20),
            Text(
              'App version',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'v0.1.0 (offline preview)',
              style: TextStyle(color: accentTextColor),
            ),
            SizedBox(height: 20),
            Text(
              'Contact / feedback',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'feedback@example.com',
              style: TextStyle(color: accentTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
