import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// Delivery state of an outgoing message, mirroring
/// `whatsapp_message_logs.status` on the backend.
enum MessageStatus { pending, sent, delivered, read, failed }

/// A single chat bubble.
///
/// Hugs its content up to [AppDimens.bubbleMaxWidth] (≈291), then wraps. Meta —
/// timestamp and status ticks — sits at the trailing edge on outgoing messages
/// and is inlined at the end of the text run so a short message keeps its
/// timestamp on the same line, which is what the frames show.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.text,
    required this.timeLabel,
    required this.isOutgoing,
    this.status,
    this.kindIcon,
    this.kindLabel,
    super.key,
  });

  final String text;

  /// Pre-formatted by the caller so this widget stays locale-agnostic.
  final String timeLabel;
  final bool isOutgoing;
  final MessageStatus? status;

  /// Type affordance for a non-text message — a glyph and a translated name
  /// shown above the body.
  ///
  /// Passed in rather than derived here so this widget keeps knowing nothing
  /// about the message model or about localisation. Both null for plain text,
  /// which renders exactly as it always has.
  final IconData? kindIcon;
  final String? kindLabel;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    final Color background = isOutgoing
        ? (isLight ? AppColor.bubbleOut : const Color(0xFF1F3A26))
        : (isLight ? Colors.white : AppColor.surfaceDark);

    return Align(
      alignment: isOutgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: AppDimens.bubbleMaxWidth),
        margin: const EdgeInsetsDirectional.symmetric(vertical: 3),
        padding: const EdgeInsetsDirectional.only(
          start: 11,
          end: 9,
          top: 7,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(12),
            topEnd: const Radius.circular(12),
            bottomStart: Radius.circular(isOutgoing ? 12 : 3),
            bottomEnd: Radius.circular(isOutgoing ? 3 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The type line. A photo, an order or a location says almost
            // nothing through its text — an order carries none at all — so
            // without this the bubble is blank and reads as a rendering fault
            // rather than as content the app cannot show inline.
            if (kindLabel != null) ...<Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (kindIcon != null) ...<Widget>[
                    Icon(
                      kindIcon,
                      size: 15,
                      color: isOutgoing ? AppColor.brandDeep : AppColor.inkMuted,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      kindLabel!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isOutgoing
                                ? AppColor.brandDeep
                                : AppColor.inkMuted,
                          ),
                    ),
                  ),
                ],
              ),
              if (text.isNotEmpty) const SizedBox(height: 4),
            ],
            if (text.isNotEmpty)
              Text(
                text,
                style:
                    Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 10.5, color: AppColor.inkFaint),
                ),
                if (isOutgoing && status != null) ...<Widget>[
                  const SizedBox(width: 3),
                  _StatusTicks(status: status!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTicks extends StatelessWidget {
  const _StatusTicks({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      MessageStatus.pending => (Icons.schedule, AppColor.inkFaint),
      MessageStatus.sent => (Icons.check, AppColor.inkFaint),
      MessageStatus.delivered => (Icons.done_all, AppColor.inkFaint),
      MessageStatus.read => (Icons.done_all, AppColor.info),
      MessageStatus.failed => (Icons.error_outline, AppColor.danger),
    };

    return Icon(icon, size: 13, color: color);
  }
}

/// Centered day separator between message groups ("Today", "Yesterday", a date).
class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColor.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColor.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
