import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/weekly_bar_chart.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_summary.dart';

/// Dashboard — Figma 38:1032.
///
/// The frame's seven-day chart and "My queue" list are here as of the 30 Jul
/// API pass, which added `series7d` and `agentQueue`. Both render only when the
/// API actually sends them: an all-zero chart would read as a quiet week rather
/// than as missing data.
///
/// Resolved today and CSAT are still absent, deliberately. Nothing records when
/// a conversation was resolved and CSAT is not collected, so either card would
/// be permanently zero. The unassigned count keeps the warning tone because it
/// is the one number an agent should act on.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// The greeting was a single hardcoded "Good morning", so it was wrong for
  /// most of the working day. Boundaries follow the usual English reading:
  /// afternoon from noon, evening from 17:00.
  static String _greetingFor(AppLocalizations l10n) {
    final int hour = DateTime.now().hour;
    if (hour < 12) return l10n.dashboardGreetingMorning;
    if (hour < 17) return l10n.dashboardGreetingAfternoon;
    return l10n.dashboardGreetingEvening;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<DashboardSummary> summary =
        ref.watch(dashboardSummaryProvider);
    final String agentName =
        ref.watch(authControllerProvider).session?.user.name ?? '';

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GreetingHeader(greeting: _greetingFor(l10n), name: agentName),
          Expanded(
            child: AsyncValueView<DashboardSummary>(
              value: summary,
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
              builder: (DashboardSummary d) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: <Widget>[
                    SectionLabel(l10n.dashboardConversations),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gutter,
                      ),
                      child: Column(
                        children: <Widget>[
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${d.openConversations}',
                                label: l10n.dashboardOpen,
                                icon: Icons.forum_outlined,
                              ),
                              StatCard(
                                value: '${d.unassigned}',
                                label: l10n.dashboardUnassigned,
                                icon: Icons.person_off_outlined,
                                // Semantic, not decorative: work nobody owns.
                                iconColor: AppColor.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${d.assigned}',
                                label: l10n.dashboardAssigned,
                                icon: Icons.assignment_ind_outlined,
                                iconColor: AppColor.success,
                              ),
                              StatCard(
                                value: '${d.queued}',
                                label: l10n.dashboardQueued,
                                icon: Icons.schedule_send_outlined,
                                iconColor: AppColor.info,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SectionLabel(l10n.dashboardToday),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gutter,
                      ),
                      child: Column(
                        children: <Widget>[
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${d.inboundToday}',
                                label: l10n.dashboardInbound,
                                icon: Icons.call_received,
                                iconColor: AppColor.info,
                              ),
                              StatCard(
                                value: '${d.outboundToday}',
                                label: l10n.dashboardOutbound,
                                icon: Icons.call_made,
                                iconColor: AppColor.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${d.newContactsToday}',
                                label: l10n.dashboardNewContacts,
                                icon: Icons.person_add_alt,
                              ),
                              StatCard(
                                value: '${d.totalContacts}',
                                label: l10n.dashboardTotalContacts,
                                icon: Icons.people_outline,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Avg response, full width: it is the one performance
                    // number here and there is no natural partner to pair it
                    // with, so a single wide card reads as a summary rather
                    // than as an orphan in a 2-up grid.
                    if (d.avgFirstResponseSeconds > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: StatCardRow(
                          cards: <StatCard>[
                            StatCard(
                              value: DurationFormat.coarse(
                                d.avgFirstResponseSeconds,
                              ),
                              label: l10n.agAvgResponse,
                              icon: Icons.timer_outlined,
                              iconColor: AppColor.info,
                            ),
                          ],
                        ),
                      ),

                    // The frame's weekly chart. Drawn only when the API sent a
                    // series — an all-zero chart reads as "a quiet week" rather
                    // than "no data", which is a different and wrong claim.
                    if (d.series7d.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: ChartCard(
                          title: l10n.dashboardWeek,
                          // Seven flat bars at zero are accurate but
                          // indistinguishable from a chart that failed to
                          // draw. When the whole week is zero, say so.
                          child: d.series7d.every(
                                  (DaySeriesPoint p) => p.count == 0)
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 28,
                                  ),
                                  child: Text(
                                    l10n.dashboardWeekQuiet,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                )
                              : WeeklyBarChart(
                            data: <BarDatum>[
                              for (final DaySeriesPoint p in d.series7d)
                                BarDatum(
                                  label: DateFormat.E(
                                    Localizations.localeOf(context)
                                        .toLanguageTag(),
                                  ).format(p.date).characters.first.toString(),
                                  value: p.count,
                                ),
                            ],
                            semanticsLabel: l10n.dashboardWeek,
                          ),
                        ),
                      ),
                    ],

                    // "My queue · See all", per the frame.
                    if (d.agentQueue.isNotEmpty) ...<Widget>[
                      SectionHeader(
                        title: l10n.dashboardMyQueue,
                        actionLabel: l10n.actionSeeAll,
                        onAction: () => context.go(AppRoutes.chats),
                      ),
                      for (final QueueEntry q in d.agentQueue)
                        AppListTile(
                          title: q.name,
                          subtitle: q.lastMessage,
                          leading: InitialsAvatar(name: q.name),
                          showChevron: false,
                          trailing: q.unreadCount > 0
                              ? StatusPill(
                                  label: '${q.unreadCount}',
                                  tone: StatusTone.success,
                                  showDot: false,
                                )
                              : null,
                          onTap: () =>
                              context.push(AppRoutes.chat(q.contactUid)),
                        ),
                    ],

                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gutter,
                      ),
                      child: FilledButton.icon(
                        onPressed: () => context.go(AppRoutes.chats),
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: Text(l10n.dashboardOpenInbox),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The frame rounds the header's bottom edge into the page rather than
      // cutting it square.
      decoration: const BoxDecoration(
        color: AppColor.brand,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppDimens.gutter,
            end: AppDimens.gutter,
            top: 10,
            bottom: 18,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      greeting,
                      style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (name.isNotEmpty)
                InitialsAvatar.onBrand(name: name, size: 36),
            ],
          ),
        ),
      ),
    );
  }
}
