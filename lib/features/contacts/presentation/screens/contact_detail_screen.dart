import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../data/contact_repository.dart';
import '../../../inbox/data/conversation_repository.dart';
import '../../../inbox/domain/conversation.dart';
import '../../domain/contact.dart';
import 'contacts_screen.dart' show stageBadge;
import '../../../../l10n/app_localizations.dart';

/// Contact detail — Figma 290:68.
class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Contact> contact = ref.watch(contactDetailProvider(uid));

    return Scaffold(
      // A static title, per the frame. Binding it to the contact left the
      // header blank while loading and on error — the name is already the hero
      // directly below, so repeating it bought nothing.
      appBar: AppHeader.back(title: l10n.cdTitle),
      body: AsyncValueView<Contact>(
        value: contact,
        onRetry: () => ref.invalidate(contactDetailProvider(uid)),
        builder: (Contact c) => ListView(
          children: <Widget>[
            const SizedBox(height: 20),
            Center(
              // Filled deep green with light initials, as the frame draws the
              // hero — the hash-tinted pastels are for list rows.
              child: InitialsAvatar.onBrand(
                name: c.name.isEmpty ? c.phone : c.name,
                size: AppDimens.avatarHero,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                c.name.isEmpty ? c.phone : c.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                c.phone,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            // The frame's pill under the name is the lifecycle stage; it only
            // appeared for blocked contacts before, so most contacts showed
            // nothing. stageBadge folds blocked in as the higher-priority fact.
            if (stageBadge(l10n, c) != null) ...<Widget>[
              const SizedBox(height: 8),
              Center(
                child: StatusPill(
                  label: stageBadge(l10n, c)!.label,
                  tone: stageBadge(l10n, c)!.tone,
                ),
              ),
            ],

            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.gutter),
              child: Row(
                children: <Widget>[
                  _ActionTile(
                    icon: Icons.chat_bubble_outline,
                    label: l10n.ciActionMessage,
                    onTap: () => context.push(AppRoutes.chat(c.uid)),
                  ),
                  const SizedBox(width: 10),
                  _ActionTile(
                    icon: Icons.call_outlined,
                    label: l10n.ciActionCall,
                    onTap: c.phone.isEmpty
                        ? null
                        : () => launchUrl(Uri(scheme: 'tel', path: c.phone)),
                  ),
                  const SizedBox(width: 10),
                  // The frame's third tile is Favourite, which has no endpoint
                  // behind it — notes do, and are reachable from here in the
                  // navigation graph, so the slot carries a working action
                  // rather than a decorative one.
                  _ActionTile(
                    icon: Icons.sticky_note_2_outlined,
                    label: l10n.ciActionNote,
                    onTap: () => context.push(AppRoutes.chatNotes(c.uid)),
                  ),
                ],
              ),
            ),

            SectionLabel(l10n.cdInformation),
            // Label left, value right, no icon tiles — the frame reads these as
            // a data table, and stacking value under label made two rows look
            // like four. Absent values are omitted rather than shown blank.
            _InfoRow(label: l10n.cdPhone, value: c.phone),
            _InfoRow(label: l10n.cdEmail, value: c.email),
            _InfoRow(label: l10n.ciCountry, value: c.countryCode),
            _InfoRow(label: l10n.cdCity, value: c.city),
            _InfoRow(label: l10n.cdLanguage, value: c.language),
            _InfoRow(
              label: l10n.ciFirstSeen,
              value: c.createdAt == null
                  ? null
                  : DateFormat.yMMMd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(c.createdAt!),
            ),

            // Rendered even when empty: the frame keeps the section, and having
            // it vanish made the screen's shape depend on data the user cannot
            // see the absence of.
            ...<Widget>[
              SectionLabel(l10n.cdTags),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (c.labels.isEmpty)
                      Text(
                        l10n.cdNoTags,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      for (final String label in c.labels)
                        StatusPill(
                          label: label,
                          tone: StatusTone.info,
                          showDot: false,
                        ),
                  ],
                ),
              ),
            ],

            if (c.groups.isNotEmpty) ...<Widget>[
              SectionLabel(l10n.cdGroups),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String g in c.groups)
                      StatusPill(
                        label: g,
                        tone: StatusTone.neutral,
                        showDot: false,
                      ),
                  ],
                ),
              ),
            ],
            _RecentConversation(contactUid: c.uid),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

/// The frame's RECENT CONVERSATIONS section.
///
/// WhatsApp gives a contact exactly one thread, so "conversations" is a single
/// row here rather than a list — inventing multiple entries would misrepresent
/// the product. Sourced from [chatThreadProvider] rather than the inbox list so
/// it also works when this screen is reached by deep link, and it renders
/// nothing at all while loading or on error: a contact page is still useful
/// without it, and an error strip here would imply the contact itself failed.
class _RecentConversation extends ConsumerWidget {
  const _RecentConversation({required this.contactUid});

  final String contactUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ChatThread? t = ref.watch(chatThreadProvider(contactUid)).valueOrNull;
    if (t == null || t.messages.isEmpty) return const SizedBox.shrink();

    final ChatMessage last = t.messages.last;
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: l10n.cdRecentConversations,
          actionLabel: l10n.actionSeeAll,
          onAction: () => context.push(AppRoutes.chat(contactUid)),
        ),
        AppListTile(
          title: t.name.isEmpty ? contactUid : t.name,
          subtitle: last.body,
          leading: const IconTile(
            icon: Icons.forum_outlined,
            color: AppColor.brandDeep,
          ),
          trailing: last.sentAt == null
              ? null
              : Text(
                  DateFormat.MMMd(locale).format(last.sentAt!),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
          onTap: () => context.push(AppRoutes.chat(contactUid)),
        ),
      ],
    );
  }
}

/// One equal-width tile in the hero action row.
///
/// Disabled rather than hidden when there is nothing to act on, so the row keeps
/// its three-up rhythm instead of reflowing per contact.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color ink = enabled ? AppColor.brandDeep : AppColor.inkFaint;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: enabled ? AppColor.brandWash : AppColor.surfaceAlt,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 20, color: ink),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label-left, value-right information row. Renders nothing when [value] is
/// absent, so the block shows only what the backend actually returned.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.gutter,
        vertical: 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value!,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
