import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the agent is telling the workspace about their availability.
enum Presence { available, busy, away }

/// The agent's own presence selection, as offered by the Profile frame.
///
/// Session-local on purpose. There is no presence endpoint on the mobile API —
/// `/agents` exposes only `active`, the account-enabled flag — so there is
/// nothing to publish the choice to yet. Keeping it in a provider rather than
/// in [State] means the selection survives leaving Profile, and swapping the
/// default for a fetched value later is a one-file change.
final presenceProvider = StateProvider<Presence>(
  (Ref ref) => Presence.available,
);
