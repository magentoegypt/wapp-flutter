/// What a call is doing, or did.
///
/// All seven the engine can write, not just the two this workspace has produced
/// (`completed` ×41 and `no_answer` ×1). Handling only the observed set renders
/// a blank row the first time somebody rejects a call, which is the kind of gap
/// that only shows up in front of a customer.
enum CallStatus { initiated, ringing, active, failed, rejected, noAnswer, completed }

extension CallStatusX on CallStatus {
  /// The API spells `no_answer`; Dart cannot.
  static CallStatus fromApi(Object? raw) {
    final String key = '${raw ?? ''}'.trim().toLowerCase().replaceAll('_', '');
    for (final CallStatus s in CallStatus.values) {
      if (s.name.toLowerCase() == key) return s;
    }
    return CallStatus.failed;
  }

  bool get isTerminal =>
      this == CallStatus.completed ||
      this == CallStatus.failed ||
      this == CallStatus.rejected ||
      this == CallStatus.noAnswer;

  bool get isConnected => this == CallStatus.active;
}

/// One row of call history.
///
/// [uid] and [callId] are different identifiers and are easy to confuse:
/// accept / reject / terminate all take **uid**. [callId] is Meta's `wacid.…`
/// and is only good for correlating a webhook.
class CallRecord {
  const CallRecord({
    required this.uid,
    required this.isIncoming,
    required this.status,
    this.callId,
    this.initiatedAt,
    this.connectedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.durationText,
    this.initiatedAtText,
    this.initiatedAgoText,
    this.receivedOn,
    this.outsideBusinessHours = false,
    this.callbackConsentGiven = false,
    this.recordingEnabled = false,
    this.hasRecording = false,
    this.recordingUrl,
  });

  final String uid;
  final String? callId;
  final bool isIncoming;
  final CallStatus status;
  final DateTime? initiatedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final int durationSeconds;

  /// Server-rendered `mm:ss`. Preferred over reformatting [durationSeconds] so
  /// the app and the console never disagree by a rounding rule.
  final String? durationText;
  final String? initiatedAtText;
  final String? initiatedAgoText;

  /// The workspace WhatsApp number the call came in on.
  final String? receivedOn;
  final bool outsideBusinessHours;
  final bool callbackConsentGiven;
  final bool recordingEnabled;
  final bool hasRecording;

  /// A real, fetchable URL. Recordings used to 404 because they were written
  /// outside the media tree; that is fixed, so playback can be built on this.
  final String? recordingUrl;

  bool get isPlayable => hasRecording && (recordingUrl?.isNotEmpty ?? false);
}

/// Whether this workspace may place a call, and why not when it may not.
///
/// The gates are reported separately on purpose. One boolean would hide the
/// difference between "the workspace switched it off" and "Meta will not allow
/// it from this number" — only the first is fixable by the user.
class CallCapability {
  const CallCapability({
    this.enabled = false,
    this.outboundSupported = false,
    this.outboundRestrictedReason,
    this.businessHoursEnabled = false,
    this.withinBusinessHours = false,
    this.recordingEnabled = false,
    this.iceServersConfigured = false,
    this.canPlaceCall = false,
  });

  final bool enabled;
  final bool outboundSupported;

  /// Null when unrestricted. On this workspace it reads "USA / Canada".
  final String? outboundRestrictedReason;
  final bool businessHoursEnabled;

  /// Time-of-day, and it flips during the day — re-read it rather than caching
  /// the value from login.
  final bool withinBusinessHours;
  final bool recordingEnabled;
  final bool iceServersConfigured;

  /// The conjunction, computed server-side. Branch on this rather than
  /// re-deriving the rule, or the client drifts from the engine.
  final bool canPlaceCall;
}
