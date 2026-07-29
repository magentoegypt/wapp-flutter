import 'package:flutter/material.dart';

import '../../app/theme/app_dimens.dart';

/// The uppercase group heading that repeats on 14 of the 20 screens.
///
/// This is a real widget rather than a styled `Text` on purpose — the handoff
/// calls that out specifically. Centralising it keeps the tracking, casing and
/// gutter identical everywhere instead of drifting screen by screen.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.padded = true, super.key});

  final String text;

  /// Applies the screen gutter horizontally. Turn off when the caller already
  /// sits inside a padded container.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    );

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: padded ? AppDimens.gutter : 0,
        end: padded ? AppDimens.gutter : 0,
        top: 20,
        bottom: 8,
      ),
      child: label,
    );
  }
}

/// A [SectionLabel] with a trailing action, as used by the dashboard's
/// "My queue · See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppDimens.gutter,
        end: AppDimens.gutter,
        top: 20,
        bottom: 8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
