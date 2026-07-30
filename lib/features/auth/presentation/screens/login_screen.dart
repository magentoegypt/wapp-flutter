import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../../core/widgets/text_prompt_dialog.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/auth_repository.dart';
import '../auth_controller.dart';

/// Sign in — Figma 289:4.
///
/// The frame is a green brand hero with a white sheet lifted over it, not a
/// plain white form. An earlier version of this screen was written from the
/// token tables before the rendered frames were available and diverged badly:
/// no hero, inverted logo colours, no field labels, wrong copy. This is built
/// against the frame.
///
/// Credentials are per-agent by design: the token issued here is scoped to this
/// person and this device, so message attribution is correct and revoking one
/// employee doesn't disturb the rest of the team.
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

  /// Requests a reset link for whatever address is in the email field.
  ///
  /// The confirmation deliberately does not say whether an account was found:
  /// the endpoint answers 200 either way to avoid being an enumeration oracle,
  /// and a UI that said "we found you" would give away exactly what the API is
  /// withholding.
  /// Requests a reset link for whatever address is in the email field.
  ///
  /// The confirmation deliberately does not say whether an account was found:
  /// the endpoint answers 200 either way to avoid being an enumeration oracle,
  /// and a UI that said "we found you" would give away exactly what the API is
  /// withholding.
  Future<void> _forgotPassword() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? email = await showTextPromptDialog(
      context,
      title: l10n.loginForgotPassword,
      message: l10n.loginResetPrompt,
      confirmLabel: l10n.loginResetSend,
      hintText: l10n.loginEmailHint,
      initialValue: _email.text.trim(),
      keyboardType: TextInputType.emailAddress,
    );
    if (email == null) return;

    try {
      await ref.read(authRepositoryProvider).forgotPassword(email);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginResetSent)),
      );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // No navigation here — the router's redirect owns post-login routing so a
    // deep link captured before the session resolved is honoured.
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
    final ValidationFailure? validation =
        failure is ValidationFailure ? failure : null;

    return Scaffold(
      backgroundColor: AppColor.brand,
      // resizeToAvoidBottomInset keeps the sheet above the keyboard rather than
      // letting the hero squash it.
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Expanded(child: _BrandHero()),
            _Sheet(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l10n.loginWelcome,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.loginWorkspaceHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),

                    if (failure != null && validation == null) ...<Widget>[
                      _ErrorBanner(message: failure.message),
                      const SizedBox(height: 14),
                    ],

                    _FieldLabel(l10n.loginEmailLabel),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: l10n.loginEmailHint,
                        errorText: validation?.forField('email'),
                      ),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.loginEmailRequired
                          : null,
                    ),
                    const SizedBox(height: 14),

                    _FieldLabel(l10n.loginPasswordLabel),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const <String>[AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: l10n.loginPasswordHint,
                        errorText: validation?.forField('password'),
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
                      validator: (String? v) => (v == null || v.isEmpty)
                          ? l10n.loginPasswordRequired
                          : null,
                    ),

                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: auth.busy ? null : _forgotPassword,
                        child: Text(l10n.loginForgotPassword),
                      ),
                    ),
                    const SizedBox(height: 6),

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
                    const SizedBox(height: 16),
                    Text(
                      l10n.loginNoAccount,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green hero: the product mark, wordmark and tagline, reversed out of the
/// brand green. Shares [BrandMark] with Splash so the logo does not shift when
/// one hands over to the other.
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

/// Field caption sitting above its input, per the frame — the previous version
/// relied on placeholders, which vanish as soon as the user types.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

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
