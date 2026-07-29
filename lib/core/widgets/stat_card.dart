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
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF141C17),
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : const Color(0xFF243029),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.displayLarge?.copyWith(fontSize: 24),
                ),
              ),
              Icon(icon, size: 18, color: iconColor),
            ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}
