import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// History access — one screen serving both the agent and the admin frame.
///
/// `/history-access` self-gates: a non-admin is answered with empty queues and
/// nothing but their own status, so the two frames are the same read rendered
/// two ways. Splitting them would mean two routes hitting one endpoint and a
/// caller that has to know which one it is entitled to before it can ask.
///
/// Stateful because two mutations need local state the snapshot cannot supply:
/// a busy flag, so a second tap cannot fire a second decision on a row that is
/// already being decided, and an optimistic value for the reveal switch — the
/// provider keeps serving the stale snapshot while it refetches, so without one
/// the toggle springs back under the user's finger and reads as a failure.
class HistoryAccessScreen extends ConsumerStatefulWidget {
  const HistoryAccessScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<HistoryAccessScreen> createState() =>
      _HistoryAccessScreenState();
}

class _HistoryAccessScreenState extends ConsumerState<HistoryAccessScreen> {
  /// Held across every mutation on the screen: approving one row and revoking
  /// another at the same time races two writes against one refetch.
  bool _busy = false;

  /// The reveal value this screen last wrote successfully, or null to trust the
  /// snapshot. Cleared on failure so the server's answer wins again.
  bool? _pendingReveal;

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Re-reads the endpoint. Every mutation ends here rather than patching the
  /// snapshot in place — a decision can change the queues, the current user's
  /// status and the reveal flag at once, and only the server knows how.
  void _reload() => ref.invalidate(historyAccessProvider(widget.contactUid));

