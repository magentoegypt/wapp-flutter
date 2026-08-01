import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/bot_flow_repository.dart';
import 'bot_replies_screen.dart' show triggerLabel;

/// Bot flows — the More frame lists this row; the screen behind it is new.
///
/// Envelope only. See [BotFlow] for why the node graph stays in the console.
class BotFlowsScreen extends ConsumerWidget {
  const BotFlowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.bfTitle),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-bot-flows',
        onPressed: () => context.push(AppRoutes.botFlowNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<BotFlow>>(
        value: ref.watch(botFlowListProvider),
        onRetry: () => ref.invalidate(botFlowListProvider),
        builder: (List<BotFlow> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.account_tree_outlined,
              title: l10n.bfEmpty,
              message: l10n.bfEmptyHint,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(botFlowListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppDimens.fabClearance),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(indent: AppDimens.gutter),
              itemBuilder: (BuildContext context, int i) {
                final BotFlow f = items[i];
                // The step count is only mentioned when the payload gave one.
                // The list endpoint does not, and filling that gap with "No
                // steps" labelled every built-out flow as empty.
                final int? steps = f.stepCount;
                return AppListTile(
                  title: f.title,
                  subtitle: <String>[
                    triggerLabel(l10n, f.startTrigger),
                    if (f.keyword != null) f.keyword!,
                    if (steps != null) l10n.bfSteps(steps),
                  ].join(' · '),
                  subtitleMaxLines: 2,
                  leading: const IconTile(
                    icon: Icons.account_tree_outlined,
                    color: AppColor.brandDeep,
                  ),
                  // Running vs stopped is the one thing worth seeing without
                  // opening the row. A flow known to be running with zero steps
                  // triggers and then sends nothing, so that one case gets an
                  // amber pill instead of a green one — but only when the count
                  // is known, never inferred from its absence.
                  trailing: StatusPill(
                    label: f.active
                        ? (f.isKnownEmpty ? l10n.bfActiveEmpty : l10n.bfActive)
                        : l10n.bfInactive,
                    tone: f.active
                        ? (f.isKnownEmpty
                            ? StatusTone.warning
                            : StatusTone.success)
                        : StatusTone.neutral,
                  ),
                  onTap: () => context.push(AppRoutes.botFlow(f.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
