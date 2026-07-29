import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/util/duration_format.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../data/agent_repository.dart';
import '../../../../l10n/app_localizations.dart';

/// Agent detail — Figma 291:147. Bottom-pinned CTA.
class AgentDetailScreen extends ConsumerWidget {
  const AgentDetailScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Agent> agent = ref.watch(agentDetailProvider(uid));

    return Scaffold(
      appBar: AppHeader.back(title: agent.valueOrNull?.name ?? ''),
      body: AsyncValueView<Agent>(
        value: agent,
        onRetry: () => ref.invalidate(agentDetailProvider(uid)),
        builder: (Agent a) => SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  children: <Widget>[
                    const SizedBox(height: 20),
                    Center(
                      child: InitialsAvatar(
                        name: a.name,
                        size: AppDimens.avatarHero,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        a.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        a.email,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: StatusPill(
                        label: a.online ? l10n.agOnline : l10n.agAway,
                        tone: a.online ? StatusTone.success : StatusTone.neutral,
                      ),
                    ),

                    SectionLabel(l10n.agPerformance),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gutter,
                      ),
                      child: Column(
                        children: <Widget>[
                          StatCardRow(
                            cards: <StatCard>[
                              StatCard(
                                value: '${a.openConversations}',
                                label: l10n.agOpen,
                                icon: Icons.forum_outlined,
                              ),
                              StatCard(
                                value: '${a.resolvedToday}',
                                label: l10n.agResolvedToday,
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
                                  a.avgResponseSeconds,
                                ),
                                label: l10n.agAvgResponse,
                                icon: Icons.timer_outlined,
                                iconColor: AppColor.info,
                              ),
                              StatCard(
                                // No reviews yet reads as "—", not 0%.
                                value: a.csatPercent == null
                                    ? '—'
                                    : '${a.csatPercent}%',
                                label: l10n.agCsat,
                                icon: Icons.star_outline,
                                iconColor: AppColor.warning,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (a.teams.isNotEmpty) ...<Widget>[
                      SectionLabel(l10n.agTeams),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final String t in a.teams)
                              StatusPill(
                                label: t,
                                tone: StatusTone.info,
                                showDot: false,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppDimens.gutter),
                child: FilledButton(
                  onPressed: () {},
                  child: Text(l10n.agAssign),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
