import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/team_repository.dart';

/// Create or edit a team.
///
/// The name is editable; the roster is not. The console posts membership as an
/// array of integer `_id`s, which an API would very likely translate to uids —
/// but the API controller is absent from this checkout, so the field name and
/// id format are unverified. A guessed key that the server ignores would look
/// exactly like a successful save, so members are shown read-only.
class TeamEditorScreen extends ConsumerWidget {
  const TeamEditorScreen({this.uid, super.key});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) return const _Form(existing: null);

    return AsyncValueView<WorkTeam>(
      value: ref.watch(teamProvider(uid!)),
      onRetry: () => ref.invalidate(teamProvider(uid!)),
      builder: (WorkTeam t) => _Form(existing: t),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.existing});

  final WorkTeam? existing;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _title;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String title = _title.text.trim();
    // The server requires at least 2 characters, so a single letter is caught
    // here rather than coming back as a 422 the form cannot attach anywhere.
    if (title.length < TeamLimits.titleMin) {
      _toast(l10n.tmNameRequired);
      return;
    }

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      final TeamRepository repo = ref.read(teamRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.existing!.uid, title);
      } else {
        await repo.create(title);
      }
      ref.invalidate(teamListProvider);
      _toast(l10n.tmSaved);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final WorkTeam t = widget.existing!;

    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(l10n.tmDeleteConfirm(t.title)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColor.danger),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      await ref.read(teamRepositoryProvider).delete(t.uid);
      ref.invalidate(teamListProvider);
      _toast(l10n.tmDeleted);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<TeamMember> members =
        widget.existing?.members ?? const <TeamMember>[];

    return Scaffold(
      appBar: AppHeader.back(
        title: _isEdit ? l10n.tmEdit : l10n.tmNew,
        actions: <Widget>[
          if (_isEdit)
            IconButton(
              tooltip: l10n.tmDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.gutter,
          14,
          AppDimens.gutter,
          32,
        ),
        children: <Widget>[
          TextField(
            controller: _title,
            maxLength: TeamLimits.titleMax,
            decoration: InputDecoration(labelText: l10n.tmName),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.actionSave),
          ),

          if (_isEdit) ...<Widget>[
            const SizedBox(height: 24),
            SectionLabel(l10n.tmMembers(members.length), padded: false),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Text(
                l10n.tmMembersNote,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColor.inkMuted),
              ),
            ),
            for (final TeamMember m in members)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    InitialsAvatar(name: m.name, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        m.role == null ? m.name : '${m.name} · ${m.role}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
