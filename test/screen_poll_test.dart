import 'package:clickalize/core/util/screen_poll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timer that makes the inbox and an open conversation live.
///
/// This started as a `Timer.periodic` inside the providers. The smoke test
/// caught it: "A Timer is still pending even after the widget tree was
/// disposed." That was not a test artefact — a provider does not know when it
/// is visible, and autoDispose runs a frame late, so the timer really did
/// outlive the screen. `State.dispose` is synchronous and exact, so the timer
/// moved here.
class _Probe extends StatefulWidget {
  const _Probe({required this.onTick, this.delay = Duration.zero});

  final VoidCallback onTick;
  final Duration delay;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with ScreenPoll<_Probe> {
  @override
  Duration get pollInterval => const Duration(seconds: 5);

  @override
  Future<void> onPoll() async {
    widget.onTick();
    if (widget.delay > Duration.zero) await Future<void>.delayed(widget.delay);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('it ticks on the interval, not before', (WidgetTester t) async {
    int ticks = 0;
    await t.pumpWidget(_app(_Probe(onTick: () => ticks++)));

    await t.pump(const Duration(seconds: 4));
    expect(ticks, 0, reason: 'nothing fires early');

    await t.pump(const Duration(seconds: 2));
    expect(ticks, 1);

    await t.pump(const Duration(seconds: 5));
    expect(ticks, 2);
  });

  testWidgets('it stops the moment the screen goes', (WidgetTester t) async {
    int ticks = 0;
    await t.pumpWidget(_app(_Probe(onTick: () => ticks++)));
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 1);

    // Replacing the tree disposes the State. If the timer survived this, the
    // test framework would fail the test with a pending-timer assertion — which
    // is exactly how the provider-owned version was found.
    await t.pumpWidget(_app(const SizedBox.shrink()));
    await t.pump(const Duration(seconds: 30));
    expect(ticks, 1, reason: 'no ticks after dispose');
  });

  testWidgets('a slow tick does not stack up behind itself', (
    WidgetTester t,
  ) async {
    int ticks = 0;
    await t.pumpWidget(
      _app(_Probe(onTick: () => ticks++, delay: const Duration(seconds: 12))),
    );

    // Three intervals pass while the first request is still in flight. Without
    // the in-flight guard those would queue and land together, which on a slow
    // connection turns one stale screen into a burst of four requests.
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 1);

    // Once it finishes, the next interval is served normally.
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 2);

    // Let the second slow tick's own delay drain, then take the screen away —
    // otherwise the test ends with this test's fixture pending, not the
    // mixin's timer.
    await t.pumpWidget(_app(const SizedBox.shrink()));
    await t.pump(const Duration(seconds: 15));
  });

  testWidgets('a covered screen does not poll', (WidgetTester t) async {
    int ticks = 0;
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(body: _Probe(onTick: () => ticks++)),
      ),
    );
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 1);

    // Opening the actions sheet, a picker or the contact keeps this State
    // alive. Without the route check every screen in the stack would poll.
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    );
    await t.pumpAndSettle();

    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 1, reason: 'covered');

    nav.currentState!.pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    expect(ticks, 2, reason: 'uncovered again');
  });
}
