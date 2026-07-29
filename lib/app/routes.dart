/// Centralised route paths and the four persistent bottom-nav tabs.
///
/// Paths mirror the "Suggested route" column of the Figma handoff's screen
/// inventory so a frame can be traced to a route and back.
abstract final class AppRoutes {
  // Outside the shell entirely.
  static const String login = '/login';

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

  /// Component gallery — every shared widget in light/dark × LTR/RTL.
  /// Debug builds only; not reachable from the UI.
  static const String devGallery = '/dev/gallery';

  static String chat(String contactUid) => '/chats/$contactUid';
  static String chatInfo(String contactUid) => '/chats/$contactUid/info';
  static String chatNotes(String contactUid) => '/chats/$contactUid/notes';
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
