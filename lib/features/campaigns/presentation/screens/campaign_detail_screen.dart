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
      // Static, per the frame. Bound to the campaign it left the header
      // blank while loading and on error, and repeated the title block below.
      appBar: AppHeader.back(title: l10n.cpTitle),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              c.title,
                              style: Theme.of(context).textTheme.displayLarge,
                            ),
                            const SizedBox(height: 8),
                            // The frame's meta line: status, schedule and
                            // audience on one row under the name. This was
                            // scattered into a "Setup" list further down, so the
                            // three facts that identify a campaign were not
                            // visible with its name.
                            Row(
                              children: <Widget>[
                                StatusPill(
                                  label: badge.label,
                                  tone: badge.tone,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    <String>[
                                      if (c.scheduledAt != null)
                                        DateFormat.yMMMd(locale)
                                            .format(c.scheduledAt!)
                                      else
                                        l10n.campNotScheduled,
                                      l10n.campContacts(c.totalContacts),
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SectionLabel(l10n.cpPerformance),
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
                                  value: _pct(c.delivered, c.sent),
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
                                  value: _pct(c.read, c.sent),
                                  label: l10n.cpRead,
                                  icon: Icons.mark_email_read_outlined,
                                  iconColor: AppColor.info,
                                ),
                                StatCard(
                                  value: _pct(c.failed, c.sent),
                                  label: l10n.cpFailed,
                                  icon: Icons.error_outline,
                                  iconColor: AppColor.danger,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // The frame's DELIVERY BREAKDOWN. Same three rates as the
                      // cards above, but as bars — the cards give the number,
                      // the bars give the shape at a glance, which is what tells
                      // you whether a send went well.
                      if (c.sent > 0) ...<Widget>[
                        SectionLabel(l10n.cpBreakdown),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.gutter,
                          ),
                          child: Column(
                            children: <Widget>[
                              _BreakdownBar(
                                label: l10n.cpDelivered,
                                value: c.delivered,
                                total: c.sent,
                                tint: AppColor.success,
                              ),
                              _BreakdownBar(
                                label: l10n.cpRead,
                                value: c.read,
                                total: c.sent,
                                tint: AppColor.info,
                              ),
                              _BreakdownBar(
                                label: l10n.cpFailed,
                                value: c.failed,
                                total: c.sent,
                                tint: AppColor.danger,
                              ),
                            ],
                          ),
                        ),
                      ],
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
                // No bottom CTA on purpose. This slot held a "Send campaign"
                // button whose onPressed was `() {}` — it looked live on a
                // draft and did nothing. There is no send endpoint to wire it
                // to (campaign_repository exposes only list/byUid/meta/create),
                // and the frame's own CTA here is "View full report", which has
                // no endpoint either. A control that cannot work is worse than
                // no control, especially one a user would read as "broadcast to
                // my customers". The `cpSend` string is kept for when the API
                // gains the endpoint.
              ],
            ),
          );
        },
      ),
    );
  }
}


/// A rate of [total] as a whole-number percentage, or an em dash when there is
/// nothing to divide by — "0%" would claim a measurement that was never taken.
String _pct(int value, int total) =>
    total <= 0 ? '—' : '${(value * 100 / total).round()}%';

/// One labelled progress row in the delivery breakdown.
class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.label,
    required this.value,
    required this.total,
    required this.tint,
  });

  final String label;
  final int value;
  final int total;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final double fraction = total <= 0 ? 0 : (value / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                _pct(value, total),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppColor.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ],
      ),
    );
  }
}
