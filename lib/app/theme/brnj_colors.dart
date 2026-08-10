import 'package:flutter/material.dart';

/// Brnj's palette, drawn from Iraqi material culture rather than the usual
/// food-app red-orange: glazed pottery teal, brass, pomegranate, unglazed clay.
///
/// One accent does the work (glaze). Brass appears only on seasonal and
/// verified moments so it stays meaningful.
abstract final class BrnjColors {
  // Brand
  static const glaze = Color(0xFF0D6A64);
  static const glazeLight = Color(0xFF58BFB4);
  static const brass = Color(0xFFC8891F);
  static const brassLight = Color(0xFFE0B45C);
  static const pomegranate = Color(0xFF7A2B3C);
  static const pomegranateLight = Color(0xFFD98A9C);

  // Light neutrals — warm, biased toward the clay ground, never pure grey.
  static const slip = Color(0xFFF5F2EC);
  static const slipRaised = Color(0xFFFFFFFF);
  static const slipSunken = Color(0xFFEBE6DC);
  static const ink = Color(0xFF1A1714);
  static const inkMuted = Color(0xFF6B635A);
  static const hairline = Color(0xFFDED8CD);

  // Dark neutrals
  static const nightGround = Color(0xFF14120F);
  static const nightRaised = Color(0xFF1F1C18);
  static const nightSunken = Color(0xFF0D0B09);
  static const nightInk = Color(0xFFF0EBE3);
  static const nightInkMuted = Color(0xFF9C948A);
  static const nightHairline = Color(0xFF322D26);
}
