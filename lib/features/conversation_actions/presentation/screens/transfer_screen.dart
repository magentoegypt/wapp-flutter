import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../../agents/data/agent_repository.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Transfer conversation.
///
/// A transfer is a *request*. It goes through the workspace approval policy and
/// nothing about the conversation changes when this screen closes — the owner
/// an agent sees afterwards is still the old one, by design. Assign is the
/// immediate one, and the two sit next to each other in the ⋮ sheet reading
/// almost identically, so the amber banner names Assign outright rather than
/// leaving someone to discover the difference from a stale owner line.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final TextEditingController _reason = TextEditingController();

  /// One destination, rather than a nullable team uid beside a nullable user
  /// uid.
  ///
  /// The endpoint rejects a body carrying both, so the invalid state is kept
  /// unrepresentable here instead of being validated after the fact: choosing a
  /// team overwrites an agent and vice versa, which is exactly the clearing the
  /// UI has to show anyway.
  _TransferTarget? _target;

  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _TransferTarget? target = _target;

    if (target == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.trPickOne)));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(conversationActionRepositoryProvider).transfer(
            contactUid: widget.contactUid,
            toTeamUid: target.isTeam ? target.uid : null,
            toUserUid: target.isTeam ? null : target.uid,
            // Optional, and the repository drops it when blank. It is the only
            // context the approver gets, so it is worth asking for.
            reason: _reason.text,
          );
      if (!mounted) return;
      // Nothing cached is invalidated on purpose: the request is queued for
      // approval, so the inbox row and the chat header are still correct.
      // ScaffoldMessenger sits above this route, so the confirmation survives
      // the pop on the next line.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.trDone)));
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Team>> teams = ref.watch(teamsProvider);
    final AsyncValue<List<Agent>> agents = ref.watch(agentListProvider);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.trTitle),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Pinned above the picker rather than sat next to the button: an
            // agent who wanted an immediate owner change should find that out
            // before spending time choosing a destination on the wrong screen.
            AppBanner(
              message: l10n.trNotAssign,
              tone: BannerTone.warning,
              icon: Icons.how_to_reg_outlined,
            ),
            Expanded(
              // Nested so the picker appears once both lists are in. The choice
              // spans the two of them, and rendering teams while the roster is
              // still spinning invites a pick made without seeing half the
              // options.
              child: AsyncValueView<List<Team>>(
                value: teams,
                onRetry: () => ref.invalidate(teamsProvider),
                builder: (List<Team> teamList) => AsyncValueView<List<Agent>>(
                  value: agents,
                  onRetry: () => ref.invalidate(agentListProvider),
                  builder: (List<Agent> agentList) =>
                      _body(context, l10n, teamList, agentList),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
              child: FilledButton(
                // Left enabled with nothing chosen: the button is where an
                // agent looks for "what now", and trPickOne answers that there.
                // A disabled control just goes quiet about why.
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.trSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    List<Team> teams,
    List<Agent> agents,
  ) {
    return ListView(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppDimens.gutter,
            end: AppDimens.gutter,
            top: 14,
          ),
          child: Text(
            l10n.trPrompt,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        // A one-person workspace has no teams, and a small one can have a
        // roster of just the reader. An empty group under a heading reads as a
        // failed load, so the heading goes with its rows.
        if (teams.isNotEmpty) ...<Widget>[
          SectionLabel(l10n.trToTeam),
          for (final Team t in teams)
            _ChoiceRow(
              title: t.name,
              leading: const IconTile(
                icon: Icons.groups_outlined,
                color: AppColor.info,
              ),
              selected: _target?.isTeam == true && _target?.uid == t.uid,
              onTap: () => setState(
                () => _target = _TransferTarget(uid: t.uid, isTeam: true),
              ),
            ),
        ],
        if (agents.isNotEmpty) ...<Widget>[
          SectionLabel(l10n.trToAgent),
          for (final Agent a in agents)
            _ChoiceRow(
              title: a.name,
              subtitle: a.email.isEmpty ? null : a.email,
              // Sized to the team rows' icon tile so both lists share one left
              // edge; the avatar's own default is a list-row 42.
              leading: InitialsAvatar(name: a.name, size: AppDimens.iconTile),
              selected: _target?.isTeam == false && _target?.uid == a.uid,
              onTap: () => setState(
                () => _target = _TransferTarget(uid: a.uid, isTeam: false),
              ),
            ),
        ],
        SectionLabel(l10n.trReason),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppDimens.gutter,
            end: AppDimens.gutter,
          ),
          child: TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(hintText: l10n.trReasonHint),
          ),
        ),
      ],
    );
  }
}

/// Where a transfer is headed. [isTeam] decides which of the two mutually
/// exclusive request fields [uid] is written into.
class _TransferTarget {
  const _TransferTarget({required this.uid, required this.isTeam});

  final String uid;
  final bool isTeam;
}

/// One destination row: the shared tile plus the state of the choice.
///
/// Disc glyphs, not boxes — a transfer has exactly one destination, and the
/// shape says so before anyone has tapped. The glyph is the only visual cue, so
/// the row announces its selection too; a screen reader hearing only the team
/// name has no way to tell which destination is armed.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.leading,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: AppListTile(
        title: title,
        subtitle: subtitle,
        leading: leading,
        onTap: onTap,
        // No chevron: this row commits a choice in place, it does not push.
        showChevron: false,
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 20,
          color: selected ? AppColor.brandDeep : AppColor.inkFaint,
        ),
      ),
    );
  }
}
