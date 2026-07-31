import 'package:flutter/material.dart';
// SystemUiOverlayStyle — the status bar sits on brand green here and its icons
// have to be forced light; it is not re-exported by material.dart.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/call_session.dart';

/// The live call.
///
/// Full-screen and outside the shell: while media is up there is nothing else
/// the agent can usefully do in the app, and a bottom tab bar under a live call
/// invites exactly the tap that abandons it.
///
/// Stateful for two reasons that both come down to not terminating one call
/// twice — an in-flight guard around hang-up, and a one-shot latch on the
/// navigation to the ended screen, which the session's per-second tick would
/// otherwise re-fire on every rebuild.
///
/// There is no `dispose` here on purpose. The peer connection, the microphone
/// stream and the timer belong to [CallSessionController], which releases them
/// when the autoDispose provider goes; holding any of them in a widget would
/// keep the microphone live for as long as the element tree felt like keeping
/// the widget, which is a privacy problem rather than an untidy one.
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({required this.contactUid, this.name, super.key});

  final String contactUid;

  /// Absent when the call was opened from a notification rather than from the
  /// chat, which is why nothing here may assume a name exists.
  final String? name;

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  /// True from the first tap on hang-up until terminate answers. `phase` stays
  /// `active` across that round trip, so without this a second tap sends a
  /// second terminate for the same call.
  bool _ending = false;

  /// Latches the one navigation away from here. The session rebuilds this
  /// screen every second while the timer runs, and `ended` persists in state
  /// once reached.
  bool _left = false;

  String get _display {
    final String trimmed = (widget.name ?? '').trim();
    // The uid is a poor label, but it is the only handle always present and a
    // nameless call is worse than an ugly one — the agent still has to know who
    // is on the line.
    return trimmed.isEmpty ? widget.contactUid : trimmed;
  }

  /// Ends the call and lets the session decide what happens next.
  ///
  /// Deliberately does not navigate: hanging up and leaving this screen are two
  /// different events, and pairing them here would leave the mic open whenever
  /// the call ends by any route other than this button.
  Future<void> _hangUp() async {
    if (_ending) return;
    setState(() => _ending = true);

    try {
      await ref.read(callSessionProvider.notifier).hangUp();
    } on Failure catch (e) {
      // The session folds terminate's Failure into `errorMessage` and ends the
      // call anyway, so this is a backstop rather than the expected path. It
      // stays because the alternative — one escaping Failure — leaves the agent
      // on a live-call screen whose only exit no longer responds.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  /// Hands the call over to the outcome screen once it is over.
  ///
  /// `pushReplacement` rather than `push`: a finished call must not stay on the
  /// stack under its own summary, or the back gesture returns to a dead screen
  /// showing a timer that stopped. The name travels as `extra` so the summary
  /// can name the person without re-fetching the contact.
  void _onSession(CallSessionState? previous, CallSessionState next) {
    if (_left || next.phase != CallPhase.ended) return;
    if (previous?.phase == CallPhase.ended) return;
    _left = true;
    context.pushReplacement(
      AppRoutes.callEnded(widget.contactUid),
      extra: widget.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CallSessionState session = ref.watch(callSessionProvider);

    ref.listen<CallSessionState>(callSessionProvider, _onSession);

    return PopScope(
      // A live call is not something to walk away from silently. Back ends it
      // through the same path as the button — the alternative leaves the peer
      // connection and the microphone running behind whatever screen the agent
      // landed on next.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _hangUp();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Dark status-bar glyphs are unreadable on brand green, and this is the
        // one screen in the app that is green edge to edge.
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColor.brandDeep,
          body: DecoratedBox(
            // Bright brand at the top, deep at the bottom: the avatar disc is
            // brandDeep, so it needs the light end of the ramp behind it, while
            // the controls read better against the dark end.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topCenter,
                end: AlignmentDirectional.bottomCenter,
                colors: <Color>[AppColor.brand, AppColor.brandDeep],
              ),
            ),
            child: SafeArea(
              // Spaced by flex when there is room and scrolled when there is
              // not. The fixed parts of this screen come to roughly 400pt, which
              // is taller than a phone in landscape and taller again at a large
              // text scale — and the control that ends the call is the last
              // thing that may fall off the bottom.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppDimens.gutter,
                  ),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    // IntrinsicHeight, because the Spacers inside need a bounded
                    // main axis: in a scroll view without it they assert.
                    child: IntrinsicHeight(child: _content(l10n, session)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(AppLocalizations l10n, CallSessionState session) {
    return Column(
      children: <Widget>[
        const Spacer(flex: 3),
        InitialsAvatar.onBrand(name: _display, size: 128),
        const SizedBox(height: 26),
        Text(
          _display,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _phaseLabel(l10n, session),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        // Only once there is a call to measure. A 00:00 printed while the peer
        // connection is still coming up claims a conversation that has not
        // started.
        if (session.elapsed > Duration.zero)
          Text(
            formatCallElapsed(session.elapsed),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              // Tabular figures: the timer is centred and would shuffle
              // sideways once a second otherwise.
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        if (session.errorMessage != null) ...<Widget>[
          const SizedBox(height: 14),
          // Shown in place rather than as a snackbar: a call that drops lands in
          // `failed`, which stays on this screen, so the reason has to remain
          // readable next to the hang-up that is now the way out. A snackbar
          // would take it away after four seconds.
          Text(
            session.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        ],
        const Spacer(flex: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          // Top-aligned so a two-line label under one control does not push the
          // other two circles up out of line with it.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CallControl(
              icon: session.muted ? Icons.mic_off : Icons.mic,
              // The label names what the tap does, so it inverts against the
              // state the icon reports.
              label: session.muted ? l10n.clUnmute : l10n.clMute,
              toggled: session.muted,
              onPressed: () =>
                  ref.read(callSessionProvider.notifier).toggleMute(),
            ),
            _CallControl(
              icon: session.speakerOn ? Icons.volume_up : Icons.volume_down,
              // One key for both positions — the ARB has no "speaker off"
              // string, so the state lives in the icon, the fill and the toggled
              // semantics rather than in copy invented here.
              label: l10n.clSpeaker,
              toggled: session.speakerOn,
              onPressed: () =>
                  ref.read(callSessionProvider.notifier).toggleSpeaker(),
            ),
            _CallControl(
              icon: Icons.call_end,
              label: l10n.clHangUp,
              destructive: true,
              busy: _ending,
              onPressed: _ending ? null : _hangUp,
            ),
          ],
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

/// `mm:ss`, and `h:mm:ss` once a call passes the hour.
///
/// Hand-rolled rather than pulled from a package: this is the only duration the
/// app renders, and no formatter already in the tree spells a call timer this
/// way. Shared with the ended screen so one call cannot read `04:07` while it
/// runs and `4:07` after it stops.
String formatCallElapsed(Duration elapsed) {
  // Clamped because a clock adjustment mid-call is the one way this goes
  // negative, and `-1:-05` on screen would look like a crash.
  final int total = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final String seconds = (total % 60).toString().padLeft(2, '0');
  final String minutes = (total ~/ 60 % 60).toString().padLeft(2, '0');
  final int hours = total ~/ 3600;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// The line under the name.
///
/// Every phase is spelled out rather than defaulting to "In call". This screen
/// is normally entered on connect, but the session can hand it `connecting`
/// during the gap between accept and first media, and it drops back there if the
/// peer connection renegotiates — claiming an active call through a silence the
/// agent can hear is worse than saying nothing.
String _phaseLabel(AppLocalizations l10n, CallSessionState session) =>
    switch (session.phase) {
      CallPhase.active => l10n.clActive,
      CallPhase.idle || CallPhase.connecting => l10n.clConnecting,
      CallPhase.ringing => (session.call?.isIncoming ?? false)
          ? l10n.clIncoming
          : l10n.clOutgoing,
      CallPhase.ended => l10n.clEnded,
      CallPhase.failed => l10n.clFailed,
      CallPhase.permissionDenied => l10n.clMicDenied,
    };

/// One round control with its caption underneath.
///
/// The three of them are the whole interface of a live call, so they are sized
/// for a thumb on a phone held to an ear (68pt, well over the 48pt minimum)
/// rather than for the density of the rest of the app.
class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.toggled,
    this.destructive = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Null for hang-up: it is an action, not a switch, and announcing it as an
  /// off switch would invite a second tap.
  final bool? toggled;
  final bool destructive;
  final bool busy;

  static const double _size = 68;

  @override
  Widget build(BuildContext context) {
    final Color background = destructive
        ? AppColor.danger
        : (toggled ?? false)
            ? Colors.white
            : Colors.white24;
    final Color foreground = destructive
        ? Colors.white
        : (toggled ?? false)
            ? AppColor.brandDeep
            : Colors.white;

    return Semantics(
      button: true,
      label: label,
      toggled: toggled,
      enabled: onPressed != null,
      // The action is declared here and the descendants are excluded, so the
      // control announces once — as one labelled, toggleable button — instead of
      // once for the ink well and again for the caption below it.
      onTap: onPressed,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            color: background,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: _size,
                height: _size,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        )
                      : Icon(icon, size: 28, color: foreground),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            // Capped so the Arabic labels, which run longer than the English
            // ones, wrap under their own control instead of shoving the row.
            width: 96,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
