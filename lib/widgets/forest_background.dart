import 'package:flutter/material.dart';

class ForestBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String backgroundAsset;
  final bool useGradientOverlay;
  final Gradient? overlayGradient;
  final Color? overlayColor;
  final bool includeTopSafeArea;
  final bool includeBottomSafeArea;

  const ForestBackground({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.backgroundAsset = 'assets/images/bg1.png',
    this.useGradientOverlay = true,
    this.overlayGradient,
    this.overlayColor,
    this.includeTopSafeArea = true,
    this.includeBottomSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF1F4E3D)),
        Image.asset(
          backgroundAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        if (useGradientOverlay)
          Container(
            decoration: BoxDecoration(
              gradient: overlayGradient ??
                  const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x551F4E3D),
                      Color(0xB31F4E3D),
                    ],
                  ),
            ),
          )
        else
          ColoredBox(
            color: overlayColor ?? Colors.black.withValues(alpha: 0.15),
          ),
        SafeArea(
          top: includeTopSafeArea,
          bottom: includeBottomSafeArea,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ],
    );
  }
}
