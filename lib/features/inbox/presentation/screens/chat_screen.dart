import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/message_composer.dart';
import '../../../../core/widgets/reply_window_ring.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../calls/data/call_repository.dart';
import '../../../calls/domain/call.dart';
import '../../../quick_replies/data/quick_reply_repository.dart';
import '../../data/conversation_repository.dart';
import '../../data/instagram_repository.dart';
import '../../data/media_repository.dart';
import '../../domain/channel.dart';
import '../../domain/conversation.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/chat_actions_sheet.dart';
import '../widgets/message_kind_style.dart';
import '../widgets/message_payload_view.dart';
import '../widgets/reply_lock_strip.dart';
import '../widgets/reaction_picker.dart';

/// Chat — Figma 37:1032.
///
/// Vertical order matches the frame exactly: app bar → service-window banner →
/// reversed message list → reply-lock strip → quick replies → composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final GlobalKey<MessageComposerState> _composerKey =
      GlobalKey<MessageComposerState>();

  Future<void> _send(String body) async {
    await ref
        .read(conversationRepositoryProvider)
        .sendMessage(widget.contactUid, body);
    // reload(), not invalidate(): invalidating rebuilds from page 1 and throws
    // away every older page the reader had scrolled back through, so a send
    // used to collapse a long thread to the newest 50 and jump them to the
    // bottom. reload() has the same effect here only because a send is already
    // a return to the bottom; anywhere else, prefer prepend().
    await ref.read(chatThreadProvider(widget.contactUid).notifier).reload();
    // Sending is what takes the lock — the engine claims a fresh five minutes
    // on every send and extends it on the next. Without this the strip still
    // reads "no one is replying" immediately after this agent replied.
    ref.invalidate(replyLockProvider(widget.contactUid));
  }

  /// Picks a file, uploads it, then sends the returned name.
  ///
  /// Always uploads, even on WhatsApp where a mediaUrl would also be accepted.
  /// Instagram is upload-only, and one path exercised by every send beats a
  /// second one exercised by two contacts out of thirty-six.
  Future<void> _attach(MessageChannel channel) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PickedMedia? picked = await showAttachSheet(context, channel: channel);
    if (picked == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mediaSending), duration: const Duration(minutes: 5)),
    );

    try {
      final MediaRepository repo = ref.read(mediaRepositoryProvider);
      final String name = await repo.upload(
        path: picked.path,
        fileName: picked.fileName,
      );
      await repo.send(
        contactUid: widget.contactUid,
        uploadedFileName: name,
        kind: picked.kind,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.mediaSent)));
      await ref.read(chatThreadProvider(widget.contactUid).notifier).reload();
    } on Failure catch (e) {
      // Surface the server's wording verbatim. Instagram's accepted formats
      // are narrower than WhatsApp's, and only the server knows which list
      // applies — an invented client message would be wrong half the time.
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Long-press a bubble to react. Instagram only — there is no WhatsApp
  /// endpoint, so the gesture does nothing on a WhatsApp thread rather than
  /// offering a picker whose send would 422.
  Future<void> _react(ChatMessage message) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? emoji = await showReactionPicker(context);
    if (emoji == null || !mounted) return;
    try {
      await ref.read(instagramRepositoryProvider).react(
            contactUid: widget.contactUid,
            messageUid: message.uid,
            emoji: emoji,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.igReacted)));
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Loads the next older page when the reader nears the top of the thread.
  ///
  /// The list is reversed, so "the top" is `maxScrollExtent`. Fires early —
  /// 400px out — so the page is usually there before the reader reaches the
  /// end of what is loaded. Re-entry is guarded inside the controller, not
  /// here, because the notification fires on every frame of a fling.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
      ref.read(chatThreadProvider(widget.contactUid).notifier).loadOlder();
    }
    return false;
  }

  /// Conversation status for [contactUid] from the loaded inbox list, or null
  /// if that list has no entry for it.
  ConversationStatus? _statusOf(String contactUid) {
    final List<Conversation>? rows = ref.watch(inboxListProvider).valueOrNull;
    if (rows == null) return null;
    for (final Conversation c in rows) {
      if (c.contactUid == contactUid) return c.status;
    }
    return null;
  }

  Future<void> _setStatus(ConversationStatus status) async {
    await ref
        .read(conversationRepositoryProvider)
        .setStatus(widget.contactUid, status);
    ref.invalidate(chatThreadProvider(widget.contactUid));
    // The inbox rows carry the status too, so a change made here has to
    // invalidate that list or the two screens disagree until a manual refresh.
    ref.invalidate(inboxListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ChatThread> thread =
        ref.watch(chatThreadProvider(widget.contactUid));

    return Scaffold(
      appBar: AppHeader.back(
        title: thread.valueOrNull?.name ?? '',
        subtitle: thread.valueOrNull?.phone,
        // The countdown leads the avatar so the first thing in the header,
        // after the way back, is how long free-form replies still work. The
        // ring renders nothing at all once the window has closed, so on a
        // dormant thread this collapses to the avatar alone.
        avatar: thread.valueOrNull == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ReplyWindowRing(
                    expiresAt: thread.valueOrNull!.windowExpiresAt,
                    windowOpen: thread.valueOrNull!.windowOpen,
                  ),
                  InitialsAvatar(name: thread.valueOrNull!.name, size: 30),
                ],
              ),
        // The chat detail payload carries no conversation status — only
        // per-message delivery state — so it is read from the inbox row for
        // this contact, which does have it. When that row isn't loaded (deep
        // link straight into a chat) the pill is omitted rather than guessed.
        // Gated on the thread too, not just the status: the inbox row resolves
        // first, so the pill used to hang in the app bar on its own for the
        // second or two before the name and avatar arrived.
        subtitleTrailing: thread.valueOrNull == null ||
                _statusOf(widget.contactUid) == null
            ? null
            : _StatusMenu(
                status: _statusOf(widget.contactUid)!,
                onSelected: _setStatus,
              ),
        // Tapping the contact in the app bar opens conversation info — the
        // handoff's `Chat → Contact info` edge, and the only entry point to
        // that screen.
        onTitleTap: () => context.push(AppRoutes.chatInfo(widget.contactUid)),
        actions: <Widget>[
          _CallButton(
            contactUid: widget.contactUid,
            name: thread.valueOrNull?.name,
          ),
          IconButton(
            onPressed: () => showChatActionsSheet(
              context,
              contactUid: widget.contactUid,
              name: thread.valueOrNull?.name ?? '',
              phone: thread.valueOrNull?.phone,
              channel:
                  thread.valueOrNull?.channel ?? MessageChannel.whatsapp,
            ),
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
      body: AsyncValueView<ChatThread>(
        value: thread,
        onRetry: () => ref.invalidate(chatThreadProvider(widget.contactUid)),
        builder: (ChatThread data) => Column(
          children: <Widget>[
            _ServiceWindowBanner(thread: data, l10n: l10n),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: _MessageList(
                  thread: data,
                  // Null on WhatsApp: the long-press only exists where the
                  // endpoint does.
                  onReact: data.channel.isInstagram ? _react : null,
                ),
              ),
            ),
            // Both strips can be visible at once — the handoff requires their
            // copy stay non-contradictory, and neither disables the composer.
            // Read from its own endpoint rather than from the thread payload:
            // the payload's copy is only as fresh as the last full thread
            // fetch, and a five-minute lock changes far more often than that.
            ReplyLockStrip(contactUid: widget.contactUid),
            // Chat detail carries no canned replies, so the chips come from
            // the quick-replies endpoint. Failure is non-fatal — the chips
            // simply don't render rather than taking the chat down.
            Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                final List<String> replies = ref
                        .watch(quickReplyListProvider)
                        .valueOrNull
                        ?.where((QuickReply q) => q.active)
                        .map((QuickReply q) => q.title)
                        .toList() ??
                    const <String>[];
                if (replies.isEmpty) return const SizedBox.shrink();
                return QuickReplyChips(
                  replies: replies,
                  onSelected: (String title) {
                    final QuickReply? q = ref
                        .read(quickReplyListProvider)
                        .valueOrNull
                        ?.firstWhere((QuickReply e) => e.title == title);
                    // Insert the message body, not the shortcut label.
                    _composerKey.currentState?.setText(q?.body ?? title);
                  },
                );
              },
            ),
            MessageComposer(
              key: _composerKey,
              hintText: l10n.chatComposerHint,
              onSend: _send,
              onAttach: () => _attach(data.channel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceWindowBanner extends StatelessWidget {
  const _ServiceWindowBanner({required this.thread, required this.l10n});

  final ChatThread thread;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (!thread.windowOpen) {
      return AppBanner(
        message: l10n.chatServiceWindowClosed,
        tone: BannerTone.warning,
      );
    }

    final DateTime? expiry = thread.windowExpiresAt;
    if (expiry == null) return const SizedBox.shrink();

    final int secondsLeft = expiry.difference(DateTime.now()).inSeconds;
    if (secondsLeft <= 0) {
      // Server said open, but the deadline has passed while the screen was
      // sitting there. Trust the deadline over the stale flag.
      return AppBanner(
        message: l10n.chatServiceWindowClosed,
        tone: BannerTone.warning,
      );
    }

    return AppBanner(
      message: l10n.chatServiceWindowOpen(DurationFormat.coarse(secondsLeft)),
      tone: BannerTone.warning,
    );
  }
}

/// The app-bar call button, gated on what the workspace may actually do.
///
/// Meta refuses business-initiated calls from USA/Canada numbers, and this
/// workspace's sending number is one — so `canPlaceCall` is false here and
/// placing a call always fails. Rather than let an agent tap a button that
/// cannot work, the button stays disabled and says why on tap.
///
/// It reads the capability rather than hard-coding the rule, so it starts
/// working by itself the day the sending number changes. Capability is also
/// re-read rather than cached, because `withinBusinessHours` flips during the
/// day.
class _CallButton extends ConsumerWidget {
  const _CallButton({required this.contactUid, this.name});

  final String contactUid;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CallCapability? cap = ref.watch(callCapabilityProvider).valueOrNull;
    // Until capability resolves the button is inert rather than absent —
    // appearing a moment later would shift the whole app bar.
    final bool canCall = cap?.canPlaceCall ?? false;

    return IconButton(
      tooltip: canCall ? null : l10n.clUnavailable,
      onPressed: () {
        if (canCall) {
          context.push('/calls/$contactUid/outgoing', extra: name);
          return;
        }
        // Say which gate closed. "Calling is off for this workspace" is
        // fixable by the user; "Meta will not allow it from this number" is
        // not, and conflating them sends someone hunting through settings.
        final String reason = cap == null
            ? l10n.clUnavailable
            : !cap.enabled
                ? l10n.clDisabled
                : l10n.clRestricted(
                    cap.outboundRestrictedReason ?? l10n.clUnavailable,
                  );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
      },
      icon: Icon(
        Icons.call,
        color: canCall ? Colors.white : Colors.white54,
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.thread, this.onReact});

  final ChatThread thread;

  /// Set only on an Instagram thread — see [ChatScreen._react].
  final void Function(ChatMessage message)? onReact;

  @override
  Widget build(BuildContext context) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    // Already newest-first — see ChatThread.messages. Do NOT reverse here: the
    // list below is reverse: true, so index 0 renders at the bottom against the
    // composer and the thread grows upward. Reversing as well puts the newest
    // message at the top, which is the bug this comment exists to prevent
    // recurring.
    final List<ChatMessage> ordered = thread.messages;

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      // One extra slot at the tail — the visual top of a reversed list — for
      // the older-page spinner, so the reader can see that scrolling back is
      // fetching rather than stuck.
      itemCount: ordered.length + (thread.loadingMore ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= ordered.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final ChatMessage m = ordered[i];
        // In a reversed list the "next" item is the older one, so a day
        // divider belongs after a message whose predecessor is on another day.
        final ChatMessage? older = i + 1 < ordered.length ? ordered[i + 1] : null;
        final bool startsDay = older == null ||
            !_sameDay(older.sentAt, m.sentAt);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (startsDay && m.sentAt != null)
              ChatDayDivider(label: _dayLabel(context, m.sentAt!)),
            // The whole bubble is the target, not a separate affordance: a
            // reaction is a low-stakes gesture and the frames show no button.
            GestureDetector(
              onLongPress: onReact == null ? null : () => onReact!(m),
              child: _bubbleFor(context, m, locale),
            ),
          ],
        );
      },
    );
  }

  /// Builds a bubble that says what kind of message it is.
  ///
  /// The old fallback rendered "no text" for every empty body, because
  /// ChatMessage carried no type. The API now resolves one, so a photo says
  /// photo and an order says order — which matters most for the commerce kinds,
  /// whose bodies are empty by construction: the cart lives in a webhook the
  /// API strips, so those bubbles were blank rather than merely terse.
  Widget _bubbleFor(BuildContext context, ChatMessage m, String locale) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MessageKindStyle style = MessageKindStyle.of(m.kind, l10n);
    final String body = m.body.trim();

    // The structured payload, when there is one. Until this existed the label
    // WAS the bubble: an order said "Order" and showed none of its lines.
    final Widget? content = messagePayloadView(context, m, locale);

    // Once the payload renders the cart, the header, the buttons — repeating
    // the type name above it is noise. The label stays only when nothing else
    // announces the kind.
    final bool labelRedundant = content != null &&
        const <MessageKind>{
          MessageKind.order,
          MessageKind.template,
          MessageKind.interactiveButtons,
          MessageKind.interactiveList,
        }.contains(m.kind);

    return MessageBubble(
      kindIcon: labelRedundant ? null : style.icon,
      kindLabel: labelRedundant ? null : style.label,
      // With a type line or a payload present an empty body is fine. Only an
      // untyped, textless message still needs the old placeholder.
      text: body.isEmpty && style.label == null && content == null
          ? l10n.chatNoTextBody
          : body,
      content: content,
      badge: _badgeFor(context, m),
      timeLabel:
          m.sentAt == null ? '' : DateFormat.Hm(locale).format(m.sentAt!),
      isOutgoing: !m.isIncoming,
      status: _status(m.status),
    );
  }

  /// "Bot" or a campaign name above the bubble.
  ///
  /// Both answer the same question — who actually sent this? In a shared inbox
  /// an agent reading back through a thread otherwise credits a teammate for
  /// the bot's replies, or reads a campaign blast as a personal message to this
  /// one customer.
  Widget? _badgeFor(BuildContext context, ChatMessage m) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? text = m.isBotReply
        ? l10n.mtBot
        : (m.campaignName == null ? null : '${l10n.mtCampaign} · ${m.campaignName}');
    if (text == null) return null;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColor.infoWash,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColor.info,
        ),
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(BuildContext context, DateTime at) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime now = DateTime.now();

    if (_sameDay(at, now)) return l10n.commonToday;
    if (_sameDay(at, now.subtract(const Duration(days: 1)))) {
      return l10n.commonYesterday;
    }
    return DateFormat.yMMMd(locale).format(at);
  }

  MessageStatus? _status(String? raw) => switch (raw) {
    'sent' => MessageStatus.sent,
    'delivered' => MessageStatus.delivered,
    'read' => MessageStatus.read,
    'failed' => MessageStatus.failed,
    null => null,
    _ => MessageStatus.pending,
  };
}

