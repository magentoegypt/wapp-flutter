import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/campaign_repository.dart';

/// Maps campaign lifecycle onto the semantic tones. Kept next to the screens
/// that render it so detail and list can never disagree.
({String label, StatusTone tone}) campaignBadge(
  AppLocalizations l10n,
  CampaignStatus s,
) =>
    switch (s) {
      CampaignStatus.draft => (label: l10n.campDraft, tone: StatusTone.neutral),
      CampaignStatus.scheduled => (label: l10n.campScheduled, tone: StatusTone.info),
      CampaignStatus.running => (label: l10n.campRunning, tone: StatusTone.warning),
      CampaignStatus.completed => (label: l10n.campCompleted, tone: StatusTone.success),
      CampaignStatus.failed => (label: l10n.campFailed, tone: StatusTone.danger),
    };

/// Campaigns — Figma 283:2.
class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Campaign>> rows = ref.watch(campaignListProvider);
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppHeader.back(title: l10n.moreCampaigns),
      floatingActionButton: FloatingActionButton(
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
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(campaignListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 76),
              itemBuilder: (BuildContext context, int i) {
                final Campaign c = items[i];
                final badge = campaignBadge(l10n, c.status);
                return AppListTile(
                  title: c.title,
                  subtitle: c.scheduledAt == null
                      ? l10n.campContacts(c.totalContacts)
                      : '${l10n.campContacts(c.totalContacts)} · ${DateFormat.yMMMd(locale).format(c.scheduledAt!)}',
                  leading: const IconTile(
                    icon: Icons.campaign_outlined,
                    color: AppColor.warning,
                  ),
                  trailing: StatusPill(label: badge.label, tone: badge.tone),
                  onTap: () => context.push(AppRoutes.campaign(c.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
