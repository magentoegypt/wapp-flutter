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

  /// Document extensions this channel accepts, lowercase and without the dot.
  ///
  /// Instagram takes **PDF only**; WhatsApp takes Meta's wider office set. It
  /// lives here rather than in the attach sheet because it is a fact about the
  /// network, and because the sheet needs it twice — once to filter the picker
  /// and once to re-check afterwards, since some pickers ignore the filter.
  ///
  /// The server remains authoritative. This narrows what can be chosen so a
  /// refusal arrives before the upload rather than after it.
  List<String> get documentExtensions => this == MessageChannel.instagram
      ? const <String>['pdf']
      : const <String>[
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
        ];

  bool acceptsDocument(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    // No extension at all is not a document this can vouch for. Letting it
    // through would upload the file and learn the answer from a 422.
    if (dot < 0 || dot == fileName.length - 1) return false;
    return documentExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

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
