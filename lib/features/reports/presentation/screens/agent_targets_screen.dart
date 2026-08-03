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

/// `GET /reports/agent-targets` — targets vs actuals for one calendar month.
///
/// The only month-scoped report here, matching the console. Targets are set in
/// the web console; this screen reads them.
class AgentTargetsScreen extends ConsumerWidget {
  const AgentTargetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TargetMonth month = ref.watch(targetMonthProvider);
    final TargetMonth now = TargetMonth.current();
    // Stepping past the current month asks the server for a period that cannot
    // have data yet, so forward is stopped at today rather than returning an
    // empty report the user has to interpret.
    final bool canGoForward = month.year < now.year ||
        (month.year == now.year && month.month < now.month);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rpTargets),
      body: AsyncValueView<AgentTargetsReport>(
        value: ref.watch(agentTargetsProvider),
        onRetry: () => ref.invalidate(agentTargetsProvider),
        builder: (AgentTargetsReport r) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.stripGutter,
                vertical: 6,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    // matchTextDirection is not enough on a paging control:
                    // in RTL the arrow must also *mean* "earlier", which it
                    // does because the handler, not the glyph, defines it.
                    onPressed: () => ref.read(targetMonthProvider.notifier)
                        .state = month.shift(-1),
                  ),
                  Expanded(
                    child: Text(
                      // The server's own label, so the header cannot disagree
                      // with the data beneath it.
                      r.monthLabel.isNotEmpty
                          ? r.monthLabel
                          : '${r.year}-${r.month}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: canGoForward
                        ? () => ref.read(targetMonthProvider.notifier).state =
                            month.shift(1)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: r.isEmpty
                  ? EmptyState(
                      icon: Icons.flag_outlined,
                      title: l10n.rpNoTargets,
                      message: l10n.rpNoTargetsHint,
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(agentTargetsProvider),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.stripGutter,
                          4,
                          AppDimens.stripGutter,
                          AppDimens.gutter,
                        ),
                        children: <Widget>[
                          for (final AgentTargetRow row in r.rows)
                            ReportCard(
                              title: row.name,
                              child: row.hasNoTargets
                                  ? Text(
                                      l10n.rpNoTargetSet,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        _Measure(
                                          label: l10n.rpLeads,
                                          target: row.targets.leads,
                                          actual: row.actuals.leads,
                                        ),
                                        _Measure(
                                          label: l10n.rpOrders,
                                          target: row.targets.orders,
                                          actual: row.actuals.orders,
                                        ),
                                        _Measure(
                                          label: l10n.rpRevenue,
                                          target: row.targets.revenue,
                                          actual: row.actuals.revenue,
                                        ),
                                        _Measure(
                                          label: l10n.rpResponseTime,
                                          target: row.targets.responseTime,
                                          actual: row.actuals.responseTime,
                                          lowerIsBetter: true,
                                          suffix: l10n.rpMinuteSuffix,
                                        ),
                                        _Measure(
                                          label: l10n.rpCsat,
                                          target: row.targets.csat,
                                          actual: row.actuals.csat,
                                        ),
                                      ],
                                    ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One measure's target, actual and attainment bar.
///
/// A measure with **no target set** is skipped entirely rather than drawn
/// against zero: "0 of 0" reads as a met target, which is the opposite of what
/// an unset one means. A measure with a target but no actual still draws, since
/// zero progress against a real target is a fact worth showing.
class _Measure extends StatelessWidget {
  const _Measure({
    required this.label,
    required this.target,
    required this.actual,
    this.lowerIsBetter = false,
    this.suffix = '',
  });

  final String label;
  final num? target;
  final num? actual;

  /// Response time is the one measure where progress runs downward — being
  /// under the target is success, so the attainment ratio inverts.
  final bool lowerIsBetter;

  final String suffix;

  @override
  Widget build(BuildContext context) {
    if (target == null) return const SizedBox.shrink();

    final TextTheme text = Theme.of(context).textTheme;
    final num t = target!;
    final num a = actual ?? 0;

    // Guard the divide: a zero target would otherwise produce NaN/Infinity and
    // paint a bar of undefined width.
    final double ratio = t == 0
        ? 0
        : lowerIsBetter
            ? (a == 0 ? 1 : (t / a)).clamp(0.0, 1.0).toDouble()
            : (a / t).clamp(0.0, 1.0).toDouble();

    final bool met = lowerIsBetter ? (a != 0 && a <= t) : a >= t;
    final Color colour = met ? AppColor.success : AppColor.warning;

    String fmt(num v) => v is int || v == v.roundToDouble()
        ? '${groupDigits(v)}$suffix'
        : '${v.toStringAsFixed(1)}$suffix';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: text.bodyMedium)),
              Text(
                '${fmt(a)} / ${fmt(t)}',
                style: text.labelMedium?.copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: <Widget>[
                Container(height: 6, color: AppColor.surfaceAlt),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(height: 6, color: colour),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
