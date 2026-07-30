import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/quick_reply_repository.dart';

/// The chip row's "everything" option. Not a category id, so it is namespaced
/// out of the way of one arriving from the API.
const String _allCategories = '__all__';

/// Label for a category id, falling back to the raw value.
///
/// Shared with the editor's select so a category can never read one way in the
/// chip row and another in the form.
String quickReplyCategoryLabel(AppLocalizations l10n, String id) =>
    switch (id) {
      QuickReplyCategories.greetings => l10n.qrCategoryGreetings,
      QuickReplyCategories.orders => l10n.qrCategoryOrders,
      QuickReplyCategories.support => l10n.qrCategorySupport,
      // A category the backend invented on its own still has to render.
      _ => id,
    };

/// Quick replies — Figma 281:71.
class QuickRepliesScreen extends ConsumerStatefulWidget {
  const QuickRepliesScreen({super.key});

  @override
  ConsumerState<QuickRepliesScreen> createState() => _QuickRepliesScreenState();
}

class _QuickRepliesScreenState extends ConsumerState<QuickRepliesScreen> {
  String _query = '';
  String _category = _allCategories;

  /// The categories actually in use, frame order first.
  ///
  /// Derived from the loaded rows rather than hardcoded: `GET /quick-replies`
  /// has no category vocabulary endpoint, so a fixed chip row would offer
  /// buckets that can only ever come back empty.
  List<String> _categoriesIn(List<QuickReply> items) {
    final Set<String> used = <String>{
      for (final QuickReply q in items)
        if (q.category != null) q.category!,
    };
    return <String>[
      ...QuickReplyCategories.known.where(used.contains),
      ...used.where((String c) => !QuickReplyCategories.known.contains(c)),
    ];
  }

  List<QuickReply> _visible(List<QuickReply> items, List<String> categories) {
    // A category can disappear when the list refreshes; falling back to "all"
    // beats showing an empty list under a chip row with nothing selected.
    final bool byCategory =
        _category != _allCategories && categories.contains(_category);
    final String q = _query.trim().toLowerCase();

    return items.where((QuickReply r) {
      if (byCategory && r.category != _category) return false;
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.body.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<QuickReply>> rows = ref.watch(quickReplyListProvider);
    final String agentName =
        ref.watch(authControllerProvider).session?.user.name ?? '';

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.moreQuickReplies,
        searchHint: l10n.qrSearchHint,
        // Filtered in place: the whole library is already loaded, so there is
        // nothing for a dedicated search screen to fetch.
        onSearchChanged: (String q) => setState(() => _query = q),
        // Pushed from More, so the header has to carry the way back itself.
        showBack: true,
        trailing: agentName.isEmpty
            ? null
            : InitialsAvatar.onBrand(name: agentName, size: 36),
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct hero tag. Inbox and Contacts are both kept alive by
        // StatefulShellRoute.indexedStack, so two FABs sharing Flutter's
        // default tag collide and throw on every tab switch.
        heroTag: 'fab-quick-replies',
        onPressed: () => context.push(AppRoutes.quickReplyNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<QuickReply>>(
        value: rows,
        onRetry: () => ref.invalidate(quickReplyListProvider),
        builder: (List<QuickReply> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.bolt_outlined,
              title: l10n.qrEmptyTitle,
              message: l10n.qrEmptyMessage,
            );
          }

          final List<String> categories = _categoriesIn(items);
          final List<QuickReply> visible = _visible(items, categories);

          return Column(
            children: <Widget>[
              // Outside the RefreshIndicator so it stays pinned while the list
              // pulls.
              if (categories.isNotEmpty)
                FilterChipBar(
                  options: <FilterOption>[
                    FilterOption(id: _allCategories, label: l10n.qrCategoryAll),
                    for (final String c in categories)
                      FilterOption(
                        id: c,
                        label: quickReplyCategoryLabel(l10n, c),
                      ),
                  ],
                  selectedId: _category,
                  onSelected: (String id) => setState(() => _category = id),
                ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: l10n.searchNoMatches,
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(quickReplyListProvider),
                        child: ListView.separated(
                          padding: const EdgeInsetsDirectional.only(
                            start: AppDimens.gutter,
                            end: AppDimens.gutter,
                            top: 12,
                            // Clears the FAB on the last card.
                            bottom: AppDimens.fab + AppDimens.gutter * 2,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int i) =>
                              _QuickReplyCard(item: visible[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One card in the list: shortcut chip, then up to two lines of the message.
///
/// The frame also shows a display name and a usage count on this row; the API
/// exposes neither, so the row stops at what exists rather than filling the
/// slots with invented values.
class _QuickReplyCard extends StatelessWidget {
  const _QuickReplyCard({required this.item});

  final QuickReply item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.push(AppRoutes.quickReply(item.uid)),
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ShortcutChip(label: item.title),
              const SizedBox(height: 8),
              Text(
                item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `/shortcut` token on a brand wash.
///
/// Not a [StatusPill]: a shortcut is an identifier, not state, and the palette
/// reserves the semantic greens for state. [AppColor.brandDeep] is the
/// text-safe green for the label.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColor.brandWash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColor.brandDeep,
        ),
      ),
    );
  }
}
