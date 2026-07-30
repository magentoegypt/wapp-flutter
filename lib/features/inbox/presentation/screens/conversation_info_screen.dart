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
import '../../../contacts/data/contact_repository.dart';
import '../../../contacts/domain/contact.dart';
import '../../data/conversation_repository.dart';
import '../../data/note_repository.dart';
import '../../domain/conversation.dart';

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
    final List<Widget> details = _detailRows(l10n, contact, locale);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.ciContactInfo),
      body: AsyncValueView<ChatThread>(
        value: thread,
        onRetry: () => ref.invalidate(chatThreadProvider(contactUid)),
        builder: (ChatThread t) => ListView(
          children: <Widget>[
            const SizedBox(height: 20),
            Center(
              child: InitialsAvatar(name: t.name, size: AppDimens.avatarHero),
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
                  t.phone!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],

            const SizedBox(height: 18),
            _QuickActions(contactUid: contactUid, phone: t.phone, l10n: l10n),

            if (details.isNotEmpty || _receivedOn(t) != null) ...<Widget>[
              SectionLabel(l10n.ciContactDetails),
              ...details,
              // Which workspace number the customer reached. Taken from the
              // most recent message that carries one rather than the newest
              // outright, so an outbound-only tail does not blank the row.
              if (_receivedOn(t) != null)
                _DetailRow(label: l10n.ciReceivedOn, value: _receivedOn(t)!),
            ],

            // The frame's LABELS chips. Read-only: ContactRepository has no
            // label mutation, so the frame's "+ Add" chip is not here — an add
            // affordance that cannot add is worse than none.
            if ((contact?.labels ?? const <String>[]).isNotEmpty) ...<Widget>[
              SectionLabel(l10n.cdLabels),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String label in contact!.labels)
                      StatusPill(
                        label: label,
                        tone: StatusTone.info,
                        showDot: false,
                      ),
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
            AppListTile(
              title: l10n.notesTitle,
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
  /// The frame also lists Channel and Customer status. Neither exists on
  /// [Contact] or in the conversation payload, and a row rendered from nothing
  /// reads as a fact — so they are left out until the API carries them.
  /// Language is here: it was listed as absent by a stale comment, but the
  /// field has existed since contacts gained city/language.
  List<Widget> _detailRows(
    AppLocalizations l10n,
    Contact? contact,
    String locale,
  ) {
    if (contact == null) return const <Widget>[];
    final String? email = contact.email;
    final String? country = contact.countryCode;
    // `createdAt` is the date the
    // workspace first saw this customer, which is exactly the frame's row.
    final DateTime? firstSeen = contact.createdAt;

    return <Widget>[
      if (email != null && email.isNotEmpty)
        _DetailRow(label: l10n.ciEmail, value: email),
      if (country != null && country.isNotEmpty)
        _DetailRow(label: l10n.ciCountry, value: country),
      if ((contact.language ?? '').isNotEmpty)
        _DetailRow(label: l10n.cdLanguage, value: contact.language!),
      if (firstSeen != null)
        _DetailRow(
          label: l10n.ciFirstSeen,
          value: DateFormat.yMMMd(locale).format(firstSeen),
        ),
    ];
  }
}

/// One label/value line in the CONTACT DETAILS block.
///
/// Deliberately not an [AppListTile]: the frame's detail block is a tight
/// two-column list with no leading tile and no chevron. Borrowing the row
/// idiom made seven pieces of read-only data look like seven tappable
/// settings.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.gutter,
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              // End-aligned, so the values line up on the trailing edge in
              // both writing directions.
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(
                color: AppColor.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three-up action row the frame puts under the hero block.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.contactUid,
    required this.l10n,
    this.phone,
  });

  final String contactUid;
  final AppLocalizations l10n;
  final String? phone;

  /// Message returns to the chat instead of pushing a fresh one — this screen
  /// is only ever reached from there, so a push would stack a second copy of
  /// the same thread behind it.
  void _openChat(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.chat(contactUid));
    }
  }

  /// Hands off to the platform dialer. The app cannot place a call itself, and
  /// leaving the app is more honest than a tile that looks live and isn't.
  Future<void> _dial(String number) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      // No dialer on this device (tablet, emulator). Staying inert beats
      // throwing out of a tap handler.
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? number = phone;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.gutter,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _QuickAction(
              icon: Icons.mail_outline,
              label: l10n.ciActionMessage,
              onTap: () => _openChat(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.call_outlined,
              label: l10n.ciActionCall,
              onTap: number == null ? null : () => _dial(number),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.sticky_note_2_outlined,
              label: l10n.ciActionNote,
              onTap: () => context.push(AppRoutes.chatNotes(contactUid)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One brand-wash tile in the quick-action row.
///
/// [AppColor.brandDeep] for the glyph and the label, not [AppColor.brand]:
/// brand green is a fill colour and does not reach AA as text on the wash.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColor.brandWash,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 20, color: AppColor.brandDeep),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColor.brandDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
