import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';

/// The three pieces of chrome every full-screen call surface is built from.
///
/// Extracted rather than copied into each screen: the incoming and outgoing
/// surfaces differ only in how many action circles they draw and how they
/// phrase a refusal, and two copies of the backdrop would drift the moment one
/// of them is retouched. Nothing here knows about the session — the screens
/// map phase to copy and hand the result down.

/// The dark-green ground both call surfaces sit on.
///
/// A gradient rather than a flat fill so the action circles at the bottom sit
/// on near-black: [AppColor.danger] and [AppColor.success] are both mid-tone
/// and lose their edge against full brand green.
class CallBackdrop extends StatelessWidget {
  const CallBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topCenter,
          end: AlignmentDirectional.bottomCenter,
          colors: <Color>[AppColor.brandDeep, AppColor.groundDark],
        ),
      ),
      child: child,
    );
  }
}

/// A refusal, stated in place of the call status.
///
/// Given a card of its own rather than a red banner because on this workspace
/// these are not edge cases: Meta refuses outbound calling from this number
/// outright, so this panel is the screen an agent actually reads. It has to
/// look like an answer, not like a crash.
class CallTroublePanel extends StatelessWidget {
  const CallTroublePanel({
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Already localised, and already resolved against any server-supplied
  /// reason — this widget never picks between messages.
  final String message;
  final IconData icon;

  /// Both null on a dead end that the surrounding screen already has an exit
  /// from, so the panel does not grow a button that only repeats the hang-up.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? label = actionLabel;

    return Container(
      // Capped so the copy does not run edge to edge on a tablet, where a
      // full-width paragraph under a centred avatar reads as a layout bug.
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsetsDirectional.only(
        start: 18,
        end: 18,
        top: 18,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        // Translucent white rather than one of the wash tokens: every wash in
        // the palette is built for a light ground and turns to mud here.
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          if (label != null && onAction != null) ...<Widget>[
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onAction,
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the large circular call controls.
///
/// Sized well past the 48pt minimum because these are pressed in a hurry, often
/// one-handed, and the cost of hitting the wrong one is a dropped customer.
class RoundCallAction extends StatelessWidget {
  const RoundCallAction({
    required this.icon,
    required this.tint,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final String label;

  /// Null disables the control. The circle dims rather than disappearing so the
  /// row does not reflow when a phase change takes one action away — a button
  /// that moves under a thumb already travelling towards it gets mis-tapped.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            color: enabled ? tint : tint.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 74,
                height: 74,
                // Not mirrored in RTL: these are dialer glyphs the way every
                // phone draws them, not navigation, so flipping them in Arabic
                // would change what they mean.
                child: Icon(icon, color: Colors.white, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: enabled ? Colors.white : Colors.white54),
          ),
        ],
      ),
    );
  }
}
