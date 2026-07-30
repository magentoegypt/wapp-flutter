/// Layout constants from the Figma handoff, measured on the 390×844 frame.
///
/// [gutter] governs the whole app. Every text block, card, list row, FAB and
/// section label aligns to it — the handoff is explicit that there must be no
/// 16px card inset competing with a 22px text inset. When a widget needs
/// horizontal padding, it takes [gutter] or nothing.
abstract final class AppDimens {
  /// The single horizontal inset for every screen.
  static const double gutter = 22;

  /// Persistent bottom tab bar, excluding the home indicator.
  static const double tabBar = 82;

  /// App bar variants: a plain back-nav header, and the taller header that
  /// carries a title plus an inline search field (Inbox, Contacts).
  static const double headerBack = 96;


  /// Floating compose button, inset by [gutter] from both edges.
  static const double fab = 56;

  static const double avatarList = 42;
  static const double avatarHero = 64;

  /// Leading icon tile on a list row, and the glyph drawn inside it.
  static const double iconTile = 34;
  static const double glyph = 16;

  /// Cards sit in a 12–14 band; [radiusCard] is the default and
  /// [radiusCardLarge] is for the hero/stat surfaces.
  static const double radiusCard = 12;
  static const double radiusCardLarge = 14;

  /// Outgoing chat bubbles hug their content up to this width.
  static const double bubbleMaxWidth = 291;

  /// Home indicator, on screens that don't carry the tab bar. Present for
  /// reference only — use SafeArea rather than subtracting this by hand.
  static const double homeIndicatorWidth = 134;
  static const double homeIndicatorHeight = 5;
}
