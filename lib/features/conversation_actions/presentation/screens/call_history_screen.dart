import 'package:flutter/material.dart';
// PlatformException — url_launcher throws it when no installed app claims the
// URL, and it is not re-exported by material.dart.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/error/failure.dart';
import '../../../calls/data/recording_player.dart';
import '../../../calls/domain/call.dart';
import '../../data/conversation_action_repository.dart';

/// Call history for one contact, reached from the ⋮ chat actions sheet.
///
/// Read-only. Placing, accepting and ending calls belong to the Calling module;
/// the only thing this screen can do is hand a recording to the OS.
class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<CallHistoryPage> history =
        ref.watch(callHistoryProvider(contactUid));
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppHeader.back(title: l10n.chTitle),
      body: AsyncValueView<CallHistoryPage>(
        value: history,
        onRetry: () => ref.invalidate(callHistoryProvider(contactUid)),
        builder: (CallHistoryPage page) {
          if (page.calls.isEmpty) {
            return EmptyState(icon: Icons.call_outlined, title: l10n.chEmpty);
          }

          // `page.hasMore` is knowingly not surfaced. callHistoryProvider is a
          // family keyed on contactUid alone and always asks the repository for
          // page 1, so there is no second page reachable from here; a load-more
          // affordance would need both a paging notifier and an ARB key this
          // screen does not own. Left as a deliberate gap rather than a button
          // that silently re-fetches the same rows.
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(callHistoryProvider(contactUid)),
            child: ListView.separated(
              padding: const EdgeInsetsDirectional.only(
                start: AppDimens.gutter,
                end: AppDimens.gutter,
                top: 12,
                bottom: AppDimens.gutter,
              ),
              itemCount: page.calls.length,
              separatorBuilder: (BuildContext context, int i) =>
                  const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int i) =>
                  _CallCard(record: page.calls[i], locale: locale),
            ),
          );
        },
      ),
    );
  }
}

/// One call.
///
/// The status pill and duration ride in [AppListTile]'s trailing slot; the
/// conditional extras — outside-hours, the recording — sit on a second line
/// beneath it. That slot is a single widget and the Arabic labels are longer
/// than the English ones, so stacking four things there pushed the duration off
/// the row at 390pt.
class _CallCard extends ConsumerWidget {
  const _CallCard({required this.record, required this.locale});

  final CallRecord record;

  /// Only used by the timestamp fallback below — see [_timeLabel].
  final String locale;

  /// Plays the recording in-app, with the bearer token attached.
  ///
  /// This used to hand the URL to the OS with url_launcher, which was right
  /// when `recordingUrl` was a plain asset URL. It is now
  /// `GET /api/v1/calls/{uid}/recording` behind a token — the recordings were
  /// world-readable and were moved off the public disk — and the system player
  /// sends no Authorization header, so that path now returns 401 and plays
  /// silence. An authenticated URL cannot be delegated to the OS.
  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final String? url = record.recordingUrl;
    if (url == null || url.isEmpty) {
      _tell(context, l10n.chNoRecording);
      return;
    }

    try {
      await ref.read(recordingPlayerProvider).toggle(record.uid, url);
    } on Failure catch (e) {
      if (!context.mounted) return;
      _tell(context, e.message);
    }
  }

  void _tell(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The contact-facing time.
  ///
  /// Both `initiatedAtText` and `initiatedAgoText` arrive rendered by the
  /// server, and are preferred over formatting [CallRecord.initiatedAt] so the
  /// app and the web console never disagree about the same call. The intl
  /// fallback is last and exists only so a row is never timeless when the API
  /// omits both.
  String? _timeLabel() {
    final String? absolute = record.initiatedAtText;
    if (absolute != null && absolute.isNotEmpty) return absolute;
    final String? relative = record.initiatedAgoText;
    if (relative != null && relative.isNotEmpty) return relative;
    final DateTime? at = record.initiatedAt;
    if (at == null) return null;
    return DateFormat.yMMMd(locale).add_jm().format(at);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final StatusTone tone = _toneFor(record.status);
    final String? duration = record.durationText;

    // "No recording" is only worth saying where a recording was expected. On a
    // workspace with recording switched off it would print on every single row.
    final bool showsRecording = record.isPlayable || record.recordingEnabled;
    final bool hasFooter = record.outsideBusinessHours || showsRecording;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppListTile(
            title: record.isIncoming ? l10n.chIncoming : l10n.chOutgoing,
            subtitle: _timeLabel(),
            // Not mirrored in RTL: these are outcome glyphs the way every phone
            // dialer draws them, not a navigation affordance, so flipping them
            // in Arabic would swap the meaning of received and made.
            leading: IconTile(
              icon: record.isIncoming ? Icons.call_received : Icons.call_made,
              color: tone.foreground,
            ),
            // Nothing to push to — the chevron would promise a detail screen
            // that does not exist.
            showChevron: false,
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                StatusPill(label: _statusLabel(l10n, record.status), tone: tone),
                if (duration != null && duration.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(duration, style: text.labelMedium),
                ],
              ],
            ),
          ),
          if (hasFooter)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                // Matches AppListTile's own inset so the footer lines up with
                // the row above it.
                start: AppDimens.gutter,
                end: AppDimens.gutter,
                bottom: 12,
              ),
              // Wrap, not Row: the outside-hours pill and the recording control
              // together overflow one line in Arabic, and a call that happened
              // out of hours is exactly the row you least want clipped.
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (record.outsideBusinessHours)
                    StatusPill(
                      label: l10n.chOutsideHours,
                      tone: StatusTone.warning,
                      // No dot: it qualifies the call rather than reporting a
                      // second state alongside the status pill above.
                      showDot: false,
                    ),
                  if (showsRecording) ...<Widget>[
                    Text(l10n.chRecording, style: text.labelMedium),
                    if (record.isPlayable)
                      TextButton.icon(
                        onPressed: () => _play(context, ref, l10n),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: Text(l10n.chPlay),
                      )
                    else
                      Text(l10n.chNoRecording, style: text.labelMedium),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// All seven statuses the engine can write.
///
/// A switch expression over the enum rather than a map with a default, so that
/// adding an eighth status is a compile error here instead of a blank pill in
/// front of a customer. Today this workspace only produces `completed` and
/// `noAnswer`, which is precisely why the other five are easy to forget.
String _statusLabel(AppLocalizations l10n, CallStatus status) =>
    switch (status) {
      CallStatus.initiated => l10n.chStInitiated,
      CallStatus.ringing => l10n.chStRinging,
      CallStatus.active => l10n.chStActive,
      CallStatus.failed => l10n.chStFailed,
      CallStatus.rejected => l10n.chStRejected,
      CallStatus.noAnswer => l10n.chStNoAnswer,
      CallStatus.completed => l10n.chStCompleted,
    };

/// `noAnswer` is warning rather than danger: nobody picked up is an ordinary
/// outcome, while `failed` and `rejected` mean the call could not or would not
/// happen. `initiated` and `ringing` are neutral because they are transient —
/// by the time history is read they have almost always moved on, and colouring
/// a stale in-flight row would read as a verdict.
StatusTone _toneFor(CallStatus status) => switch (status) {
      CallStatus.completed => StatusTone.success,
      CallStatus.active => StatusTone.info,
      CallStatus.initiated || CallStatus.ringing => StatusTone.neutral,
      CallStatus.noAnswer => StatusTone.warning,
      CallStatus.failed || CallStatus.rejected => StatusTone.danger,
    };
