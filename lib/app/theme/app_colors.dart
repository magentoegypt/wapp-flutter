import 'package:flutter/material.dart';

/// Design tokens, transcribed verbatim from the Figma handoff
/// ("Clickalize Mobile — Flutter handoff", Figma section 286:2).
///
/// Two rules travel with this palette and are worth restating at the call site:
///
/// 1. **Semantic is not accent.** [success] is a darker green than [brand] and
///    exists only to encode state. A "positive" metric must not borrow the
///    brand hue — that was called out explicitly in design review.
/// 2. **[brandDeep] is the text-safe green.** [brand] does not hit AA on white
///    at body sizes; use [brandDeep] for any green text or icon on a light
///    ground, and reserve [brand] for fills.
abstract final class AppColor {
  static const Color brand = Color(0xFF2BAC32);
  static const Color brandDeep = Color(0xFF1B731F); // AA text on white
  static const Color brandWash = Color(0xFFEAF7EC);

  static const Color ink = Color(0xFF101828);
  static const Color inkMuted = Color(0xFF667085);
  static const Color inkFaint = Color(0xFF98A2B3);
  static const Color hairline = Color(0xFFEAECF0);
  static const Color surfaceAlt = Color(0xFFF2F4F7);

  // Semantic — never reuse as the accent.
  static const Color success = Color(0xFF067647);
  static const Color successWash = Color(0xFFE7F8EC);
  static const Color warning = Color(0xFFB54708);
  static const Color warningWash = Color(0xFFFEF3E2);
  static const Color info = Color(0xFF175CD3);
  static const Color infoWash = Color(0xFFEAF1FF);
  static const Color danger = Color(0xFFB42318);
  static const Color dangerWash = Color(0xFFFDECEB);

  // Chat + internal notes.
  static const Color bubbleOut = Color(0xFFDCF8C6);
  static const Color noteFill = Color(0xFFFFF8D6);
  static const Color noteLine = Color(0xFFF3E7A1);
  static const Color noteInk = Color(0xFF8A6D00);
}
