import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/quick_reply_repository.dart';
import 'quick_replies_screen.dart' show quickReplyCategoryLabel;

/// Placeholders the backend substitutes when the reply is sent.
///
/// Deliberately **not** localised: substitution is a literal match server-side,
/// so a translated token would never be replaced.
const List<String> _tokens = <String>['{{name}}', '{{order}}', '{{link}}'];

/// Quick reply editor — Figma 291:109.
///
/// Serves both create and edit: [uid] is null when composing a new one. Save
/// and Cancel live in the header per the frame; the bottom slot is the
/// destructive action, and only exists once there is a record to destroy.
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

  String? _category;

  /// Covers save *and* delete: while either is in flight both affordances have
  /// to be inert, or a second tap fires a second request.
  bool _busy = false;
  bool _prefilled = false;

  bool get _isNew => widget.uid == null;

  @override
  void initState() {
    super.initState();
    // The preview renders the message as it is typed, so it has to rebuild on
    // every keystroke — the form itself would not.
    _body.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    if (mounted) setState(() {});
  }

  /// Category ids the select offers: the known set, plus whatever this record
  /// already carries so an unrecognised value is not silently dropped on save.
  List<String> get _categoryIds => <String>[
        ...QuickReplyCategories.known,
        if (_category != null && !QuickReplyCategories.known.contains(_category))
          _category!,
      ];

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    try {
      final QuickReplyRepository repo = ref.read(quickReplyRepositoryProvider);
      if (_isNew) {
        await repo.create(
          title: _title.text.trim(),
          body: _body.text.trim(),
          category: _category,
        );
      } else {
        await repo.update(
          widget.uid!,
          title: _title.text.trim(),
          body: _body.text.trim(),
          category: _category,
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
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deleting a quick reply is not undoable and the button sits in the primary
  /// bottom slot, so it asks first.
  Future<void> _confirmDelete() async {
    if (_isNew) return;
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(l10n.qrDelete),
        content: Text(l10n.qrDeleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(quickReplyRepositoryProvider).remove(widget.uid!);
      ref.invalidate(quickReplyListProvider);
      if (mounted) context.pop();
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Drops [token] where the caret is, replacing any selected run.
  void _insertToken(String token) {
    final TextEditingValue value = _body.value;
    final TextSelection selection = value.selection;
    // A field that has never held focus reports an invalid selection
    // (offset -1); appending is the only sensible reading of "insert here".
    final int start = selection.isValid ? selection.start : value.text.length;
    final int end = selection.isValid ? selection.end : value.text.length;

    _body.value = value.copyWith(
      text: value.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
      composing: TextRange.empty,
    );
  }

  /// The message with placeholders swapped for sample values, as the frame's
  /// preview bubble shows it.
  String _previewText(AppLocalizations l10n) {
    final Map<String, String> samples = <String, String>{
      _tokens[0]: l10n.qrSampleName,
      _tokens[1]: l10n.qrSampleOrder,
      _tokens[2]: l10n.qrSampleLink,
    };
    String out = _body.text;
    samples.forEach((String token, String sample) {
      out = out.replaceAll(token, sample);
    });
    return out;
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
    // The form is editable while the record is still in flight, so on a slow
    // response the user can start typing before this fires. Overwriting then
    // would silently discard their input with no undo — so anything already
    // entered wins, and the fetched record is dropped instead.
    if (_title.text.isNotEmpty || _body.text.isNotEmpty) {
      _prefilled = true;
      return;
    }
    _prefilled = true;
    _title.text = q.title;
    _body.text = q.body;
    _category = q.category;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();

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

    final String preview = _previewText(l10n).trim();

    return Scaffold(
      appBar: AppHeader.back(
        title: _isNew ? l10n.qrNewTitle : l10n.qrEditTitle,
        // Cancel replaces the back arrow, and Save moves up here — the frame
        // gives the bottom slot to the destructive action instead.
        leading: TextButton(
          onPressed: _busy ? null : () => context.pop(),
          style: _headerActionStyle,
          child: Text(l10n.actionCancel),
        ),
        actions: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              style: _headerActionStyle,
              child: Text(l10n.actionSave),
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
                    DropdownButtonFormField<String?>(
                      // A FormField only reads `initialValue` when its state is
                      // created, and the record arrives after the first build —
                      // re-keying on the value is what makes the prefilled
                      // category actually show.
                      key: ValueKey<String?>(_category),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.qrCategory),
                      items: <DropdownMenuItem<String?>>[
                        DropdownMenuItem<String?>(
                          child: Text(l10n.qrCategoryNone),
                        ),
                        for (final String id in _categoryIds)
                          DropdownMenuItem<String?>(
                            value: id,
                            child: Text(
                              quickReplyCategoryLabel(l10n, id),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (String? v) => setState(() => _category = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _body,
                      // Capped at five lines and then scrolls internally. At ten
                      // a long reply grew the field until the variable chips,
                      // PREVIEW and Delete were pushed off the bottom — the
                      // frame keeps the field a fixed block so the rest of the
                      // form stays reachable.
                      minLines: 4,
                      maxLines: 5,
                      decoration: InputDecoration(labelText: l10n.qrMessage),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.qrMessageRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String token in _tokens)
                          _TokenChip(
                            token: token,
                            onTap: () => _insertToken(token),
                          ),
                      ],
                    ),
                    // Nothing typed yet means nothing to preview — an empty
                    // bubble would only read as a rendering fault.
                    if (preview.isNotEmpty) ...<Widget>[
                      SectionLabel(l10n.qrPreview, padded: false),
                      MessageBubble(
                        text: preview,
                        timeLabel: DateFormat.Hm(locale).format(DateTime.now()),
                        isOutgoing: true,
                        status: MessageStatus.delivered,
                      ),
                    ],
                  ],
                ),
              ),
              if (!_isNew)
                Padding(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  child: FilledButton(
                    onPressed: _busy ? null : _confirmDelete,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.dangerWash,
                      foregroundColor: AppColor.danger,
                    ),
                    child: Text(l10n.qrDelete),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White-on-green text action for the header slots.
final ButtonStyle _headerActionStyle = TextButton.styleFrom(
  foregroundColor: Colors.white,
  padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
);

/// Tappable `+ {{token}}` chip that inserts a placeholder into the message.
class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.token, required this.onTap});

  final String token;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: AppColor.brandWash,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.add, size: 13, color: AppColor.brandDeep),
            const SizedBox(width: 4),
            Text(
              token,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColor.brandDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
