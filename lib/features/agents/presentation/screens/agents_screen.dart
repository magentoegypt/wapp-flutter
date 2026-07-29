import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/agent_repository.dart';

/// Agents — Figma 283:89.
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Agent>> rows = ref.watch(agentListProvider);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.moreAgents),
      body: AsyncValueView<List<Agent>>(
        value: rows,
        onRetry: () => ref.invalidate(agentListProvider),
        builder: (List<Agent> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: l10n.agEmptyTitle,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(agentListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 76),
              itemBuilder: (BuildContext context, int i) {
                final Agent a = items[i];
                return AppListTile(
                  title: a.name,
                  subtitle: a.teams.isEmpty ? a.email : a.teams.join(' · '),
                  leading: InitialsAvatar(name: a.name),
                  trailing: StatusPill(
                    label: a.online ? l10n.agOnline : l10n.agAway,
                    tone: a.online ? StatusTone.success : StatusTone.neutral,
                  ),
                  onTap: () => context.push(AppRoutes.agent(a.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
