/// A team a conversation can be assigned or transferred to.
class Team {
  const Team({required this.uid, required this.name});
  final String uid;
  final String name;
}

/// A conversation label. Distinct from a contact tag, which lives on Contact.
class ConversationLabel {
  const ConversationLabel({required this.uid, required this.name, this.color});
  final String uid;
  final String name;
  final String? color;
}

/// A placeholder inside an approved template.
///
/// The keys are derived server-side (`field_1`, `header_field_1`, `button_0`)
/// and differ per template, so the form is rendered from this list and never
/// from a hard-coded set. Unknown keys are dropped by the API.
class TemplateField {
  const TemplateField({required this.key, this.label, this.example});
  final String key;
  final String? label;
  final String? example;

  /// `field_1` reads as nothing to an agent; "Field 1" at least reads as a
  /// position. A server-supplied label always wins.
  String get displayLabel {
    if (label != null && label!.trim().isNotEmpty) return label!;
    final String pretty = key.replaceAll('_', ' ').trim();
    if (pretty.isEmpty) return key;
    return pretty[0].toUpperCase() + pretty.substring(1);
  }
}

class MessageTemplate {
  const MessageTemplate({
    required this.uid,
    required this.name,
    this.language,
    this.category,
    this.body,
    this.fields = const <TemplateField>[],
  });

  final String uid;
  final String name;
  final String? language;
  final String? category;
  final String? body;
  final List<TemplateField> fields;
}

/// Where this agent stands on seeing a contact's history, plus the queues an
/// admin has to act on.
///
/// One endpoint serves both the agent and admin frames: it self-gates, so a
/// non-admin gets empty [pending] and [approved] and only their own state.
/// That is why there is one model rather than two.
class HistoryAccessSnapshot {
  const HistoryAccessSnapshot({
    this.currentUserStatus = HistoryAccessStatus.none,
    this.pending = const <HistoryAccessRequest>[],
    this.approved = const <HistoryAccessRequest>[],
    this.isVendorAdmin = false,
    this.revealFullHistory = false,
  });

  final HistoryAccessStatus currentUserStatus;
  final List<HistoryAccessRequest> pending;
  final List<HistoryAccessRequest> approved;
  final bool isVendorAdmin;

  /// Workspace-wide per-contact visibility. Admin only — the endpoint answers
  /// 403 for anyone else rather than aborting, so the control can be hidden
  /// instead of crashing on it.
  final bool revealFullHistory;
}

enum HistoryAccessStatus { none, pending, approved, denied }

class HistoryAccessRequest {
  const HistoryAccessRequest({
    required this.uid,
    required this.agentName,
    this.requestedAt,
    this.status = HistoryAccessStatus.pending,
  });

  final String uid;
  final String agentName;
  final DateTime? requestedAt;
  final HistoryAccessStatus status;
}

/// A scheduled template send.
///
/// Not its own table server-side — it is a message row with `status='reminder'`
/// and `messaged_at` holding the scheduled time.
class Reminder {
  const Reminder({
    required this.uid,
    this.templateUid,
    this.templateName,
    this.scheduleAt,
    this.fields = const <String, String>{},
  });

  final String uid;
  final String? templateUid;
  final String? templateName;

  /// Workspace-local wall clock, **not** UTC. The engine parses it in the
  /// workspace's configured timezone and converts itself; sending UTC shifts
  /// every reminder by the offset and reads as a scheduling bug.
  final DateTime? scheduleAt;
  final Map<String, String> fields;
}

/// The current snooze on a conversation, when there is one.
class SnoozeState {
  const SnoozeState({this.until, this.reason, this.snoozedByName});
  final DateTime? until;
  final String? reason;
  final String? snoozedByName;

  bool get isSnoozed => until != null;
}
