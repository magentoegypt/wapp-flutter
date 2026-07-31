import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/message_composer.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../quick_replies/data/quick_reply_repository.dart';
import '../../data/conversation_repository.dart';
import '../../domain/conversation.dart';
import '../widgets/chat_actions_sheet.dart';

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
        avatar: thread.valueOrNull == null
            ? null
            : InitialsAvatar(name: thread.valueOrNull!.name, size: 30),
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
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.call, color: Colors.white),
          ),
          IconButton(
            onPressed: () => showChatActionsSheet(
              context,
              contactUid: widget.contactUid,
              name: thread.valueOrNull?.name ?? '',
              phone: thread.valueOrNull?.phone,
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
                child: _MessageList(thread: data),
              ),
            ),
            // Both strips can be visible at once — the handoff requires their
            // copy stay non-contradictory, and neither disables the composer.
            if (data.isReplyLockOpen)
              AppBanner(
                message: l10n.chatReplyLockOpen,
                tone: BannerTone.neutral,
              ),
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
              onAttach: () {},
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

class _MessageList extends StatelessWidget {
  const _MessageList({required this.thread});

  final ChatThread thread;

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
            MessageBubble(
              // An empty body renders as a bubble containing only a timestamp,
              // which reads as a rendering fault. Almost always this is a media
              // message, but ChatMessage carries no type, so the placeholder
              // says what is certain — there is no text — rather than claiming
              // an attachment we cannot see.
              text: m.body.trim().isEmpty
                  ? AppLocalizations.of(context).chatNoTextBody
                  : m.body,
              timeLabel: m.sentAt == null
                  ? ''
                  : DateFormat.Hm(locale).format(m.sentAt!),
              isOutgoing: !m.isIncoming,
              status: _status(m.status),
            ),
          ],
        );
      },
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
