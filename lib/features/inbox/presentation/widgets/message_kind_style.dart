import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/conversation.dart';

/// How each message kind announces itself in a bubble.
///
/// Kept out of [MessageBubble] so that widget stays free of both the message
/// model and localisation, and out of the screen so the mapping is in one place
/// when the next type is added.
class MessageKindStyle {
  const MessageKindStyle(this.icon, this.label);

  final IconData? icon;

  /// Null for plain text — the bubble then renders exactly as it always did.
  final String? label;

  static MessageKindStyle of(MessageKind kind, AppLocalizations l10n) {
    switch (kind) {
      case MessageKind.text:
        return const MessageKindStyle(null, null);

      case MessageKind.image:
        return MessageKindStyle(Icons.photo_outlined, l10n.mtImage);
      case MessageKind.video:
        return MessageKindStyle(Icons.videocam_outlined, l10n.mtVideo);
      case MessageKind.audio:
        return MessageKindStyle(Icons.mic_none, l10n.mtAudio);
      case MessageKind.document:
        return MessageKindStyle(Icons.description_outlined, l10n.mtDocument);
      case MessageKind.sticker:
        return MessageKindStyle(Icons.emoji_emotions_outlined, l10n.mtSticker);

      case MessageKind.location:
        return MessageKindStyle(Icons.place_outlined, l10n.mtLocation);
      case MessageKind.locationRequest:
        return MessageKindStyle(
            Icons.my_location_outlined, l10n.mtLocationRequest);
      case MessageKind.contacts:
        return MessageKindStyle(Icons.contact_page_outlined, l10n.mtContact);

      // Commerce. These are the ones that arrive with no body at all, so the
      // label is the entire content of the bubble — fifteen real customer
      // carts on this workspace rendered as empty bubbles without it.
      case MessageKind.order:
        return MessageKindStyle(Icons.shopping_cart_outlined, l10n.mtOrder);
      case MessageKind.product:
        return MessageKindStyle(Icons.inventory_2_outlined, l10n.mtProduct);
      case MessageKind.productList:
        return MessageKindStyle(Icons.list_alt_outlined, l10n.mtProductList);
      case MessageKind.catalog:
        return MessageKindStyle(Icons.storefront_outlined, l10n.mtCatalog);

      case MessageKind.template:
        return MessageKindStyle(Icons.article_outlined, l10n.mtTemplate);
      case MessageKind.interactiveButtons:
        return MessageKindStyle(Icons.smart_button_outlined, l10n.mtButtons);
      case MessageKind.interactiveList:
        return MessageKindStyle(Icons.checklist_outlined, l10n.mtList);
      case MessageKind.ctaUrl:
        return MessageKindStyle(Icons.link_outlined, l10n.mtLink);

      case MessageKind.unsupported:
        return MessageKindStyle(Icons.help_outline, l10n.mtUnsupported);
    }
  }
}
