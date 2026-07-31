import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';

/// Instagram-only sends.
///
/// Text and media are NOT here: `POST …/messages` and `…/messages/media` route
/// by channel server-side, so the client does not branch for those. Only the
/// three structured types and reactions have no WhatsApp equivalent.
///
/// Posting any of these at a WhatsApp thread answers 422 "This conversation is
/// not on Instagram." That is a correct server guard, not a state the UI should
/// ever reach — gate the controls on `channel == instagram` instead.
abstract interface class InstagramRepository {
  Future<void> react({
    required String contactUid,
    required String messageUid,
    required String emoji,
  });

  Future<void> sendQuickReplies({
    required String contactUid,
    required String message,
    required List<IgQuickReply> quickReplies,
  });

  Future<void> sendButtonTemplate({
    required String contactUid,
    required String message,
    required List<IgButton> buttons,
  });

  Future<void> sendGenericTemplate({
    required String contactUid,
    required List<IgCard> elements,
  });

  Future<List<IgTemplate>> templates(IgTemplateKind kind);
}

/// Meta's caps, enforced here rather than server-side.
///
/// **Over-long values are trimmed, not rejected.** A button reading "Track my
/// order now" comes back shorter with no error and no indication anything
/// happened, so the composer has to refuse it before sending — this is the one
/// validation the API will not do for us.
abstract final class IgLimits {
  static const int title = 20;
  static const int cardText = 80;
  static const int maxQuickReplies = 13;
  static const int maxButtons = 3;
  static const int maxCards = 10;
}

class IgQuickReply {
  const IgQuickReply({required this.title, this.payload, this.contentType});
  final String title;
  final String? payload;
  final String? contentType;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        if (payload != null && payload!.isNotEmpty) 'payload': payload,
        if (contentType != null && contentType!.isNotEmpty)
          'contentType': contentType,
      };
}

class IgButton {
  const IgButton({
    required this.type,
    required this.title,
    this.payload,
    this.url,
  });

  /// `postback` or `web_url`, which decides whether payload or url is used.
  final String type;
  final String title;
  final String? payload;
  final String? url;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'title': title,
        if (payload != null && payload!.isNotEmpty) 'payload': payload,
        if (url != null && url!.isNotEmpty) 'url': url,
      };
}

class IgCard {
  const IgCard({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.buttons = const <IgButton>[],
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final List<IgButton> buttons;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        if (subtitle != null && subtitle!.isNotEmpty) 'subtitle': subtitle,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (buttons.isNotEmpty)
          'buttons': buttons.map((IgButton b) => b.toJson()).toList(),
      };
}

/// Note the wire values differ from the endpoint names.
enum IgTemplateKind { quickReply, button, generic }

extension IgTemplateKindX on IgTemplateKind {
  String get wire => switch (this) {
        IgTemplateKind.quickReply => 'quick_reply',
        IgTemplateKind.button => 'button',
        IgTemplateKind.generic => 'generic',
      };
}

/// A saved template.
///
/// [payload] already arrives in the shape the send endpoints expect, so it is
/// posted straight back with the contact uid added — deliberately kept as a
/// raw map rather than parsed into typed models and rebuilt, because
/// re-shaping it on device is how a field gets dropped.
class IgTemplate {
  const IgTemplate({
    required this.uid,
    required this.name,
    required this.kind,
    this.payload = const <String, dynamic>{},
  });

  final String uid;
  final String name;
  final IgTemplateKind kind;
  final Map<String, dynamic> payload;
}

class InstagramRepositoryImpl implements InstagramRepository {
  const InstagramRepositoryImpl(this._api);

  final ApiClient _api;

  String _base(String uid) => '/conversations/$uid/instagram';

  @override
  Future<void> react({
    required String contactUid,
    required String messageUid,
    required String emoji,
  }) async {
    await _api.post('${_base(contactUid)}/react', body: <String, dynamic>{
      'messageUid': messageUid,
      'emoji': emoji,
    });
  }

  @override
  Future<void> sendQuickReplies({
    required String contactUid,
    required String message,
    required List<IgQuickReply> quickReplies,
  }) async {
    await _api.post('${_base(contactUid)}/quick-replies',
        body: <String, dynamic>{
          'message': message,
          'quickReplies':
              quickReplies.map((IgQuickReply q) => q.toJson()).toList(),
        });
  }

  @override
  Future<void> sendButtonTemplate({
    required String contactUid,
    required String message,
    required List<IgButton> buttons,
  }) async {
    await _api.post('${_base(contactUid)}/button-template',
        body: <String, dynamic>{
          'message': message,
          'buttons': buttons.map((IgButton b) => b.toJson()).toList(),
        });
  }

  @override
  Future<void> sendGenericTemplate({
    required String contactUid,
    required List<IgCard> elements,
  }) async {
    await _api.post('${_base(contactUid)}/generic-template',
        body: <String, dynamic>{
          'elements': elements.map((IgCard c) => c.toJson()).toList(),
        });
  }

  @override
  Future<List<IgTemplate>> templates(IgTemplateKind kind) async {
    final dynamic body = await _api.get(
      '/instagram/templates',
      query: <String, dynamic>{'type': kind.wire},
    );
    return envelopeRows(body, 'templates').map((Map<String, dynamic> j) {
      return IgTemplate(
        uid: '${j['uid'] ?? j['_uid'] ?? ''}',
        name: '${j['name'] ?? j['title'] ?? ''}',
        kind: kind,
        payload:
            (j['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );
    }).toList();
  }
}

final instagramRepositoryProvider = Provider<InstagramRepository>(
  (Ref ref) => InstagramRepositoryImpl(ref.watch(apiClientProvider)),
);

final igTemplatesProvider = FutureProvider.autoDispose
    .family<List<IgTemplate>, IgTemplateKind>((Ref ref, IgTemplateKind kind) {
  return ref.watch(instagramRepositoryProvider).templates(kind);
});
