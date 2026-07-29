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
/// copy has to stay non-contradictory and neither may disable the composer.
enum BannerTone { warning, neutral, brand }

class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.message,
    required this.tone,
    this.icon,
    this.onTap,
    super.key,
  });

  final String message;
  final BannerTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  Color get _background => switch (tone) {
    BannerTone.warning => AppColor.warningWash,
    BannerTone.neutral => AppColor.surfaceAlt,
    BannerTone.brand => AppColor.brandWash,
  };

  Color get _foreground => switch (tone) {
    BannerTone.warning => AppColor.warning,
    BannerTone.neutral => AppColor.inkMuted,
    BannerTone.brand => AppColor.brandDeep,
  };

  IconData get _icon =>
      icon ??
      switch (tone) {
        BannerTone.warning => Icons.schedule_outlined,
        BannerTone.neutral => Icons.lock_open_outlined,
        BannerTone.brand => Icons.lock_outline,
      };

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
            horizontal: AppDimens.gutter,
            vertical: 9,
          ),
          child: Row(
            children: <Widget>[
              Icon(_icon, size: AppDimens.glyph, color: _foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _foreground,
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
