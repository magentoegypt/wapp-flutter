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
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/campaign_repository.dart';

/// Maps campaign lifecycle onto the semantic tones. Kept next to the screens
/// that render it so detail and list can never disagree.
({String label, StatusTone tone}) campaignBadge(
  AppLocalizations l10n,
  CampaignExecution e,
) =>
    switch (e) {
      CampaignExecution.upcoming =>
        (label: l10n.campUpcoming, tone: StatusTone.info),
      CampaignExecution.awaiting =>
        (label: l10n.campAwaiting, tone: StatusTone.info),
      CampaignExecution.processing =>
        (label: l10n.campProcessing, tone: StatusTone.warning),
      CampaignExecution.executed =>
        (label: l10n.campCompleted, tone: StatusTone.success),
      CampaignExecution.paused =>
        (label: l10n.campPaused, tone: StatusTone.neutral),
      CampaignExecution.na => (label: l10n.campNa, tone: StatusTone.neutral),
    };

/// Free-text filter over the loaded campaign list.
final campaignSearchProvider = StateProvider<String>((Ref ref) => '');

/// Which half of the list is showing. Archive is terminal states only.
final campaignArchivedProvider = StateProvider<bool>((Ref ref) => false);

/// Campaigns — Figma 283:2.
class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Campaign>> rows = ref.watch(campaignListProvider);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final String query = ref.watch(campaignSearchProvider).trim().toLowerCase();
    final bool archived = ref.watch(campaignArchivedProvider);

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.moreCampaigns,
        searchHint: l10n.campSearchHint,
        showBack: true,
        trailing: const AgentAvatar(),
        onSearchChanged: (String q) =>
            ref.read(campaignSearchProvider.notifier).state = q,
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct hero tag. Inbox and Contacts are both kept alive by
        // StatefulShellRoute.indexedStack, so two FABs sharing Flutter's
        // default tag collide and throw on every tab switch.
        heroTag: 'fab-campaigns',
        onPressed: () => context.push(AppRoutes.campaignNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<Campaign>>(
        value: rows,
        onRetry: () => ref.invalidate(campaignListProvider),
        builder: (List<Campaign> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.campaign_outlined,
              title: l10n.campEmptyTitle,
              message: l10n.campEmptyMessage,
            );
          }
          final List<Campaign> shown = items
              .where((Campaign c) => c.isArchived == archived)
              .where((Campaign c) =>
                  query.isEmpty || c.title.toLowerCase().contains(query))
              .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(campaignListProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: <Widget>[
                // Totals across every campaign, not the visible half — these
                // are lifetime delivery figures, and recomputing them per tab
                // would make the numbers jump for no reason the user can see.
                Padding(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  child: _DeliverySummary(items: items, l10n: l10n),
                ),
                FilterChipBar(
                  options: <FilterOption>[
                    FilterOption(
                      id: 'active',
                      label: l10n.campActive,
                      count: items
                          .where((Campaign c) => !c.isArchived)
                          .length,
                    ),
                    FilterOption(
                      id: 'archive',
                      label: l10n.campArchive,
                      count: items
                          .where((Campaign c) => c.isArchived)
                          .length,
                    ),
                  ],
                  selectedId: archived ? 'archive' : 'active',
                  onSelected: (String id) => ref
                      .read(campaignArchivedProvider.notifier)
                      .state = id == 'archive',
                ),
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
                  for (final Campaign c in shown)
                    AppListTile(
                      title: c.title,
                      // State-dependent, per the frame: once a send has begun
                      // the useful fact is how it is going, not who it was
                      // aimed at.
                      subtitle: _subtitle(l10n, locale, c),
                      // No leading tile and no chevron — the frame's row is the
                      // title, the delivery line and the status pill.
                      showChevron: false,
                      trailing: StatusPill(
                        label: campaignBadge(l10n, c.execution).label,
                        tone: campaignBadge(l10n, c.execution).tone,
                      ),
                      onTap: () => context.push(AppRoutes.campaign(c.uid)),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Row subtitle. Before a send starts the audience size and schedule are what
/// matter; once it has, progress is.
String _subtitle(AppLocalizations l10n, String locale, Campaign c) {
  if (c.sent > 0) {
    final int pct = c.sent == 0 ? 0 : (c.delivered * 100 / c.sent).round();
    return '${l10n.campSentCount(c.sent)} · ${l10n.campDeliveredPct(pct)}';
  }
  if (c.scheduledAt != null) {
    return '${l10n.campContacts(c.totalContacts)} · '
        '${DateFormat.yMMMd(locale).add_jm().format(c.scheduledAt!)}';
  }
  return '${l10n.campContacts(c.totalContacts)} · ${l10n.campNotScheduled}';
}

/// Lifetime delivery totals across all campaigns.
class _DeliverySummary extends StatelessWidget {
  const _DeliverySummary({required this.items, required this.l10n});

  final List<Campaign> items;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    int sum(int Function(Campaign) f) =>
        items.fold<int>(0, (int s, Campaign c) => s + f(c));

    return StatCardRow(
      cards: <StatCard>[
        StatCard(
          value: '${sum((Campaign c) => c.sent)}',
          label: l10n.cpSent,
          icon: Icons.send_outlined,
          iconColor: AppColor.warning,
        ),
        StatCard(
          value: '${sum((Campaign c) => c.delivered)}',
          label: l10n.cpDelivered,
          icon: Icons.done_all,
          iconColor: AppColor.success,
        ),
        StatCard(
          value: '${sum((Campaign c) => c.read)}',
          label: l10n.cpRead,
          icon: Icons.visibility_outlined,
          iconColor: AppColor.info,
        ),
      ],
    );
  }
}
