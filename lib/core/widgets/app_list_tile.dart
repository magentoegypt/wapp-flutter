import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// The standard row: leading icon tile or avatar, title, optional subtitle,
/// optional trailing widget, and a chevron.
///
/// The chevron is a stroked vector at a fixed optical size — never a ">"
/// character. The handoff names glyph-instead-of-icon substitution as the
/// single largest source of visual defects found in design review.
class AppListTile extends StatelessWidget {
  const AppListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.dense = false,
    this.titleColor,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool dense;

  /// Overrides the title ink. For destructive rows — Sign out, Clear chat
  /// history — which the frames render in danger red rather than as a bordered
  /// button somewhere else on the screen.
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.gutter,
          vertical: dense ? 9 : 12,
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (showChevron) ...<Widget>[
              const SizedBox(width: 4),
              // Directional so it points the right way in Arabic.
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColor.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square tinted tile holding a stroked glyph — the leading element on most
/// settings and action rows.
class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    required this.color,
    this.background,
    super.key,
  });

  final IconData icon;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimens.iconTile,
      height: AppDimens.iconTile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: AppDimens.glyph, color: color),
    );
  }
}

/// A row inside the Chat actions sheet.
///
/// [destructive] renders the danger tone and drops the chevron — it performs an
/// action rather than navigating, so the affordance shouldn't promise a push.
class ActionSheetRow extends StatelessWidget {
  const ActionSheetRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
    this.destructive = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color color = destructive ? AppColor.danger : (tint ?? AppColor.info);

    return AppListTile(
      title: label,
      onTap: onTap,
      showChevron: !destructive,
      dense: true,
      // The frame prints a destructive row's label in danger red, not just its
      // icon — tinting only the tile left "Clear chat history" reading like any
      // other row.
      titleColor: destructive ? AppColor.danger : null,
      leading: IconTile(icon: icon, color: color),
    );
  }
}
