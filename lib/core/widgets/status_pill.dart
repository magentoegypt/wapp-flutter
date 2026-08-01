import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Semantic tone for state chips and banners.
///
/// Deliberately separate from the brand accent: the handoff is explicit that
/// success green (#067647) is darker than brand green and must never be used
/// as an accent — a "positive" metric does not get to borrow the brand hue.
enum StatusTone { success, warning, info, danger, neutral }

extension StatusToneColors on StatusTone {
  Color get foreground => switch (this) {
    StatusTone.success => AppColor.success,
    StatusTone.warning => AppColor.warning,
    StatusTone.info => AppColor.info,
    StatusTone.danger => AppColor.danger,
    StatusTone.neutral => AppColor.inkMuted,
  };

  Color get background => switch (this) {
    StatusTone.success => AppColor.successWash,
    StatusTone.warning => AppColor.warningWash,
    StatusTone.info => AppColor.infoWash,
    StatusTone.danger => AppColor.dangerWash,
    StatusTone.neutral => AppColor.surfaceAlt,
  };
}

/// Dot + label on a semantic wash. Used for conversation state (open, pending,
/// solved), campaign state, and agent availability.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.tone,
    this.showDot = true,
    this.showChevron = false,
    super.key,
  });

  final String label;
  final StatusTone tone;
  final bool showDot;

  /// A trailing caret, for a pill that opens a menu.
  ///
  /// The chat header's status pill *is* a dropdown and drew nothing to say so —
  /// the frame (37:1032) puts a caret inside it. Without one the only clue that
  /// a conversation's status is changeable was tapping it to find out.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tone.foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tone.foreground,
            ),
          ),
          if (showChevron) ...<Widget>[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: tone.foreground,
            ),
          ],
        ],
      ),
    );
  }
}
