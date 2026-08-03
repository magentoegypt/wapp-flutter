import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/util/contact_format.dart';
import '../../../contacts/data/contact_repository.dart';
import '../../../contacts/presentation/screens/contacts_screen.dart' show stageBadge;
import '../../../contacts/domain/contact.dart';
import '../../data/conversation_repository.dart';
import '../../data/note_repository.dart';
import '../../domain/channel.dart';
import '../../domain/conversation.dart';
import '../../../contacts/presentation/widgets/contact_ui.dart';
import '../../../contacts/presentation/widgets/tag_picker.dart';
import '../widgets/chat_actions_sheet.dart';

/// Conversation info — Figma 290:4.
///
/// The contact-side companion to the chat: who they are, who owns the
/// conversation, and the entry point into internal notes.
///
/// Section order follows the frame — hero, contact details, then everything
/// operational. The service window used to sit directly under the hero, which
/// pushed the customer's own details off the first screenful.
class ConversationInfoScreen extends ConsumerWidget {
  const ConversationInfoScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ChatThread> thread =
        ref.watch(chatThreadProvider(contactUid));
    // The chat payload describes the *thread*; email, country and the
    // first-seen date live on the customer record. Read them through the
    // contacts repository rather than widening this feature's endpoint, and
    // treat them as optional — the thread is what this screen is about, so a
    // slow or failed contact fetch must not block it.
    final Contact? contact =
        ref.watch(contactDetailProvider(contactUid)).valueOrNull;
    final int noteCount =
        ref.watch(notesProvider(contactUid)).valueOrNull?.length ?? 0;
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final List<Widget> detailsBefore = _detailRowsBefore(l10n, contact, locale);
    final List<Widget> detailsAfter = _detailRowsAfter(l10n, contact, locale);
    // The Instagram handle travels on the inbox row, not on the thread — the
    // chat endpoint has never carried it. Read it back out of the list that is
    // already loaded behind this screen and drop the line when the row isn't
    // there (a filtered inbox, a cold start), rather than widening an endpoint
    // for one string.
    final String? handle = _instagramHandle(
      ref.watch(inboxListProvider).valueOrNull ?? const <Conversation>[],
    );

