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
  /// Title + search header.
  ///
  /// The handoff's table says 182, but that number leaves ~60 logical px of
  /// dead green under the search field on a device whose status-bar inset the
  /// header also has to absorb — the frames put the field about 20px above the
  /// green's bottom edge, measured across inbox, contacts and agents. 152 is
  /// content (title row + 12 + field) plus that 20, plus a typical inset.
  /// Bracketed on device against the frames, which put the search field about
  /// 18-24 logical px above the green's bottom edge. The handoff's 182 left 82,
  /// 165 left 61, 124 left 48; 96 overflowed by 4px, so the content floor is 98.
  /// 100 clears it with 2px to spare and lands at ~24 — the contacts and agents
  /// frames measure 23.6.
  static const double headerSearch = 100;

  /// Title-only header: the search variant's 182 minus the field and its gap.
  /// Used by a tab root that has a title but nothing to search.
  static const double headerTitle = 110;

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
