import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../inbox/domain/channel.dart';

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
      // The frame has a proper screen title with the agent avatar, and the
      // profile card sits *below* it as a white card. The card had absorbed the
      // header entirely, so the screen had no title at all.
      // Title only — the frame's More header is the title and the avatar, with
      // no search field.
      appBar: AppHeader.title(
        title: l10n.moreTitle,
        trailing: const AgentAvatar(),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _ProfileCard(
            name: auth.session?.user.name ?? '',
            role: auth.session?.user.role ?? '',
            onTap: () => context.go(AppRoutes.profile),
          ),

          // WORKSPACE / ACCOUNT, per the frame. "MORE" duplicated the screen
          // title and "LANGUAGE" named a single control rather than the group it
          // belongs to.
          SectionLabel(l10n.moreWorkspace),
          // Campaigns first, per the frame — it is the destination people come
          // to this screen for.
          AppListTile(
            title: l10n.moreCampaigns,
            leading: const IconTile(
              icon: Icons.campaign_outlined,
              color: AppColor.warning,
            ),
            onTap: () => context.push(AppRoutes.campaigns),
          ),
          AppListTile(
            title: l10n.moreQuickReplies,
            leading: const IconTile(
              icon: Icons.bolt_outlined,
              color: AppColor.info,
            ),
            onTap: () => context.push(AppRoutes.quickReplies),
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
            title: l10n.tmTitle,
            leading: const IconTile(
              icon: Icons.workspaces_outline,
              color: AppColor.success,
            ),
            onTap: () => context.push(AppRoutes.teams),
          ),
          AppListTile(
            title: l10n.brTitle,
            leading: const IconTile(
              icon: Icons.smart_toy_outlined,
              color: AppColor.info,
            ),
            onTap: () => context.push(AppRoutes.botReplies),
          ),
          // The frame has this row. It was omitted because no endpoint backed
          // it; the 31 Jul API pass added template CRUD, so it exists now.
          AppListTile(
            title: l10n.tplTitle,
            leading: const IconTile(
              icon: Icons.article_outlined,
              color: AppColor.brandDeep,
            ),
            onTap: () => context.push(AppRoutes.templates),
          ),
          // Admins only, because every endpoint behind it answers 403 to anyone
          // else. Hidden rather than disabled: a visible row that always
          // refuses reads as a broken feature, not a permission boundary. The
          // screen still handles the 403 — role can change after login.
          if (auth.session?.user.isAdmin ?? false)
            AppListTile(
              title: l10n.igsTitle,
              leading: IconTile(
                icon: MessageChannel.instagram.badgeIcon,
                // Reuses the badge's own colour rather than restating the hex,
                // so this row and the inbox badges cannot drift apart.
                color: MessageChannel.instagram.badgeColor,
              ),
              onTap: () => context.push(AppRoutes.instagramSettings),
            ),
          // No Bot Flows row yet. The frame lists one and the endpoints now
          // exist, but the screen behind it is the flow builder — a node
          // canvas, deliberately out of scope.

          SectionLabel(l10n.moreAccount),
          // Language is a choice between two named options, not an on/off state
          // — a Switch here gave no clue what enabling it would do.
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppDimens.gutter,
              end: AppDimens.gutter,
              top: 2,
              bottom: 8,
            ),
            child: _LanguageChoice(
              isArabic: isArabic,
              onSelect: (bool arabic) {
                if (arabic != isArabic) {
                  ref.read(localeControllerProvider.notifier).toggle();
                }
              },
            ),
          ),
          // Sign out is a destructive row in the frame, not a bordered button
          // floating at the end of the scroll — it belongs in the ACCOUNT group
          // with the rest of the account actions.
          AppListTile(
            title: l10n.moreSignOut,
            titleColor: AppColor.danger,
            leading: const IconTile(
              icon: Icons.logout,
              color: AppColor.danger,
            ),
            showChevron: false,
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}

/// The signed-in agent's card under the header.
///
/// Tapping it opens Profile, which is why there is no separate Profile row: the
/// frame reaches the profile from here, and a row as well would be two
/// affordances for one destination.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.role,
    required this.onTap,
  });

  final String name;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.gutter),
          child: Row(
            children: <Widget>[
              InitialsAvatar.onBrand(
                name: name.isEmpty ? '?' : name,
                size: AppDimens.avatarList,
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      <String>[
                        if (role.isNotEmpty) role,
                        l10n.moreViewProfile,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColor.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-option language selector.
///
/// With exactly two locales a segmented control beats both a toggle (which
/// hides what it switches to) and a picker sheet (a whole route for one
/// choice): the alternative is on screen, named in its own script, and one tap
/// away. `Cairo` is forced on the Arabic label so it reads correctly even while
/// the app is still in English.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({required this.isArabic, required this.onSelect});

  final bool isArabic;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColor.surfaceAlt,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Row(
        children: <Widget>[
          _Segment(
            label: 'English',
            fontFamily: 'Inter',
            selected: !isArabic,
            onTap: () => onSelect(false),
          ),
          _Segment(
            label: 'العربية',
            fontFamily: 'Cairo',
            selected: isArabic,
            onTap: () => onSelect(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String fontFamily;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimens.radiusCard - 3),
              border: selected
                  ? Border.all(color: AppColor.hairline)
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColor.brandDeep : AppColor.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
