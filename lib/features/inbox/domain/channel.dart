import 'package:flutter/material.dart';

/// Which network a conversation arrives over.
///
/// Defaulted server-side, so it is never null — but it is never absent from a
/// payload either, which is why an unknown value maps to [whatsapp] rather
/// than to a third "unknown" state that no screen would know how to draw.
enum MessageChannel { whatsapp, instagram }

extension MessageChannelX on MessageChannel {
  static MessageChannel fromApi(Object? raw) {
    return '${raw ?? ''}'.trim().toLowerCase() == 'instagram'
        ? MessageChannel.instagram
        : MessageChannel.whatsapp;
  }

  bool get isInstagram => this == MessageChannel.instagram;

  /// Brand marks, not theme tokens.
  ///
  /// These are WhatsApp's and Instagram's own colours and must not be swapped
  /// for the app's palette: the badge means "this is that network", and a
  /// green Instagram badge would be actively misleading. This is the one place
  /// in the app where a raw hex is correct.
  Color get badgeColor => this == MessageChannel.instagram
      ? const Color(0xFFE0356C)
      : const Color(0xFF25D366);

  /// Filled glyphs on purpose. At 12px a 2px stroke turns to mush — the
  /// handoff records this being redrawn twice before it was legible.
  IconData get badgeIcon => this == MessageChannel.instagram
      ? Icons.camera_alt
      : Icons.chat;
}
