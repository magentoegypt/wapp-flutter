import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/bot_reply_repository.dart';
import 'bot_replies_screen.dart' show triggerLabel;

/// Create or edit a keyword auto-reply.
///
/// Only a **simple text** reply is editable. A reply that sends buttons, a list
/// or media carries its own validated payload, and this form has no fields for
/// it — saving would post `message_type: simple` and quietly replace a rich
/// reply with a plain one. Those open read-only instead.
class BotReplyEditorScreen extends ConsumerWidget {
  const BotReplyEditorScreen({this.uid, super.key});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) return const _Form(existing: null);

    return AsyncValueView<BotReply>(
      value: ref.watch(botReplyProvider(uid!)),
      onRetry: () => ref.invalidate(botReplyProvider(uid!)),
      builder: (BotReply r) => _Form(existing: r),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.existing});

  final BotReply? existing;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _name;
  late final TextEditingController _keyword;
  late final TextEditingController _reply;
  late BotTrigger _trigger;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;
  bool get _readOnly =>
      _isEdit && !widget.existing!.messageKind.isEditable;

  @override
  void initState() {
    super.initState();
    final BotReply? r = widget.existing;
    _name = TextEditingController(text: r?.name);
    _keyword = TextEditingController(text: r?.keyword);
    _reply = TextEditingController(text: r?.replyText);
    _trigger = r?.trigger ?? BotTrigger.is_;
  }

  @override
  void dispose() {
    _name.dispose();
    _keyword.dispose();
    _reply.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _name.text.trim();
    final String reply = _reply.text.trim();
    final String keyword = _keyword.text.trim();

    // The keyword is required for every trigger except the two that fire on a
    // first inbound message, where there is nothing to match against.
    if (name.isEmpty ||
        reply.isEmpty ||
        (_trigger.needsKeyword && keyword.isEmpty)) {
      _toast(l10n.brIncomplete);
      return;
    }

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      final BotReply r = BotReply(
        uid: widget.existing?.uid ?? '',
        name: name,
        trigger: _trigger,
        keyword: _trigger.needsKeyword ? keyword : null,
        replyText: reply,
      );
      final BotReplyRepository repo = ref.read(botReplyRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.existing!.uid, r);
      } else {
        await repo.create(r);
      }
      ref.invalidate(botReplyListProvider);
      _toast(l10n.brSaved);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicate() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(botReplyRepositoryProvider)
          .duplicate(widget.existing!.uid);
      ref.invalidate(botReplyListProvider);
      _toast(l10n.brDuplicated);
    } catch (e) {
      // Duplicating counts against the plan's bot-reply allowance, so a 422
      // here is a real answer — the server's wording says which limit was hit.
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BotReply r = widget.existing!;

    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(l10n.brDeleteConfirm(r.name)),
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
      await ref.read(botReplyRepositoryProvider).delete(r.uid);
      ref.invalidate(botReplyListProvider);
      _toast(l10n.brDeleted);
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

    return Scaffold(
      appBar: AppHeader.back(
        title: _isEdit ? l10n.brEdit : l10n.brNew,
        actions: <Widget>[
          if (_isEdit) ...<Widget>[
            IconButton(
              tooltip: l10n.brDuplicate,
              icon: const Icon(Icons.copy_outlined, color: Colors.white),
              onPressed: _busy ? null : _duplicate,
            ),
            IconButton(
              tooltip: l10n.brDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _busy ? null : _delete,
            ),
          ],
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
          if (_readOnly) ...<Widget>[
            AppBanner(message: l10n.brReadOnly, tone: BannerTone.warning),
            const SizedBox(height: 14),
          ],
          if (widget.existing?.isInFlow ?? false) ...<Widget>[
            AppBanner(message: l10n.brInFlow, tone: BannerTone.neutral),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _name,
            enabled: !_readOnly,
            maxLength: BotReplyLimits.name,
            decoration: InputDecoration(labelText: l10n.brName),
          ),
          DropdownButtonFormField<BotTrigger>(
            initialValue: _trigger,
            decoration: InputDecoration(labelText: l10n.brTrigger),
            items: <DropdownMenuItem<BotTrigger>>[
              for (final BotTrigger t in BotTrigger.values)
                DropdownMenuItem<BotTrigger>(
                  value: t,
                  child: Text(triggerLabel(l10n, t)),
                ),
            ],
            onChanged: _readOnly
                ? null
                : (BotTrigger? v) => setState(() => _trigger = v ?? _trigger),
          ),
          // Hidden, not disabled, for welcome and ads_welcome: there is no
          // keyword to type, and a greyed box invites the question of what
          // belongs in it.
          if (_trigger.needsKeyword)
            TextField(
              controller: _keyword,
              enabled: !_readOnly,
              maxLength: BotReplyLimits.keyword,
              decoration: InputDecoration(labelText: l10n.brKeyword),
            ),
          TextField(
            controller: _reply,
            enabled: !_readOnly,
            minLines: 3,
            maxLines: 8,
            maxLength: BotReplyLimits.replyText,
            decoration: InputDecoration(labelText: l10n.brReplyText),
          ),

          const SizedBox(height: 18),
          if (!_readOnly)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(l10n.actionSave),
            ),
        ],
      ),
    );
  }
}
