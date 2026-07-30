import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The product mark on its white tile, reversed out of a brand-green ground.
///
/// Shared rather than inlined because Splash hands straight over to Login: any
/// difference in size, radius or padding between the two makes the logo visibly
/// jump at the moment the session resolves.
///
/// The asset is a self-contained two-tone SVG (brand green plus opaque white
/// for its negative space), so it needs a white ground beneath it — it is not
/// tintable.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: SvgPicture.asset('assets/branding/logo.svg'),
      ),
    );
  }
}
