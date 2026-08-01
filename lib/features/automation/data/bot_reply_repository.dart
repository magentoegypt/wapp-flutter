import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';

/// When a bot reply fires.
///
/// `welcome` and `ads_welcome` both fire on a customer's *first* inbound
/// message, so neither has a keyword to match — which is why [needsKeyword] is
/// false for them and the server drops `reply_trigger` in both cases.
enum BotTrigger {
  welcome,
  adsWelcome,
  is_,
  startsWith,
  endsWith,
  containsWord,
  contains,
}

extension BotTriggerX on BotTrigger {
  String get wire => switch (this) {
        BotTrigger.welcome => 'welcome',
        BotTrigger.adsWelcome => 'ads_welcome',
        BotTrigger.is_ => 'is',
        BotTrigger.startsWith => 'starts_with',
        BotTrigger.endsWith => 'ends_with',
        BotTrigger.containsWord => 'contains_word',
        BotTrigger.contains => 'contains',
      };

  /// False only for the two that fire on a first message.
  bool get needsKeyword =>
      this != BotTrigger.welcome && this != BotTrigger.adsWelcome;

  static BotTrigger fromApi(Object? raw) {
    switch ('${raw ?? ''}'.trim().toLowerCase()) {
      case 'welcome':
        return BotTrigger.welcome;
      case 'ads_welcome':
        return BotTrigger.adsWelcome;
      case 'starts_with':
        return BotTrigger.startsWith;
      case 'ends_with':
        return BotTrigger.endsWith;
      case 'contains_word':
        return BotTrigger.containsWord;
      case 'contains':
        return BotTrigger.contains;
      default:
        return BotTrigger.is_;
    }
  }
}

/// What the bot sends back.
///
/// Only `simple` is editable here. `interactive` carries buttons or list
/// sections with their own validation, and `media` needs
/// `uploaded_media_file_name` from a prior upload — both are shown read-only so
/// an agent can see what exists without this screen silently flattening one
/// into a plain text reply on the next save.
enum BotMessageKind { simple, interactive, media, other }

extension BotMessageKindX on BotMessageKind {
  bool get isEditable => this == BotMessageKind.simple;

  static BotMessageKind fromApi(Object? raw) {
    switch ('${raw ?? ''}'.trim().toLowerCase()) {
      case 'simple':
        return BotMessageKind.simple;
      case 'interactive':
        return BotMessageKind.interactive;
      case 'media':
        return BotMessageKind.media;
      case '':
        return BotMessageKind.simple;
      default:
        return BotMessageKind.other;
    }
  }

  /// What a reply actually sends, worked out from its payload.
  ///
  /// **There is no `message_type` field.** The API describes a rich reply only
  /// by what sits in `data.interaction_message` — buttons, a list, a CTA, a
  /// header image. Keying the read-only guard off a type field that is never
  /// sent meant the guard never fired: a live reply carrying an image header
  /// and three buttons opened as a plain editable text reply, and saving it
  /// would have posted `reply_text` alone and destroyed the rest.
  ///
  /// So the payload is the evidence. Anything interactive wins over media,
  /// because an interactive reply with an image header is still interactive.
  static BotMessageKind fromPayload(Map<String, dynamic>? interaction) {
    if (interaction == null || interaction.isEmpty) return BotMessageKind.simple;

    bool present(Object? v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is Iterable) return v.isNotEmpty;
      if (v is Map) return v.isNotEmpty;
      return true;
    }

    if (present(interaction['interactive_type']) ||
        // `buttons` arrives as a map keyed "1","2","3", not a list.
        present(interaction['buttons']) ||
        present(interaction['list_data']) ||
        present(interaction['cta_url'])) {
      return BotMessageKind.interactive;
    }

    final String header =
        '${interaction['header_type'] ?? ''}'.trim().toLowerCase();
    if (present(interaction['media_link']) ||
        const <String>{'image', 'video', 'document', 'audio'}.contains(header)) {
      return BotMessageKind.media;
    }
    return BotMessageKind.simple;
  }
}

class BotReply {
  const BotReply({
    required this.uid,
    required this.name,
    required this.trigger,
    this.keyword,
    this.messageKind = BotMessageKind.simple,
    this.replyText,
    this.active = true,
    this.isInFlow = false,
  });

  final String uid;

  /// Required and **unique per workspace** — but only for a standalone reply.
  /// A reply inside a flow has no name of its own.
  final String name;

  final BotTrigger trigger;

  /// The text the trigger matches against.
  ///
  /// Read from **`trigger`**, which is the field the API actually sends —
  /// not `reply_trigger`, which is what the *write* side takes. A live row is
  /// `{triggerType: starts_with, trigger: "محتاج تواصل"}`. Reading the write
  /// name back showed an empty Keyword box on every reply that has one, which
  /// is how this was found.
  final String? keyword;

  final BotMessageKind messageKind;
  final String? replyText;

  /// Whether the reply is switched on. Read-only here — see [BotReply.toJson].
  final bool active;

