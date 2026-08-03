/// Layout constants from the Figma handoff, measured on the 390×844 frame.
///
/// [gutter] governs the whole app. Every text block, card, list row, FAB and
/// section label aligns to it — the handoff is explicit that there must be no
/// 16px card inset competing with a 22px text inset. When a widget needs
/// horizontal padding, it takes [gutter] or nothing.
abstract final class AppDimens {
  /// The single horizontal inset for every screen.
  static const double gutter = 22;

  /// The app bar's own horizontal inset. Smaller than [gutter] because the
  /// icon buttons inside it already carry 36dp touch targets.
  static const double headerGutter = 12;

  /// Horizontal inset for the chat's full-bleed furniture — both banners, the
  /// quick-reply row and the composer. Narrower than [gutter] so these strips
  /// line up with each other rather than with body copy.
  static const double stripGutter = 14;

  /// Persistent bottom tab bar, excluding the home indicator.
  static const double tabBar = 82;

  /// App bar variants: a plain back-nav header, and the taller header that
  /// carries a title plus an inline search field (Inbox, Contacts).
  /// Content height of the back-nav header, **excluding** the status bar.
  ///
  /// 96 was read from the handoff's constants table as though it were the
  /// content box, but that figure is the whole green band — status bar
  /// included. `SafeArea` inside the header already adds the inset, so the
  /// band came out at 96 + inset ≈ 132 on a device with a 36dp status bar:
  /// roughly double the ~50 the frames draw, and a quarter of a short phone's
  /// screen spent on a back arrow and one word.
  ///
  /// 56 is Material's standard app-bar height and the smallest value that
  /// still clears a 36dp touch target with breathing room. It measures within
  /// a few px of the frames.
  static const double headerBack = 56;


  /// Floating compose button, inset by [gutter] from both edges.
  static const double fab = 56;

  /// Bottom padding for a scrolling list that sits under a FAB.
  ///
  /// The button floats over the list rather than inside it, so without this the
  /// last row is permanently half-covered — on Inbox that hid a conversation's
  /// timestamp, and no amount of scrolling revealed it because the list had
  /// already hit its end.
  static const double fabClearance = fab + gutter + 12;

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
