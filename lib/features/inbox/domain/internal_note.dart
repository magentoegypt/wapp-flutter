/// A note attached to a conversation, visible to the workspace team only.
///
/// These must never appear in a customer-facing surface and must never be
/// included in an outbound message payload. That constraint is why they live
/// on their own endpoints rather than riding along in the chat response, and
/// why the UI renders them in the sticky-note palette instead of as bubbles.
class InternalNote {
  const InternalNote({
    required this.uid,
    required this.body,
    required this.authorName,
    required this.createdAt,
    this.edited = false,
  });

  final String uid;
  final String body;
  final String authorName;
  final DateTime? createdAt;
  final bool edited;
}
