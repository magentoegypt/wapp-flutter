import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_repository.dart';
import '../../domain/conversation.dart';

/// Inbox — Figma 36:1032.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            options: <FilterOption>[
              FilterOption(id: InboxFilter.all.name, label: l10n.inboxFilterAll),
              FilterOption(id: InboxFilter.unread.name, label: l10n.inboxFilterNew),
              FilterOption(
                id: InboxFilter.unassigned.name,
                label: l10n.inboxFilterUnassigned,
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
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(indent: 76),
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
      subtitle: item.lastMessage,
      leading: InitialsAvatar(name: item.name),
      showChevron: false,
      onTap: () => context.push(AppRoutes.chat(item.contactUid)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            _stamp(context, item.lastMessageAt),
            style: Theme.of(context).textTheme.labelMedium,
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
    if (age.inDays < 7) return DateFormat.E(locale).format(at);
    return DateFormat.yMd(locale).format(at);
  }
}
