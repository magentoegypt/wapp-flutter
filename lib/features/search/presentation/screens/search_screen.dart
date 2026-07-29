import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/data/conversation_repository.dart';
import '../../../inbox/domain/conversation.dart';

/// The live query. Kept at module scope so the field and the results provider
/// stay in sync without threading a controller through.
final searchQueryProvider = StateProvider.autoDispose<String>((Ref ref) => '');

final searchResultsProvider =
    FutureProvider.autoDispose<List<Conversation>>((Ref ref) async {
  final String q = ref.watch(searchQueryProvider).trim();
  // Don't hit the API on a single character — it returns most of the workspace.
  if (q.length < 2) return const <Conversation>[];
  return ref.watch(conversationRepositoryProvider).list(query: q);
});

/// Search conversations — Figma 281:2.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String query = ref.watch(searchQueryProvider);
    final AsyncValue<List<Conversation>> results =
        ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.inboxSearchHint,
        searchHint: l10n.inboxSearchHint,
        // Pushed route - without this there is no way back out.
        showBack: true,
        onSearchChanged: (String q) =>
            ref.read(searchQueryProvider.notifier).state = q,
      ),
      body: query.trim().length < 2
          ? EmptyState(
              icon: Icons.search,
              title: l10n.searchPrompt,
              message: l10n.searchMinChars,
            )
          : AsyncValueView<List<Conversation>>(
              value: results,
              onRetry: () => ref.invalidate(searchResultsProvider),
              builder: (List<Conversation> items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppDimens.gutter),
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: l10n.searchNoMatches,
                      message: l10n.searchNothingFor(query.trim()),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(indent: 76),
                  itemBuilder: (BuildContext context, int i) {
                    final Conversation c = items[i];
                    return AppListTile(
                      title: c.name,
                      subtitle: c.lastMessage,
                      leading: InitialsAvatar(name: c.name),
                      showChevron: false,
                      onTap: () => context.push(AppRoutes.chat(c.contactUid)),
                    );
                  },
                );
              },
            ),
    );
  }
}
