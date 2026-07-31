import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../../l10n/app_localizations.dart';

/// The signed-out chrome: brand-green hero above a white sheet.
///
/// Shared by Login, Forgot password and Reset password so the three read as one
/// flow. It was private to Login until recovery became its own screens, at
/// which point copying the hero twice would have guaranteed drift.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, this.onBack, super.key});

  final Widget child;

  /// Shown as a back affordance over the hero. Login is the root of this flow
  /// and passes null.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.brand,
      // Scrolls once the keyboard no longer leaves room for the form.
      //
      // The hero took Expanded and the sheet its natural height, which is fine
      // at rest and overflows the moment the keyboard opens: the hero cannot
      // shrink below its own content, so the column ran 125px past the bottom
      // and Flutter painted the yellow-and-black bar over Login. It affected
      // all three signed-out screens, since they share this scaffold.
      //
      // minHeight pins the layout to the full viewport when there IS room, so
      // the hero still fills the screen and the sheet still sits at the
      // bottom; IntrinsicHeight is what keeps Expanded meaningful inside a
      // scroll view, whose children are otherwise unbounded.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Stack(
                          children: <Widget>[
                            // Deliberately NOT Positioned.fill, which is what
                            // it was: a Stack reports the intrinsic height of
                            // its non-positioned children only, so a wholly
                            // positioned Stack measures zero. IntrinsicHeight
                            // then budgeted nothing for the hero and squeezed
                            // it until its own Column overflowed. Unpositioned,
                            // it both measures and still fills, because
                            // Expanded hands the Stack a tight height and
                            // Center expands into it.
                            const _BrandHero(),
                            if (onBack != null)
                              PositionedDirectional(
                                start: 6,
                                top: 0,
                                child: IconButton(
                                  onPressed: onBack,
                                  icon: const Icon(Icons.arrow_back),
                                  color: Colors.white,
                                  tooltip: MaterialLocalizations.of(context)
                                      .backButtonTooltip,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _Sheet(child: child),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const BrandMark(),
          const SizedBox(height: 14),
          const Text(
            'Clickalize',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).loginTagline,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// White card lifted over the hero, rounded on its top corners only.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      // Plain padding, not a scroll view: the scaffold above now scrolls the
      // whole page, and nesting a second vertical scroller inside it would
      // give this one unbounded height.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter,
          24,
          AppDimens.gutter,
          24,
        ),
        child: child,
      ),
    );
  }
}

/// Field caption sitting above its input, per the frames — placeholders vanish
/// as soon as the user types.
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6, start: 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColor.inkMuted,
          ),
        ),
      ),
    );
  }
}
