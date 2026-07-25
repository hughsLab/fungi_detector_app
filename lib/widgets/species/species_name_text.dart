import 'package:flutter/material.dart';

class SpeciesNameText extends StatelessWidget {
  const SpeciesNameText({
    super.key,
    required this.scientificName,
    this.commonName,
    this.scientificStyle,
    this.commonStyle,
    this.spacing = 4,
  });

  final String scientificName;
  final String? commonName;
  final TextStyle? scientificStyle;
  final TextStyle? commonStyle;
  final double spacing;

  static TextStyle italic(TextStyle style) =>
      style.copyWith(fontStyle: FontStyle.italic);

  @override
  Widget build(BuildContext context) {
    final common = commonName?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          scientificName,
          style: italic(
            scientificStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (common.isNotEmpty) ...[
          SizedBox(height: spacing),
          Text(
            common,
            style: italic(
              commonStyle ??
                  const TextStyle(color: Color(0xCCFFFFFF), fontSize: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class LabeledSpeciesNameText extends StatelessWidget {
  const LabeledSpeciesNameText({
    super.key,
    required this.label,
    required this.name,
    required this.style,
  });

  final String label;
  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: style,
      children: [
        TextSpan(text: '$label: '),
        TextSpan(
          text: name,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    ),
  );
}
