import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons the Material font does not have.
///
/// Most of this app's glyphs are Material, which is fine — a house is a house.
/// Three are not, and each was wrong in a way no substitute fixes:
///
/// * **The chat bubble.** Material's `chat_bubble_outline` is a rectangle with
///   a hard-cornered tail. The frame draws a round bubble with a soft tail, and
///   at 24px in the tab bar that difference is the whole character of the icon.
///   `messenger_outline` and the `_rounded` variants are the same rectangle.
/// * **WhatsApp and Instagram.** These were standing in as `Icons.chat` and
///   `Icons.camera_alt` — a generic speech bubble and a generic camera. The
///   badge's entire job is to say *which network this conversation is on*, so a
///   glyph that merely suggests "messaging" does not do it. These are the
///   networks' own marks, used to identify the channel, which is what the
///   frames do too.
///
/// All four take their colour from the caller so they behave like an [Icon].
abstract final class AppIcons {
  static const String chatOutline = 'assets/icons/chat_outline.svg';
  static const String chatFilled = 'assets/icons/chat_filled.svg';
  static const String whatsapp = 'assets/icons/whatsapp.svg';
  static const String instagram = 'assets/icons/instagram.svg';
}

/// An SVG asset drawn at [size] in [color], sized and tinted like an [Icon].
class AppIcon extends StatelessWidget {
  const AppIcon(this.asset, {required this.size, required this.color, super.key});

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      // srcIn, not modulate: the paths carry `currentColor`, which flutter_svg
      // resolves to black. Replacing the source colour outright is what makes
      // one asset serve a grey tab, a green tab and a white badge alike.
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
