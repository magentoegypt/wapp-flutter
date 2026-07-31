import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/error/failure.dart';
import '../domain/call.dart';
import 'call_repository.dart';

/// Where the live session is, as opposed to [CallStatus] which is what the
/// server thinks of the call row.
///
/// The two disagree on purpose and must not be merged: the server can still be
/// reporting `ringing` while the microphone here is already open, and it keeps
/// reporting `completed` long after this notifier has been thrown away. This
/// enum is about *this device*.
enum CallPhase {
  idle,

  /// The user refused the microphone, so nothing else can be attempted. The
  /// screen offers [CallSessionController.openMicrophoneSettings] from here —
  /// see that method for why settings are never opened on our own initiative.
  permissionDenied,

  /// Signalling and ICE are in flight. Nothing is audible yet.
  connecting,

  /// The far end has been reached and is being alerted.
  ringing,

  /// Media is flowing. Only in this phase does [CallSessionState.elapsed] move.
  active,

  /// Finished normally — hung up here, rejected here, or closed by the far end.
  ended,

  /// Finished abnormally, or never started. See [CallSessionState.errorMessage]
  /// and [CallSessionState.restrictedReason].
  failed,
}

/// Everything the call screens need, and nothing that is a WebRTC type.
///
/// The peer connection, the media stream and the timer live in the controller
/// as private fields precisely so they cannot leak into a widget: a screen that
/// could reach the [MediaStream] could also outlive it.
@immutable
class CallSessionState {
  const CallSessionState({
    this.phase = CallPhase.idle,
    this.call,
    this.muted = false,
    this.speakerOn = false,
    this.errorMessage,
    this.restrictedReason,
    this.elapsed = Duration.zero,
  });

  final CallPhase phase;

  /// The row this session is attached to. Null before [CallRepository.place]
  /// returns, which is why the outgoing screen has a contact but no call for
  /// the first moment.
  final CallRecord? call;
  final bool muted;
  final bool speakerOn;

  /// A complete, user-safe sentence that came from the server via
  /// [Failure.message]. Show it as-is; never wrap it in another string.
  final String? errorMessage;

  /// A *fragment* — on this workspace it reads "USA / Canada" — and not a
  /// sentence, so it is kept apart from [errorMessage] rather than sharing the
  /// slot. The screen feeds it to `l10n.clRestricted(reason)`; showing it raw
  /// would print a country list where an explanation belongs.
  ///
  /// Non-null only when the capability gate refused an outbound call *and* gave
  /// a reason. A refusal with no reason (calling switched off for the
  /// workspace, or outside business hours) leaves this null and the screen
  /// falls back to `l10n.clUnavailable` / `l10n.clDisabled`.
  final String? restrictedReason;

  /// Time since media started, not since the user pressed the button — dialling
  /// and ringing are not billable and are not what a duration means to anyone.
  final Duration elapsed;

  /// Whether a session is already under way. Guards the entry points so a
  /// double tap on Call cannot open a second microphone.
  bool get isBusy =>
      phase == CallPhase.connecting ||
      phase == CallPhase.ringing ||
      phase == CallPhase.active;

  /// True once nothing more will happen without the user acting again.
  bool get isFinished => phase == CallPhase.ended || phase == CallPhase.failed;

