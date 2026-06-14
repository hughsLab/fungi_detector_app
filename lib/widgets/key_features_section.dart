import 'package:flutter/material.dart';

class KeyFeaturesSection extends StatelessWidget {
  final List<String> features;
  final bool contained;
  final String title;
  final String emptyText;
  final int? maxItems;

  const KeyFeaturesSection({
    super.key,
    required this.features,
    this.contained = false,
    this.title = 'Key Identifying Features',
    this.emptyText = 'No identifying features listed.',
    this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> visibleFeatures = features
        .map((feature) => feature.trim())
        .where((feature) => feature.isNotEmpty)
        .take(maxItems ?? features.length)
        .toList(growable: false);
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        if (visibleFeatures.isEmpty)
          Text(
            emptyText,
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: visibleFeatures.map((feature) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '- ',
                      style: TextStyle(color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );

    if (!contained) {
      return content;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: content,
    );
  }
}
