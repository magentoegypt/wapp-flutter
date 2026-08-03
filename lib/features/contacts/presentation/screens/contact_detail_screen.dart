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
import '../widgets/tag_picker.dart';
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
          // Two icons, not a label and an overflow. Both actions belong to the
          // whole contact, so neither sits in the action row beside Message
          // and Call — "delete this person" next to "send them a message"
          // reads badly and is one mis-tap from being irreversible.
          if (contact.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: l10n.actionEdit,
              onPressed: () =>
                  context.push(AppRoutes.contactEdit(contact.value!.uid)),
            ),
          _ContactDelete(uid: uid, contact: contact.valueOrNull),
        ],
      ),
      body: AsyncValueView<Contact>(
        value: contact,
        onRetry: () => ref.invalidate(contactDetailProvider(uid)),
        builder: (Contact c) => ListView(
          // The frame is a white sheet on a tinted page: hero and rows sit on
          // white, and the section headings sit on the page colour, which is
          // what makes them read as bands rather than as floating labels.
          // Everything used to share one flat background, so nothing was
          // grouped and the dividers had nothing to divide.
          children: <Widget>[
            _Surface(children: <Widget>[
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
                textAlign: TextAlign.center,
                // The frame's name is the biggest thing on the screen;
                // titleMedium left it the same weight as a row label.
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 22,
                      height: 1.2,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                // Formatted here too. The INFORMATION row was fixed and this
                // one was not, so the same number appeared twice on one screen
                // in two different shapes.
                formatPhone(c.phone),
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
                    // Envelope, as the frame draws it — and as Conversation
                    // info already used, so the same action stopped wearing
                    // two different glyphs.
                    icon: Icons.mail_outline,
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

            const SizedBox(height: 14),
            ]),

            SectionLabel(l10n.cdInformation),
            // Label left, value right, no icon tiles — the frame reads these as
            // a data table, and stacking value under label made two rows look
            // like four. Absent values are omitted rather than shown blank.
            // Null rows are dropped before the surface sees them, not hidden
            // inside it — a row that collapses to nothing still counts as a
            // child, so a divided surface would draw a rule against an
            // invisible row and the block would end up with double lines.
            _Surface(divided: true, children: <Widget>[
              ?infoRow(l10n.cdPhone, formatPhone(c.phone)),
              ?infoRow(l10n.cdEmail, c.email),
              // Favourite is no longer a row — it is the third action tile
              // now, which is both where the frame puts it and the only place
              // it can be changed rather than merely read.
              ?infoRow(l10n.ciCountry, c.countryCode),
              ?infoRow(l10n.cdCity, c.city),
              // "en" is a wire value, not something to show an agent.
              ?infoRow(l10n.cdLanguage, languageName(c.language)),
              ?infoRow(
                l10n.cdCreated,
                c.createdAt == null
                    ? null
                    : DateFormat.yMMMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(c.createdAt!),
              ),
            ]),

            // Rendered even when empty: the frame keeps the section, and having
            // it vanish made the screen's shape depend on data the user cannot
            // see the absence of.
            ...<Widget>[
              SectionLabel(l10n.cdTags),
              _Surface(children: <Widget>[
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
                    AddTagChip(contact: c),
                  ],
                ),
              ),
              ]),
            ],

            if (c.groups.isNotEmpty) ...<Widget>[
              SectionLabel(l10n.cdGroups),
              _Surface(children: <Widget>[
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
              ]),
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
              _Surface(divided: true, children: <Widget>[
                for (final ContactCustomValue f in c.customFields)
                  ?infoRow(f.name, f.value),
              ]),
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
        children: <Widget>[
          // The label takes its own width and no more. It used to be
          // `Expanded` while the value was merely `Flexible`, so the label
          // claimed the row and squeezed the value — which is why a long
          // address broke mid-token into "mahmoudmagdy74" over "237@gmail.com"
          // instead of sitting on one line as the frame draws it.
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              // Scale down rather than wrap or ellipsize. An email is only
              // useful whole: truncating it hides the domain, and wrapping it
              // splits it at whatever character happens to land on the edge.
              // Shrinking keeps every character on one line, and only kicks in
              // for values too long to fit at full size.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  value!,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One label/value line, or nothing when there is no value.
///
/// Returns `Widget?` rather than an empty box so a caller can drop it with the
/// null-aware element operator — see the divided-surface note at the call site.
Widget? infoRow(String label, String? value) {
  if (value == null || value.isEmpty) return null;
  return _InfoRow(label: label, value: value);
}

/// A full-bleed white block on the tinted page.
///
/// The frame is a white sheet interrupted by tinted bands — the section
/// headings sit on the page colour and everything else sits on white. Without
/// this the screen was one flat tone, so the headings floated and there was
/// nothing for a divider to separate.
///
/// [divided] draws a hairline between children, inset past the gutter so the
/// rules line up under the values rather than running edge to edge.
class _Surface extends StatelessWidget {
  const _Surface({required this.children, this.divided = false});

  final List<Widget> children;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final List<Widget> rows = <Widget>[];

    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (divided && i < children.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: AppDimens.gutter,
          endIndent: AppDimens.gutter,
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ));
      }
    }

    return Container(
      width: double.infinity,
      color: isLight ? Colors.white : AppColor.surfaceDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}

/// Delete, as a header icon.
///
/// A bare icon for an irreversible action is only acceptable because it opens
/// a confirmation naming the contact — the tap arms it, it does not fire it.
class _ContactDelete extends ConsumerWidget {
  const _ContactDelete({required this.uid, required this.contact});

  final String uid;
  final Contact? contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Nothing to act on until the contact has loaded, and the name is needed
    // for the confirmation.
    if (contact == null) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.delete_outline, color: Colors.white),
      tooltip: l10n.cdDelete,
      onPressed: () => _confirmDelete(context, ref, l10n),
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
