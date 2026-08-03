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
import 'window_chips.dart';

/// `GET /reports/pause-reasons` — time each agent spent away or busy.
///
/// ⚠ These rows carry **no identifier** — not a uid, not an id. The backend
/// aggregates by user but serialises only the display name, so nothing here can
/// link through to an agent's profile. That is inherited from the console
/// report; it is a limitation to state, not a gap to paper over with a guess at
/// matching names.
class PauseReasonsScreen extends ConsumerWidget {
  const PauseReasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rpPauseReasons),
      body: Column(
        children: <Widget>[
          WindowChips(provider: pauseWindowProvider),
          Expanded(
            child: AsyncValueView<PauseReasonReport>(
              value: ref.watch(pauseReasonsProvider),
              onRetry: () => ref.invalidate(pauseReasonsProvider),
              builder: (PauseReasonReport r) {
                if (r.isEmpty) {
                  return EmptyState(
                    icon: Icons.pause_circle_outline,
                    title: l10n.rpNoPauses,
                    message: l10n.rpNoPausesHint,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(pauseReasonsProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.stripGutter,
                      4,
                      AppDimens.stripGutter,
                      AppDimens.gutter,
                    ),
                    children: <Widget>[
                      ReportCard(
                        title: l10n.rpTotals,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _Big(
                                    // The server's own rendering, not a local
                                    // reformat — so the app and the console can
                                    // never disagree by a rounding rule.
                                    value: r.grandHuman,
                                    label: l10n.rpTotalPaused,
                                  ),
                                ),
                                Expanded(
                                  child: _Big(
                                    value: '${r.grandSessions}',
                                    label: l10n.rpSessions,
                                  ),
                                ),
                              ],
                            ),
                            if (r.reasonTotals.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 14),
                              AgentBars(
                                series: AgentSeries(<AgentSeriesRow>[
                                  for (final PauseReasonTotal t
                                      in r.reasonTotals)
                                    AgentSeriesRow(
                                      name: t.label,
                                      value: t.seconds,
                                    ),
                                ]),
                                format: (num v) => humanizeSeconds(v.round()),
                                color: AppColor.warning,
                              ),
                            ],
                          ],
                        ),
                      ),
                      for (final PauseAgent a in r.agents)
                        ReportCard(
                          title: a.name,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                l10n.rpAgentPauseSummary(
                                  a.totalHuman,
                                  a.sessions,
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 10),
                              for (final PauseRow row in a.rows)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          row.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        l10n.rpPauseRowValue(
                                          row.totalHuman,
                                          row.sessions,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.displayLarge?.copyWith(fontSize: 20, height: 1.1),
        ),
        Text(label, style: text.labelMedium),
      ],
    );
  }
}
