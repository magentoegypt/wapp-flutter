import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/domain/session.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Profile — Figma 289:111.
///
/// Sits inside the More branch, so it keeps the bottom tab bar (the inventory
/// marks it `tabs`, unlike its sibling More destinations).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Session? session = ref.watch(authControllerProvider).session;

    return Scaffold(
      appBar: AppHeader.back(title: l10n.moreProfile),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 20),
          Center(
            child: InitialsAvatar(
              name: session?.user.name ?? '?',
              size: AppDimens.avatarHero,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              session?.user.name ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: StatusPill(
              label: (session?.user.isAdmin ?? false) ? l10n.prAdmin : l10n.prAgent,
              tone: StatusTone.success,
              showDot: false,
            ),
          ),

          SectionLabel(l10n.prAccount),
          AppListTile(
            title: l10n.prEmail,
            subtitle: session?.user.email ?? '—',
            leading: const IconTile(
              icon: Icons.mail_outline,
              color: AppColor.info,
            ),
            showChevron: false,
          ),
          AppListTile(
            title: l10n.prWorkspace,
            subtitle: session?.vendor.name ?? '—',
            leading: const IconTile(
              icon: Icons.business_outlined,
              color: AppColor.brandDeep,
            ),
            showChevron: false,
          ),

          SectionLabel(l10n.prPermissions),
          if ((session?.user.permissions ?? const <String>[]).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.gutter,
                vertical: 6,
              ),
              child: Text(
                session?.user.isAdmin ?? false
                    ? l10n.prFullAccess
                    : l10n.prNoPermissions,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.gutter,
                vertical: 4,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String p in session!.user.permissions)
                    StatusPill(label: p, tone: StatusTone.info, showDot: false),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
