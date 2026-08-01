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
}

class BotReply {
  const BotReply({
    required this.uid,
    required this.name,
    required this.trigger,
    this.keyword,
    this.messageKind = BotMessageKind.simple,
    this.replyText,
    this.flowUid,
  });

  final String uid;

  /// Required and **unique per workspace** — but only for a standalone reply.
  /// A reply inside a flow has no name of its own.
  final String name;

  final BotTrigger trigger;

  /// `reply_trigger`. Absent for the two welcome triggers.
  final String? keyword;

  final BotMessageKind messageKind;
  final String? replyText;

  /// Set when this reply belongs to a flow, in which case the flow's edges
  /// decide when it fires and `trigger_type` is forced to `is` server-side.
  final String? flowUid;

  bool get isInFlow => flowUid != null && flowUid!.isNotEmpty;

  static BotReply fromJson(Map<String, dynamic> j) {
    String? str(Object? v) {
      final String s = '${v ?? ''}'.trim();
      return s.isEmpty ? null : s;
    }

    final Map<String, dynamic> data =
        (j['__data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    return BotReply(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      name: '${j['name'] ?? ''}',
      trigger: BotTriggerX.fromApi(j['trigger_type'] ?? j['triggerType']),
      keyword: str(j['reply_trigger'] ?? j['replyTrigger']),
      messageKind:
          BotMessageKindX.fromApi(j['message_type'] ?? j['messageType']),
      // The reply body lives on the row for a simple reply and inside `__data`
      // for the richer kinds, so both are read.
      replyText: str(j['reply_text'] ?? j['replyText'] ?? data['reply_text']),
      flowUid: str(j['bot_flow_uid'] ?? j['botFlowUid'] ?? j['bot_flows__id']),
    );
  }

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
