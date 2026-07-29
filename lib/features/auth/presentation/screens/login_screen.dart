import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// Sign in with the agent's own credentials — Figma 289:4.
///
/// Deliberately per-agent rather than a workspace-wide key: the token issued
/// here is scoped to this person and this device, so message attribution is
/// correct and revoking one employee doesn't disturb the rest of the team.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // No navigation on success. The router's redirect owns post-login routing:
    // it restores a deep link captured before the session resolved, falling
    // back to Home. Calling context.go(home) here raced that and always won,
    // so a link that sent the user to Login — the most common case — was
    // consumed and then discarded, landing them on Home instead.
    await ref.read(authControllerProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final Failure? failure = auth.failure;

    // Field-level messages when the server returns 422, otherwise one banner.
    final ValidationFailure? validation =
        failure is ValidationFailure ? failure : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.gutter,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _Wordmark(),
                    const SizedBox(height: 28),
                    Text(
                      l10n.loginTitle,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.loginSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),

                    if (failure != null && validation == null) ...<Widget>[
                      _ErrorBanner(message: failure.message),
                      const SizedBox(height: 14),
                    ],

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.loginEmailLabel,
                        errorText: validation?.forField('email'),
                      ),
                      validator: (String? v) =>
                          (v == null || v.trim().isEmpty) ? l10n.loginEmailRequired : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const <String>[AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: l10n.loginPasswordLabel,
                        errorText: validation?.forField('password'),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          color: AppColor.inkFaint,
                        ),
                      ),
                      validator: (String? v) =>
                          (v == null || v.isEmpty) ? l10n.loginPasswordRequired : null,
                    ),
                    const SizedBox(height: 22),

                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.loginSubmit),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColor.brand,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.chat_bubble, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text(
          'Clickalize',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColor.ink,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.dangerWash,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppColor.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColor.danger),
            ),
          ),
        ],
      ),
    );
  }
}
