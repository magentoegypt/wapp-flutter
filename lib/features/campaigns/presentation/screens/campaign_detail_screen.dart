import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../data/campaign_repository.dart';
import 'campaigns_screen.dart' show campaignBadge;
import '../../../../l10n/app_localizations.dart';

/// Campaign detail — Figma 291:4. Bottom-pinned CTA per the handoff.
class CampaignDetailScreen extends ConsumerWidget {
  const CampaignDetailScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Campaign> campaign = ref.watch(campaignDetailProvider(uid));
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppHeader.back(title: campaign.valueOrNull?.title ?? ''),
      body: AsyncValueView<Campaign>(
        value: campaign,
        onRetry: () => ref.invalidate(campaignDetailProvider(uid)),
        builder: (Campaign c) {
          final badge = campaignBadge(l10n, c.status);
          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(AppDimens.gutter),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                c.title,
                                style: Theme.of(context).textTheme.displayLarge,
                              ),
                            ),
                            StatusPill(label: badge.label, tone: badge.tone),
                          ],
                        ),
                      ),
                      SectionLabel(l10n.cpDelivery),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: Column(
                          children: <Widget>[
                            StatCardRow(
                              cards: <StatCard>[
                                StatCard(
                                  value: '${c.sent}',
                                  label: l10n.cpSent,
                                  icon: Icons.send_outlined,
                                ),
                                StatCard(
                                  value: '${c.delivered}',
                                  label: l10n.cpDelivered,
                                  icon: Icons.done_all,
                                  iconColor: AppColor.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            StatCardRow(
                              cards: <StatCard>[
                                StatCard(
                                  value: '${c.read}',
                                  label: l10n.cpRead,
                                  icon: Icons.mark_email_read_outlined,
                                  iconColor: AppColor.info,
                                ),
                                StatCard(
                                  value: '${c.failed}',
                                  label: l10n.cpFailed,
                                  icon: Icons.error_outline,
                                  iconColor: AppColor.danger,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SectionLabel(l10n.cpSetup),
                      AppListTile(
                        title: l10n.cpTemplate,
                        subtitle: c.templateName ?? '—',
                        leading: const IconTile(
                          icon: Icons.description_outlined,
                          color: AppColor.info,
                        ),
                        showChevron: false,
                      ),
                      AppListTile(
                        title: l10n.cpAudience,
                        subtitle: l10n.campContacts(c.totalContacts),
                        leading: const IconTile(
                          icon: Icons.people_outline,
                          color: AppColor.brandDeep,
                        ),
                        showChevron: false,
                      ),
                      if (c.scheduledAt != null)
                        AppListTile(
                          title: l10n.cpScheduled,
                          subtitle: DateFormat.yMMMd(locale)
                              .add_jm()
                              .format(c.scheduledAt!),
                          leading: const IconTile(
                            icon: Icons.schedule_outlined,
                            color: AppColor.warning,
                          ),
                          showChevron: false,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  child: FilledButton(
                    onPressed: c.status == CampaignStatus.draft ? () {} : null,
                    child: Text(l10n.cpSend),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
