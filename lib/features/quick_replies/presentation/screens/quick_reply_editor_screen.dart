import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/quick_reply_repository.dart';

/// Quick reply editor — Figma 291:109.
///
/// Serves both create and edit: [uid] is null when composing a new one. The
/// save CTA is pinned to the bottom safe area per the handoff.
class QuickReplyEditorScreen extends ConsumerStatefulWidget {
  const QuickReplyEditorScreen({this.uid, super.key});

  final String? uid;

  @override
  ConsumerState<QuickReplyEditorScreen> createState() =>
      _QuickReplyEditorScreenState();
}

class _QuickReplyEditorScreenState
    extends ConsumerState<QuickReplyEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  bool _saving = false;
  bool _prefilled = false;

  bool get _isNew => widget.uid == null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final QuickReplyRepository repo = ref.read(quickReplyRepositoryProvider);
      if (_isNew) {
        await repo.create(title: _title.text.trim(), body: _body.text.trim());
      } else {
        await repo.update(
          widget.uid!,
          title: _title.text.trim(),
          body: _body.text.trim(),
        );
      }
      ref.invalidate(quickReplyListProvider);
      if (mounted) context.pop();
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_isNew) return;
    await ref.read(quickReplyRepositoryProvider).remove(widget.uid!);
    ref.invalidate(quickReplyListProvider);
    if (mounted) context.pop();
  }

  /// Copies the loaded record into the fields exactly once.
  ///
  /// This deliberately does **not** happen during `build`. Assigning to a
  /// TextEditingController mid-build does not schedule a repaint, so the text
  /// landed in the controller but the fields stayed visually empty — and
  /// because the guard flag was set at the same time, no later rebuild ever
  /// corrected it. Prefilling from a listener keeps the mutation outside the
  /// build phase, where it does take effect.
  void _prefill(QuickReply q) {
    if (_prefilled) return;
    _prefilled = true;
    _title.text = q.title;
    _body.text = q.body;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (!_isNew) {
      ref.listen<AsyncValue<QuickReply>>(
        quickReplyDetailProvider(widget.uid!),
        (AsyncValue<QuickReply>? _, AsyncValue<QuickReply> next) {
          final QuickReply? q = next.valueOrNull;
          if (q != null) _prefill(q);
        },
      );
      // The listener only fires on change, so cover the case where the record
      // is already cached and resolves before this screen first builds.
      final QuickReply? cached =
          ref.watch(quickReplyDetailProvider(widget.uid!)).valueOrNull;
      if (cached != null && !_prefilled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _prefill(cached));
        });
      }
    }

    return Scaffold(
      appBar: AppHeader.back(
        title: _isNew ? l10n.qrNewTitle : l10n.qrEditTitle,
        actions: <Widget>[
          if (!_isNew)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  children: <Widget>[
                    TextFormField(
                      controller: _title,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: l10n.qrShortcut),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.qrShortcutRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _body,
                      minLines: 4,
                      maxLines: 10,
                      decoration: InputDecoration(labelText: l10n.qrMessage),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.qrMessageRequired
                          : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppDimens.gutter),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.actionSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
