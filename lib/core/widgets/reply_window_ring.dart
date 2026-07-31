import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Live countdown on WhatsApp's 24-hour customer-service window, drawn as a
/// ring around the remaining time.
///
/// It exists to give an agent one glanceable answer to "can I still type a free
/// reply to this person?". Under an hour the ring and digits go red, because
/// that is the moment the answer is about to become no and every message after
/// it has to be an approved template.
///
/// The arc is hand-drawn with a [CustomPainter] — one stroked circle and one
/// stroked sweep is not worth a charting dependency.
class ReplyWindowRing extends StatefulWidget {
  const ReplyWindowRing({
    required this.expiresAt,
    required this.windowOpen,
    this.size = 36,
    super.key,
  });

  /// When the current service window lapses. Meaningless on its own — see
  /// [windowOpen].
  final DateTime? expiresAt;

  /// Whether there is an open window at all, and the **only** thing this widget
  /// gates on.
  ///
  /// The API never clears `conversationExpiresAt` when the window closes: it
  /// keeps the historical timestamp forever. A client that reads non-null as
  /// "open" therefore renders a countdown that already ran out — or a negative
  /// one — on every long-dormant conversation. Gate on the flag, and treat the
  /// timestamp as detail that only matters once the flag says it does.
  final bool windowOpen;

  /// Diameter. The default sits inside the 96px back-nav header without
  /// crowding the avatar beside it.
  final double size;

  @override
  State<ReplyWindowRing> createState() => _ReplyWindowRingState();
}

class _ReplyWindowRingState extends State<ReplyWindowRing> {
  /// The window Meta grants, and therefore the full sweep of the ring.
  static const Duration _window = Duration(hours: 24);

  /// Below this the ring turns red — the cue that free-form replies are about
  /// to stop working.
  static const Duration _urgent = Duration(hours: 1);

  static const Color _amber = Color(0xFFF5A623);
  static const Color _red = Color(0xFFFF4D4F);

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ReplyWindowRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A thread reload can hand us a fresh deadline, or close the window
    // outright, so the clock has to be re-evaluated rather than left running
    // against the old one.
    if (oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.windowOpen != widget.windowOpen) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Time left, or [Duration.zero] whenever there is nothing to count down.
  ///
  /// Zero covers three cases deliberately collapsed into one: no open window,
  /// no deadline, and a deadline that has already passed. The last one matters
  /// because the deadline can lapse while the chat sits open on screen, long
  /// after the server sent `windowOpen: true`.
  Duration get _remaining {
    final DateTime? at = widget.expiresAt;
    if (!widget.windowOpen || at == null) return Duration.zero;
    final Duration left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Runs the one-second clock only while something is actually counting down.
  void _syncTicker() {
    if (_remaining > Duration.zero) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (Timer _) => _tick(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    // setState on this widget alone — the chat screen above it holds a message
    // list that must not rebuild once a second.
    setState(() {});
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final Duration left = _remaining;
    if (left <= Duration.zero) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String hours = left.inHours.toString().padLeft(2, '0');
    final String minutes = (left.inMinutes % 60).toString().padLeft(2, '0');
    final Color tint = left < _urgent ? _red : _amber;

    return Tooltip(
      message: l10n.rwTooltip(hours, minutes),
      child: Padding(
        // The ring owns the gap to whatever follows it. A sibling spacer would
        // survive the SizedBox.shrink above and leave a phantom indent in the
        // header on every closed conversation.
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: left.inSeconds / _window.inSeconds,
              tint: tint,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(_RingPainter.stroke + 1),
              child: FittedBox(
                // scaleDown, never contain: contain would happily inflate five
                // small digits until they touched the stroke.
                fit: BoxFit.scaleDown,
                child: Text(
                  '$hours:$minutes',
                  // Time remaining, not a clock reading, and never mirrored:
                  // under Arabic the paragraph runs right-to-left and the pair
                  // would be at the mercy of the bidi algorithm.
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: tint,
                    // Fixed-width digits, or the label jitters as the seconds
                    // roll a 1 into an 8.
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The track and the elapsed sweep.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.tint});

  /// Fraction of the 24-hour window still left, 0..1.
  final double progress;
  final Color tint;

  static const double stroke = 3;

  /// The ring only ever sits on the brand-green header, so the track is a wash
  /// of the ground rather than a palette colour.
  static const Color _track = Colors.white24;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke, which straddles the path — without this the
    // outer half of the ring is clipped by the widget's own bounds.
    final Rect box = (Offset.zero & size).deflate(stroke / 2);

    canvas.drawArc(
      box,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _track,
    );

    // -pi/2 is 12 o'clock, and a positive sweep runs clockwise because the
    // canvas y axis points down.
    canvas.drawArc(
      box,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = tint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tint != tint;
}
