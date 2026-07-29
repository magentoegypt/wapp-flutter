import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';

/// More — Figma 289:34.
///
/// The hub for everything that isn't a tab. Note the routing split from the
/// handoff: Profile stays inside this branch and keeps the bottom bar, while
/// Quick replies, Campaigns and Agents push over the shell.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final bool isArabic = ref.watch(isRtlProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _AccountHeader(
            name: auth.session?.user.name ?? '',
            vendor: auth.session?.vendor.name ?? '',
            onTap: () => context.go(AppRoutes.profile),
          ),

          SectionLabel(l10n.moreTitle),
          AppListTile(
            title: l10n.moreQuickReplies,
            leading: const IconTile(icon: Icons.bolt_outlined, color: AppColor.info),
            onTap: () => context.push(AppRoutes.quickReplies),
          ),
          AppListTile(
            title: l10n.moreCampaigns,
            leading: const IconTile(
              icon: Icons.campaign_outlined,
              color: AppColor.warning,
            ),
            onTap: () => context.push(AppRoutes.campaigns),
          ),
          AppListTile(
            title: l10n.moreAgents,
            leading: const IconTile(
              icon: Icons.groups_outlined,
              color: AppColor.success,
            ),
            onTap: () => context.push(AppRoutes.agents),
          ),
          AppListTile(
            title: l10n.moreProfile,
            leading: const IconTile(
              icon: Icons.person_outline,
              color: AppColor.brandDeep,
            ),
            onTap: () => context.go(AppRoutes.profile),
          ),

          SectionLabel(l10n.moreLanguage),
          AppListTile(
            title: l10n.moreLanguage,
            subtitle: isArabic ? 'العربية' : 'English',
            leading: const IconTile(
              icon: Icons.translate,
              color: AppColor.inkMuted,
            ),
            showChevron: false,
            trailing: Switch(
              value: isArabic,
              onChanged: (_) =>
                  ref.read(localeControllerProvider.notifier).toggle(),
            ),
            onTap: () => ref.read(localeControllerProvider.notifier).toggle(),
          ),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(AppDimens.gutter),
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout, size: 18),
              label: Text(l10n.moreSignOut),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColor.danger,
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: AppColor.dangerWash),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.name,
    required this.vendor,
    required this.onTap,
  });

  final String name;
  final String vendor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColor.brand,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.gutter),
            child: Row(
              children: <Widget>[
                InitialsAvatar(
                  name: name.isEmpty ? '?' : name,
                  size: AppDimens.avatarHero,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (vendor.isNotEmpty)
                        Text(
                          vendor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