    return Scaffold(
      appBar: AppHeader.back(
        title: l10n.ciContactInfo,
        actions: <Widget>[
          // The frame's ⋯. It was absent, so every conversation action —
          // snooze, transfer, labels, templates, history access — was
          // reachable only by going back to the chat first.
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            tooltip: l10n.caTitle,
            onPressed: () => showChatActionsSheet(
              context,
              contactUid: contactUid,
              name: thread.valueOrNull?.name ?? '',
              phone: thread.valueOrNull?.phone,
              channel:
                  thread.valueOrNull?.channel ?? MessageChannel.whatsapp,
            ),
          ),
        ],
      ),
      body: AsyncValueView<ChatThread>(
        value: thread,
        onRetry: () => ref.invalidate(chatThreadProvider(contactUid)),
        builder: (ChatThread t) => ListView(
          children: <Widget>[
            Surface(children: <Widget>[
            const SizedBox(height: 20),
            Center(
              // Filled brand green with light initials, matching the frame and
              // Contact detail. The hash-tinted pastels are for list rows; a
              // hero rendered in one of them made the same customer look like
              // two different people across the two screens.
              child: InitialsAvatar.onBrand(
                name: t.name,
                size: AppDimens.avatarHero,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                t.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (t.phone != null) ...<Widget>[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  formatPhone(t.phone!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
            // The frame's pill under the number is the customer's lifecycle
            // stage. It was missing here while Contact detail had it, so the
            // same customer read as "Returning" on one screen and as nothing
            // on the other.
            if (contact != null && stageBadge(l10n, contact) != null) ...<Widget>[
              const SizedBox(height: 8),
              Center(
                child: StatusPill(
                  label: stageBadge(l10n, contact)!.label,
                  tone: stageBadge(l10n, contact)!.tone,
                ),
              ),
            ],

            const SizedBox(height: 18),
            // The same three tiles Contact detail draws, Favourite included.
            // This screen used to end on Note while the other ended on
            // Favourite, so the same customer offered different actions
            // depending on the way in.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.gutter,
              ),
              child: Row(
                children: <Widget>[
                  ActionTile(
                    icon: Icons.mail_outline,
                    label: l10n.ciActionMessage,
                    // Returns to the chat rather than pushing a fresh one —
                    // this screen is only reached from there, so a push would
                    // stack a second copy of the same thread behind it.
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.chat(contactUid)),
                  ),
                  const SizedBox(width: 10),
                  ActionTile(
                    icon: Icons.call_outlined,
                    label: l10n.ciActionCall,
                    onTap: t.phone == null
                        ? null
                        : () => launchUrl(Uri(scheme: 'tel', path: t.phone!)),
                  ),
                  const SizedBox(width: 10),
                  if (contact != null)
                    FavouriteTile(contact: contact)
                  else
                    ActionTile(
                      icon: Icons.star_outline,
                      label: l10n.cdFavorite,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ]),

            SectionLabel(l10n.ciContactDetails),
            // White rows on the tinted page, with hairlines between — the
            // frame's shape, and what Contact detail already did. This screen
            // stayed one flat tone, so its headings floated and its rows had
            // no grouping.
            Surface(divided: true, children: <Widget>[
            ...detailsBefore,
            // Which network the thread runs on. Always shown, even though it
            // is WhatsApp for almost every row: an agent has to know before
            // replying, because what may be sent and how long the window stays
            // open differ between the two, and an absent row would read as
            // "WhatsApp" by default on exactly the threads where that is wrong.
            InfoRow(
              label: l10n.ciChannel,
              value: t.channel.isInstagram
                  ? l10n.chanInstagram
                  : l10n.chanWhatsapp,
              secondary: t.channel.isInstagram ? handle : null,
            ),
            ?_firstSeenRow(l10n, contact, locale),
            // Which workspace number the customer reached. Taken from the
            // most recent message that carries one rather than the newest
            // outright, so an outbound-only tail does not blank the row.
            if (_receivedOn(t) != null)
              InfoRow(label: l10n.ciReceivedOn, value: _receivedOn(t)!),
            ...detailsAfter,
            ]),

            // The frame's LABELS chips, with its "+ Add".
            //
            // The section is always drawn; it used to vanish entirely when a
            // contact had no labels, which hid the way to add the first one.
            if (contact != null) ...<Widget>[
              SectionLabel(l10n.cdLabels),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    for (final String label in contact.labels)
                      StatusPill(
                        label: label,
                        tone: StatusTone.info,
                        showDot: false,
                      ),
                    // The same picker Contact detail uses. It writes here
                    // rather than sending the agent to the edit form: this
                    // screen already holds the full contact — labels, city,
                    // groups and custom fields — through the same provider, so
                    // it can assemble the whole-record write the endpoint
                    // needs. The earlier note claiming otherwise was wrong.
                    AddTagChip(contact: contact),
                  ],
                ),
              ),
            ],

            SectionLabel(l10n.ciServiceWindow),
            // Open/Closed once, in the pill. It used to be both the title and
            // the trailing pill, so the row read "Closed ... Closed"; the title
            // now carries the deadline, which is the fact the pill cannot show.
            AppListTile(
              title: t.windowExpiresAt == null
                  ? (t.windowOpen ? l10n.ciOpen : l10n.ciReopenHint)
                  : DateFormat.yMMMd(locale)
                      .add_jm()
                      .format(t.windowExpiresAt!),
              subtitle: t.windowExpiresAt != null && !t.windowOpen
                  ? l10n.ciReopenHint
                  : null,
              leading: IconTile(
                icon: Icons.schedule_outlined,
                color: t.windowOpen ? AppColor.success : AppColor.warning,
              ),
              showChevron: false,
              trailing: StatusPill(
                label: t.windowOpen ? l10n.ciOpen : l10n.ciClosed,
                tone: t.windowOpen ? StatusTone.success : StatusTone.warning,
              ),
            ),

            SectionLabel(l10n.ciAssignedTo),
            // The frame leads this row with the agent's own avatar and puts
            // their name in the title slot — the label lives in the section
            // heading, so repeating it as the title left the row saying
            // nothing.
            AppListTile(
              title: t.assignedAgentName ?? l10n.ciUnassigned,
              leading: t.assignedAgentName == null
                  ? const IconTile(
                      icon: Icons.person_outline,
                      color: AppColor.info,
                    )
                  : InitialsAvatar(
                      name: t.assignedAgentName!,
                      size: AppDimens.iconTile,
                    ),
              showChevron: false,
              // The frame's "Change" link. The assign screen already existed
              // and was reachable only from the chat's actions sheet, so this
              // row named an owner it gave no way to change.
              trailing: TextButton(
                onPressed: () =>
                    context.push(AppRoutes.chatAssign(contactUid)),
                child: Text(l10n.ciChangeAssignee),
              ),
            ),
            AppListTile(
              title: l10n.ciReplyLock,
              subtitle: t.isReplyLockOpen
                  ? l10n.ciReplyLockFree
                  : l10n.ciReplyLockHeld(t.replyLockHeldBy ?? ''),
              leading: IconTile(
                icon: t.isReplyLockOpen ? Icons.lock_open_outlined : Icons.lock_outline,
                color: t.isReplyLockOpen ? AppColor.inkMuted : AppColor.warning,
              ),
              showChevron: false,
            ),

            SectionLabel(l10n.notesTitle),
            // The frame's "View all ›". The row already navigated; it just did
            // not say so.
            AppListTile(
              title: l10n.notesViewAll,
              subtitle: l10n.notesCount(noteCount),
              leading: const IconTile(
                icon: Icons.sticky_note_2_outlined,
                color: AppColor.warning,
              ),
              onTap: () => context.push(AppRoutes.chatNotes(contactUid)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// This contact's Instagram handle from the loaded inbox, or null when the
  /// list does not currently hold the row.
  String? _instagramHandle(List<Conversation> rows) {
    for (final Conversation c in rows) {
      if (c.contactUid != contactUid) continue;
      // Empty and absent are the same thing here — the field comes back as ""
      // on a row the sync has not filled in, and a blank second line reads as
      // a rendering fault.
      final String handle = (c.instagramUsername ?? '').trim();
      return handle.isEmpty ? null : handle;
    }
    return null;
  }

  /// The number this conversation arrived on, or null if no message carries
  /// one.
  String? _receivedOn(ChatThread t) {
    for (final ChatMessage m in t.messages.reversed) {
      final String? on = m.receivedOn;
      if (on != null && on.isNotEmpty) return on;
    }
    return null;
  }

  /// The CONTACT DETAILS block, restricted to fields the customer record
  /// actually carries.
  ///
  /// Row order follows the frame: Email, Country, Channel, First seen,
  /// Received on, Customer status, Language. Channel and Received on come off
  /// the thread rather than the contact, so the caller interleaves them — the
  /// two halves are split by where the data lives, not by how it reads.
  ///
  /// **Customer status** is here now. A stale comment claimed it existed
  /// "neither on [Contact] nor in the conversation payload" and kept the row
  /// out; it is `customerType`, which the contact has carried since the
  /// lifecycle stage was wired, and is the same value the pill under the hero
  /// shows.
  List<Widget> _detailRowsBefore(
    AppLocalizations l10n,
    Contact? contact,
    String locale,
  ) {
    if (contact == null) return const <Widget>[];
    final String? email = contact.email;
    final String? country = contact.countryCode;

    return <Widget>[
      if (email != null && email.isNotEmpty)
        InfoRow(label: l10n.ciEmail, value: email),
      if (country != null && country.isNotEmpty)
        InfoRow(label: l10n.ciCountry, value: country),
    ];
  }

  /// First seen, which the frame places between Channel and Received on.
  ///
  /// `createdAt` is the date the workspace first saw this customer, which is
  /// exactly the frame's row. It sits on its own because the rows either side
  /// of it come off the thread rather than the contact.
  Widget? _firstSeenRow(
    AppLocalizations l10n,
    Contact? contact,
    String locale,
  ) {
    final DateTime? firstSeen = contact?.createdAt;
    if (firstSeen == null) return null;
    return InfoRow(
      label: l10n.ciFirstSeen,
      value: DateFormat.yMMMd(locale).format(firstSeen),
    );
  }

  /// The rows the frame places after Received on.
  List<Widget> _detailRowsAfter(
    AppLocalizations l10n,
    Contact? contact,
    String locale,
  ) {
    if (contact == null) return const <Widget>[];
    final String? stage = stageBadge(l10n, contact)?.label;
    // "English (en)" — the frame shows both, because an agent choosing a
    // template needs the code and everyone else needs the name.
    final String? language = languageName(contact.language);

    return <Widget>[
      if (stage != null) InfoRow(label: l10n.ciCustomerStatus, value: stage),
      if (language != null)
        InfoRow(
          label: l10n.cdLanguage,
          value: language.toLowerCase() == (contact.language ?? '').toLowerCase()
              ? language
              : '$language (${contact.language})',
        ),
    ];
  }
}