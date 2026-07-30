import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'initials_avatar.dart';

/// The signed-in agent's avatar, for the trailing slot of a search header.
///
/// A widget rather than a helper on each screen so the session lookup lives in
/// one place — the frames put this in the top-right of every list root, and
/// three screens were each about to read the auth provider themselves.
///
/// Renders nothing until the session resolves, so a cold start does not flash a
/// "?" placeholder in the header.
class AgentAvatar extends ConsumerWidget {
  const AgentAvatar({this.size = 34, super.key});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String name =
        ref.watch(authControllerProvider).session?.user.name ?? '';
    if (name.isEmpty) return const SizedBox.shrink();
    // onBrand: this sits on the green header, where the hash-tinted list
    // pastels can land on pink or purple.
    return InitialsAvatar.onBrand(name: name, size: size);
  }
}
