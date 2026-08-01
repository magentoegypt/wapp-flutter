import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// Full-bleed advisory strip.
///
/// Distinct from [StatusPill]: a pill labels a row, a banner spans the screen
/// and explains a condition. Three tones are in use:
///
/// * [BannerTone.warning] — the 24h service window is closing (under the app bar)
/// * [BannerTone.neutral] — the reply lock (above the composer)
/// * [BannerTone.brand]   — the "private to your team" notice on internal notes
///
/// The handoff notes that the first two can both be visible at once, so their
/// copy has to stay non-contradictory, neither may disable the composer, and
/// each has to hold one line — two banners wrapping is four lines of a phone
/// screen spent on advisories.
enum BannerTone { warning, neutral, brand }

class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.message,
    required this.tone,
    this.icon,
    this.onTap,
    this.background,
    super.key,
  });

  final String message;
  final BannerTone tone;
  final IconData? icon;

  /// Overrides the tone's wash. Used by the reply-lock strip, which the spec
  /// puts at 7% brand rather than the standard wash.
  final Color? background;
  final VoidCallback? onTap;

  Color get _background => background ?? switch (tone) {
    BannerTone.warning => AppColor.warningWash,
    BannerTone.neutral => AppColor.surfaceAlt,
    BannerTone.brand => AppColor.brandWash,
  };

  Color get _foreground => switch (tone) {
    BannerTone.warning => AppColor.warning,
    BannerTone.neutral => AppColor.inkMuted,
    BannerTone.brand => AppColor.brandDeep,
  };

  /// Falls back to a plain information mark, never to a glyph chosen by tone.
  ///
  /// The default used to be `warning → clock, neutral → open padlock, brand →
  /// padlock`, which picked an icon from a *colour*. So the bot-flow editor's
  /// "name the flow, its steps are built in the console" carried an open
  /// padlock, the read-only bot reply carried a clock, and the Instagram
  /// format note carried a clock — each one a confident statement about
  /// something the sentence was not about. A caller that has no better glyph
  /// gets a neutral one instead of a misleading one.
  IconData get _icon => icon ?? Icons.info_outline;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          color: _background,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppDimens.stripGutter,
            vertical: 9,
          ),
          child: Row(
            children: <Widget>[
              Icon(_icon, size: AppDimens.glyph, color: _foreground),
              const SizedBox(width: 8),
              // One line at any width. These strips sit under the app bar and
              // above the composer, where a second line shoves the whole
              // conversation down — and the two of them can be on screen at
              // once, so wrapping cost four lines of a phone screen.
              //
              // scaleDown rather than `overflow: ellipsis`: on a narrow phone
              // the text shrinks a point or two and stays readable, where
              // truncating "reply to keep it open" to "reply to k…" would drop
              // the only actionable half of the sentence.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    message,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
