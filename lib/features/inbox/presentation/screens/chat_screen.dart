import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/message_composer.dart';
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
    ref.invalidate(chatThreadProvider(widget.contactUid));
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
            Expanded(child: _MessageList(thread: data)),
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
    // Newest first, because the list is reversed — the thread grows upward
    // from the composer rather than down from the app bar.
    final List<ChatMessage> ordered = thread.messages.reversed.toList();

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      itemCount: ordered.length,
      itemBuilder: (BuildContext context, int i) {
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
              text: m.body,
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
