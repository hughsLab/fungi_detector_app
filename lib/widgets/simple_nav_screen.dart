import 'package:flutter/material.dart';

class SimpleNavScreen extends StatelessWidget {
  final String title;
  final String label;
  final String backRoute;
  final String forwardRoute;
  final String? backgroundAsset;

  const SimpleNavScreen({
    super.key,
    required this.title,
    required this.label,
    required this.backRoute,
    required this.forwardRoute,
    this.backgroundAsset,
  });

  void _goTo(BuildContext context, String route) {
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final background = backgroundAsset;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (background != null)
            Image.asset(
              background,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          if (background != null)
            ColoredBox(color: Colors.black.withValues(alpha: 0.15)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: () => _goTo(context, backRoute),
                      child: const Text('Back'),
                    ),
                    ElevatedButton(
                      onPressed: () => _goTo(context, forwardRoute),
                      child: const Text('Forward'),
                    ),
                    OutlinedButton(
                      onPressed: () => _goTo(context, '/detect'),
                      child: const Text('Detection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
