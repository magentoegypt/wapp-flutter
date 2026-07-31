import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../agents/data/agent_repository.dart';
import '../../data/conversation_action_repository.dart';

/// Quality review — the manager's own scoring of a handled conversation.
///
/// The whole screen leans on one distinction: this is an *internal* review, not
/// the customer's CSAT. Both are a 1-5 number attached to the same conversation,
/// so an agent who reads this as "rate the customer's satisfaction" would push
/// invented numbers into a series the team reports on. Hence the standing
/// banner rather than a one-time hint.
class QualityReviewScreen extends ConsumerStatefulWidget {
  const QualityReviewScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<QualityReviewScreen> createState() =>
      _QualityReviewScreenState();
}

class _QualityReviewScreenState extends ConsumerState<QualityReviewScreen> {
  final TextEditingController _comment = TextEditingController();

  int? _score;

  /// Null means "let the server fall back to the assigned agent". That fallback
  /// is the API's, not ours — resolving the assignee here would freeze whoever
  /// held the conversation when this screen opened, which is not necessarily
  /// who is being reviewed by the time it is submitted.
  String? _agentUid;

  /// Set on a submit attempt with no score. The required-score message stays
  /// hidden until then: showing it on arrival scolds the user for not having
  /// filled in a form they have not seen yet.
  bool _scoreMissing = false;

  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final int? score = _score;
    // Deliberately reachable with no score, rather than disabling the button:
    // a dead button explains nothing, and qvScoreRequired is the only copy that
    // names the 1-5 range at all.
    if (score == null) {
      setState(() => _scoreMissing = true);
      return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String comment = _comment.text.trim();
    setState(() => _busy = true);

    try {
      await ref.read(conversationActionRepositoryProvider).qualityReview(
            contactUid: widget.contactUid,
            score: score,
            agentUid: _agentUid,
            comment: comment.isEmpty ? null : comment,
            // The criteria taxonomy is defined server-side per workspace and
            // has no localised labels shipped with the app, so there is nothing
            // honest to render a picker from. Sent empty rather than omitted so
            // the call site matches the endpoint's shape.
            criteria: const <String>[],
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.qvDone)));
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Agent>> agents = ref.watch(agentListProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppHeader.back(title: l10n.qvTitle),
      body: Column(
        children: <Widget>[
          // Warning tone, not the brand tone the notes privacy notice uses:
          // that one reassures, this one corrects a misreading that silently
          // corrupts the CSAT series if it goes unnoticed.
          AppBanner(
            message: l10n.qvNotCsat,
            tone: BannerTone.warning,
            icon: Icons.info_outline,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppDimens.gutter),
              children: <Widget>[
                Text(l10n.qvPrompt, style: text.bodyMedium),
                SectionLabel(l10n.qvScore, padded: false),
                _StarRating(
                  score: _score,
                  onChanged: _busy
                      ? null
                      : (int value) => setState(() {
                            _score = value;
                            _scoreMissing = false;
                          }),
                ),
                if (_scoreMissing) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    l10n.qvScoreRequired,
                    style: text.bodyMedium?.copyWith(color: AppColor.danger),
                  ),
                ],
                SectionLabel(l10n.qvAgent, padded: false),
                // The roster gets the full loading/error treatment instead of
                // degrading to the default-only picker: agentUid is optional,
                // so a silently empty list would look like a workspace with one
                // agent rather than like a request that failed.
                AsyncValueView<List<Agent>>(
                  value: agents,
                  onRetry: () => ref.invalidate(agentListProvider),
                  builder: (List<Agent> rows) => DropdownButtonFormField<String?>(
                    initialValue: _agentUid,
                    isExpanded: true,
                    items: <DropdownMenuItem<String?>>[
                      DropdownMenuItem<String?>(
                        child: Text(l10n.qvAgentDefault),
                      ),
                      for (final Agent a in rows)
                        DropdownMenuItem<String?>(
                          value: a.uid,
                          child: Text(a.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (String? value) => setState(() => _agentUid = value),
                  ),
                ),
                SectionLabel(l10n.qvComment, padded: false),
                TextField(
                  controller: _comment,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: l10n.qvCommentHint),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.qvSubmit),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 1-5 score, as five tappable stars.
///
/// Stars rather than a select because the value is ordinal and the frame reads
/// it at a glance; a dropdown would hide four of the five options behind a tap
/// and give no sense of where a 3 sits.
class _StarRating extends StatelessWidget {
  const _StarRating({required this.score, required this.onChanged});

  final int? score;

  /// Null while a submit is in flight, which also greys the row out.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final int filled = score ?? 0;
    // Locale digits, so the screen reader announces "٣" in Arabic rather than a
    // Latin "3" dropped into an RTL sentence. Formatted rather than hard-coded
    // for the same reason every other number in the app is.
    final NumberFormat digits = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: i <= filled,
            value: digits.format(i),
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(i),
              customBorder: const CircleBorder(),
              child: SizedBox(
                // 46 keeps every star above the 44pt minimum target even though
                // the glyph itself is 32 — at glyph size the stars sat close
                // enough together to mis-tap a neighbouring score.
                width: 46,
                height: 46,
                child: Icon(
                  i <= filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 32,
                  // Brand green as a fill, not warning amber: amber is the
                  // semantic attention tone, and a five-star review is not a
                  // warning.
                  color: onChanged == null
                      ? AppColor.inkFaint
                      : (i <= filled ? AppColor.brand : AppColor.inkFaint),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
