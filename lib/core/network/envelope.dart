/// Readers for this API's response envelope.
///
/// The convention is a domain-named key rather than `data`:
/// `{success, conversations: [...]}`, `{success, historyAccess: {...}}`. So
/// [ApiClient] cannot unwrap it generically, and each caller has to reach its
/// payload by name.
///
/// Both helpers fall back to `data` and then to the body itself, because a
/// couple of endpoints do answer flat and an envelope change should not empty a
/// screen.
///
/// These live here rather than being re-declared per repository because getting
/// one wrong is silent. Reading a nested field from the top level does not
/// throw — it yields null and falls to whatever default the model declares.
/// That is how an owner was shown the agent view of History access: the payload
/// nested `isVendorAdmin: true` under `historyAccess`, the repository read it
/// from the root, and `?? false` did the rest.
library;

/// A single record nested under [key].
Map<String, dynamic> envelopeRecord(dynamic body, String key) {
  // `is`, not `as ...?`. A cast only tolerates null — anything else that is not
  // a map throws a raw TypeError, which escapes the data layer as something
  // other than a Failure and degrades to the generic "Something went wrong".
  // A proxy or maintenance page answering 200 with HTML is exactly that case.
  if (body is! Map<String, dynamic>) return const <String, dynamic>{};
  final Object? inner = body[key] ?? body['data'];
  return inner is Map<String, dynamic> ? inner : body;
}

/// A list nested under [key].
List<Map<String, dynamic>> envelopeRows(dynamic body, String key) {
  if (body is List) return body.whereType<Map<String, dynamic>>().toList();
  if (body is! Map<String, dynamic>) return const <Map<String, dynamic>>[];
  final Object? raw = body[key] ?? body['data'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.whereType<Map<String, dynamic>>().toList();
}
