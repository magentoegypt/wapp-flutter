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

/// The dialling surface for a call we place to the customer.
///
/// The mirror of the incoming screen, minus a choice: there is one action, and
/// it ends the attempt. Immersive for the same reason — a half-negotiated peer
/// connection left behind an inbox screen keeps the microphone open with
/// nothing on screen to close it.
///
/// Worth knowing before reading the failure handling below: on this workspace
/// the happy path is unreachable. Meta refuses outbound calling from this
/// number, so `permissionDenied` and `failed` are the only phases an agent will
/// ever see here. The refusal copy is not an edge case, it is the screen.
class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({required this.contactUid, this.name, super.key});

  final String contactUid;

  /// Optional: the dialler may only know the uid it was handed. [_display]
  /// falls back to it rather than showing an anonymous disc.
  final String? name;

  @override
  ConsumerState<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen>
    with WidgetsBindingObserver {
  /// Latched the moment this route hands over, so a phase change arriving after
  /// navigation cannot pop a screen that is already gone — hanging up drives
  /// the session to `ended` while `_close` is still running.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Post-frame rather than inline: startOutgoing can refuse synchronously —
    // microphone denied, or capability off — and writing provider state during
    // this route's first build throws.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      // Not gated on callCapabilityProvider first. The engine's refusal is the
      // authoritative one and pre-checking would add a round trip in front of
      // every legitimate call; capability is read below only to phrase a
      // refusal that has already happened.
      ref.read(callSessionProvider.notifier).startOutgoing(widget.contactUid);
    });
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

  void _close() {
    if (_leaving) return;
    _leaving = true;
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Nothing underneath — dialled from a deep link, so popping would leave an
    // empty navigator.
    context.go(AppRoutes.chats);
  }

  /// The connected call gets its own route because it owns mute, speaker and
  /// the elapsed timer, none of which belong on a dialling screen.
  void _openActiveCall() {
    if (_leaving) return;
    _leaving = true;
    // pushReplacement, not push: leaving the dialler on the stack means a back
    // gesture from the active call lands on "Calling…" for a call already up.
    context.pushReplacement(AppRoutes.callActive(widget.contactUid));
  }

  /// Why the call could not be placed, in the agent's own language.
  ///
  /// Ordered most specific first, and `restrictedReason` leads because it is
  /// the branch that actually runs on this workspace: the controller stores the
  /// bare fragment ("USA / Canada") and `clRestricted` is the sentence that
  /// wraps it. Printing the fragment on its own would put a country list where
  /// an explanation belongs.
  ///
  /// A refusal with no reason leaves both message slots empty, which is why
  /// capability is consulted at all — it is the only thing that can tell
  /// "switched off for this workspace" apart from "not right now".
  String _failureMessage(
    AppLocalizations l10n,
    CallSessionState session,
    CallCapability? capability,
  ) {
    final String? reason = session.restrictedReason;
    if (reason != null && reason.isNotEmpty) return l10n.clRestricted(reason);

    // Already a complete, user-safe sentence from Failure.message — shown as-is
    // rather than wrapped, or it ends up nested inside a second sentence.
    final String? message = session.errorMessage;
    if (message != null && message.isNotEmpty) return message;

    if (capability != null && !capability.enabled) return l10n.clDisabled;
    if (capability != null && !capability.canPlaceCall) {
      return l10n.clUnavailable;
    }
    return l10n.clFailed;
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

    // Watched unconditionally, and fetched in parallel with the call attempt
    // rather than in front of it, so the reason is already in hand by the time
    // the engine refuses. The provider is autoDispose and designed to be
    // re-read — `withinBusinessHours` flips during the day.
    final CallCapability? capability =
        ref.watch(callCapabilityProvider).valueOrNull;

    final bool denied = session.phase == CallPhase.permissionDenied;
    final bool blocked = denied || session.phase == CallPhase.failed;

    return PopScope(
      // `isBusy` is the controller's own definition of "a session is under
      // way", reused rather than re-derived. Unlike the incoming screen it also
      // covers `ringing`: once we have dialled, the call is ours, and backing
      // out silently would leave it alerting the customer's handset with the
      // microphone still open here — so the gesture becomes a hang-up.
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
                    // scale instead of overflowing behind the action, which is
                    // the only way off this screen.
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
                              message: denied
                                  ? l10n.clMicDenied
                                  : _failureMessage(l10n, session, capability),
                              actionLabel:
                                  denied ? l10n.clMicOpenSettings : null,
                              // Routed through the controller rather than
                              // calling permission_handler's openAppSettings
                              // here: the plugin stays out of the widget layer,
                              // and the controller already swallows the
                              // platform error a device with no settings
                              // activity throws. Not awaited — the settings app
                              // takes over, and recovery is the resume
                              // handler's job. No action on a refusal: the
                              // control below is already the way out.
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
                  // One control, whose meaning follows the phase. Once the call
                  // is already refused there is nothing left to hang up, and a
                  // red "Hang up" under a message explaining that no call was
                  // placed reads as a second failure.
                  child: RoundCallAction(
                    icon: blocked ? Icons.close : Icons.call_end,
                    tint: AppColor.danger,
                    label: blocked ? l10n.actionClose : l10n.clHangUp,
                    onPressed: blocked
                        ? _close
                        : () => ref.read(callSessionProvider.notifier).hangUp(),
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

/// The one-line status under the callee's name.
///
/// A switch expression rather than a map with a default, so an eighth phase is
/// a compile error here instead of a blank line under a dialling call. `idle`
/// shares the connecting arm: it is the gap between this route building and the
/// post-frame `startOutgoing` landing, and reads to the agent as the same wait.
String _phaseLabel(AppLocalizations l10n, CallPhase phase) => switch (phase) {
      CallPhase.idle || CallPhase.connecting => l10n.clConnecting,
      CallPhase.ringing => l10n.clOutgoing,
      CallPhase.active => l10n.clActive,
      CallPhase.ended => l10n.clEnded,
      // Unreachable while `blocked` gates this call, but the switch must be
      // exhaustive and "unavailable" is the honest reading of both.
      CallPhase.permissionDenied || CallPhase.failed => l10n.clUnavailable,
    };
