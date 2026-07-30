import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/brand_mark.dart';

/// Shown while a stored token is validated against `GET /me`.
///
/// Deliberately a separate route from Login. When the two were the same
/// screen, "checking your session" and "you are signed out" were
/// indistinguishable, so a cold start always flashed the sign-in form — and if
/// the resolved auth state failed to reach the router, the user was stranded
/// on it with a perfectly valid token.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColor.brand,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandMark(),
            SizedBox(height: 14),
            Text(
              'Clickalize',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
