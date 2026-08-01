import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/team_repository.dart';

/// Teams — no frame; the endpoints arrived after the handoff was drawn.
///
/// Follows `AgentsScreen`, which is the closest thing the app already has.
class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.tmTitle),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-teams',
        onPressed: () => context.push(AppRoutes.teamNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<WorkTeam>>(
        value: ref.watch(teamListProvider),
        onRetry: () => ref.invalidate(teamListProvider),
        builder: (List<WorkTeam> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: l10n.tmEmpty,
              message: l10n.tmEmptyHint,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(teamListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppDimens.fabClearance),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(indent: AppDimens.gutter),
              itemBuilder: (BuildContext context, int i) {
                final WorkTeam t = items[i];
                return AppListTile(
                  title: t.title,
                  subtitle: l10n.tmMembers(t.displayCount),
                  leading: const IconTile(
                    icon: Icons.groups_outlined,
                    color: AppColor.success,
                  ),
                  onTap: () => context.push(AppRoutes.team(t.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
