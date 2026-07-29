import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_summary.dart';

/// Dashboard — Figma 38:1032, adapted to the metrics the API exposes.
///
/// The frame specified Resolved today / Avg. response / CSAT plus a seven-day
/// chart and an agent queue. `GET /dashboard` provides none of those, so the
/// screen is built from the eight metrics that do exist, keeping the frame's
/// greeting header and 2×2 stat-card idiom. The unassigned count is given the
/// warning tone because it is the one number an agent should act on.
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
