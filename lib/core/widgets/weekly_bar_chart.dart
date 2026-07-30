import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// One column of [WeeklyBarChart].
class BarDatum {
  const BarDatum({required this.label, required this.value});

  /// Already localized — the chart does no date formatting itself.
  final String label;
  final int value;
}

/// The "Conversations this week" chart on the dashboard.
///
/// Hand-drawn rather than pulling in a charting package: it is seven bars with
/// no axes, legend, tooltip or interaction, and a dependency would cost more
/// than it saves. Bars scale to the largest value in the set; an all-zero week
/// renders flat baselines instead of dividing by zero.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    required this.data,
    this.height = 96,
    this.semanticsLabel,
    super.key,
  });

  final List<BarDatum> data;
  final double height;

  /// Screen-reader description. Pass the localized chart title — the bars
  /// themselves carry no text, so without this the chart is announced as an
  /// unlabelled group.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);

    final int max = data.fold<int>(0, (int m, BarDatum d) => d.value > m ? d.value : m);
    final TextStyle? labelStyle = Theme.of(context).textTheme.labelMedium;

    return Semantics(
      label: semanticsLabel,
      value: data.map((BarDatum d) => '${d.label} ${d.value}').join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final BarDatum d in data)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        // Zero-height bars are invisible; floor at a sliver so
                        // an empty day still reads as a day.
                        heightFactor: max == 0 ? 0.02 : (d.value / max).clamp(0.02, 1.0),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: AppColor.brand,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(d.label, style: labelStyle),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card wrapper matching the dashboard's surrounding surface.
class ChartCard extends StatelessWidget {
  const ChartCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColor.surfaceDark,
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
        border: Border.all(
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
