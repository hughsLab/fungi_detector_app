import 'package:flutter/material.dart';

import '../models/navigation_args.dart';
import '../services/settings_service.dart';
import '../widgets/forest_background.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  Future<void> _acknowledge(BuildContext context, DisclaimerArgs? args) async {
    await SettingsService.instance.setDisclaimerAcknowledged(true);
    if (!context.mounted) return;
    if (args?.nextRoute != null) {
      Navigator.of(context).pushReplacementNamed(args!.nextRoute!);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as DisclaimerArgs?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety & Disclaimer'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: args?.allowBack ?? true,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        includeTopSafeArea: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Before you continue',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This app provides offline AI assistance only.',
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _DisclaimerCard(
              items: const [
                'Do not consume based on app results.',
                'AI identification is probabilistic.',
                'Always consult experts.',
                'Edibility or toxicity cannot be confirmed by this app.',
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _acknowledge(context, args),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8FBFA1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'I Understand',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  final List<String> items;

  const _DisclaimerCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x33FF6B6B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x66FF8A8A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
