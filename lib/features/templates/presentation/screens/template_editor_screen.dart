import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/template_repository.dart';
import '../../domain/whatsapp_template.dart';

/// Create or edit a WhatsApp template.
///
/// No frame. Built from `WhatsAppTemplateController`'s validation rules, which
/// are the only authoritative statement of what this endpoint accepts — the
/// handoff documents none of the limits.
///
/// Scope is deliberately the components that occur live: BODY (103 rows),
/// BUTTONS (39), HEADER:TEXT (34) and FOOTER (23). Image, video and document
/// headers need `uploaded_media_file_name` from a prior upload whose contract
/// for a *template* header is not the call the composer makes, and they account
/// for 7 rows between them — so the screen says where to manage them rather
/// than shipping an unverified guess.
class TemplateEditorScreen extends ConsumerWidget {
  const TemplateEditorScreen({this.uid, super.key});

  /// Null when creating.
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) return const _Form(existing: null);

    // Fetched, not taken from the list. The list is a summary: it has name,
    // language, category and status, and none of the content. Building the
    // form from it showed every field blank on a template that has a body.
    return AsyncValueView<WhatsAppTemplate>(
      value: ref.watch(templateProvider(uid!)),
      onRetry: () => ref.invalidate(templateProvider(uid!)),
      builder: (WhatsAppTemplate t) => _Form(existing: t),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.existing});

  final WhatsAppTemplate? existing;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _name;
  late final TextEditingController _language;
  late final TextEditingController _header;
  late final TextEditingController _body;
  late final TextEditingController _footer;

  late WaTemplateCategory _category;
  late WaHeaderKind _headerKind;
  late List<_ButtonDraft> _buttons;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final WhatsAppTemplate? t = widget.existing;
    _name = TextEditingController(text: t?.name);
    // A sensible default rather than a blank box: en_US is what every template
    // on this workspace uses, and the field is immutable after creation.
    _language = TextEditingController(text: t?.language ?? 'en_US');
    _header = TextEditingController(text: t?.headerText);
    _body = TextEditingController(text: t?.body);
    _footer = TextEditingController(text: t?.footer);
    _category = t?.category ?? WaTemplateCategory.utility;
    _headerKind =
        (t?.headerText == null) ? WaHeaderKind.none : WaHeaderKind.text;
    _buttons =
        (t?.buttons ?? const <WaButton>[]).map(_ButtonDraft.from).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _language.dispose();
    _header.dispose();
    _body.dispose();
    _footer.dispose();
    for (final _ButtonDraft b in _buttons) {
      b.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Null when required fields are missing or a button is half-filled.
  WhatsAppTemplate? _collect() {
    final String name = _name.text.trim();
    final String language = _language.text.trim();
    final String body = _body.text.trim();
    if (name.isEmpty || language.isEmpty || body.isEmpty) return null;

    final List<WaButton> buttons = <WaButton>[];
    for (final _ButtonDraft d in _buttons) {
      final WaButton? b = d.build();
      if (b == null) return null;
      buttons.add(b);
    }

    final String header = _header.text.trim();
    final String footer = _footer.text.trim();

    return WhatsAppTemplate(
      uid: widget.existing?.uid ?? '',
      name: name,
      language: language,
      category: _category,
      body: body,
      headerText:
          _headerKind == WaHeaderKind.text && header.isNotEmpty ? header : null,
      footer: footer.isEmpty ? null : footer,
      buttons: buttons,
    );
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final WhatsAppTemplate? t = _collect();
    if (t == null) {
      _toast(l10n.tplIncomplete);
      return;
    }

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      final TemplateRepository repo = ref.read(templateRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.existing!.uid, t);
      } else {
        await repo.create(t);
      }
      ref.invalidate(templateListProvider);
      _toast(_isEdit ? l10n.tplUpdated : l10n.tplSaved);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final WhatsAppTemplate t = widget.existing!;

    // Worded for what it actually does. This is not a list delete: the engine
    // calls Meta's delete endpoint, and no local cleanup brings the template
    // back.
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(l10n.tplDeleteConfirm(t.name)),
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
      await ref.read(templateRepositoryProvider).delete(t.uid);
      ref.invalidate(templateListProvider);
      _toast(l10n.tplDeleted);
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
    final bool locked = _isEdit;

    return Scaffold(
      appBar: AppHeader.back(
        title: _isEdit ? l10n.tplEdit : l10n.tplNew,
        actions: <Widget>[
          if (_isEdit)
            IconButton(
              tooltip: l10n.tplDelete,
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
          if (locked) ...<Widget>[
            AppBanner(message: l10n.tplLockedNote, tone: BannerTone.neutral),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _name,
            // Disabled rather than hidden once Meta holds the template: the
            // value still identifies it, and a field that accepts typing then
            // silently discards it is worse than one that cannot be typed in.
            enabled: !locked,
            maxLength: WaTemplateLimits.name,
            decoration: InputDecoration(labelText: l10n.tplName),
          ),
          TextField(
            controller: _language,
            enabled: !locked,
            maxLength: WaTemplateLimits.language,
            decoration: InputDecoration(labelText: l10n.tplLanguage),
          ),
          DropdownButtonFormField<WaTemplateCategory>(
            initialValue: _category,
            decoration: InputDecoration(labelText: l10n.tplCategory),
            items: <DropdownMenuItem<WaTemplateCategory>>[
              DropdownMenuItem<WaTemplateCategory>(
                value: WaTemplateCategory.marketing,
                child: Text(l10n.tplCategoryMarketing),
              ),
              DropdownMenuItem<WaTemplateCategory>(
                value: WaTemplateCategory.utility,
                child: Text(l10n.tplCategoryUtility),
              ),
            ],
            onChanged: locked
                ? null
                : (WaTemplateCategory? v) =>
                    setState(() => _category = v ?? _category),
          ),

          const SizedBox(height: 18),
          SectionLabel(l10n.tplHeader, padded: false),
          DropdownButtonFormField<WaHeaderKind>(
            initialValue: _headerKind,
            items: <DropdownMenuItem<WaHeaderKind>>[
              DropdownMenuItem<WaHeaderKind>(
                value: WaHeaderKind.none,
                child: Text(l10n.tplHeaderNone),
              ),
              DropdownMenuItem<WaHeaderKind>(
                value: WaHeaderKind.text,
                child: Text(l10n.tplHeaderText),
              ),
            ],
            onChanged: (WaHeaderKind? v) =>
                setState(() => _headerKind = v ?? _headerKind),
          ),
          if (_headerKind == WaHeaderKind.text)
            TextField(
              controller: _header,
              maxLength: WaTemplateLimits.headerText,
              decoration: InputDecoration(labelText: l10n.tplHeaderText),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
            child: Text(
              l10n.tplMediaHeaderNote,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColor.inkMuted),
            ),
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            maxLength: WaTemplateLimits.body,
            decoration: InputDecoration(labelText: l10n.tplBody),
          ),
          TextField(
            controller: _footer,
            maxLength: WaTemplateLimits.footer,
            decoration: InputDecoration(labelText: l10n.tplFooter),
          ),

          const SizedBox(height: 18),
          SectionLabel(l10n.tplButtons, padded: false),
          for (final _ButtonDraft d in _buttons)
            _ButtonRow(
              draft: d,
              onChanged: () => setState(() {}),
              onRemove: () {
                setState(() => _buttons.remove(d));
                d.dispose();
              },
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _buttons.add(_ButtonDraft.empty())),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.tplAddButton),
            ),
          ),

          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.tplSave),
          ),
        ],
      ),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final _ButtonDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 20),
                color: AppColor.inkMuted,
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              ),
            ),
            DropdownButtonFormField<WaButtonType>(
              initialValue: draft.type,
              items: <DropdownMenuItem<WaButtonType>>[
                DropdownMenuItem<WaButtonType>(
                  value: WaButtonType.quickReply,
                  child: Text(l10n.tplButtonQuickReply),
                ),
                DropdownMenuItem<WaButtonType>(
                  value: WaButtonType.url,
                  child: Text(l10n.tplButtonUrl),
                ),
                DropdownMenuItem<WaButtonType>(
                  value: WaButtonType.phoneNumber,
                  child: Text(l10n.tplButtonPhone),
                ),
              ],
              onChanged: (WaButtonType? v) {
                if (v == null) return;
                draft.type = v;
                onChanged();
              },
            ),
            TextField(
              controller: draft.text,
              maxLength: WaTemplateLimits.buttonText,
              decoration: InputDecoration(labelText: l10n.tplButtonText),
            ),
            // Only the field this type actually sends. The server validates
            // `url` as a URL and `phone_number` as numeric, so offering both
            // invites filling the wrong one and reading the 422 as a bad value
            // rather than a wrong field.
            if (draft.type == WaButtonType.url)
              TextField(
                controller: draft.value,
                keyboardType: TextInputType.url,
                maxLength: WaTemplateLimits.buttonUrl,
                decoration: InputDecoration(labelText: l10n.tplButtonUrlValue),
              )
            else if (draft.type == WaButtonType.phoneNumber)
              TextField(
                controller: draft.value,
                keyboardType: TextInputType.phone,
                decoration:
                    InputDecoration(labelText: l10n.tplButtonPhoneValue),
              ),
          ],
        ),
      ),
    );
  }
}

class _ButtonDraft {
  _ButtonDraft({required this.type, String? text, String? value})
      : text = TextEditingController(text: text),
        value = TextEditingController(text: value);

  factory _ButtonDraft.empty() => _ButtonDraft(type: WaButtonType.quickReply);

  factory _ButtonDraft.from(WaButton b) =>
      _ButtonDraft(type: b.type, text: b.text, value: b.value);

  WaButtonType type;
  final TextEditingController text;
  final TextEditingController value;

  /// Null when incomplete, so a half-filled button blocks the save rather than
  /// being dropped — three buttons typed, two sent, is the silent kind of wrong.
  WaButton? build() {
    final String t = text.text.trim();
    if (t.isEmpty) return null;

    if (type == WaButtonType.quickReply) {
      return WaButton(type: type, text: t);
    }

    final String v = value.text.trim();
    if (v.isEmpty) return null;
    if (type == WaButtonType.url) {
      // The server requires a real scheme and answers 422 for "example.com".
      final Uri? parsed = Uri.tryParse(v);
      if (parsed == null || !parsed.hasScheme) return null;
    }
    return WaButton(type: type, text: t, value: v);
  }

  void dispose() {
    text.dispose();
    value.dispose();
  }
}
