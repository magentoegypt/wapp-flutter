import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/call_repository.dart';
import '../../data/call_session.dart';
import '../../domain/call.dart';
import '../widgets/call_chrome.dart';

/// The ringing surface for a call the customer placed to us.
///
/// Deliberately immersive — no header, no bottom bar, nothing else tappable. A
/// ringing call is a modal event, and any affordance that lets the agent wander
/// into the inbox mid-ring strands a live WebRTC session behind a screen with
/// no way to end it.
///
/// Everything about the call itself lives in the session controller; this
/// screen renders a phase and forwards two taps. That split is what lets the
/// active-call route replace this one without interrupting the session.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({required this.contactUid, this.name, super.key});

  final String contactUid;

  /// Optional because a ring can arrive from a push payload carrying only the
  /// contact uid. [_display] falls back to the uid rather than blanking the
  /// screen — an unnamed caller is still a caller.
  final String? name;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with WidgetsBindingObserver {
  /// Latched the moment this route hands over, so a phase change arriving after
  /// navigation cannot pop a screen that is already gone. Decline races the
  /// session directly: `reject` drives the phase to `ended` while `_decline` is
  /// still popping.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Paired with the addObserver above — the observer outlives this State
    // otherwise and keeps firing into a disposed ref.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Granting the microphone happens in the OS settings app, which gives the
    // plugin no callback at all. Re-asking on resume is the only way this
    // screen recovers by itself; without it the agent grants permission, comes
    // back, and still sees the denial copy with no way past it.
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(callSessionProvider).phase != CallPhase.permissionDenied) {
      return;
    }
    ref.read(callSessionProvider.notifier).ensureMicPermission();
  }

  String get _display {
    final String trimmed = widget.name?.trim() ?? '';
    return trimmed.isEmpty ? widget.contactUid : trimmed;
  }

  /// Not awaited on purpose: the controller owns the negotiation and reports
  /// every step through the session phase, which [build]'s listener turns into
  /// navigation. Awaiting here would mean running the same state machine twice
  /// and eventually disagreeing with itself.
  void _accept(CallRecord call) {
    ref.read(callSessionProvider.notifier).acceptIncoming(call);
  }

  void _decline(CallRecord? call) {
    // Null only when the ring reached this route before /calls/pending
    // answered. There is no uid to reject, but the agent must still be able to
    // leave — a decline button that does nothing is worse than one that only
    // closes the screen.
    if (call != null) {
      ref.read(callSessionProvider.notifier).reject(call);
    }
    _close();
  }

  void _close() {
    if (_leaving) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Nothing underneath: this route was opened cold from a notification tap,
    // so popping would leave an empty navigator.
    context.go(AppRoutes.chats);
  }

  /// The connected call gets its own route because it owns mute, speaker and
  /// the elapsed timer, none of which belong on a ringing screen.
  void _openActiveCall() {
    if (_leaving) return;
    _leaving = true;
    // pushReplacement, not push: leaving the ringing UI on the stack means a
    // back gesture from the active call lands on an Accept button for a call
    // that is already up.
    context.pushReplacement(AppRoutes.callActive(widget.contactUid));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final CallSessionState session = ref.watch(callSessionProvider);

    ref.listen<CallSessionState>(
      callSessionProvider,
      (CallSessionState? previous, CallSessionState next) {
        if (next.phase == CallPhase.active) {
          _openActiveCall();
        } else if (next.phase == CallPhase.ended) {
          _close();
        }
      },
    );

    // `session.call` as soon as the controller has adopted the ringing call.
    // Until then the only source is /calls/pending, and a CallRecord carries no
    // contact at all, so it cannot be matched against widget.contactUid. At
    // most one call rings at a time, which is why taking the first row is safe
    // here and would not be in a list.
    final List<CallRecord> pending =
        ref.watch(pendingCallsProvider).valueOrNull ?? const <CallRecord>[];
    final CallRecord? call =
        session.call ?? (pending.isEmpty ? null : pending.first);

    final bool denied = session.phase == CallPhase.permissionDenied;
    final bool blocked = denied || session.phase == CallPhase.failed;

    return PopScope(
      // Only bolted shut once we have taken the call — `isBusy` is the
      // controller's own definition of "a session is under way", reused rather
      // than re-derived here. While the call is merely ringing, backing out is
      // an ordinary decline and the button path handles it; after accept the
      // same gesture would abandon a live peer connection with the microphone
      // still open, so it is converted into a hang-up instead.
      canPop: !session.isBusy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        ref.read(callSessionProvider.notifier).hangUp();
      },
      child: Scaffold(
        backgroundColor: AppColor.groundDark,
        body: CallBackdrop(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Center(
                    // Scrollable so the identity block survives a large text
                    // scale instead of overflowing behind the actions, which
                    // are the one thing here that must stay reachable.
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppDimens.gutter,
                        end: AppDimens.gutter,
                        top: 24,
                        bottom: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // The hash-tinted variant, not InitialsAvatar.onBrand:
                          // that one draws a brandDeep disc, which is the top of
                          // this very gradient and would sink into it.
                          InitialsAvatar(name: _display, size: 132),
                          const SizedBox(height: 28),
                          Text(
                            _display,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (blocked)
                            CallTroublePanel(
                              icon: denied
                                  ? Icons.mic_off_outlined
                                  : Icons.info_outline,
                              // The controller's own message wins when it has
                              // one: it carries the server's reason for this
                              // specific call, which always beats generic copy.
                              message: denied
                                  ? l10n.clMicDenied
                                  : (session.errorMessage ?? l10n.clFailed),
                              actionLabel:
                                  denied ? l10n.clMicOpenSettings : null,
                              // Routed through the controller rather than
                              // calling permission_handler's openAppSettings
                              // here: the plugin stays out of the widget layer,
                              // and the controller already swallows the
                              // platform error a device with no settings
                              // activity throws. Not awaited — the settings app
                              // takes over, and recovery is the resume
                              // handler's job. No action on a failure: Decline
                              // below is already the way out.
                              onAction: denied
                                  ? () => ref
                                      .read(callSessionProvider.notifier)
                                      .openMicrophoneSettings()
                                  : null,
                            )
                          else
                            Text(
                              _phaseLabel(l10n, session.phase),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppDimens.gutter,
                    end: AppDimens.gutter,
                    top: 8,
                    bottom: 40,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      RoundCallAction(
                        icon: Icons.call_end,
                        tint: AppColor.danger,
                        label: l10n.clDecline,
                        // Never disabled. This is the exit from the screen and
                        // has to stay live even when the microphone is refused.
                        onPressed: () => _decline(call),
                      ),
                      RoundCallAction(
                        icon: Icons.call,
                        tint: AppColor.success,
                        label: l10n.clAccept,
                        // Nothing to accept without a call row, and accepting
                        // with a refused microphone would connect a call the
                        // agent cannot speak on.
                        onPressed:
                            call == null || blocked ? null : () => _accept(call),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-line status under the caller's name.
///
/// A switch expression rather than a map with a default, so an eighth phase is
/// a compile error here instead of a blank line under a ringing call. The two
/// refusal phases still need an arm even though CallTroublePanel replaces this
/// line for them — "unavailable" is the honest reading of both.
String _phaseLabel(AppLocalizations l10n, CallPhase phase) => switch (phase) {
      CallPhase.idle || CallPhase.ringing => l10n.clIncoming,
      CallPhase.connecting => l10n.clConnecting,
      CallPhase.active => l10n.clActive,
      CallPhase.ended => l10n.clEnded,
      CallPhase.permissionDenied || CallPhase.failed => l10n.clUnavailable,
    };
