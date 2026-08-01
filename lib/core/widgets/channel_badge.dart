import 'package:flutter/material.dart';

import '../../app/theme/app_dimens.dart';
import '../../features/inbox/domain/channel.dart';
import 'app_icon.dart';
import 'initials_avatar.dart';

/// The network mark that rides on a contact's avatar.
///
/// Drawn as a filled disc with a knocked-out glyph rather than a line icon: at
/// [markSize] a 2px stroke turns to mush, and the handoff records this being
/// redrawn twice before it was legible. The colour is the network's own brand
/// green/pink from [MessageChannelX.badgeColor] — the badge's whole job is to
/// say "this is that network", so it must not follow the app palette.
class ChannelBadge extends StatelessWidget {
  const ChannelBadge({required this.channel, this.markSize = _mark, super.key});

  final MessageChannel channel;

  /// Diameter of the coloured disc, excluding [_ring]. The ring is drawn
  /// *outside* it, so the mark keeps its designed size whatever it sits on.
  final double markSize;

  static const double _mark = 12;
  static const double _ring = 2;

  /// The ring is white, not the surface colour: it lands on a hash-tinted
  /// avatar that can be any of six pastels — or deep green on the header
  /// variant — so the separator has to be one constant that beats all of them.
  static const Color _ringColor = Colors.white;

  double get _diameter => markSize + _ring * 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _ringColor,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: markSize,
        height: markSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: channel.badgeColor,
          shape: BoxShape.circle,
        ),
        child: AppIcon(
          channel.badgeAsset,
          // Leaves roughly 2px of colour around the glyph. Any larger and the
          // mark bleeds into the ring and the disc stops reading as a disc.
          size: markSize * 0.66,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// An [InitialsAvatar] carrying its conversation's [ChannelBadge].
///
/// Pinned to the bottom-end corner through [PositionedDirectional], so the mark
/// moves to the bottom-left in Arabic and stays on the outside of the row
/// rather than colliding with the title.
class AvatarWithChannel extends StatelessWidget {
  const AvatarWithChannel({
    required this.name,
    required this.channel,
    this.size = AppDimens.avatarList,
    super.key,
  });

  final String name;
  final MessageChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        InitialsAvatar(name: name, size: size),
        // Flush with the box corner rather than nudged inwards: that puts the
        // badge's centre almost exactly on the disc's 45° rim point, which is
        // the straddle the frame shows. Insetting it left the mark floating in
        // the middle of the initials.
        PositionedDirectional(
          bottom: 0,
          end: 0,
          child: ChannelBadge(channel: channel),
        ),
      ],
    );
  }
}
