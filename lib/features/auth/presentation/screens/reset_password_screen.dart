import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_scaffold.dart';

/// Reset password — the second step, taking the emailed code and a new
/// password.
///
/// Reached from Forgot password, which passes the address along as `extra` so
/// it does not have to be retyped. It is also reachable directly, for someone
/// who already has a code, which is why the email field is editable rather than
/// display-only.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({this.email, super.key});

  final String? email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.email ?? '');
  final TextEditingController _token = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(
            email: _email.text.trim(),
            token: _token.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      // Every token is revoked server-side on success, so there is no session
      // to return to — Login is the only correct destination.
      context.go(AppRoutes.login);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.resetDone)),
      );
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AuthScaffold(
      onBack: () => context.pop(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.resetTitle,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.resetPrompt,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            AuthFieldLabel(l10n.loginEmailLabel),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(hintText: l10n.loginEmailHint),
              validator: (String? v) => (v == null || v.trim().isEmpty)
                  ? l10n.loginEmailRequired
                  : null,
            ),
            const SizedBox(height: 14),

            AuthFieldLabel(l10n.resetCodeLabel),
            TextFormField(
              controller: _token,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(hintText: l10n.resetCodeHint),
              validator: (String? v) => (v == null || v.trim().isEmpty)
                  ? l10n.resetCodeRequired
                  : null,
            ),
            const SizedBox(height: 14),

            AuthFieldLabel(l10n.resetNewPassword),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const <String>[AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: l10n.loginPasswordHint,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  color: AppColor.inkFaint,
                ),
              ),
              validator: (String? v) => (v == null || v.length < 8)
                  ? l10n.resetPasswordTooShort
                  : null,
            ),
            const SizedBox(height: 14),

            AuthFieldLabel(l10n.resetConfirmPassword),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(hintText: l10n.loginPasswordHint),
              // Checked here rather than left to the server: the API returns a
              // single message for a failed `confirmed` rule, which would land
              // on neither field.
              validator: (String? v) =>
                  v == _password.text ? null : l10n.resetPasswordMismatch,
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.resetSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
