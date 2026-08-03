import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../domain/reports.dart';

/// A signed percentage change, rendered beside the figure it qualifies.
///
/// Renders **nothing** when the change is absent or zero. A grey "0%" would
/// claim the metric held steady, which is a different statement from "nothing
/// was compared" — and the API omits the `…Old` key often enough that the
/// difference matters.
///
/// Direction is not assumed to be good or bad here; [lowerIsBetter] flips the
/// colour for wait and response times, where a rise is the bad outcome.
class DeltaPill extends StatelessWidget {
  const DeltaPill({required this.metric, this.lowerIsBetter = false, super.key});

  final ReportMetric metric;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    if (!metric.hasChange) return const SizedBox.shrink();

    final int pct = metric.changePercent!;
    final bool good = lowerIsBetter ? pct < 0 : pct > 0;
    final Color colour = good ? AppColor.success : AppColor.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            pct > 0 ? Icons.arrow_upward : Icons.arrow_downward,
            size: 11,
            color: colour,
          ),
          const SizedBox(width: 2),
          Text(
            '${pct.abs()}%',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colour, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

/// A metric tile: figure, label, and its change against the previous period.
class ReportStat extends StatelessWidget {
  const ReportStat({
    required this.value,
    required this.label,
    required this.metric,
    this.lowerIsBetter = false,
    super.key,
  });

  /// Pre-formatted — "1,204", "3m", "94%". Formatting is the caller's job so
  /// this stays locale-agnostic.
  final String value;
  final String label;
  final ReportMetric metric;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 82),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColor.surfaceDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.displayLarge?.copyWith(fontSize: 20, height: 1.1),
                ),
              ),
              const SizedBox(width: 6),
              DeltaPill(metric: metric, lowerIsBetter: lowerIsBetter),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// A horizontal bar per row, scaled to the largest value in the set.
///
/// Used for every per-agent breakdown. Bars are drawn with [FractionallySized]
/// widths rather than a chart library because these sets are short — one row
/// per agent — and a real chart would add a dependency to draw ten rectangles.
///
/// An all-zero set draws no bars at all rather than ten full-width ones: with a
/// zero maximum every fraction would be meaningless, and a full bar next to "0"
/// reads as a rendering fault.
class AgentBars extends StatelessWidget {
  const AgentBars({
    required this.series,
    required this.format,
    this.color = AppColor.brand,
    super.key,
  });

  final AgentSeries series;

  /// Turns a raw value into its display string — counts, minutes and durations
  /// all share this widget.
  final String Function(num) format;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final num max = series.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final AgentSeriesRow row in series.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(format(row.value), style: text.labelMedium),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: <Widget>[
                      Container(height: 6, color: AppColor.surfaceAlt),
                      if (max > 0)
                        FractionallySizedBox(
                          widthFactor: (row.value / max).clamp(0.0, 1.0),
                          child: Container(height: 6, color: color),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A card wrapping one titled block of a report.
class ReportCard extends StatelessWidget {
  const ReportCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColor.surfaceDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// "2h 5m" from a second count.
///
/// Only used where the server did **not** already send its own `…_human`
/// string. Where it did, that string is preferred verbatim so the app and the
/// console can never disagree by a rounding rule.
String humanizeSeconds(int seconds) {
  if (seconds <= 0) return '0m';
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  return m > 0 ? '${m}m' : '<1m';
}

/// Thousands separators without pulling in `intl` number formatting here —
/// the app already loads `intl` for dates, but these are plain counts and the
/// grouping character is the same in both shipped locales.
String groupDigits(num v) {
  final String s = v.round().abs().toString();
  final StringBuffer out = StringBuffer(v < 0 ? '-' : '');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
