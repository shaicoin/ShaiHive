import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  static const black = Color(0xFF000000);
  static const darkGrey = Color(0xFF1A1A1A);
  static const gold = Color(0xFFFFD700);
  static const goldLight = Color(0xFFFFF1AA);
  static const goldDark = Color(0xFFBFA100);
  static const purple = Color(0xFF00E5FF);
  static const purpleLight = Color(0xFF66F0FF);
  
  static const glassWhite = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? borderColor;
  final double borderWidth;
  
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.blur = 10,
    this.borderColor,
    this.borderWidth = 1,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.glassBorder,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
} 