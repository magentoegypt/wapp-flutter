import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../data/agent_repository.dart';
import 'agents_screen.dart' show AgentPresence, presenceOf;
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
      // Static, per the frame — the name is the hero immediately below, and
      // binding the bar to it left the header blank while loading.
      appBar: AppHeader.back(title: l10n.agTitle),
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
                      // The frame's hero avatar is a filled deep-green disc
                      // with light initials, not one of the hash-tinted list
                      // pastels.
                      child: InitialsAvatar.onBrand(
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
                      // "role · team", per the frame. The email is in the
                      // ACCOUNT rows further down; up here the role and team are
                      // what identify a teammate.
                      child: Text(
                        <String>[
                          a.role,
                          if (a.teams.isNotEmpty) a.teams.join(', '),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      // Same three-way presence as the roster, via the shared
                      // presenceOf — a binary online/away could not express the
                      // frame's amber "handling N chats".
                      child: StatusPill(
                        label: switch (presenceOf(a)) {
                          AgentPresence.available => l10n.agAvailable,
                          AgentPresence.handling =>
                            l10n.agHandling(a.openConversations),
                          AgentPresence.away => l10n.agAway,
                        },
                        tone: switch (presenceOf(a)) {
                          AgentPresence.available => StatusTone.success,
                          AgentPresence.handling => StatusTone.warning,
                          AgentPresence.away => StatusTone.neutral,
                        },
                      ),
                    ),

                    // Two cards, not four. The frame's Performance block wants
                    // Open · Resolved today · Avg. response · CSAT; the agent
                    // payload carries only `openConversations` and
                    // `assignedTotal`. The other three came from keys that do
                    // not exist and rendered 0, 0s and — on every agent, for
                    // every workspace, permanently.
                    SectionLabel(l10n.agWorkload),
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
                                label: l10n.agActiveChats,
                                icon: Icons.forum_outlined,
                              ),
                              StatCard(
                                value: '${a.assignedTotal}',
                                label: l10n.agAssignedTotal,
                                icon: Icons.assignment_ind_outlined,
                                iconColor: AppColor.info,
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
              // No bottom CTA on purpose — see campaign_detail_screen for the
              // same call. This was an "Assign a conversation" button with an
              // empty onPressed; agent_repository has no assign method and the
              // API exposes no such endpoint, so it could never do anything.
              // `agAssign` is kept for when it can.
            ],
          ),
        ),
      ),
    );
  }
}
