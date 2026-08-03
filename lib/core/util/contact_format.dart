/// Display formatting shared by Contact detail and Conversation info.
///
/// Both screens render the same customer record and must not disagree about
/// how a phone number or a language code looks.
library;

/// A wire phone number as the frame shows it: `+20 102 998 1200`.
///
/// `wa_id` is stored bare — country code first, no `+`, no separators — which
/// is exactly what the send endpoints want and exactly what nobody wants to
/// read.
///
/// The trailing ten digits are grouped 3-3-4 and whatever precedes them is
/// shown as the dialling code. That boundary is **inferred from length, not
/// known**: it is exact for Egypt (`20` + 10 digits), which is this
/// workspace's market and the frame's example, and can split a digit early for
/// a country with a three-digit code and a shorter subscriber number. Getting
/// it right everywhere needs a per-country table, which is a lot to carry for
/// a display string.
///
/// What it never does is change the digits — [formatPhone] is presentation
/// only, and every send path uses the raw `wa_id`.
///
/// Anything that is not a bare number is returned untouched, so a value that
/// already carries a `+` or spaces is not mangled.
String formatPhone(String raw) {
  final String digits = raw.trim();
  if (digits.isEmpty) return digits;
  if (!RegExp(r'^\d{7,15}$').hasMatch(digits)) return digits;

  final int n = digits.length;
  if (n <= 10) return '+$digits';

  final String code = digits.substring(0, n - 10);
  final String a = digits.substring(n - 10, n - 7);
  final String b = digits.substring(n - 7, n - 4);
  final String c = digits.substring(n - 4);

  return '+$code $a $b $c';
}

/// A language name for a wire code — "en" → "English".
///
/// Only the codes this workspace actually uses are mapped. An unknown code is
/// returned upper-cased rather than guessed at, which reads as a code and not
/// as a wrong language.
String? languageName(String? code) {
  final String c = (code ?? '').trim().toLowerCase();
  if (c.isEmpty) return null;
  const Map<String, String> names = <String, String>{
    'en': 'English',
    'ar': 'العربية',
    'fr': 'Français',
    'es': 'Español',
    'de': 'Deutsch',
    'it': 'Italiano',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'hi': 'हिन्दी',
    'ur': 'اردو',
    'pt': 'Português',
    'zh': '中文',
  };
  return names[c] ?? names[c.split(RegExp('[-_]')).first] ?? c.toUpperCase();
}
