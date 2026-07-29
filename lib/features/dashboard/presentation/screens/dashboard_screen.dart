import 'package:flutter/material.dart';
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
import '../../../../core/widgets/weekly_bar_chart.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_summary.dart';

/// Dashboard — Figma 38:1032.
///
/// Greeting header, a 2×2 stat grid, the weekly conversation chart, then the
/// agent's own queue.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

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
          _GreetingHeader(greeting: l10n.dashboardGreeting, name: agentName),
          Expanded(
            child: AsyncValueView<DashboardSummary>(
              value: summary,
              onRetry: () => ref.invalidate(dashboardSummaryProvider),
              builder: (DashboardSummary data) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: <Widget>[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gutter,
                      ),
                      child: Column(
                        children: <Widget>[
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${data.open}',
                                label: l10n.dashboardOpen,
                                icon: Icons.forum_outlined,
                              ),
                              StatCard(
                                value: '${data.resolvedToday}',
                                label: l10n.dashboardResolvedToday,
                                icon: Icons.check_circle_outline,
                                iconColor: AppColor.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: DurationFormat.compact(
                                  data.avgResponseSeconds,
                                ),
                                label: l10n.dashboardAvgResponse,
                                icon: Icons.timer_outlined,
                                iconColor: AppColor.info,
                              ),
                              StatCard(
                                value: '${data.csatPercent}%',
                                label: l10n.dashboardCsat,
                                icon: Icons.star_outline,
                                iconColor: AppColor.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          ChartCard(
                            title: l10n.dashboardWeeklyChart,
                            child: WeeklyBarChart(
                              data: _toBars(context, data.week),
                              semanticsLabel: l10n.dashboardWeeklyChart,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionHeader(
                      title: l10n.dashboardMyQueue,
                      actionLabel: data.queue.isEmpty ? null : l10n.actionSeeAll,
                      onAction: () => context.go(AppRoutes.chats),
                    ),
                    if (data.queue.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                          vertical: 8,
                        ),
                        child: Text(
                          l10n.dashboardQueueEmpty,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else
                      for (final QueueItem item in data.queue)
                        AppListTile(
                          title: item.name,
                          leading: InitialsAvatar(name: item.name),
                          trailing: Text(
                            DurationFormat.coarse(item.waitingSeconds),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          onTap: () =>
                              context.push(AppRoutes.chat(item.contactUid)),
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

  /// Maps weekday numbers to localized single-letter labels via the ambient
  /// MaterialLocalizations, so Arabic gets Arabic initials for free.
  List<BarDatum> _toBars(BuildContext context, List<DayCount> week) {
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    return week
        .map(
          (DayCount d) => BarDatum(
            // narrowWeekdays is Sunday-first; DateTime.weekday is Monday-first.
            label: m.narrowWeekdays[d.weekday % 7],
            value: d.count,
          ),
        )
        .toList();
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColor.brand,
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
              if (name.isNotEmpty) InitialsAvatar(name: name, size: 36),
            ],
          ),
        ),
      ),
    );
  }
}
