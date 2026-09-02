import 'package:flutter/material.dart';

/// Design tokens. [brand] is `#2BAC32` — the green the Figma frames actually
/// draw, with [brandDeep] and [brandWash] rederived at that hue (123°) so the
/// contrast behaviour they encode still holds.
///
/// This reverses the correction recorded in `4036732`, which had followed the
/// product logo's own fill (`/imgs/logo-short.svg`, `#00BF63`) over the Figma
/// variable on the handoff's authority: "this document and the Figma file
/// disagree on purpose." The logo still disagrees. The frames win because they
/// are what QA tests against, and CL037-TC17 failed on exactly this: the
/// shipping mint read as "very different from the UI" beside a leaf-green
/// design. Measured off `docs/frames/` — 26,399 header pixels across twelve
/// frames sample #2BAD31, which is this value inside webp's rounding.
///
/// If the logo is ever re-exported to match, delete this paragraph rather than
/// flipping the constant a third time.
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
  /// #2BAC32 — the Figma frames' header green.
  static const Color brand = Color(0xFF2BAC32);

  /// Rederived at [brand]'s hue and saturation (123°, 60%). 6.28:1 on white,
  /// against the 6.22:1 the #00703A it replaces carried — so every green text
  /// and icon site keeps the contrast it was signed off with.
  static const Color brandDeep = Color(0xFF1C6F20);

  static const Color brandWash = Color(0xFFEBFAEC);

  // Dark-mode grounds. These were repeated as raw literals across eight call
  // sites in seven files, so a dark-theme tweak meant hunting hex. They are
  // deliberately named for their role, not their lightness, and pair with the
  // light-mode `Colors.white` / [hairline] / [surfaceAlt] they stand in for.
  static const Color surfaceDark = Color(0xFF141C17);
  static const Color hairlineDark = Color(0xFF243029);
  static const Color groundLight = Color(0xFFF6F9F6);
  static const Color groundDark = Color(0xFF0D1310);

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

  /// The chat canvas — a warm beige, sampled straight off the frame
  /// (37:1032, #EFEAE2). The screen used the app's cool near-white scaffold,
  /// which left the white incoming bubbles with almost nothing to sit against:
  /// the whole point of this tone is that both bubble colours read as raised
  /// off it.
  static const Color chatCanvas = Color(0xFFEFEAE2);
  static const Color noteFill = Color(0xFFFFF8D6);
  static const Color noteLine = Color(0xFFF3E7A1);
  static const Color noteInk = Color(0xFF8A6D00);
}