  /// True when this reply belongs to a flow, in which case the flow's edges
  /// decide when it fires and `triggerType` is forced to `is` server-side.
  final bool isInFlow;

  static BotReply fromJson(Map<String, dynamic> j) {
    String? str(Object? v) {
      final String s = '${v ?? ''}'.trim();
      return s.isEmpty ? null : s;
    }

    bool flag(Object? v) =>
        v == true || v == 1 || '$v'.toLowerCase() == 'true' || '$v' == '1';

    // `data` on the wire. `__data` is kept as a fallback because the templates
    // endpoint uses that spelling and the two have been seen to swap.
    final Map<String, dynamic> data =
        (j['data'] as Map<String, dynamic>?) ??
            (j['__data'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final Map<String, dynamic>? interaction =
        data['interaction_message'] as Map<String, dynamic>?;

    return BotReply(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      name: '${j['name'] ?? ''}',
      trigger: BotTriggerX.fromApi(j['triggerType'] ?? j['trigger_type']),
      keyword: str(j['trigger'] ?? j['reply_trigger'] ?? j['replyTrigger']),
      // The payload decides, because no type field is sent. An explicit
      // `message_type` still wins if one ever appears.
      messageKind: j['message_type'] != null || j['messageType'] != null
          ? BotMessageKindX.fromApi(j['message_type'] ?? j['messageType'])
          : BotMessageKindX.fromPayload(interaction),
      // The body sits on the row for a simple reply and inside the interaction
      // payload for the richer kinds, so both are read.
      replyText: str(
        j['replyText'] ?? j['reply_text'] ?? interaction?['body_text'],
      ),
      active: flag(j['active'] ?? true),
      isInFlow: flag(j['inFlow'] ?? j['in_flow']) ||
          str(j['bot_flow_uid'] ?? j['botFlowUid']) != null,
    );
  }

  /// The create/update body.
  ///
  /// Note the asymmetry: the keyword is read back as `trigger` and written as
  /// `reply_trigger`. That is the API's shape, not a mistake here — the write
  /// side is snake_case validation input, the read side is a camelCase
  /// resource.
  ///
  /// `active` is deliberately absent. It is read from the payload so a switched
  /// off reply does not look live, but this form does not offer to change it:
  /// the write contract for it has not been exercised, and a toggle that
  /// silently does nothing is worse than no toggle.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'trigger_type': trigger.wire,
        // Omitted rather than sent empty for the welcome triggers: the server
        // nulls it itself, and sending "" would fail the max:250 rule's
        // required sibling on the others.
        if (trigger.needsKeyword) 'reply_trigger': keyword,
        'message_type': 'simple',
        'reply_text': replyText,
      };
}

/// `name` ≤ 200 and unique per workspace; `reply_trigger` ≤ 250.
abstract final class BotReplyLimits {
  static const int name = 200;
  static const int keyword = 250;
  static const int replyText = 1024;
}

abstract interface class BotReplyRepository {
  /// Without [flowUid] this returns **standalone replies only** — the ones with
  /// no flow attached. That is the server's default, not a filter applied here.
  Future<List<BotReply>> list({String? flowUid});

  Future<BotReply> byUid(String uid);
  Future<void> create(BotReply reply);
  Future<void> update(String uid, BotReply reply);
  Future<void> delete(String uid);

  /// Counts against the workspace's plan allowance, so a 422 here is a
  /// legitimate answer rather than a malformed request.
  Future<void> duplicate(String uid);
}

class BotReplyRepositoryImpl implements BotReplyRepository {
  const BotReplyRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<BotReply>> list({String? flowUid}) async => envelopeRows(
        await _api.get(
          '/bot-replies',
          query: <String, dynamic>{if (flowUid != null) 'flow': flowUid},
        ),
        'botReplies',
      ).map(BotReply.fromJson).toList();

  @override
  Future<BotReply> byUid(String uid) async => BotReply.fromJson(
        envelopeRecord(await _api.get('/bot-replies/$uid'), 'botReply'),
      );

  @override
  Future<void> create(BotReply r) =>
      _api.post('/bot-replies', body: r.toJson());

  @override
  Future<void> update(String uid, BotReply r) =>
      _api.put('/bot-replies/$uid', body: r.toJson());

  @override
  Future<void> delete(String uid) => _api.delete('/bot-replies/$uid');

  @override
  Future<void> duplicate(String uid) =>
      _api.post('/bot-replies/$uid/duplicate');
}

final botReplyRepositoryProvider = Provider<BotReplyRepository>(
  (Ref ref) => BotReplyRepositoryImpl(ref.watch(apiClientProvider)),
);

final botReplyListProvider = FutureProvider<List<BotReply>>(
  (Ref ref) => ref.watch(botReplyRepositoryProvider).list(),
);

final botReplyProvider = FutureProvider.autoDispose.family<BotReply, String>(
  (Ref ref, String uid) => ref.watch(botReplyRepositoryProvider).byUid(uid),
);
