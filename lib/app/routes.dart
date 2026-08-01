/// Centralised route paths and the four persistent bottom-nav tabs.
///
/// Paths mirror the "Suggested route" column of the Figma handoff's screen
/// inventory so a frame can be traced to a route and back.
abstract final class AppRoutes {
  // Outside the shell entirely.

  /// Shown while a stored token is being validated. Exists so "still
  /// checking" is a distinct state from "signed out" — conflating the two
  /// makes the app flash the sign-in form on every cold start, and strands
  /// the user there if the resolved state never reaches the router.
  static const String splash = '/splash';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Tab roots — these live inside the StatefulShellRoute branches.
  static const String home = '/home';
  static const String chats = '/chats';
  static const String contacts = '/contacts';
  static const String more = '/more';

  /// Inside the More branch, so it keeps the bottom bar (the inventory marks
  /// Profile as `tabs`, unlike the other More destinations).
  static const String profile = '/more/profile';

  // Pushed full-screen over the shell — the bottom bar is covered.
  static const String search = '/search';
  static const String contactNew = '/contacts/new';
  static const String quickReplies = '/quick-replies';
  static const String quickReplyNew = '/quick-replies/new';
  static const String campaigns = '/campaigns';
  static const String campaignNew = '/campaigns/new';
  static const String agents = '/agents';

  /// Instagram's persistent menu and ice breakers. Workspace settings, not a
  /// conversation action — admin-gated, and the API answers 403 to anyone else.
  static const String instagramSettings = '/settings/instagram';

  /// WhatsApp template management. The More frame lists this row; the screen
  /// behind it had no endpoints until the 31 Jul API pass.
  static const String templates = '/templates';
  static const String templateNew = '/templates/new';

  /// Teams and keyword auto-replies. Both arrived with the 31 Jul API pass.
  static const String teams = '/teams';
  static const String teamNew = '/teams/new';
  static const String botReplies = '/bot-replies';
  static const String botReplyNew = '/bot-replies/new';

  /// Multi-step flows. The envelope only — the node graph stays in the console.
  static const String botFlows = '/bot-flows';
  static const String botFlowNew = '/bot-flows/new';

  /// Component gallery — every shared widget in light/dark × LTR/RTL.
  /// Debug builds only; not reachable from the UI.
  static const String devGallery = '/dev/gallery';

  static String chat(String contactUid) => '/chats/$contactUid';

  static String template(String uid) => '/templates/$uid';

  static String team(String uid) => '/teams/$uid';
  static String botReply(String uid) => '/bot-replies/$uid';
  static String botFlow(String uid) => '/bot-flows/$uid';
  static String chatInfo(String contactUid) => '/chats/$contactUid/info';
  static String chatNotes(String contactUid) => '/chats/$contactUid/notes';

  // Conversation actions — the ⋮ sheet's destinations. All push over the shell.
  static String chatSnooze(String uid) => '/chats/$uid/snooze';
  static String chatTransfer(String uid) => '/chats/$uid/transfer';
  static String chatAssign(String uid) => '/chats/$uid/assign';
  static String chatReview(String uid) => '/chats/$uid/review';
  static String chatLabels(String uid) => '/chats/$uid/labels';
  static String chatTemplate(String uid) => '/chats/$uid/template';
  static String chatCalls(String uid) => '/chats/$uid/calls';
  static String chatCallPermission(String uid) => '/chats/$uid/call-permission';
  static String chatHistoryAccess(String uid) => '/chats/$uid/history-access';
  static String chatReminder(String uid) => '/chats/$uid/reminder';

  /// Instagram's three structured message types. Only reachable on an
  /// Instagram conversation — the send endpoints answer 422 on a WhatsApp one.
  static String chatInstagram(String uid) => '/chats/$uid/instagram';

  // Calling — full-screen, outside the shell entirely.
  static String callIncoming(String uid) => '/calls/$uid/incoming';
  static String callOutgoing(String uid) => '/calls/$uid/outgoing';
  static String callActive(String uid) => '/calls/$uid/active';
  static String callEnded(String uid) => '/calls/$uid/ended';
  static String contact(String uid) => '/contacts/$uid';
  static String quickReply(String uid) => '/quick-replies/$uid';
  static String campaign(String uid) => '/campaigns/$uid';
  static String agent(String uid) => '/agents/$uid';
}

/// Persistent bottom-navigation destinations, in bar order.
enum AppTab { home, chats, contacts, more }

extension AppTabRoute on AppTab {
  String get route => switch (this) {
    AppTab.home => AppRoutes.home,
    AppTab.chats => AppRoutes.chats,
    AppTab.contacts => AppRoutes.contacts,
    AppTab.more => AppRoutes.more,
  };
}
