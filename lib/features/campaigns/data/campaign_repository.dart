import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../contacts/domain/contact.dart' show NamedRef;

/// Campaign lifecycle. Backend stores these as integers on `campaigns.status`.
enum CampaignStatus { draft, scheduled, running, completed, failed }

class Campaign {
  const Campaign({
    required this.uid,
    required this.title,
    required this.status,
    this.templateName,
    this.scheduledAt,
    this.totalContacts = 0,
    this.sent = 0,
    this.delivered = 0,
    this.read = 0,
    this.failed = 0,
  });

  final String uid;
  final String title;
  final CampaignStatus status;
  final String? templateName;
  final DateTime? scheduledAt;
  final int totalContacts;
  final int sent;
  final int delivered;
  final int read;
  final int failed;
}

/// Dropdown data for Create campaign, fetched in one call.
class CampaignMeta {
  const CampaignMeta({
    this.templates = const <NamedRef>[],
    this.groups = const <NamedRef>[],
  });

  final List<NamedRef> templates;
  final List<NamedRef> groups;

  static const CampaignMeta empty = CampaignMeta();
}

abstract interface class CampaignRepository {
  Future<List<Campaign>> list();
  Future<Campaign> byUid(String uid);
  Future<CampaignMeta> meta();
  Future<void> create({
    required String title,
    required String templateName,
    List<String> groupIds,
    DateTime? scheduledAt,
  });
}

class CampaignRepositoryImpl implements CampaignRepository {
  const CampaignRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Campaign>> list() async {
    final dynamic body = await _api.get('/campaigns');
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().map(campaignFromJson).toList();
    }
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rows =
        (m['campaigns'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().map(campaignFromJson).toList();
  }

  @override
  Future<Campaign> byUid(String uid) async {
    final dynamic body = await _api.get('/campaigns/$uid');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    // Singular domain key, not `data`.
    return campaignFromJson((m['campaign'] as Map<String, dynamic>?) ??
        (m['data'] as Map<String, dynamic>?) ??
        m);
  }

  @override
  Future<CampaignMeta> meta() async {
    final dynamic body = await _api.get('/campaigns/meta');
    final Map<String, dynamic> j = (body as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    List<NamedRef> refs(Object? raw) => raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> e) => NamedRef(
                  id: (e['uid'] ?? e['id'] ?? e['name'] ?? '').toString(),
                  name: (e['title'] ?? e['name'] ?? '').toString(),
                ))
            .toList()
        : const <NamedRef>[];
    return CampaignMeta(
      templates: refs(j['templates']),
      groups: refs(j['groups']),
    );
  }

  @override
  Future<void> create({
    required String title,
    required String templateName,
    List<String> groupIds = const <String>[],
    DateTime? scheduledAt,
  }) {
    return _api.post('/campaigns', body: <String, dynamic>{
      'title': title,
      'template_name': templateName,
      if (groupIds.isNotEmpty) 'groups': groupIds,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    });
  }
}

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

CampaignStatus _status(Object? raw) {
  if (raw is String) {
    return CampaignStatus.values.firstWhere(
      (CampaignStatus s) => s.name == raw,
      orElse: () => CampaignStatus.draft,
    );
  }
  return switch (_int(raw)) {
    1 => CampaignStatus.running,
    2 => CampaignStatus.scheduled,
    5 => CampaignStatus.completed,
    6 => CampaignStatus.failed,
    _ => CampaignStatus.draft,
  };
}

Campaign campaignFromJson(Map<String, dynamic> j) {
  final Map<String, dynamic> stats =
      (j['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  return Campaign(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    status: _status(j['status']),
    templateName: (j['templateName'] ?? j['template_name']) as String?,
    scheduledAt: DateTime.tryParse('${j['scheduledAt'] ?? ''}')?.toLocal(),
    // `targeted` is the audience size; `allContacts` means the whole book.
    totalContacts: _int(j['targeted'] ?? j['totalContacts']),
    sent: _int(stats['sent'] ?? j['sent']),
    delivered: _int(stats['delivered'] ?? j['delivered']),
    read: _int(stats['read'] ?? j['read']),
    failed: _int(stats['failed'] ?? j['failed']),
  );
}

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (Ref ref) => CampaignRepositoryImpl(ref.watch(apiClientProvider)),
);

final campaignListProvider = FutureProvider.autoDispose<List<Campaign>>((Ref ref) {
  return ref.watch(campaignRepositoryProvider).list();
});

final campaignDetailProvider =
    FutureProvider.autoDispose.family<Campaign, String>((Ref ref, String uid) {
  return ref.watch(campaignRepositoryProvider).byUid(uid);
});

final campaignMetaProvider = FutureProvider.autoDispose<CampaignMeta>((Ref ref) {
  return ref.watch(campaignRepositoryProvider).meta();
});
