import 'dart:async';

import 'package:flutter/widgets.dart';

/// Re-runs [onPoll] on an interval while the screen is on top and the app is
/// in the foreground.
///
/// This API has no websocket and no push channel, so a timer is the only way
/// the inbox and an open conversation stay current. Everything here is about
/// not making that worse than the staleness it fixes:
///
/// * **The screen owns the timer, not a provider.** A provider does not know
///   when it is visible — another listener can keep it alive — and autoDispose
///   runs a frame late, which leaves a timer ticking over a torn-down tree.
///   `State.dispose` is synchronous and exact.
/// * **Backgrounded means stopped.** A phone in a pocket should not be
///   spending the user's data on pixels nobody is looking at. The tick resumes
///   on the way back, and fires once immediately so returning to the app shows
///   current state rather than whatever was there when it was locked.
/// * **Covered means stopped.** Pushing a route over this one (the actions
///   sheet, the contact, a picker) keeps the State alive, so without a route
///   check a stack of screens would all poll at once.
/// * **No overlap.** A tick that is still in flight when the next fires is
///   skipped rather than queued, so a slow network cannot build a backlog of
///   requests that all land together.
mixin ScreenPoll<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _inFlight = false;

  /// How often to poll. Screens override this.
  Duration get pollInterval;

  /// The work. Errors are the implementation's to swallow — a failed poll must
  /// never replace a working screen with an error state.
  Future<void> onPoll();

  /// Set false to suspend polling without tearing the timer down.
  ///
  /// The route check below only sees the nearest Navigator. A screen inside a
  /// shell branch stays "current" within that branch while a route is pushed
  /// over the whole shell, so such a screen must say so here — otherwise it
  /// keeps polling underneath whatever covered it.
  bool get pollEnabled => true;

  @override
  void initState() {
    super.initState();
    // AppLifecycleListener rather than the WidgetsBindingObserver mixin: it is
    // a plain object, so this stays a mixin any State can add without also
    // inheriting sixteen callbacks it does not implement.
    _lifecycle = AppLifecycleListener(onResume: _tick);
    _timer = Timer.periodic(pollInterval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted || _inFlight || !pollEnabled) return;
    // Null means the framework has not reported a lifecycle yet, which is the
    // case on a cold start — the screen is on and visible. Treating that as
    // "not resumed" would leave a freshly-opened app not polling until the
    // first lifecycle event happened to arrive.
    final AppLifecycleState? lifecycle =
        WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    // `isCurrent` is relative to the *nearest* Navigator, which is enough for
    // a screen pushed onto the navigator it lives on. A screen inside a shell
    // branch needs more than this — see [pollEnabled] and the inbox's
    // override.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _inFlight = true;
    try {
      await onPoll();
    } finally {
      _inFlight = false;
    }
  }
}
