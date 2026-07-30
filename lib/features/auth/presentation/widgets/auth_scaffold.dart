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
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(child: _BrandHero()),
                  if (onBack != null)
                    PositionedDirectional(
                      start: 6,
                      top: 0,
                      child: IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                      ),
                    ),
                ],
              ),
            ),
            _Sheet(child: child),
          ],
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
      child: SingleChildScrollView(
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
