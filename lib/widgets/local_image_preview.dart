import 'dart:io';

import 'package:flutter/material.dart';

class LocalImagePreview extends StatelessWidget {
  final String? path;
  final Widget placeholder;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final int? cacheHeight;

  const LocalImagePreview({
    super.key,
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final String? resolvedPath = path?.trim();
    final Widget content;
    if (resolvedPath == null || resolvedPath.isEmpty) {
      content = placeholder;
    } else {
      content = Image.file(
        File(resolvedPath),
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    final BorderRadius? resolvedBorderRadius = borderRadius;
    if (resolvedBorderRadius == null) {
      return content;
    }
    return ClipRRect(borderRadius: resolvedBorderRadius, child: content);
  }
}
