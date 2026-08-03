import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/report_repository.dart';
import '../../domain/reports.dart';
import '../widgets/report_bits.dart';

/// `GET /reports/conversational` — the overview behind the dashboard.
///
/// Two filters, both server-side: a date window and an optional agent. The
/// agent list arrives with the report itself, so changing either is one round
/// trip rather than two.
class ConversationalReportScreen extends ConsumerWidget {
  const ConversationalReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ConversationalQuery query = ref.watch(conversationalQueryProvider);

    String windowLabel(ReportWindow w) => switch (w) {
      ReportWindow.day => l10n.rpWindowDay,
      ReportWindow.week => l10n.rpWindowWeek,
      ReportWindow.month => l10n.rpWindowMonth,
      ReportWindow.year => l10n.rpWindowYear,
    };

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rpConversational),
      body: Column(
        children: <Widget>[
          // The window chips sit outside the async body on purpose: they stay
          // usable while the next window is loading, so a slow request cannot
          // strand the user on a filter they are trying to leave.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.stripGutter,
              vertical: 10,
            ),
            child: Row(
              children: <Widget>[
                for (final ReportWindow w in ReportWindow.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(windowLabel(w)),
                      selected: query.window == w,
                      onSelected: (_) => ref
                          .read(conversationalQueryProvider.notifier)
                          .state = query.copyWith(window: w),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncValueView<ConversationalReport>(
              value: ref.watch(conversationalReportProvider),
              onRetry: () => ref.invalidate(conversationalReportProvider),
              builder: (ConversationalReport r) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(conversationalReportProvider),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.stripGutter,
                    4,
                    AppDimens.stripGutter,
                    AppDimens.gutter,
                  ),
                  children: <Widget>[
                    if (r.agents.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String?>(
                          initialValue: query.agentUid,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.rpAgentFilter,
                            isDense: true,
                          ),
                          items: <DropdownMenuItem<String?>>[
                            // "All agents" must be a real selectable entry, not
                            // just the absence of one — without it there is no
                            // way back to the unfiltered report once an agent
                            // has been picked.
                            DropdownMenuItem<String?>(
                              child: Text(l10n.rpAllAgents),
                            ),
                            for (final ReportAgent a in r.agents)
                              DropdownMenuItem<String?>(
                                value: a.uid,
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (String? uid) => ref
                              .read(conversationalQueryProvider.notifier)
                              .state = query.copyWith(agentUid: uid),
                        ),
                      ),

                    // The four headline figures, each with its previous-period
                    // delta. Wait time flags lower-is-better so a fall is not
                    // painted as a regression.
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ReportStat(
                            value: groupDigits(r.received.value),
                            label: l10n.rpReceived,
                            metric: r.received,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ReportStat(
                            value: l10n.rpMinutes(
                              r.avgWaitMinutes.value.round(),
                            ),
                            label: l10n.rpAvgWait,
                            metric: r.avgWaitMinutes,
                            lowerIsBetter: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ReportStat(
                            value: groupDigits(r.opened.value),
                            label: l10n.rpOpened,
                            metric: r.opened,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ReportStat(
                            value: groupDigits(r.closed.value),
                            label: l10n.rpClosed,
                            metric: r.closed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ReportCard(
                      title: l10n.rpConversations,
                      child: Column(
                        children: <Widget>[
                          _Line(
                            label: l10n.rpTotalConversations,
                            value: groupDigits(r.totalConversations),
                          ),
                          _Line(
                            label: l10n.rpMissed,
                            value: groupDigits(r.missed),
                            emphasis: r.missed > 0,
                          ),
                          _Line(
                            label: l10n.rpTransfers,
                            value: groupDigits(r.chatTransfers),
                          ),
                          _Line(
                            label: l10n.rpChatDuration,
                            value: humanizeSeconds(r.chatDurationSeconds),
                          ),
                          _Line(
                            label: l10n.rpNewCustomers,
                            value: groupDigits(r.newCustomers),
                          ),
                          _Line(
                            label: l10n.rpReturningCustomers,
                            value: groupDigits(r.returningCustomers),
                            last: true,
                          ),
                        ],
                      ),
                    ),

                    // Per-agent breakdowns. Each is hidden when empty rather
                    // than drawn as an empty card — an agent list with no rows
                    // says nothing and costs a screenful.
                    if (!r.conversationsPerAgent.isEmpty)
                      ReportCard(
                        title: l10n.rpConversationsPerAgent,
                        child: AgentBars(
                          series: r.conversationsPerAgent,
                          format: groupDigits,
                        ),
                      ),
                    if (!r.messagesPerAgent.isEmpty)
                      ReportCard(
                        title: l10n.rpMessagesPerAgent,
                        child: AgentBars(
                          series: r.messagesPerAgent,
                          format: groupDigits,
                          color: AppColor.info,
                        ),
                      ),
                    if (!r.firstResponsePerAgent.isEmpty)
                      ReportCard(
                        title: l10n.rpFirstResponsePerAgent,
                        child: AgentBars(
                          series: r.firstResponsePerAgent,
                          format: (num v) => l10n.rpMinutes(v.round()),
                          color: AppColor.warning,
                        ),
                      ),
                    if (!r.responseTimePerAgent.isEmpty)
                      ReportCard(
                        title: l10n.rpResponseTimePerAgent,
                        child: AgentBars(
                          series: r.responseTimePerAgent,
                          format: (num v) => l10n.rpMinutes(v.round()),
                          color: AppColor.warning,
                        ),
                      ),

                    if (r.received.value == 0 &&
                        r.totalConversations == 0 &&
                        r.conversationsPerAgent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.insights_outlined,
                          title: l10n.rpNoData,
                          message: l10n.rpNoDataHint,
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

/// One label/value line inside a [ReportCard].
class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.last = false,
  });

  final String label;
  final String value;

  /// Colours the number when it represents something to act on — today only
  /// missed conversations, and only when there are any.
  final bool emphasis;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 9),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              color: emphasis ? AppColor.danger : null,
            ),
          ),
        ],
      ),
    );
  }
}
