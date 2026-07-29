/// Normalises message bodies coming off the WhatsApp log.
///
/// The console stores some message bodies as HTML — link-tracking rewrites in
/// particular arrive as a full `<a href="…">…</a>`. The web console renders
/// that as markup; a Flutter `Text` renders it as literal angle brackets, so
/// the agent sees raw tags in the bubble. Strip it once here, at the mapper
/// boundary, so both the chat bubble and the inbox preview stay clean.
abstract final class MessageText {
  static final RegExp _anchor = RegExp(
    r'<a\s[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _tag = RegExp(r'<[^>]+>');
  static final RegExp _blankRuns = RegExp(r'[ \t]{2,}');

  static const Map<String, String> _entities = <String, String>{
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
  };

  /// Returns display text: anchors collapse to their visible label (falling
  /// back to the URL when the label is empty), remaining tags are dropped and
  /// entities decoded. Plain text passes through untouched.
  static String plain(String raw) {
    if (raw.isEmpty) return raw;
    // Cheap guard so ordinary messages skip the regex work entirely.
    if (!raw.contains('<') && !raw.contains('&')) return raw;

    String out = raw.replaceAllMapped(_anchor, (Match m) {
      final String label = (m.group(2) ?? '').trim();
      final String href = (m.group(1) ?? '').trim();
      return label.isEmpty ? href : label;
    });

    out = out.replaceAll(_tag, '');
    _entities.forEach((String k, String v) => out = out.replaceAll(k, v));
    return out.replaceAll(_blankRuns, ' ').trim();
  }
}
