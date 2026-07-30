import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// A single metric tile from the dashboard's 2×2 grid.
///
/// Always place these as [Expanded] children of a [Row] — the handoff is
/// specific that widths must stay integral, and letting the cards size to
/// their content produces the half-pixel seams that showed up in review.
/// [StatCardRow] does this for you.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.iconColor = AppColor.brandDeep,
    super.key,
  });

  /// Pre-formatted for display — "18", "2m 14s", "94%". Formatting is the
  /// caller's job so this widget stays locale-agnostic.
  final String value;
  final String label;
  final IconData icon;

  /// Semantic where the metric implies state; never the brand hue for a
  /// merely "positive" number.
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(14),
      // Floor the height so two cards side by side stay level even when one
      // label wraps. Doing it here rather than via the parent keeps the card
      // safe inside any unbounded-height parent.
      constraints: const BoxConstraints(minHeight: 118),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColor.surfaceDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ),
      ),
      // Icon, then value, then label — top to bottom, all left-aligned, as the
      // frame stacks them. The icon used to sit trailing on the value's line,
      // which competed with the number for the eye and squeezed long values
      // like "2m 14s" into an ellipsis.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Tinted wash behind the glyph, per the frame — the icon is a marker
          // for the metric, not a decoration floating on the card.
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.displayLarge?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 2),
          Text(label, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Lays out stat cards two-up with equal widths and the screen gutter.
class StatCardRow extends StatelessWidget {
  const StatCardRow({required this.cards, this.spacing = 12, super.key});

  final List<StatCard> cards;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT CrossAxisAlignment.stretch, and deliberately not
    // wrapped in IntrinsicHeight. These rows sit inside a ListView, so the
    // vertical constraint is unbounded:
    //   * `stretch` resolves to an infinite height and aborts layout for the
    //     entire scroll view (blank screen, not an error);
    //   * `IntrinsicHeight` cannot measure through the `Expanded` inside
    //     StatCard's own Row and hangs the renderer.
    // Equal heights come from StatCard's own minimum height instead, which
    // needs no parent cooperation.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}