  CallSessionState copyWith({
    CallPhase? phase,
    CallRecord? call,
    bool? muted,
    bool? speakerOn,
    String? errorMessage,
    String? restrictedReason,
    Duration? elapsed,
    bool clearCall = false,
    bool clearError = false,
  }) {
    return CallSessionState(
      phase: phase ?? this.phase,
      call: clearCall ? null : (call ?? this.call),
      muted: muted ?? this.muted,
      speakerOn: speakerOn ?? this.speakerOn,
      // One flag clears both message slots: they describe the same failure from
      // two angles, and leaving one behind would caption the next attempt with
      // the reason the previous one died.
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      restrictedReason:
          clearError ? null : (restrictedReason ?? this.restrictedReason),
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

/// The one place in the app that touches flutter_webrtc.
///
/// Screens talk to this and never import the plugin: WebRTC objects are native
/// handles with a manual lifetime, and a widget that holds one keeps it alive
/// for as long as the element tree feels like keeping the widget. Funnelling
/// every handle through a single autoDispose notifier makes "who closes this"
/// answerable in one file.
class CallSessionController extends AutoDisposeNotifier<CallSessionState> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Timer? _ticker;
  DateTime? _activeSince;
  bool _disposed = false;

  /// How long to keep asking for the far end's session description.
  ///
  /// Signalling here is HTTP, not a socket, so the remote SDP has to be pulled.
  /// The bound is the point: an unbounded poll on a call nobody answers holds
  /// the microphone open indefinitely.
  static const Duration _sdpPollInterval = Duration(seconds: 1);
  static const int _sdpPollAttempts = 15;

  @override
  CallSessionState build() {
    // Registered before anything can be created, so no early-return or thrown
    // exception below can leave a native handle with nobody to close it. A peer
    // connection that outlives this notifier keeps the microphone live — the OS
    // recording indicator stays lit and the far end keeps hearing the room
    // after the user believes the call is over.
    ref.onDispose(() {
      _disposed = true;
      unawaited(_release());
    });
    return const CallSessionState();
  }

  /// Riverpod 2.6 exposes no `mounted` on `Notifier`, and writing `state` after
  /// disposal throws. Every await in this file is followed by a check of this.
  bool get mounted => !_disposed;

  CallRepository get _repo => ref.read(callRepositoryProvider);

  // ---------------------------------------------------------------- permission

  /// Asks for the microphone, and reports whether it may be used.
  ///
  /// Returns false *and* moves the phase to [CallPhase.permissionDenied] on
  /// refusal, so callers can early-return on the boolean while the screen still
  /// gets something to render.
  Future<bool> ensureMicPermission() async {
    try {
      final PermissionStatus status = await Permission.microphone.request();
      if (!mounted) return false;

      // `limited` counts as granted: it is an iOS partial grant that still
      // yields a usable capture device, and refusing it would strand a user who
      // did say yes.
      if (status.isGranted || status.isLimited) return true;

      // Permanent and one-off denial land in the same phase. They differ only
      // in whether a second request() would prompt again, and the screen's
      // remedy — try again, or open settings — is safe either way, so a second
      // state flag would buy nothing but a branch to get wrong.
      state = state.copyWith(phase: CallPhase.permissionDenied, clearError: true);
      return false;
    } catch (error) {
      // permission_handler throws PlatformException (and MissingPluginException
      // on a platform with no permission model at all). Neither is a Failure,
      // so the repository-shaped catch below would miss it, and neither may
      // escape a tap handler.
      debugPrint('[call] microphone permission request failed: $error');
      if (!mounted) return false;
      state = state.copyWith(phase: CallPhase.permissionDenied, clearError: true);
      return false;
    }
  }

  /// Sends the user to the OS settings page for this app.
  ///
  /// Only ever called from an explicit tap. Opening settings on our own the
  /// moment a permission is refused throws the user out of the app for a call
  /// they may have decided against — the refusal is an answer, not an error to
  /// be routed around.
  Future<void> openMicrophoneSettings() async {
    try {
      await openAppSettings();
    } catch (error) {
      debugPrint('[call] could not open app settings: $error');
    }
  }

  // ------------------------------------------------------------------ outgoing

  /// Places a call to [contactUid].
  ///
  /// Capability is checked before anything else, and deliberately before the
  /// microphone prompt: asking for the microphone and *then* refusing the call
  /// teaches the user that the prompt is noise. On this workspace Meta blocks
  /// outbound calling for USA/Canada numbers, so `canPlaceCall` is false and
  /// the refusal below is the branch that actually runs.
  Future<void> startOutgoing(String contactUid) async {
    if (state.isBusy) return;
    state = const CallSessionState(phase: CallPhase.connecting);

    try {
      final CallCapability capability = await _repo.capability();
      if (!mounted) return;

      if (!capability.canPlaceCall) {
        // Branch on the server's own conjunction rather than re-deriving it
        // from `enabled` + `outboundSupported` + business hours; a client that
        // recomputes the rule drifts from the engine and starts placing calls
        // the API will reject.
        state = state.copyWith(
          phase: CallPhase.failed,
          restrictedReason: capability.outboundRestrictedReason,
        );
        return;
      }

      if (!await ensureMicPermission()) return;
      if (!mounted) return;

      final CallRecord placed = await _repo.place(contactUid);
      if (!mounted) return;
      // Ringing, not active: `place` only means the request was accepted for
      // delivery — nobody has picked up.
      state = state.copyWith(phase: CallPhase.ringing, call: placed);

      await _negotiate(placed, incoming: false);
    } on Failure catch (e) {
      await _failAndRelease(e.message);
    }
  }

  // ------------------------------------------------------------------ incoming

  /// Answers a ringing call.
  Future<void> acceptIncoming(CallRecord call) async {
    if (state.isBusy) return;
    // The record is stored before the permission prompt so that a refusal still
    // leaves the screen something to decline.
    state = CallSessionState(phase: CallPhase.connecting, call: call);

    if (!await ensureMicPermission()) return;
    if (!mounted) return;

    await _negotiate(call, incoming: true);
  }

  /// Declines a ringing call without ever opening the microphone.
  Future<void> reject(CallRecord call) async {
    String? message;
    try {
      // uid, not callId — callId is Meta's `wacid.…` and this endpoint 404s on
      // it.
      await _repo.reject(call.uid);
    } on Failure catch (e) {
      message = e.message;
    }

    // Torn down regardless of what the server said. The user declined; leaving
    // a half-built session alive because a request failed would be the one
    // outcome they explicitly asked not to have.
    await _release();
    if (!mounted) return;
    state = state.copyWith(
      phase: CallPhase.ended,
      call: call,
      errorMessage: message,
      // Cleared when the reject succeeded, so a message left over from an
      // earlier attempt does not caption a clean decline.
      clearError: message == null,
    );
    _refreshPending();
  }

  /// Ends whatever is running, from any phase.
  Future<void> hangUp() async {
    final CallRecord? call = state.call;
    String? message;

    if (call != null) {
      try {
        await _repo.terminate(call.uid);
      } on Failure catch (e) {
        message = e.message;
      }
    }

    // Read the clock one last time before the ticker dies, so the ended screen
    // shows the duration the call actually had rather than whatever the last
    // whole second happened to be.
    final Duration finalElapsed = _elapsedNow();
    await _release();
    if (!mounted) return;
    state = state.copyWith(
      phase: CallPhase.ended,
      elapsed: finalElapsed,
      errorMessage: message,
      clearError: message == null,
    );
    _refreshPending();
  }

  /// Returns the session to [CallPhase.idle] so the same screen can be reused
  /// for a second attempt — used by "call back" and by dismissing an error.
  void reset() {
    if (!mounted) return;
    state = const CallSessionState();
  }

  // ------------------------------------------------------------------- controls

  /// Mutes by disabling the track rather than by stopping it.
  ///
  /// A stopped track cannot be restarted, and re-running `getUserMedia` to
  /// unmute would re-trigger the OS capture indicator mid-call. `enabled =
  /// false` keeps the transport up and sends silence, which is what every
  /// dialer means by mute.
  void toggleMute() {
    final MediaStream? stream = _localStream;
    if (stream == null) return;

    final bool next = !state.muted;
    for (final MediaStreamTrack track in stream.getAudioTracks()) {
      track.enabled = !next;
    }
    if (!mounted) return;
    state = state.copyWith(muted: next);
  }

  /// Routes audio to the loudspeaker.
  Future<void> toggleSpeaker() async {
    final bool next = !state.speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (error) {
      // The route did not change, so the button must not either — a speaker
      // icon that lies about where the audio is going is worse than one that
      // did not move.
      debugPrint('[call] could not switch audio route: $error');
      return;
    }
    if (!mounted) return;
    state = state.copyWith(speakerOn: next);
  }

  // ---------------------------------------------------------------- negotiation

  /// Builds the peer connection and exchanges descriptions.
  ///
  /// Never throws: WebRTC failures are not user-safe strings (the plugin throws
  /// bare `String`s, not exceptions), so they are logged and surfaced as a
  /// generic failed phase that the screen captions with `l10n.clFailed`.
  Future<void> _negotiate(CallRecord call, {required bool incoming}) async {
    try {
      final List<Map<String, dynamic>> ice = await _repo.iceServers();
      if (!mounted) return;

      // A plain map, not an `RTCConfiguration` object: flutter_webrtc 1.5.2
      // rides on webrtc_interface 1.5.1, where that class is commented out and
      // `createPeerConnection` takes `Map<String, dynamic>`.
      final Map<String, dynamic> configuration = <String, dynamic>{
        'iceServers': ice,
        // Named explicitly because plan-b is gone from libwebrtc and the
        // default has moved before; pinning it keeps the SDP shape stable
        // across plugin upgrades.
        'sdpSemantics': 'unified-plan',
      };

      final RTCPeerConnection pc = await createPeerConnection(configuration);
      _pc = pc;
      // Disposal can land while the native connection is being built. Nothing
      // else holds this handle at that point, so releasing here is the only
      // thing standing between the user and a live microphone.
      if (!mounted) {
        await _release();
        return;
      }
      pc.onConnectionState = _onConnectionState;

      final MediaStream stream = await navigator.mediaDevices.getUserMedia(
        // Audio only. `video: false` rather than omitted: an omitted key is
        // "unconstrained" to some implementations, and a call that silently
        // opens the camera is a privacy incident.
        <String, dynamic>{'audio': true, 'video': false},
      );
      _localStream = stream;
      if (!mounted || _pc != pc) {
        await _release();
        return;
      }

      for (final MediaStreamTrack track in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }
      if (!mounted || _pc != pc) return;

      if (incoming) {
        await _answer(pc, call);
      } else {
        await _offer(pc, call);
      }
    } on Failure catch (e) {
      await _failAndRelease(e.message);
    } catch (error, stack) {
      debugPrint('[call] negotiation failed: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      await _failAndRelease(null);
    }
  }

  /// Incoming: take the caller's offer, answer it, and hand the answer back
  /// through the accept endpoint.
  Future<void> _answer(RTCPeerConnection pc, CallRecord call) async {
    final String? offer = await _pollRemoteSdp(call.uid);
    if (!mounted || _pc != pc) return;
    if (offer == null || offer.isEmpty) {
      // The caller hung up before their description arrived, or the engine
      // never wrote one. Either way there is nothing to answer.
      await _failAndRelease(null);
      return;
    }

    await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    if (!mounted || _pc != pc) return;

    final RTCSessionDescription answer = await pc.createAnswer(_sdpConstraints);
    if (!mounted || _pc != pc) return;
    await pc.setLocalDescription(answer);
    if (!mounted || _pc != pc) return;

    // Accept carries the answer, so the server never has to poll us back.
    await _repo.accept(call.uid, sdpAnswer: answer.sdp);
    if (!mounted || _pc != pc) return;
    _refreshPending();
    // Phase stays where it is; `_onConnectionState` promotes to active only
    // once media is genuinely flowing. Declaring "in call" on an HTTP 200 shows
    // a running timer over silence.
  }

  /// Outgoing: offer, then wait for the far end's answer.
  ///
  /// The offer is only set locally. [CallRepository] has no endpoint that
  /// uploads an outbound offer — `accept(uid, sdpAnswer:)` is the only
  /// SDP-carrying call and it belongs to an incoming call's uid — so the
  /// engine is assumed to broker the offer from the `place` call itself. This
  /// path cannot be exercised on this workspace (outbound is refused before it
  /// is reached), and is the piece to re-check first when it can be.
  Future<void> _offer(RTCPeerConnection pc, CallRecord call) async {
    final RTCSessionDescription offer = await pc.createOffer(_sdpConstraints);
    if (!mounted || _pc != pc) return;
    await pc.setLocalDescription(offer);
    if (!mounted || _pc != pc) return;

    final String? answer = await _pollRemoteSdp(call.uid);
    if (!mounted || _pc != pc) return;
    if (answer == null || answer.isEmpty) {
      // Nobody picked up within the poll window.
      await _endQuietly();
      return;
    }

    await pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
  }

  /// Legacy `mandatory`/`optional` shape, which is what the native side of
  /// flutter_webrtc 1.5.2 still expects — the modern `offerToReceiveAudio` key
  /// is ignored there and the call comes up send-only.
  static const Map<String, dynamic> _sdpConstraints = <String, dynamic>{
    'mandatory': <String, dynamic>{
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': <Object>[],
  };

  /// Pulls the far end's description until it exists or the window closes.
  Future<String?> _pollRemoteSdp(String callUid) async {
    for (int attempt = 0; attempt < _sdpPollAttempts; attempt++) {
      String? sdp;
      try {
        sdp = await _repo.sdp(callUid);
      } on NotFoundFailure {
        // Expected, repeatedly: the row exists but the description has not been
        // written yet. Treated as "not ready", not as an error, or every call
        // would die on its first poll.
        sdp = null;
      }
      if (!mounted) return null;
      if (sdp != null && sdp.isNotEmpty) return sdp;

      await Future<void>.delayed(_sdpPollInterval);
      if (!mounted) return null;
    }
    return null;
  }

  // -------------------------------------------------------------- connection

  void _onConnectionState(RTCPeerConnectionState pcState) {
    if (!mounted) return;
    // Terminal phases are absorbing: `close()` in _release fires this callback
    // one last time, and letting that overwrite an `ended` set by hangUp would
    // replace the duration screen with a failure.
    if (state.isFinished) return;

    switch (pcState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _startTicker();
        state = state.copyWith(phase: CallPhase.active, clearError: true);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        unawaited(_failAndRelease(null));
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        // Disconnected is recoverable in principle via an ICE restart, but this
        // signalling channel cannot renegotiate — there is no endpoint to push
        // a new offer through — so it is treated as the end of the call rather
        // than left hanging on a screen that will never recover.
        unawaited(_endQuietly());
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        // Left alone on purpose: the flow above has already set `ringing` for
        // an outbound call, and demoting that to `connecting` would flip the
        // caption from "Calling…" back a step while the phone is ringing.
        break;
    }
  }

  // ------------------------------------------------------------------ teardown

  /// Terminal failure: report it, then free everything.
  ///
  /// [message] is a [Failure.message] when one exists — a complete sentence the
  /// server wrote — and null when the cause was a WebRTC error, which is never
  /// fit to show. The screen captions null with `l10n.clFailed`.
  Future<void> _failAndRelease(String? message) async {
    await _release();
    if (!mounted) return;
    state = state.copyWith(
      phase: CallPhase.failed,
      errorMessage: message,
      clearError: message == null,
    );
  }

  /// Terminal but not an error — the far end went away, or nobody answered.
  Future<void> _endQuietly() async {
    final Duration finalElapsed = _elapsedNow();
    await _release();
    if (!mounted) return;
    state = state.copyWith(phase: CallPhase.ended, elapsed: finalElapsed);
    _refreshPending();
  }

  /// Frees every native resource this session created.
  ///
  /// A peer connection that is never closed keeps the audio session, and with
  /// it the microphone, live: the OS recording indicator stays on and the far
  /// end can still hear the room long after the user thinks the call ended.
  /// That is a privacy failure rather than untidiness, which is why this runs
  /// on every terminal path *and* from `ref.onDispose`, and why it is written
  /// to be safe to call twice.
  Future<void> _release() async {
    _ticker?.cancel();
    _ticker = null;
    _activeSince = null;

    // Fields are cleared first so a concurrent path finds nothing to double
    // close, and so `_pc != pc` guards in the negotiation abort cleanly.
    final RTCPeerConnection? pc = _pc;
    _pc = null;
    final MediaStream? stream = _localStream;
    _localStream = null;

    // Detached before closing: `close()` fires onConnectionState, and that
    // handler writes `state`, which throws once the notifier is disposed.
    pc?.onConnectionState = null;
    pc?.onIceCandidate = null;

    if (stream != null) {
      // stop() before dispose(), and every track rather than just the audio
      // ones: dispose() releases the Dart-side handle, while stop() is what
      // actually turns the capture device off at the OS level.
      for (final MediaStreamTrack track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (error) {
          debugPrint('[call] track stop failed: $error');
        }
      }
      try {
        await stream.dispose();
      } catch (error) {
        debugPrint('[call] stream dispose failed: $error');
      }
    }

    if (pc != null) {
      // Each step is guarded separately: the plugin throws bare strings, and
      // one failing step must not skip the ones after it — dispose() is what
      // releases the native peer connection object.
      try {
        await pc.close();
      } catch (error) {
        debugPrint('[call] peer connection close failed: $error');
      }
      try {
        await pc.dispose();
      } catch (error) {
        debugPrint('[call] peer connection dispose failed: $error');
      }
    }
  }

  // -------------------------------------------------------------------- timing

  void _startTicker() {
    if (_ticker != null) return;
    _activeSince = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        // Belt and braces — _release cancels this — but a periodic timer that
        // survives its notifier writes to a disposed state once per second.
        timer.cancel();
        return;
      }
      state = state.copyWith(elapsed: _elapsedNow());
    });
  }

  /// Derived from the instant media started rather than counted up per tick.
  /// A timer that misses beats while the app is backgrounded would otherwise
  /// report a call shorter than it was, and this number gets compared against
  /// the web console's duration for the same call.
  Duration _elapsedNow() {
    final DateTime? since = _activeSince;
    if (since == null) return state.elapsed;
    return DateTime.now().difference(since);
  }

  /// The incoming-call list is a snapshot; every terminal transition here makes
  /// one of its rows a lie.
  void _refreshPending() {
    if (!mounted) return;
    ref.invalidate(pendingCallsProvider);
  }
}

final callSessionProvider =
    NotifierProvider.autoDispose<CallSessionController, CallSessionState>(
  CallSessionController.new,
);
