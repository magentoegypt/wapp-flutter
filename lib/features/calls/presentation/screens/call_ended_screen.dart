import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/call_session.dart';
import '../../domain/call.dart';
import 'active_call_screen.dart';

/// What the call came to.
///
/// An outcome, not a dead end: a call that failed, was declined or went
/// unanswered is most often followed by another attempt, so the summary carries
/// the way back to the dialler rather than making the agent retrace the chat →
/// ⋮ → call path to try again.
///
/// Stateless. Nothing here writes — the session already holds the terminated
/// call, and re-terminating it on a rebuild would be a bug, not a refresh.
class CallEndedScreen extends ConsumerWidget {
  const CallEndedScreen({required this.contactUid, this.name, super.key});

  final String contactUid;

  /// Absent when the call was opened from a notification rather than from the
  /// chat, which is why nothing here may assume a name exists.
  final String? name;

  String get _display {
    final String trimmed = (name ?? '').trim();
    // The uid is a poor label, but it is the only handle always present and an
    // anonymous summary tells the agent nothing about who they just spoke to.
    return trimmed.isEmpty ? contactUid : trimmed;
  }

  /// Starts a fresh attempt at the same contact.
  ///
  /// Replaces rather than pushes: the outgoing screen that began the call was
  /// itself replaced when the media came up, so there is nothing to pop back
  /// to, and pushing would stack a summary under every retry until the back
  /// gesture walked the agent through a history of finished calls.
  ///
  /// The session is reset first. It is autoDispose, but both routes are briefly
  /// alive across a replacement, so it survives the handover — and the outgoing
  /// screen would open on the *previous* call's `ended` phase and error text.
  void _callBack(BuildContext context, WidgetRef ref) {
    ref.read(callSessionProvider.notifier).reset();
    context.pushReplacement(AppRoutes.callOutgoing(contactUid), extra: name);
  }

  /// Leaves the call flow entirely.
  ///
  /// Falls through to the conversation when there is no stack behind this
  /// screen — a call answered from a notification starts here, and popping
  /// nothing would leave the agent looking at a summary with no exit.
  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.chat(contactUid));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final CallSessionState session = ref.watch(callSessionProvider);
    final CallRecord? call = session.call;
    final CallStatus? status = call?.status;
    final String? outcome = _outcomeLabel(l10n, status);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              // Centred while it fits and scrolled when it does not: the summary
              // has to survive a large text scale and a landscape phone without
              // overflowing into the two buttons pinned below it. The minHeight
              // is what makes `MainAxisAlignment.center` mean anything inside a
              // scroll view — without it the column shrink-wraps to the top.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppDimens.gutter * 2,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        InitialsAvatar(
                          name: _display,
                          size: AppDimens.avatarHero,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _display,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(l10n.clEnded, style: text.bodyMedium),
                        const SizedBox(height: 20),
                        Text(
                          _durationLabel(session, call),
                          style: text.displayLarge?.copyWith(
                            // Tabular figures for the same reason the live timer
                            // uses them: this is that number, stopped.
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        // Omitted rather than guessed. A null status means the
                        // engine has not written the record yet, and a call
                        // cannot be called completed on the strength of the
                        // media having stopped — that is just as true of a call
                        // that dropped.
                        if (outcome != null) ...<Widget>[
                          const SizedBox(height: 14),
                          StatusPill(
                            label: outcome,
                            tone: _outcomeTone(status),
                          ),
                        ],
                        if (session.errorMessage != null) ...<Widget>[
                          const SizedBox(height: 16),
                          // The sentence the server wrote about why the call
                          // failed. It is the only explanation the agent gets,
                          // so it belongs on the outcome rather than in a
                          // snackbar that expired two screens ago.
                          Text(
                            session.errorMessage!,
                            textAlign: TextAlign.center,
                            style:
                                text.bodyMedium?.copyWith(color: AppColor.danger),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
              child: Column(
                // Stretched: two centred, content-width buttons stacked on each
                // other read as one ragged block, and the primary action should
                // be the widest target on the screen.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => _callBack(context, ref),
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(l10n.clCallBack),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _close(context),
                    child: Text(l10n.actionClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long the call lasted.
///
/// `durationText` is server-rendered and wins wherever it exists — [CallRecord]
/// documents it as the one figure the app and the web console are guaranteed to
/// agree on, down to the rounding rule. The session's own stopwatch is the
/// fallback, because a call that ends before the engine writes its record still
/// lasted a real number of seconds and a blank there reads as a bug.
String _durationLabel(CallSessionState session, CallRecord? call) {
  final String? rendered = call?.durationText;
  if (rendered != null && rendered.trim().isNotEmpty) return rendered.trim();

  final Duration measured = session.elapsed > Duration.zero
      ? session.elapsed
      : Duration(seconds: call?.durationSeconds ?? 0);
  return formatCallElapsed(measured);
}

/// The four outcomes worth printing under "Call ended".
///
/// `initiated`, `ringing` and `active` are not outcomes — reaching this screen
/// with one of them means the record is a beat behind the media, and printing
/// "Ringing" beneath "Call ended" is a contradiction the agent has to resolve.
/// They fall in with the null case and the line simply does not appear. The
/// switch is exhaustive on purpose: an eighth status has to be classified here
/// rather than silently rendering blank in front of a customer.
String? _outcomeLabel(AppLocalizations l10n, CallStatus? status) =>
    switch (status) {
      CallStatus.completed => l10n.chStCompleted,
      CallStatus.failed => l10n.chStFailed,
      CallStatus.rejected => l10n.chStRejected,
      CallStatus.noAnswer => l10n.chStNoAnswer,
      CallStatus.initiated || CallStatus.ringing || CallStatus.active => null,
      null => null,
    };

/// Matches the tones call history already uses for the same four statuses, so
/// a declined call is not danger-red here and warning-amber in the list.
StatusTone _outcomeTone(CallStatus? status) => switch (status) {
      CallStatus.completed => StatusTone.success,
      CallStatus.noAnswer => StatusTone.warning,
      CallStatus.failed || CallStatus.rejected => StatusTone.danger,
      CallStatus.initiated ||
      CallStatus.ringing ||
      CallStatus.active ||
      null =>
        StatusTone.neutral,
    };
