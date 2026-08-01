import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';
import '../domain/whatsapp_template.dart';

/// WhatsApp template management.
///
/// The list has always been readable — the send-template picker uses it — but
/// creating, editing and deleting only arrived with the 31 Jul API pass.
///
/// One of these is not like the others: [delete] removes the template **at
/// Meta**, and nothing local brings it back. The API's own changelog flags it
/// as the worst of four unscoped engine methods it had to guard, because a
/// cross-tenant uid would have destroyed another workspace's live template.
abstract interface class TemplateRepository {
  Future<List<WhatsAppTemplate>> list();

  /// One template, in full.
  ///
  /// The list is a summary — it carries name, language, category and status but
  /// not the body, header, footer or buttons. Loading the editor from it
  /// produced a form with every content field blank, which reads as a template
  /// that has no body rather than a screen that did not ask for one.
  Future<WhatsAppTemplate> byUid(String uid);

  Future<void> create(WhatsAppTemplate template);

  /// Name, language and category are fixed once Meta holds the template; the
  /// engine rebuilds from the stored values and ignores whatever is sent.
  Future<void> update(String uid, WhatsAppTemplate template);

  Future<void> delete(String uid);

  /// Re-pulls from Meta and returns the refreshed list.
  ///
  /// The point is approval: a new template is PENDING and becomes APPROVED
  /// asynchronously, with nothing pushed to the client. Without this the only
  /// way to learn a template went live is to keep reopening the screen.
  Future<List<WhatsAppTemplate>> sync();
}

class TemplateRepositoryImpl implements TemplateRepository {
  const TemplateRepositoryImpl(this._api);

  final ApiClient _api;

  List<WhatsAppTemplate> _rows(dynamic body) =>
      envelopeRows(body, 'templates').map(WhatsAppTemplate.fromJson).toList();

  @override
  Future<List<WhatsAppTemplate>> list() async =>
      _rows(await _api.get('/templates'));

  @override
  Future<WhatsAppTemplate> byUid(String uid) async => WhatsAppTemplate.fromJson(
        envelopeRecord(await _api.get('/templates/$uid'), 'template'),
      );

  @override
  Future<void> create(WhatsAppTemplate t) =>
      _api.post('/templates', body: t.toJson());

  @override
  Future<void> update(String uid, WhatsAppTemplate t) =>
      _api.put('/templates/$uid', body: t.toJson());

  @override
  Future<void> delete(String uid) => _api.delete('/templates/$uid');

  @override
  Future<List<WhatsAppTemplate>> sync() async =>
      _rows(await _api.post('/templates/sync'));
}

final templateRepositoryProvider = Provider<TemplateRepository>(
  (Ref ref) => TemplateRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Not autoDispose: the editor pushes over this list and pops back to it, and
/// a dispose in between would refetch on every return.
final templateListProvider = FutureProvider<List<WhatsAppTemplate>>(
  (Ref ref) => ref.watch(templateRepositoryProvider).list(),
);

/// One template's full record, for the editor.
final templateProvider =
    FutureProvider.autoDispose.family<WhatsAppTemplate, String>(
  (Ref ref, String uid) => ref.watch(templateRepositoryProvider).byUid(uid),
);
