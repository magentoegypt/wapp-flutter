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
    this.dense = false,
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

  /// Lays the card out on one line — icon beside the number — instead of
  /// stacking icon over number over label.
  ///
  /// The frame's 2×2 grid stacks, and at four cards that is right. This
  /// dashboard carries **eight**, because the API supports eight metrics and
  /// not the frame's Resolved today or CSAT, so the stacked form costs four
  /// rows of ~96dp before the chart even starts. Horizontal halves that to
  /// ~58dp a row and is the reason the whole screen now fits.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    final Widget glyph = Container(
      width: dense ? 30 : 26,
      height: dense ? 30 : 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: dense ? 17 : 15, color: iconColor),
    );

    final Widget number = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.displayLarge?.copyWith(
        fontSize: dense ? 19 : 22,
        height: 1.1,
      ),
    );

    final Widget caption = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // labelMedium, not bodySmall: this theme never defines bodySmall, so a
      // dense label styled with it rendered as nothing at all. labelMedium is
      // the token for meta and counts and is the right size here anyway.
      style: dense ? text.labelMedium : text.bodyMedium,
    );

    return Container(
      padding: EdgeInsets.all(dense ? 11 : 12),
      // Floor the height so two cards side by side stay level even when one
      // label wraps. Doing it here rather than via the parent keeps the card
      // safe inside any unbounded-height parent.
      //
      // 96 for the stacked form, measured off the frame (38:1032) rather than
      // chosen: its cards are ~97dp and the app's were 118. `dense` is a
      // different shape entirely — see the field's doc.
      constraints: BoxConstraints(minHeight: dense ? 60 : 96),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColor.surfaceDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ),
      ),
      child: dense
          // Number and label share a column so the number stays the anchor the
          // eye lands on; putting them side by side would make the label
          // compete with it and truncate on a narrow card.
          ? Row(
              children: <Widget>[
                glyph,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[number, caption],
                  ),
                ),
              ],
            )
          // Icon, then value, then label — top to bottom, all left-aligned, as
          // the frame stacks them. The icon used to sit trailing on the value's
          // line, which competed with the number for the eye and squeezed long
          // values like "2m 14s" into an ellipsis.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                glyph,
                const SizedBox(height: 8),
                number,
                const SizedBox(height: 1),
                caption,
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
