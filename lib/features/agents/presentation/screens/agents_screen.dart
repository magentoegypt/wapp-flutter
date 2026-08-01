import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/agent_repository.dart';

/// Free-text filter over the loaded agent list.
final agentSearchProvider = StateProvider<String>((Ref ref) => '');

/// What a teammate is doing right now.
///
/// The previous binary online/away could not express the frame's third state,
/// and "Online" was the wrong word for it. Available and busy are different
/// facts to a supervisor scanning this list: someone with six open chats is
/// online but is not who you route a seventh to, which is the distinction the
/// frame's amber pill draws.
enum AgentPresence { away, available, handling }

AgentPresence presenceOf(Agent a) {
  if (!a.online) return AgentPresence.away;
  return a.openConversations > 0
      ? AgentPresence.handling
      : AgentPresence.available;
}

/// Agents — Figma 283:89.
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Agent>> rows = ref.watch(agentListProvider);
    final String query = ref.watch(agentSearchProvider).trim().toLowerCase();

    return Scaffold(
      // The search variant with showBack, which the header documents for
      // exactly this pushed-route case. The plain back-nav header left the
      // roster unsearchable.
      appBar: AppHeader.search(
        title: l10n.moreAgents,
        searchHint: l10n.agSearchHint,
        showBack: true,
        trailing: const AgentAvatar(),
        onSearchChanged: (String q) =>
            ref.read(agentSearchProvider.notifier).state = q,
      ),
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

          final List<Agent> shown = query.isEmpty
              ? items
              : items
                  .where((Agent a) =>
                      a.name.toLowerCase().contains(query) ||
                      a.email.toLowerCase().contains(query) ||
                      a.role.toLowerCase().contains(query))
                  .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(agentListProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                // Totals cover the whole roster, not the filtered view — they
                // are team figures, and having them move as you type would make
                // them meaningless.
                Padding(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  child: _Summary(items: items, l10n: l10n),
                ),
                SectionLabel(l10n.agTeamCount(items.length)),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppDimens.gutter),
                    child: Text(
                      l10n.searchNoMatches,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (final Agent a in shown) _AgentRow(agent: a, l10n: l10n),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items, required this.l10n});

  final List<Agent> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Agents · Online · Open chats, which is what the frame (283:89) counts —
    // and, not coincidentally, the only three numbers this payload supports.
    //
    // The cards used to be Open / Resolved today / Avg. reply, summed from
    // `resolvedToday` and `avgResponseSecs`. Neither key exists: an agent is
    // `{uid, name, email, active, role, team, activeChats}`. Two of the three
    // cards were therefore permanently zero — the exact thing the dashboard
    // refuses to ship a card for, for the same reason.
    final int online = items.where((Agent a) => a.online).length;
    final int open =
        items.fold<int>(0, (int s, Agent a) => s + a.openConversations);

    return StatCardRow(
      cards: <StatCard>[
        StatCard(
          value: '${items.length}',
          label: l10n.agAgents,
          icon: Icons.groups_outlined,
        ),
        StatCard(
          value: '$online',
          label: l10n.agOnline,
          icon: Icons.circle,
          iconColor: AppColor.success,
        ),
        StatCard(
          value: '$open',
          label: l10n.agOpenChats,
          icon: Icons.forum_outlined,
          iconColor: AppColor.info,
        ),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.l10n});

  final Agent agent;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ({String label, StatusTone tone}) badge = switch (presenceOf(agent)) {
      AgentPresence.available =>
        (label: l10n.agAvailable, tone: StatusTone.success),
      AgentPresence.handling => (
          label: l10n.agHandling(agent.openConversations),
          tone: StatusTone.warning,
        ),
      AgentPresence.away => (label: l10n.agAway, tone: StatusTone.neutral),
    };

    // "role · N active", per the frame. The email belongs on the detail screen:
    // in a roster the role is what you scan for, and an address is long enough
    // to crowd the pill off the row.
    final String subtitle = agent.openConversations > 0
        ? '${agent.role} · ${l10n.agActiveCount(agent.openConversations)}'
        : agent.role;

    return AppListTile(
      title: agent.name,
      subtitle: subtitle,
      leading: InitialsAvatar(name: agent.name),
      showChevron: false,
      trailing: StatusPill(label: badge.label, tone: badge.tone),
      onTap: () => context.push(AppRoutes.agent(agent.uid)),
    );
  }
}
