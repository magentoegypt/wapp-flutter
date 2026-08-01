import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../l10n/app_localizations.dart';
import '../error/failure.dart';

/// Renders an [AsyncValue] with consistent loading and error treatment, so no
/// screen hand-rolls a spinner or leaks a raw exception into the UI.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () =>
          loading ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      // A plan refusal is not an error and retrying cannot fix it — the same
      // 403 comes back every time. Showing it in the red error state with a
      // Retry button tells the user the app is broken and invites them to
      // hammer an endpoint that will never say yes.
      error: (Object error, StackTrace _) => switch (error) {
        final PlanLimitFailure f => PlanLimitMessage(failure: f),
        final Failure f => FailureMessage(message: f.message, onRetry: onRetry),
        // Anything that isn't a Failure escaped the data layer — show a
        // generic message rather than a Dart exception string.
        _ => FailureMessage(
            message: 'Something went wrong. Try again.',
            onRetry: onRetry,
          ),
      },
    );
  }
}

/// The workspace's plan does not include this module.
///
/// Deliberately calm: a lock rather than a red cross, and no Retry. The action
/// that would help is an upgrade, which happens in the web console — the app
/// has no billing screen, so this says what is missing and stops there rather
/// than pretending there is something to tap.
class PlanLimitMessage extends StatelessWidget {
  const PlanLimitMessage({required this.failure, super.key});

  final PlanLimitFailure failure;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline, size: 30, color: AppColor.warning),
            const SizedBox(height: 12),
            Text(
              l10n.planLimitTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.planLimitUpgradeHint,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColor.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centred error state with an optional retry.
class FailureMessage extends StatelessWidget {
  const FailureMessage({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 28, color: AppColor.danger),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context).actionRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centred empty state for a list with no rows.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 34, color: AppColor.inkFaint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