/// Conversation status as a pill that is also the control for changing it.
///
/// The frame puts the status beside the presence line in the app bar. It is a
/// pill rather than a menu button because status is mostly *read* here; the
/// menu is the same target so there is no second affordance to find.
/// `setStatus` is a real endpoint, so unlike the removed campaign/agent CTAs
/// this one does something.
class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onSelected});

  final ConversationStatus status;
  final ValueChanged<ConversationStatus> onSelected;

  static ({String label, StatusTone tone}) _badge(
    AppLocalizations l10n,
    ConversationStatus s,
  ) =>
      switch (s) {
        ConversationStatus.open =>
          (label: l10n.cvStatusOpen, tone: StatusTone.success),
        ConversationStatus.pending =>
          (label: l10n.cvStatusPending, tone: StatusTone.warning),
        ConversationStatus.solved =>
          (label: l10n.cvStatusSolved, tone: StatusTone.info),
        ConversationStatus.blocked =>
          (label: l10n.cvStatusBlocked, tone: StatusTone.danger),
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final badge = _badge(l10n, status);

    return PopupMenuButton<ConversationStatus>(
      onSelected: onSelected,
      tooltip: l10n.cvChangeStatus,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ConversationStatus>>[
        for (final ConversationStatus s in ConversationStatus.values)
          PopupMenuItem<ConversationStatus>(
            value: s,
            child: Row(
              children: <Widget>[
                Icon(
                  s == status ? Icons.check : null,
                  size: 16,
                  color: AppColor.brandDeep,
                ),
                const SizedBox(width: 8),
                Text(_badge(l10n, s).label),
              ],
            ),
          ),
      ],
      child: StatusPill(label: badge.label, tone: badge.tone),
    );
  }
}
