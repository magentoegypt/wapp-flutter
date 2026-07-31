import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../calls/domain/call.dart';
import '../../../inbox/data/conversation_repository.dart';
import '../../data/conversation_action_repository.dart';

/// Request call permission — reached from the chat ⋮ sheet.
///
/// Explain, then confirm. The write takes no arguments at all, so there is
/// nothing to fill in and nothing to validate; the whole screen exists so the
/// agent understands that pressing the button messages the customer rather than
/// flipping a setting on our side.
///
/// Stateful only for [_submitting]: this sends a message to a real person, and
/// an unguarded double tap sends it twice.
class CallPermissionScreen extends ConsumerStatefulWidget {
  const CallPermissionScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<CallPermissionScreen> createState() =>
      _CallPermissionScreenState();
}

class _CallPermissionScreenState extends ConsumerState<CallPermissionScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _submitting = true);

    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .requestCallPermission(widget.contactUid);

      // The request is delivered as a message in this conversation, so the
      // thread the agent lands back on is out of date the moment this returns.
      ref.invalidate(chatThreadProvider(widget.contactUid));

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.cpermDone)));
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // There is no endpoint that answers "may we call this customer" — consent
    // is recorded per call, so an earlier call carrying it is the only evidence
    // the client has. Read through `valueOrNull` rather than an AsyncValueView:
    // this is a hint about the request, not the subject of the screen, and a
    // slow or failing history fetch must not hide the one button here.
    final List<CallRecord> calls =
        ref.watch(callHistoryProvider(widget.contactUid)).valueOrNull?.calls ??
            const <CallRecord>[];
    final bool consentOnFile =
        calls.any((CallRecord c) => c.callbackConsentGiven);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.cpermTitle),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Shown, not enforced: permission lapses with the service window,
            // so a customer who agreed last month may still need asking. The
            // button stays live.
            if (consentOnFile)
              AppBanner(
                message: l10n.cpermGranted,
                tone: BannerTone.brand,
                icon: Icons.check_circle_outline,
              ),
            Expanded(
              // Scrollable so the explanation survives a large text scale
              // instead of overflowing above the pinned button.
              child: ListView(
                padding: const EdgeInsets.all(AppDimens.gutter),
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const IconTile(
                        icon: Icons.phone_outlined,
                        color: AppColor.info,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.cpermPrompt,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.cpermSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
