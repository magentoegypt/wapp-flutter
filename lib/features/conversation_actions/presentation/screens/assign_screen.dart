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
import '../../../inbox/data/conversation_repository.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Assign conversation.
///
/// The immediate counterpart to Transfer: Save writes the owner and the teams
/// straight through, with no approval step. Both halves are *replacements*
/// rather than additions — `assignUser(null)` unassigns and `assignTeams([])`
/// clears every team — so this screen's job is to make the state it is about to
/// write visible before the button is pressed, not to hide it behind an
/// untouched-means-unchanged assumption it cannot honour. There is no read
/// endpoint for the current owner, which is why the destructive defaults are
/// shown rather than pre-filled.
class AssignScreen extends ConsumerStatefulWidget {
  const AssignScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends ConsumerState<AssignScreen> {
  /// Null is a value here, not "nothing picked yet" — it is what the API reads
  /// as unassign, and the Unassigned row is how it is selected.
  String? _ownerUid;

  /// Teams accumulate; the owner replaces. A set rather than a single uid is
  /// the whole difference between the two halves of this screen.
  final Set<String> _teamUids = <String>{};

  bool _saving = false;

  void _toggleTeam(String uid) {
    setState(() {
      if (_teamUids.contains(uid)) {
        _teamUids.remove(uid);
      } else {
        _teamUids.add(uid);
      }
    });
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    setState(() => _saving = true);
    try {
      final ConversationActionRepository repo =
          ref.read(conversationActionRepositoryProvider);
      // Two writes behind one button — there is no combined endpoint. Owner
      // first: it is the change the agent came here for, so if the team write
      // fails afterwards the conversation is at least owned by someone, and the
      // failure message says the rest did not land.
      await repo.assignUser(contactUid: widget.contactUid, userUid: _ownerUid);
      await repo.assignTeams(
        contactUid: widget.contactUid,
        teamUids: _teamUids.toList(),
      );
      if (!mounted) return;
      // The owner is printed on the inbox row and in the chat header, and both
      // are cached — without this the screen popped back to still names the
      // previous one, which reads as the save having failed.
      ref.invalidate(chatThreadProvider(widget.contactUid));
      ref.invalidate(inboxListProvider);
      // ScaffoldMessenger sits above this route, so the confirmation survives
      // the pop on the next line.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.asDone)));
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
      appBar: AppHeader.back(title: l10n.asTitle),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Brand tone, pinned to the top, where Transfer carries an amber
            // "needs approval" strip in the same slot. The colour is doing the
            // work: the two screens are otherwise near-identical lists of the
            // same people, and this is the one that takes effect on Save.
            AppBanner(
              message: l10n.asPrompt,
              tone: BannerTone.brand,
              icon: Icons.bolt_outlined,
            ),
            Expanded(
              // Nested so the form appears once both lists are in: Save writes
              // owner *and* teams, and a form that renders half of what it is
              // about to submit invites a Save made without seeing the rest.
              child: AsyncValueView<List<Agent>>(
                value: agents,
                onRetry: () => ref.invalidate(agentListProvider),
                builder: (List<Agent> agentList) => AsyncValueView<List<Team>>(
                  value: teams,
                  onRetry: () => ref.invalidate(teamsProvider),
                  builder: (List<Team> teamList) =>
                      _body(l10n, agentList, teamList),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
              child: FilledButton(
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
                    : Text(l10n.asSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, List<Agent> agents, List<Team> teams) {
    return ListView(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      children: <Widget>[
        SectionLabel(l10n.asAgent),
        // First, and always present even on an empty roster: `assignUser(null)`
        // is what unassigns, so "no owner" has to be something you can point
        // at. It is also the state the screen opens in, which is the honest
        // rendering of what Save would do before anything is touched.
        _ChoiceRow(
          title: l10n.asUnassigned,
          leading: const IconTile(
            icon: Icons.person_off_outlined,
            color: AppColor.inkMuted,
          ),
          selected: _ownerUid == null,
          onTap: () => setState(() => _ownerUid = null),
        ),
        for (final Agent a in agents)
          _ChoiceRow(
            title: a.name,
            subtitle: a.email.isEmpty ? null : a.email,
            // Sized to the Unassigned row's icon tile so the column shares one
            // left edge; the avatar's own default is a list-row 42.
            leading: InitialsAvatar(name: a.name, size: AppDimens.iconTile),
            selected: _ownerUid == a.uid,
            onTap: () => setState(() => _ownerUid = a.uid),
          ),
        // Hidden entirely on a workspace with no teams: with nothing to select,
        // the heading and its warning would describe a write that cannot lose
        // anything.
        if (teams.isNotEmpty) ...<Widget>[
          SectionLabel(l10n.asTeams),
          // Only while the selection is empty, because that is the only time it
          // is true: the plural endpoint replaces the whole set, so saving from
          // here strips whatever routing the conversation already had.
          if (_teamUids.isEmpty)
            AppBanner(
              message: l10n.asTeamsHint,
              tone: BannerTone.warning,
              icon: Icons.info_outline,
            ),
          for (final Team t in teams)
            _ChoiceRow(
              title: t.name,
              leading: const IconTile(
                icon: Icons.groups_outlined,
                color: AppColor.info,
              ),
              selected: _teamUids.contains(t.uid),
              multiSelect: true,
              onTap: () => _toggleTeam(t.uid),
            ),
        ],
      ],
    );
  }
}

/// One selectable row: the shared tile plus the state of the choice.
///
/// [multiSelect] swaps discs for boxes. That shape is what tells an agent that
/// teams accumulate while the owner replaces — the two lists are otherwise
/// identical, and the distinction only surfaces after tapping a second row
/// otherwise. The glyph is the only visual cue, so the row announces its
/// selection too; a screen reader hearing just a name could not tell.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.leading,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multiSelect = false,
  });

  final String title;
  final String? subtitle;
  final Widget leading;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  IconData get _glyph => multiSelect
      ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
      : (selected ? Icons.check_circle : Icons.radio_button_unchecked);

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
          _glyph,
          size: 20,
          color: selected ? AppColor.brandDeep : AppColor.inkFaint,
        ),
      ),
    );
  }
}
