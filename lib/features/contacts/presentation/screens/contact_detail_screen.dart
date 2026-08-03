import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/util/contact_format.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../conversation_actions/data/conversation_action_repository.dart';
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
      appBar: AppHeader.back(
        title: l10n.cdTitle,
        actions: <Widget>[
          // Edit is a labelled button in the header, where the frame puts it —
          // not a line in the overflow. It is the screen's main affordance and
          // burying it made the whole update path look absent.
          if (contact.valueOrNull != null)
            TextButton(
              onPressed: () =>
                  context.push(AppRoutes.contactEdit(contact.value!.uid)),
              child: Text(
                l10n.actionEdit,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          // Delete stays behind an overflow, away from Message and Call: those
          // are the frame's primary actions and one of them removing the
          // contact would sit badly next to "send a message".
          _ContactOverflow(uid: uid, contact: contact.valueOrNull),
        ],
      ),
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
                  // Favourite, as the frame draws it. The note claiming there
                  // was no endpoint behind this was written before the toggle
                  // existed: `POST /contacts/{uid}/favorite` is keyed by
                  // contact and returns the new state, so the star reflects
                  // reality rather than guessing at it.
                  _FavouriteTile(contact: c),
                ],
              ),
            ),

            SectionLabel(l10n.cdInformation),
            // Label left, value right, no icon tiles — the frame reads these as
            // a data table, and stacking value under label made two rows look
            // like four. Absent values are omitted rather than shown blank.
            _InfoRow(label: l10n.cdPhone, value: formatPhone(c.phone)),
            _InfoRow(label: l10n.cdEmail, value: c.email),
            // Favourite is no longer a row — it is the third action tile now,
            // which is both where the frame puts it and the only place it can
            // be changed rather than merely read.
            _InfoRow(label: l10n.ciCountry, value: c.countryCode),
            _InfoRow(label: l10n.cdCity, value: c.city),
            // "en" is a wire value, not something to show an agent.
            _InfoRow(label: l10n.cdLanguage, value: languageName(c.language)),
            _InfoRow(
              label: l10n.cdCreated,
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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (final String label in c.labels)
                      StatusPill(
                        label: label,
                        tone: StatusTone.info,
                        showDot: false,
                      ),
                    // "+ Add" opens the edit form rather than adding inline.
                    //
                    // Not a shortcut: `contact_tags` is replace-not-append
                    // server-side, and a PUT that carries only tags would also
                    // null the city and unfile every group, because the
                    // endpoint derives both from what the request contains. A
                    // one-field write from here would quietly destroy two
                    // other fields; the edit form already sends the whole set
                    // safely.
                    _AddTagChip(contactUid: c.uid),
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
                    for (final NamedRef g in c.groups)
                      _GroupChip(contactUid: uid, group: g),
                  ],
                ),
              ),
            ],
            // The workspace's own fields, in the same "Other information"
            // section the Add-contact form files them under, so an agent sees
            // what they entered back where they entered it.
            //
            // Only answered fields appear. Listing every definition with a
            // blank beside it would fill the screen with the shape of the
            // workspace's schema rather than with anything about this contact.
            if (c.customFields.isNotEmpty) ...<Widget>[
              SectionLabel(l10n.acSectionOther),
              for (final ContactCustomValue f in c.customFields)
                _InfoRow(label: f.name, value: f.value),
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
/// The Favourite action tile.
///
/// Optimistic: the star flips immediately and is corrected from the response,
/// because the round trip is long enough that a tile which does nothing for a
/// second reads as broken. On failure it flips back and says so — silently
/// reverting would look like the tap missed.
class _FavouriteTile extends ConsumerStatefulWidget {
  const _FavouriteTile({required this.contact});

  final Contact contact;

  @override
  ConsumerState<_FavouriteTile> createState() => _FavouriteTileState();
}

class _FavouriteTileState extends ConsumerState<_FavouriteTile> {
  bool? _override;
  bool _busy = false;

  bool get _on => _override ?? widget.contact.isFavorite;

  Future<void> _toggle() async {
    if (_busy) return;
    final bool previous = _on;
    setState(() {
      _busy = true;
      _override = !previous;
    });

    try {
      final bool now = await ref
          .read(conversationActionRepositoryProvider)
          .toggleFavourite(widget.contact.uid);
      if (!mounted) return;
      // The server's answer wins over the optimistic guess.
      setState(() => _override = now);
      ref.invalidate(contactDetailProvider(widget.contact.uid));
      ref.invalidate(contactListProvider);
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _override = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      icon: _on ? Icons.star : Icons.star_outline,
      label: AppLocalizations.of(context).cdFavorite,
      onTap: _toggle,
    );
  }
}

/// The "+ Add" chip in the tags row.
///
/// Routes to the edit form. See the call site for why this cannot safely write
/// a tag on its own.
class _AddTagChip extends StatelessWidget {
  const _AddTagChip({required this.contactUid});

  final String contactUid;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.add, size: 15, color: AppColor.brandDeep),
      label: Text(AppLocalizations.of(context).cdAddTag),
      labelStyle: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: AppColor.brandDeep),
      backgroundColor: AppColor.brandWash,
      side: const BorderSide(color: AppColor.brandWash),
      visualDensity: VisualDensity.compact,
      onPressed: () => context.push(AppRoutes.contactEdit(contactUid)),
    );
  }
}

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

/// Delete, behind the header's overflow.
class _ContactOverflow extends ConsumerWidget {
  const _ContactOverflow({required this.uid, required this.contact});

  final String uid;
  final Contact? contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Nothing to act on until the contact has loaded, and the name is needed
    // for the confirmation.
    if (contact == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      // Was `(_) => delete`, which fired the destructive action for whatever
      // was picked. With a second entry that would have deleted the contact
      // when the user chose Edit.
      onSelected: (String value) {
        if (value == 'edit') {
          context.push(AppRoutes.contactEdit(contact!.uid));
          return;
        }
        _confirmDelete(context, ref, l10n);
      },
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: Text(l10n.actionEdit),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            l10n.cdDelete,
            style: const TextStyle(color: AppColor.danger),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(l10n.cdDeleteConfirm(contact!.name)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColor.danger),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    try {
      await ref.read(contactRepositoryProvider).delete(uid);
      ref.invalidate(contactListProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.cdDeleted)));
      router.pop();
    } catch (e) {
      // The API refuses the campaign test contact specifically, so its wording
      // is more useful here than a generic failure.
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// A group chip that can take the contact out of that group.
class _GroupChip extends ConsumerWidget {
  const _GroupChip({required this.contactUid, required this.group});

  final String contactUid;
  final NamedRef group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Without a uid there is nothing to call, so the chip stays inert rather
    // than offering a control that would 404.
    if (group.id.isEmpty) {
      return StatusPill(
        label: group.name,
        tone: StatusTone.neutral,
        showDot: false,
      );
    }

    return InputChip(
      label: Text(group.name),
      onDeleted: () => _confirm(context, ref, l10n),
      deleteIcon: const Icon(Icons.close, size: 16),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(l10n.cdRemoveFromGroup(group.name)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(contactRepositoryProvider)
          .removeFromGroup(contactUid, group.id);
      ref.invalidate(contactDetailProvider(contactUid));
      messenger.showSnackBar(SnackBar(content: Text(l10n.cdRemovedFromGroup)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
