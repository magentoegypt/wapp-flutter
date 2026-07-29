import 'package:flutter/material.dart';

import '../../app/theme/app_dimens.dart';

/// Circular avatar showing a contact's initials on a tinted ground.
///
/// The frames use initials throughout rather than photos — WhatsApp profile
/// pictures aren't available through the Business API, so there is no image to
/// fall back to. Tint is derived from the name so the same person keeps the
/// same colour across screens without the backend storing one.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    this.size = AppDimens.avatarList,
    super.key,
  });

  final String name;
  final double size;

  /// Muted, mid-saturation hues that stay legible under dark ink in light mode
  /// and don't compete with brand green.
  static const List<Color> _tints = <Color>[
    Color(0xFFD1F0D4),
    Color(0xFFDCE7FB),
    Color(0xFFFBE6D2),
    Color(0xFFEADCF8),
    Color(0xFFFAD9DE),
    Color(0xFFD6F0F4),
  ];

  static String initialsOf(String value) {
    final List<String> parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Color get _tint {
    if (name.isEmpty) return _tints.first;
    final int hash = name.codeUnits.fold<int>(0, (int a, int b) => a + b);
    return _tints[hash % _tints.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _tint, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF14532D),
        ),
      ),
    );
  }
}
