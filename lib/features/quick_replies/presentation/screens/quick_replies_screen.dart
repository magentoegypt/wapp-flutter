import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/quick_reply_repository.dart';

/// Quick replies — Figma 281:71.
class QuickRepliesScreen extends ConsumerWidget {
  const QuickRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<QuickReply>> rows = ref.watch(quickReplyListProvider);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.moreQuickReplies),
      floatingActionButton: FloatingActionButton(
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
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(quickReplyListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 76),
              itemBuilder: (BuildContext context, int i) {
                final QuickReply q = items[i];
                return AppListTile(
                  title: q.title,
                  subtitle: q.body,
                  leading: const IconTile(
                    icon: Icons.bolt_outlined,
                    color: AppColor.info,
                  ),
                  onTap: () => context.push(AppRoutes.quickReply(q.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
