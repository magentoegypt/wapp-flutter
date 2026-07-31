/// Instagram's Messenger profile: the persistent menu and the ice breakers.
///
/// Workspace settings rather than conversation actions — there is no contact
/// uid anywhere in this file. They write straight through to the live Meta
/// profile, so saving here changes what every Instagram customer sees
/// immediately, with no draft state in between.
library;

/// Meta's caps, taken from the server's validation rules rather than the
/// handoff prose, which omits two of them.
///
/// The API trims over-long values instead of refusing them, so a title typed
/// past [menuTitle] reaches the customer shortened with no error anywhere. That
/// is the whole reason these are enforced on the client.
abstract final class IgProfileLimits {
  /// Per locale, not overall.
  static const int maxMenuActions = 5;
  static const int menuTitle = 30;

  /// Per locale, and silently truncated past this.
  static const int maxIceBreakers = 4;

  /// Undocumented in the handoff; the server validates it.
  static const int iceQuestion = 80;

  static const int payload = 1000;
  static const int url = 2000;
}

/// The locale Meta falls back to, and the only one this screen edits.
const String kDefaultLocale = 'default';

/// One row of the persistent menu.
class MenuAction {
  const MenuAction({
    required this.type,
    required this.title,
    this.payload,
    this.url,
  });

  /// `postback` or `web_url` — the server rejects anything else.
  final String type;
  final String title;

  /// Carried on a `postback`; what the bot receives when the row is tapped.
  final String? payload;

  /// Carried on a `web_url`.
  final String? url;

  bool get isUrl => type == 'web_url';

  factory MenuAction.fromJson(Map<String, dynamic> j) => MenuAction(
        type: (j['type'] as String?) ?? 'postback',
        title: (j['title'] as String?) ?? '',
        payload: j['payload'] as String?,
        url: j['url'] as String?,
      );

  /// Emits only the key its type uses. Sending both is not a validation error,
  /// and that is the problem — Meta would keep whichever it prefers and the
  /// menu would quietly stop matching what the form showed.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'title': title,
        if (isUrl) 'url': url else 'payload': payload,
      };
}

/// One ice breaker.
class IceBreaker {
  const IceBreaker({required this.question, required this.payload});

  final String question;

  /// Required here, unlike [MenuAction.payload] which is optional. An ice
  /// breaker with nothing behind it is a question the bot cannot answer.
  final String payload;

  factory IceBreaker.fromJson(Map<String, dynamic> j) => IceBreaker(
        question: (j['question'] as String?) ?? '',
        payload: (j['payload'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'question': question, 'payload': payload};
}

/// A locale's worth of either list.
///
/// Generic over its rows because the two endpoints differ only in the shape of
/// `call_to_actions` — same envelope, same locale handling, same caps-per-locale
/// rule.
class LocaleBlock<T> {
  const LocaleBlock({required this.locale, required this.actions});

  final String locale;
  final List<T> actions;

  bool get isDefault => locale == kDefaultLocale;

  static LocaleBlock<T> fromJson<T>(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) row,
  ) {
    final List<dynamic> raw =
        (j['call_to_actions'] as List<dynamic>?) ?? const <dynamic>[];
    return LocaleBlock<T>(
      // Absent locale means Meta's fallback. Storing it explicitly keeps the
      // round trip lossless — a block read without one must not be written
      // back as a different locale.
      locale: (j['locale'] as String?)?.trim().isNotEmpty ?? false
          ? (j['locale'] as String).trim()
          : kDefaultLocale,
      actions: raw
          .whereType<Map<String, dynamic>>()
          .map(row)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) row) =>
      <String, dynamic>{
        'locale': locale,
        'call_to_actions': actions.map(row).toList(growable: false),
      };
}

/// What `GET /instagram/profile` reads back from Meta.
///
/// Read back from Meta rather than from local settings, so it is what Instagram
/// is actually serving right now — not what this workspace last tried to save.
class MessengerProfile {
  const MessengerProfile({required this.menu, required this.iceBreakers});

  final List<LocaleBlock<MenuAction>> menu;
  final List<LocaleBlock<IceBreaker>> iceBreakers;

  bool get isEmpty => menu.isEmpty && iceBreakers.isEmpty;
}
