/// Parses an enum by name, case- and whitespace-insensitively.
///
/// Unrecognised values fall to [fallback] rather than to a guess. That rule was
/// written after a real bug: an unknown campaign label became `draft`, and the
/// detail screen gated its Send button on exactly that, so a finished campaign
/// offered to send itself again.
///
/// It matters more now than it did then. The API resolves eighteen message
/// types and seven call statuses, and this install has only ever produced a
/// subset of each — `sticker` has never occurred, and only `completed` and
/// `no_answer` appear among call statuses. Any client that assumes the observed
/// set is the whole set breaks the first time somebody rejects a call. Both
/// vocabularies carry an explicit catch-all (`unsupported`, `failed`) that is
/// the right thing to pass as [fallback].
T enumByName<T extends Enum>(Object? raw, List<T> values, T fallback) {
  final String key = '${raw ?? ''}'.trim().toLowerCase();
  for (final T v in values) {
    if (v.name.toLowerCase() == key) return v;
  }
  return fallback;
}
