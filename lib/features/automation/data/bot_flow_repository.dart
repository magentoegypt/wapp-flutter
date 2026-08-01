import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';
import 'bot_reply_repository.dart';

/// A multi-step bot conversation.
///
/// A flow is a graph: the replies are its nodes and the buttons on each reply
/// are its edges. **This app edits the flow's envelope only** — its name, what
/// starts it, and whether it runs. The graph itself is built in the web
/// console, because a drag-and-drop node canvas on a phone is a different
/// product from the rest of this app.
///
/// That split is honest rather than partial: a flow created here is a real
/// flow with a real trigger that simply has no steps yet, and the editor says
/// so. The alternative — hiding creation entirely — would mean an agent who
/// wants a flow has to know to leave the app, with nothing telling them.
class BotFlow {
  const BotFlow({
    required this.uid,
    required this.title,
    required this.startTrigger,
    this.keyword,
    this.active = false,
    this.stepCount = 0,
  });

  final String uid;
  final String title;

  /// What starts the flow. Same vocabulary as a standalone reply's trigger —
  /// once the flow is running, its own edges decide the rest.
  ///
  /// Read from **`triggerType`**. Not from `startTrigger`, which despite its
  /// name holds the matched *text*: a live row reads
  /// `{triggerType: ads_welcome, startTrigger: "Test Ad"}`. Reading the two the
  /// other way round is silent — every trigger falls through to the `is`
  /// default and the list confidently says "Message is exactly" for all of
  /// them, which is how this was found.
  final BotTrigger startTrigger;

  /// `startTrigger` on the wire. Absent for the two welcome triggers, which
  /// fire on a first inbound message and so have nothing to match.
  final String? keyword;

  final bool active;

  /// How many replies hang off this flow, or **null when the payload does not
  /// say**.
  ///
  /// The list endpoint sends no count at all. Defaulting that to 0 made every
  /// row claim the flow was empty and put an amber warning on flows that are
  /// fully built — a wrong answer stated confidently, which is worse than no
  /// answer. Null means unknown and nothing is claimed.
  final int? stepCount;

  /// True only when the count is known *and* zero. Unknown is not empty.
  bool get isKnownEmpty => stepCount == 0;

  BotFlow copyWith({String? title, BotTrigger? startTrigger, String? keyword,
      bool? active}) {
    return BotFlow(
      uid: uid,
      title: title ?? this.title,
      startTrigger: startTrigger ?? this.startTrigger,
      keyword: keyword ?? this.keyword,
      active: active ?? this.active,
      stepCount: stepCount,
    );
  }

  static BotFlow fromJson(Map<String, dynamic> j) {
    String? str(Object? v) {
      final String s = '${v ?? ''}'.trim();
      return s.isEmpty ? null : s;
    }

    // The live list sends a real bool, but Laravel serialises tinyint 1/0
    // through other paths. `== true` alone would read 1 as false and show every
    // running flow as stopped.
    bool flag(Object? v) =>
        v == true || v == 1 || '$v'.toLowerCase() == 'true' || '$v' == '1';

    final Object? steps = j['stepCount'] ??
        j['step_count'] ??
        j['botRepliesCount'] ??
        j['bot_replies_count'];

    return BotFlow(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      // Either spelling; the list and the detail have been seen to differ.
      title: '${j['title'] ?? j['name'] ?? ''}',
      startTrigger: BotTriggerX.fromApi(j['triggerType'] ?? j['trigger_type']),
      keyword: str(j['startTrigger'] ?? j['start_trigger']),
      active: flag(j['active'] ?? j['is_active'] ?? j['isActive']),
      stepCount: steps is int
          ? steps
          : int.tryParse('${steps ?? ''}') ??
              // The detail may send the replies themselves instead of a count.
              // Absent entirely stays null — see [stepCount].
              (j['botReplies'] is List ? (j['botReplies'] as List).length : null),
    );
  }

  /// The create/update body.
  ///
  /// Snake_case in, camelCase out — the same split bot replies use, where the
  /// controller validates `trigger_type` and `reply_trigger` while the resource
  /// serialises `triggerType`. Inferred from that precedent rather than read
  /// from the write contract, which is the one part of this module that has not
  /// been exercised: sending a template send or a flow save against production
  /// is not something this build does.
  ///
  /// [withActive] is false on create. The store endpoint ignores `active`
  /// entirely and always saves an inactive flow — sending it there would make
  /// the app show a flow as running that the server has switched off, which is
  /// invisible until a customer's message goes unanswered. So creation posts
  /// without it and the caller follows with a PUT.
  Map<String, dynamic> toJson({bool withActive = true}) => <String, dynamic>{
        'title': title,
        'trigger_type': startTrigger.wire,
        if (startTrigger.needsKeyword) 'start_trigger': keyword,
        if (withActive) 'active': active,
      };
}

/// `title` ≤ 200; the trigger value follows the bot-reply keyword rule.
abstract final class BotFlowLimits {
  static const int title = 200;
  static const int keyword = BotReplyLimits.keyword;
}

abstract interface class BotFlowRepository {
  Future<List<BotFlow>> list();
  Future<BotFlow> byUid(String uid);

  /// Returns the created flow's uid.
  Future<String> create(BotFlow flow);
  Future<void> update(String uid, BotFlow flow);
  Future<void> delete(String uid);
}

class BotFlowRepositoryImpl implements BotFlowRepository {
  const BotFlowRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<BotFlow>> list() async =>
      envelopeRows(await _api.get('/bot-flows'), 'botFlows')
          .map(BotFlow.fromJson)
          .toList();

  @override
  Future<BotFlow> byUid(String uid) async => BotFlow.fromJson(
        envelopeRecord(await _api.get('/bot-flows/$uid'), 'botFlow'),
      );

  @override
  Future<String> create(BotFlow flow) async {
    final dynamic body =
        await _api.post('/bot-flows', body: flow.toJson(withActive: false));
    final Map<String, dynamic> created = envelopeRecord(body, 'botFlow');
    final String uid = '${created['uid'] ?? created['_uid'] ?? ''}';

    // Second call, deliberately. `active` is dropped by the store endpoint, so
    // a flow asked for as running is created stopped; only a PUT turns it on.
    // If the create answered without a uid there is nothing to PUT against —
    // the flow exists and is stopped, which the caller reports rather than
    // pretending the request half-succeeded.
    if (flow.active && uid.isNotEmpty) {
      await update(uid, flow);
    }
    return uid;
  }

  @override
  Future<void> update(String uid, BotFlow flow) =>
      _api.put('/bot-flows/$uid', body: flow.toJson());

  @override
  Future<void> delete(String uid) => _api.delete('/bot-flows/$uid');
}

final botFlowRepositoryProvider = Provider<BotFlowRepository>(
  (Ref ref) => BotFlowRepositoryImpl(ref.watch(apiClientProvider)),
);

final botFlowListProvider = FutureProvider<List<BotFlow>>(
  (Ref ref) => ref.watch(botFlowRepositoryProvider).list(),
);

final botFlowProvider = FutureProvider.autoDispose.family<BotFlow, String>(
  (Ref ref, String uid) => ref.watch(botFlowRepositoryProvider).byUid(uid),
);

/// The replies that make up a flow, in the order the API returns them.
///
/// Read-only on this screen. A reply inside a flow is positioned by the flow's
/// edges, and editing one in isolation would move a step without moving what
/// points at it.
final botFlowStepsProvider =
    FutureProvider.autoDispose.family<List<BotReply>, String>(
  (Ref ref, String uid) =>
      ref.watch(botReplyRepositoryProvider).list(flowUid: uid),
);
