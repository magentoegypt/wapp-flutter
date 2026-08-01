import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/channel_badge.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/util/screen_poll.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_repository.dart';
import '../../domain/conversation.dart';

/// Chip count, or null when it cannot be derived honestly.
///
/// Only the unfiltered response contains every conversation, so that is the only
/// state where a client-side count is a true total. Under any other filter the
/// chips carry no numbers rather than wrong ones.
int? _countFor(
  AsyncValue<List<Conversation>> rows,
  InboxFilter active,
  InboxFilter chip,
) {
  if (active != InboxFilter.all) return null;
  final List<Conversation>? items = rows.valueOrNull;
  if (items == null) return null;
  return switch (chip) {
    InboxFilter.all => items.length,
    InboxFilter.unread =>
      items.where((Conversation c) => c.unreadCount > 0).length,
    // No assignee on the list row, so this one cannot be counted client-side.
    InboxFilter.unassigned => null,
  };
}

/// Inbox — Figma 36:1032.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen>
    with ScreenPoll<InboxScreen> {
  @override
  Duration get pollInterval => kInboxPollInterval;

  /// `invalidate` rather than a bespoke merge: the provider refetches while
  /// keeping its current value on screen, so rows do not blink every fifteen
  /// seconds. A list is cheap to rebuild — a thread is not, which is why the
  /// chat has [ChatThreadController.refreshHead] and this does not.
  @override
  Future<void> onPoll() async => ref.invalidate(inboxListProvider);

  /// Stop while anything is pushed over the shell.
  ///
  /// This tab lives in a shell branch, so opening a chat — which pushes onto
  /// the *root* navigator — leaves the inbox's own route current and the
  /// generic route check blind to it. Measured before this: five chat ticks
  /// and two inbox ticks in the same thirty seconds, refreshing a list nobody
  /// could see.
  @override
  bool get pollEnabled {
    final NavigatorState? root =
        Navigator.maybeOf(context, rootNavigator: true);
    return root == null || !root.canPop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Conversation>> rows = ref.watch(inboxListProvider);
    final InboxFilter filter = ref.watch(inboxFilterProvider);

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.inboxTitle,
        searchHint: l10n.inboxSearchHint,
        // The field opens the dedicated Search screen rather than filtering in
        // place — that screen is the handoff's `Chats → Search` edge, and
        // without this entry point it was unreachable.
        onSearchTap: () => context.push(AppRoutes.search),
        trailing: const AgentAvatar(),
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct hero tag. Inbox and Contacts are both kept alive by
        // StatefulShellRoute.indexedStack, so two FABs sharing Flutter's
        // default tag collide and throw on every tab switch.
        heroTag: 'fab-inbox',
        onPressed: () => context.push(AppRoutes.contactNew),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: <Widget>[
          FilterChipBar(
            // Counts, per the frame. Derived from the loaded page, so they are
            // only shown on the unfiltered view where that page is the whole
            // inbox — a count taken from an already-filtered response would be
            // a subset masquerading as a total.
            options: <FilterOption>[
              FilterOption(
                id: InboxFilter.all.name,
                label: l10n.inboxFilterAll,
                count: _countFor(rows, filter, InboxFilter.all),
              ),
              FilterOption(
                id: InboxFilter.unread.name,
                label: l10n.inboxFilterNew,
                count: _countFor(rows, filter, InboxFilter.unread),
              ),
              FilterOption(
                id: InboxFilter.unassigned.name,
                label: l10n.inboxFilterUnassigned,
                count: _countFor(rows, filter, InboxFilter.unassigned),
              ),
            ],
            selectedId: filter.name,
            onSelected: (String id) => ref
                .read(inboxFilterProvider.notifier)
                .state = InboxFilter.values.byName(id),
          ),
          Expanded(
            child: AsyncValueView<List<Conversation>>(
              value: rows,
              onRetry: () => ref.invalidate(inboxListProvider),
              builder: (List<Conversation> items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.forum_outlined,
                    title: l10n.inboxEmptyTitle,
                    message: l10n.inboxEmptyMessage,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(inboxListProvider),
                  // Whitespace between rows, per the frame — the hairline made
                  // the list read as a settings table rather than a feed.
                  child: ListView.builder(
                    // Clears the FAB. Without it the button sits on top of the
                    // last conversation and hides its timestamp.
                    padding: const EdgeInsets.only(
                      bottom: AppDimens.fabClearance,
                    ),
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int i) =>
                        _ConversationRow(item: items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.item});

  final Conversation item;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: item.name,
      // A tick when we spoke last, per the frame. Conversation.isIncomingLast
      // was parsed and documented as driving exactly this, then read by no
      // widget — the field has been dead since it was added.
      subtitle: item.isIncomingLast || item.lastMessage.isEmpty
          ? item.lastMessage
          : '${item.lastMessage}  ✓',
      leading: AvatarWithChannel(name: item.name, channel: item.channel),
      showChevron: false,
      onTap: () => context.push(AppRoutes.chat(item.contactUid)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            _stamp(context, item.lastMessageAt),
            // Brand-tinted on a row with unread messages, as the frame has it —
            // the timestamp is the only part of the row that says "recent", so
            // it carries the emphasis alongside the count pill.
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: item.unreadCount > 0 ? AppColor.brandDeep : null,
                  fontWeight:
                      item.unreadCount > 0 ? FontWeight.w700 : null,
                ),
          ),
          const SizedBox(height: 4),
          if (item.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColor.brand,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${item.unreadCount}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }

  /// Time for today, weekday within the last week, otherwise a short date.
  /// Formatting goes through [DateFormat] with the ambient locale so Arabic
  /// gets Arabic weekday names and numerals.
  String _stamp(BuildContext context, DateTime? at) {
    if (at == null) return '';
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime now = DateTime.now();
    final Duration age = now.difference(at);

    if (age.inDays == 0 && now.day == at.day) {
      return DateFormat.Hm(locale).format(at);
    }
    // "Yesterday" before the weekday names start, per the frame. A bare "Thu"
    // for something that arrived last night reads as a week old at a glance.
    if (age.inDays < 2 && now.day - at.day == 1) {
      return AppLocalizations.of(context).commonYesterday;
    }
    if (age.inDays < 7) return DateFormat.E(locale).format(at);
    return DateFormat.yMd(locale).format(at);
  }
}
