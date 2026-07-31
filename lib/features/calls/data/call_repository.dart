import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';
import '../../conversation_actions/data/conversation_action_repository.dart'
    show callRecordFromJson;
import '../domain/call.dart';

/// Signalling and call control.
///
/// Media itself is WebRTC and never touches this class — the API only brokers
/// the offer/answer and the ICE servers, and everything else is state changes
/// on a call row.
abstract interface class CallRepository {
  /// Whether this workspace may place a call, and why not when it may not.
  ///
  /// Re-read rather than cached: `withinBusinessHours` is time-of-day and flips
  /// during the day.
  Future<CallCapability> capability();

  /// Calls ringing right now, for an incoming-call surface.
  Future<List<CallRecord>> pending();

  /// STUN/TURN configuration for the peer connection.
  Future<List<Map<String, dynamic>>> iceServers();

  /// Places an outbound call. Fails with the country restriction on a
  /// workspace where `canPlaceCall` is false — check capability first.
  Future<CallRecord> place(String contactUid);

  /// All three take the call **uid**, not Meta's `callId`.
  Future<void> accept(String callUid, {String? sdpAnswer});
  Future<void> reject(String callUid);
  Future<void> terminate(String callUid);

  /// The remote session description for an in-flight negotiation.
  Future<String?> sdp(String callUid);
}

class CallRepositoryImpl implements CallRepository {
  const CallRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<CallCapability> capability() async {
    final dynamic body = await _api.get('/calls/capability');
    // Nested under `calling`, the same domain-key convention as every other
    // endpoint here; falls back to flat.
    final Map<String, dynamic> c = envelopeRecord(body, 'calling');

    return CallCapability(
      enabled: (c['enabled'] as bool?) ?? false,
      outboundSupported: (c['outboundSupported'] as bool?) ?? false,
      outboundRestrictedReason: c['outboundRestrictedReason'] as String?,
      businessHoursEnabled: (c['businessHoursEnabled'] as bool?) ?? false,
      withinBusinessHours: (c['withinBusinessHours'] as bool?) ?? false,
      recordingEnabled: (c['recordingEnabled'] as bool?) ?? false,
      iceServersConfigured: (c['iceServersConfigured'] as bool?) ?? false,
      // Trust the server's conjunction rather than re-deriving it here; a
      // client that recomputes the rule drifts from the engine.
      canPlaceCall: (c['canPlaceCall'] as bool?) ?? false,
    );
  }

  @override
  Future<List<CallRecord>> pending() async {
    final dynamic body = await _api.get('/calls/pending');
    return envelopeRows(body, 'calls').map(callRecordFromJson).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> iceServers() async {
    final dynamic body = await _api.get('/calls/ice-servers');
    return envelopeRows(body, 'iceServers');
  }

  @override
  Future<CallRecord> place(String contactUid) async {
    final dynamic body = await _api.post('/conversations/$contactUid/calls');
    return callRecordFromJson(envelopeRecord(body, 'call'));
  }

  @override
  Future<void> accept(String callUid, {String? sdpAnswer}) async {
    await _api.post('/calls/$callUid/accept', body: <String, dynamic>{
      if (sdpAnswer != null) 'sdp': sdpAnswer,
    });
  }

  @override
  Future<void> reject(String callUid) => _api.post('/calls/$callUid/reject');

  @override
  Future<void> terminate(String callUid) =>
      _api.post('/calls/$callUid/terminate');

  @override
  Future<String?> sdp(String callUid) async {
    final dynamic body = await _api.get('/calls/$callUid/sdp');
    final Map<String, dynamic> m = envelopeRecord(body, 'sdp');
    return (m['sdp'] ?? m['description']) as String?;
  }
}


final callRepositoryProvider = Provider<CallRepository>(
  (Ref ref) => CallRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Capability, re-read on each subscription.
///
/// autoDispose rather than kept alive on purpose: `withinBusinessHours` is a
/// time-of-day flag, so a value cached from login goes stale silently.
final callCapabilityProvider =
    FutureProvider.autoDispose<CallCapability>((Ref ref) {
  return ref.watch(callRepositoryProvider).capability();
});

final pendingCallsProvider =
    FutureProvider.autoDispose<List<CallRecord>>((Ref ref) {
  return ref.watch(callRepositoryProvider).pending();
});
