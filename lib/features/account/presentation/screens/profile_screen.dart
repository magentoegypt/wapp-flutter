import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/domain/session.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../presence_controller.dart';

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
    final Presence presence = ref.watch(presenceProvider);
    final bool isArabic = ref.watch(isRtlProvider);
    final List<String> permissions =
        session?.user.permissions ?? const <String>[];

    return Scaffold(
      body: ListView(
        // The identity hero runs edge to edge under the status bar, so the list
        // cannot carry an inset of its own.
        padding: EdgeInsets.zero,
        children: <Widget>[
          _ProfileHero(
            name: session?.user.name ?? '',
            // The frame reads "Admin · Support agent", but the login response
            // carries a role slug and no role title, so the subtitle stops at
            // the role rather than inventing a job title.
            roleLabel: session == null
                ? ''
                : (session.user.isAdmin ? l10n.prAdmin : l10n.prAgent),
          ),

          SectionLabel(l10n.prPresence),
          FilterChipBar(
            options: <FilterOption>[
              FilterOption(id: Presence.available.name, label: l10n.prAvailable),
              FilterOption(id: Presence.busy.name, label: l10n.prBusy),
              FilterOption(id: Presence.away.name, label: l10n.prAway),
            ],
            selectedId: presence.name,
            onSelected: (String id) => ref
                .read(presenceProvider.notifier)
                .state = Presence.values.byName(id),
          ),

          SectionLabel(l10n.prAccount),
          AppListTile(
            title: l10n.prEmail,
            subtitle: session?.user.email ?? '—',
            leading: const IconTile(
              icon: Icons.mail_outline,
              color: AppColor.info,
            ),
            // Read-only: there is no edit-profile destination, and a chevron
            // would promise one.
            showChevron: false,
          ),
          // `/me` returns the vendor as uid + status only, with no display
          // name, so this is an empty string rather than null — `?? '—'` never
          // fired and the row rendered with a blank value. Omitted entirely
          // when there is nothing to show.
          if ((session?.vendor.name ?? '').isNotEmpty)
          AppListTile(
            title: l10n.prWorkspace,
            subtitle: session!.vendor.name,
            leading: const IconTile(
              icon: Icons.business_outlined,
              color: AppColor.brandDeep,
            ),
            showChevron: false,
          ),

          SectionLabel(l10n.prPreferences),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppDimens.gutter,
              end: AppDimens.gutter,
              bottom: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Named like a list-row title so the control below it reads as
                // that row's value, the way the frame's "Language · English"
                // does.
                Text(
                  l10n.moreLanguage,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _LanguageChoice(
                  isArabic: isArabic,
                  onSelect: (bool arabic) {
                    if (arabic != isArabic) {
                      ref.read(localeControllerProvider.notifier).toggle();
                    }
                  },
                ),
              ],
            ),
          ),

          // Below preferences, not above them: the frame leads with what the
          // agent can change, and permissions are a read-only footnote.
          SectionLabel(l10n.prPermissions),
          if (permissions.isEmpty)
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
                  for (final String p in permissions)
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

/// The brand-green identity block the frame opens with.
///
/// Not an [AppHeader]: the frame centres the avatar, name and role over the
/// green rather than running them along a title bar, and the back affordance
/// has to sit above that stack instead of beside it.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.name, required this.roleLabel});

  final String name;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColor.brand,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppDimens.gutter,
            end: AppDimens.gutter,
            bottom: 22,
          ),
          child: Column(
            children: <Widget>[
              // The frame omits it, but Profile is pushed inside the More
              // branch: without a back affordance the only way out is the tab
              // bar, which strands anyone who arrived from the More list.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  // Matching AppHeader's chevron exactly — same glyph, same
                  // size, same touch box. Two back affordances that look
                  // different is the same bug CL037-TC17 raised about the
                  // header itself, one control smaller.
                  icon: const Icon(Icons.chevron_left, size: 30),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                ),
              ),
              InitialsAvatar.onBrand(
                name: name.isEmpty ? '?' : name,
                size: AppDimens.avatarHero,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (roleLabel.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
              ],
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
              border: selected ? Border.all(color: AppColor.hairline) : null,
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