  Future<void> _request() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .requestHistoryAccess(widget.contactUid);
      if (!mounted) return;
      _reload();
      _snack(l10n.hxRequested);
      // Asking is all an agent can do here, and the answer arrives out of band
      // — leaving them parked on a screen that only says "awaiting approval"
      // would suggest there is something left to wait for on it.
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(HistoryAccessRequest request, bool approve) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .decideHistoryAccess(requestUid: request.uid, approve: approve);
      if (!mounted) return;
      _reload();
      _snack(l10n.hxDecided);
    } on Failure catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(HistoryAccessRequest request) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .revokeHistoryAccess(request.uid);
      if (!mounted) return;
      _reload();
      _snack(l10n.hxDecided);
    } on Failure catch (e) {
      if (!mounted) return;
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setReveal(bool reveal) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _pendingReveal = reveal;
    });
    try {
      await ref.read(conversationActionRepositoryProvider).revealFullHistory(
            contactUid: widget.contactUid,
            reveal: reveal,
          );
      if (!mounted) return;
      _reload();
      _snack(l10n.hxDecided);
    } on Failure catch (e) {
      if (!mounted) return;
      // The write did not land, so the optimistic value is a lie — drop it and
      // let the switch fall back to whatever the snapshot says.
      _pendingReveal = null;
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<HistoryAccessSnapshot> snapshot =
        ref.watch(historyAccessProvider(widget.contactUid));

    return Scaffold(
      appBar: AppHeader.back(title: l10n.hxTitle),
      body: AsyncValueView<HistoryAccessSnapshot>(
        value: snapshot,
        onRetry: _reload,
        builder: (HistoryAccessSnapshot data) => data.isVendorAdmin
            ? _adminView(context, l10n, data)
            : _agentView(context, l10n, data),
      ),
    );
  }

  /// What this agent's own request looks like, and the one control they have.
  ///
  /// Rendered through [EmptyState] rather than a list: there is nothing to list
  /// on this side — the frame is a single sentence about your standing plus one
  /// button — and it already lays out glyph, sentence and action.
  Widget _agentView(
    BuildContext context,
    AppLocalizations l10n,
    HistoryAccessSnapshot data,
  ) {
    final HistoryAccessStatus status = data.currentUserStatus;
    // Pending hides the button on purpose: the request is already queued, and a
    // second one neither reprioritises it nor tells the admin anything new.
    final bool canRequest = status == HistoryAccessStatus.none ||
        status == HistoryAccessStatus.denied;

    return Column(
      children: <Widget>[
        AppBanner(
          message: l10n.hxPromptAgent,
          tone: BannerTone.brand,
          icon: Icons.history_toggle_off,
        ),
        Expanded(
          child: EmptyState(
            icon: _statusIcon(status),
            title: _statusLabel(l10n, status),
            action: canRequest
                ? FilledButton(
                    onPressed: _busy ? null : _request,
                    child: Text(l10n.hxRequest),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  /// The two queues plus the workspace-wide switch.
  Widget _adminView(
    BuildContext context,
    AppLocalizations l10n,
    HistoryAccessSnapshot data,
  ) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final bool reveal = _pendingReveal ?? data.revealFullHistory;

    return Column(
      children: <Widget>[
        AppBanner(
          message: l10n.hxPromptAdmin,
          tone: BannerTone.brand,
          icon: Icons.verified_user_outlined,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.only(bottom: AppDimens.gutter),
            children: <Widget>[
              // The note is not decoration: this switch is not scoped to the
              // admin flipping it, it opens the contact's history to every
              // agent in the workspace and silently outranks the queues below.
              SwitchListTile(
                value: reveal,
                onChanged: _busy ? null : _setReveal,
                title: Text(l10n.hxRevealTitle),
                subtitle: Text(l10n.hxRevealNote),
                contentPadding: const EdgeInsetsDirectional.only(
                  start: AppDimens.gutter,
                  end: AppDimens.gutter - 6,
                ),
              ),
              SectionLabel(l10n.hxPending),
              if (data.pending.isEmpty)
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: l10n.hxNoPending,
                )
              else
                for (final HistoryAccessRequest r in data.pending)
                  _RequestRow(
                    request: r,
                    locale: locale,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _RowAction(
                          label: l10n.hxApprove,
                          color: AppColor.brandDeep,
                          onPressed: _busy ? null : () => _decide(r, true),
                        ),
                        _RowAction(
                          label: l10n.hxDeny,
                          color: AppColor.inkMuted,
                          onPressed: _busy ? null : () => _decide(r, false),
                        ),
                      ],
                    ),
                  ),
              // No empty copy for this section — an admin who has approved
              // nobody is the normal state, and a second "nothing here" block
              // under the first would read as a fault.
              if (data.approved.isNotEmpty) ...<Widget>[
                SectionLabel(l10n.hxApproved),
                for (final HistoryAccessRequest r in data.approved)
                  _RequestRow(
                    request: r,
                    locale: locale,
                    trailing: _RowAction(
                      label: l10n.hxRevoke,
                      color: AppColor.danger,
                      onPressed: _busy ? null : () => _revoke(r),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _statusLabel(AppLocalizations l10n, HistoryAccessStatus status) {
  return switch (status) {
    HistoryAccessStatus.none => l10n.hxStatusNone,
    HistoryAccessStatus.pending => l10n.hxStatusPending,
    HistoryAccessStatus.approved => l10n.hxStatusApproved,
    HistoryAccessStatus.denied => l10n.hxStatusDenied,
  };
}

IconData _statusIcon(HistoryAccessStatus status) {
  return switch (status) {
    HistoryAccessStatus.none => Icons.lock_outline,
    HistoryAccessStatus.pending => Icons.hourglass_empty,
    HistoryAccessStatus.approved => Icons.lock_open_outlined,
    HistoryAccessStatus.denied => Icons.block_outlined,
  };
}

/// One requester, with whatever the caller wants to offer on that row.
///
/// Both queues show the same identity — avatar, name, when it was asked for —
/// and differ only in the actions, so the row takes those as a parameter rather
/// than branching on which list it came from.
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.locale,
    required this.trailing,
  });

  final HistoryAccessRequest request;
  final String locale;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final DateTime? at = request.requestedAt;

    return AppListTile(
      title: request.agentName,
      subtitle: at == null
          ? null
          : DateFormat.yMMMd(locale).add_jm().format(at),
      leading: InitialsAvatar(name: request.agentName),
      trailing: trailing,
      // The actions live on the row itself; a chevron would promise a detail
      // page that does not exist.
      showChevron: false,
      dense: true,
    );
  }
}

/// Compact text action sized to sit inside a row's trailing slot.
///
/// A null [onPressed] is the disabled state — every one of these is inert while
/// any mutation on the screen is in flight.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
