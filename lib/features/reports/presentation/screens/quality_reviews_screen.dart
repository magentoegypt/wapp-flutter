import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/report_repository.dart';
import '../../domain/reports.dart';
import '../widgets/report_bits.dart';
import 'window_chips.dart';

/// `GET /reports/quality-reviews`.
///
/// These are **internal manager reviews**, written by
/// `POST /conversations/{uid}/quality-review` — not customer CSAT. The copy
/// says so on the screen, because a score an agent believes came from customers
/// means something quite different from one their manager wrote, and the number
/// alone cannot tell them which.
class QualityReviewsScreen extends ConsumerWidget {
  const QualityReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rpQuality),
      body: Column(
        children: <Widget>[
          WindowChips(provider: qualityWindowProvider),
          Expanded(
            child: AsyncValueView<QualityReport>(
              value: ref.watch(qualityReviewsProvider),
              onRetry: () => ref.invalidate(qualityReviewsProvider),
              builder: (QualityReport r) {
                if (r.isEmpty) {
                  return EmptyState(
                    icon: Icons.star_outline,
                    title: l10n.rpNoReviews,
                    message: l10n.rpNoReviewsHint,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(qualityReviewsProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.stripGutter,
                      4,
                      AppDimens.stripGutter,
                      AppDimens.gutter,
                    ),
                    children: <Widget>[
                      ReportCard(
                        title: l10n.rpSummary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _Big(
                                    // Null when the window held no reviews.
                                    // "—" rather than "0.0", which would read
                                    // as everyone having scored zero.
                                    value: r.averageScore == null
                                        ? '—'
                                        : r.averageScore!.toStringAsFixed(2),
                                    label: l10n.rpAvgScore,
                                  ),
                                ),
                                Expanded(
                                  child: _Big(
                                    value: '${r.totalReviews}',
                                    label: l10n.rpReviews,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.rpInternalNote,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColor.inkMuted,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (r.agents.isNotEmpty)
                        ReportCard(
                          title: l10n.rpScorePerAgent,
                          child: AgentBars(
                            series: AgentSeries(<AgentSeriesRow>[
                              for (final QualityAgent a in r.agents)
                                AgentSeriesRow(
                                  name: a.name,
                                  value: a.averageScore,
                                ),
                            ]),
                            format: (num v) => v.toStringAsFixed(2),
                            color: AppColor.info,
                          ),
                        ),
                      if (r.recent.isNotEmpty)
                        ReportCard(
                          title: l10n.rpRecentReviews,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (final QualityReview v in r.recent)
                                _ReviewRow(review: v),
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

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review});

  final QualityReview review;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  review.agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColor.infoWash,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  review.score.toStringAsFixed(1),
                  style: text.labelMedium?.copyWith(color: AppColor.info),
                ),
              ),
            ],
          ),
          if (review.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(review.comment, style: text.bodyMedium),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              <String>[
                if (review.reviewerName.isNotEmpty)
                  l10n.rpReviewedBy(review.reviewerName),
                if (review.createdAt != null)
                  DateFormat.yMMMd().format(review.createdAt!),
              ].join(' · '),
              style: text.labelSmall?.copyWith(
                color: AppColor.inkFaint,
                letterSpacing: 0,
              ),
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
