import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/messenger_profile_repository.dart';
import '../../domain/messenger_profile.dart';

/// Instagram's persistent menu and ice breakers — Figma `495:124`.
///
/// Workspace settings, not conversation actions: no contact uid reaches this
/// screen. Admin-gated server-side, and the route is hidden from non-admins in
/// More, but the 403 is still handled — role can change between login and here.
///
/// Every save writes through to the live Meta profile with no draft in between,
/// which is why the banner says so and the destructive actions confirm.
class InstagramSettingsScreen extends ConsumerWidget {
  const InstagramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.igsTitle),
      body: AsyncValueView<MessengerProfile>(
        value: ref.watch(messengerProfileProvider),
        onRetry: () => ref.invalidate(messengerProfileProvider),
        builder: (MessengerProfile profile) => _Form(profile: profile),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.profile});

  final MessengerProfile profile;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late List<_MenuDraft> _menu;
  late List<_IceDraft> _ice;
  bool _busy = false;

  /// Locale blocks this screen does not edit, kept only so they can be written
  /// back. See [replaceLocale] — dropping them is a silent delete.
  int get _otherMenuLocales =>
      widget.profile.menu.where((LocaleBlock<MenuAction> b) => !b.isDefault).length;
  int get _otherIceLocales => widget.profile.iceBreakers
      .where((LocaleBlock<IceBreaker> b) => !b.isDefault)
      .length;

  @override
  void initState() {
    super.initState();
    _menu = _defaultOf<MenuAction>(widget.profile.menu)
        .map(_MenuDraft.from)
        .toList();
    _ice = _defaultOf<IceBreaker>(widget.profile.iceBreakers)
        .map(_IceDraft.from)
        .toList();
  }

  /// The default locale's rows, or none. Meta omits `locale` on a
  /// single-locale profile, which [LocaleBlock.fromJson] already normalises.
  static List<T> _defaultOf<T>(List<LocaleBlock<T>> blocks) {
    for (final LocaleBlock<T> b in blocks) {
      if (b.isDefault) return b.actions;
    }
    return const <Never>[];
  }

  @override
  void dispose() {
    for (final _MenuDraft d in _menu) {
      d.dispose();
    }
    for (final _IceDraft d in _ice) {
      d.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Refuses rather than disables, matching the Instagram composer: a greyed
  /// Add button never says what the cap is, and the cap is Meta's, not ours.
  void _add<T>(List<T> into, int max, T Function() make) {
    if (into.length >= max) {
      _toast(AppLocalizations.of(context).igMax(max));
      return;
    }
    setState(() => into.add(make()));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      // Refetch rather than trust the local form: the endpoint reads back from
      // Meta, which trims over-long values instead of rejecting them, so what
      // was sent is not necessarily what is now live.
      ref.invalidate(messengerProfileProvider);
      _toast(done);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMenu() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<MenuAction>? rows = _collectMenu();
    if (rows == null) {
      _toast(l10n.igsIncomplete);
      return;
    }
    await _run(
      () => ref.read(messengerProfileRepositoryProvider).saveMenu(
            replaceLocale<MenuAction>(
              widget.profile.menu,
              kDefaultLocale,
              rows,
            ),
          ),
      l10n.igsSaved,
    );
  }

  Future<void> _saveIce() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<IceBreaker>? rows = _collectIce();
    if (rows == null) {
      _toast(l10n.igsIncomplete);
      return;
    }
    await _run(
      () => ref.read(messengerProfileRepositoryProvider).saveIceBreakers(
            replaceLocale<IceBreaker>(
              widget.profile.iceBreakers,
              kDefaultLocale,
              rows,
            ),
          ),
      l10n.igsSaved,
    );
  }

  /// Null when any row is incomplete — a half-filled row must not be dropped
  /// silently, or the agent saves four menu items and gets three.
  List<MenuAction>? _collectMenu() {
    final List<MenuAction> out = <MenuAction>[];
    for (final _MenuDraft d in _menu) {
      final MenuAction? a = d.build();
      if (a == null) return null;
      out.add(a);
    }
    return out;
  }

  List<IceBreaker>? _collectIce() {
    final List<IceBreaker> out = <IceBreaker>[];
    for (final _IceDraft d in _ice) {
      final IceBreaker? b = d.build();
      if (b == null) return null;
      out.add(b);
    }
    return out;
  }

  Future<void> _confirmClear(String message, Future<void> Function() go) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColor.danger),
                child: Text(l10n.igsClear),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await _run(go, l10n.igsRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.gutter,
        14,
        AppDimens.gutter,
        32,
      ),
      children: <Widget>[
        AppBanner(message: l10n.igsLive, tone: BannerTone.warning),
        const SizedBox(height: 18),

        SectionLabel(l10n.igsMenu, padded: false),
        Text(l10n.igsMenuHint, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        if (_menu.isEmpty)
          _NoneYet(text: l10n.igsNone)
        else
          for (final _MenuDraft d in _menu)
            _MenuRow(
              draft: d,
              onRemove: () {
                setState(() => _menu.remove(d));
                d.dispose();
              },
              onChanged: () => setState(() {}),
            ),
        if (_otherMenuLocales > 0) _KeptNote(count: _otherMenuLocales),
        _Actions(
          busy: _busy,
          addLabel: l10n.igsAddAction,
          onAdd: () => _add<_MenuDraft>(
            _menu,
            IgProfileLimits.maxMenuActions,
            _MenuDraft.empty,
          ),
          onSave: _saveMenu,
          onClear: widget.profile.menu.isEmpty
              ? null
              : () => _confirmClear(
                    l10n.igsClearMenu,
                    ref.read(messengerProfileRepositoryProvider).clearMenu,
                  ),
        ),

        const SizedBox(height: 26),
        SectionLabel(l10n.igsIce, padded: false),
        Text(l10n.igsIceHint, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        if (_ice.isEmpty)
          _NoneYet(text: l10n.igsNone)
        else
          for (final _IceDraft d in _ice)
            _IceRow(
              draft: d,
              onRemove: () {
                setState(() => _ice.remove(d));
                d.dispose();
              },
            ),
        if (_otherIceLocales > 0) _KeptNote(count: _otherIceLocales),
        _Actions(
          busy: _busy,
          addLabel: l10n.igsAddQuestion,
          onAdd: () => _add<_IceDraft>(
            _ice,
            IgProfileLimits.maxIceBreakers,
            _IceDraft.empty,
          ),
          onSave: _saveIce,
          onClear: widget.profile.iceBreakers.isEmpty
              ? null
              : () => _confirmClear(
                    l10n.igsClearIce,
                    ref
                        .read(messengerProfileRepositoryProvider)
                        .clearIceBreakers,
                  ),
        ),
      ],
    );
  }
}

/// Inline placeholder for an empty section.
///
/// Deliberately not [EmptyState], which is a full-height treatment for a screen
/// with nothing on it — here two of these can sit on one screen above a form
/// that is very much not empty.
class _NoneYet extends StatelessWidget {
  const _NoneYet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColor.inkMuted),
      ),
    );
  }
}

/// Says that locales this screen cannot edit exist and are safe.
///
/// Without it, an admin who configured Arabic on the web console sees only the
/// default rows here and has no way to know the save will not wipe them.
class _KeptNote extends StatelessWidget {
  const _KeptNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Text(
        AppLocalizations.of(context).igsKeptLocales(count),
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColor.inkMuted),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.addLabel,
    required this.onAdd,
    required this.onSave,
    required this.onClear,
  });

  final bool busy;
  final String addLabel;
  final VoidCallback onAdd;
  final Future<void> Function() onSave;
  final Future<void> Function()? onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: busy ? null : onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(addLabel),
          ),
          FilledButton(
            onPressed: busy ? null : () => onSave(),
            child: Text(l10n.igsSave),
          ),
          if (onClear != null)
            TextButton(
              onPressed: busy ? null : () => onClear!(),
              style: TextButton.styleFrom(foregroundColor: AppColor.danger),
              child: Text(l10n.igsClear),
            ),
        ],
      ),
    );
  }
}

// ---- Rows -------------------------------------------------------------------

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  final _MenuDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return _RowCard(
      onRemove: onRemove,
      children: <Widget>[
        TextField(
          controller: draft.title,
          maxLength: IgProfileLimits.menuTitle,
          decoration: InputDecoration(labelText: l10n.igsLabel),
        ),
        DropdownButtonFormField<String>(
          initialValue: draft.type,
          decoration: InputDecoration(labelText: l10n.igsType),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'postback',
              child: Text(l10n.igsPostback),
            ),
            DropdownMenuItem<String>(
              value: 'web_url',
              child: Text(l10n.igsWebUrl),
            ),
          ],
          onChanged: (String? v) {
            if (v == null) return;
            draft.type = v;
            onChanged();
          },
        ),
        // The two are mutually exclusive on the wire, so only one is offered —
        // a form showing both invites filling both, and the server would take
        // one without saying which.
        if (draft.type == 'web_url')
          TextField(
            controller: draft.url,
            keyboardType: TextInputType.url,
            maxLength: IgProfileLimits.url,
            decoration: InputDecoration(labelText: l10n.igsUrl),
          )
        else
          TextField(
            controller: draft.payload,
            maxLength: IgProfileLimits.payload,
            decoration: InputDecoration(labelText: l10n.igsPayload),
          ),
      ],
    );
  }
}

class _IceRow extends StatelessWidget {
  const _IceRow({required this.draft, required this.onRemove});

  final _IceDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return _RowCard(
      onRemove: onRemove,
      children: <Widget>[
        TextField(
          controller: draft.question,
          maxLength: IgProfileLimits.iceQuestion,
          decoration: InputDecoration(labelText: l10n.igsQuestion),
        ),
        TextField(
          controller: draft.payload,
          maxLength: IgProfileLimits.payload,
          decoration: InputDecoration(labelText: l10n.igsPayload),
        ),
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.children, required this.onRemove});

  final List<Widget> children;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
            ...children,
          ],
        ),
      ),
    );
  }
}

// ---- Drafts -----------------------------------------------------------------

class _MenuDraft {
  _MenuDraft({required this.type, String? title, String? payload, String? url})
      : title = TextEditingController(text: title),
        payload = TextEditingController(text: payload),
        url = TextEditingController(text: url);

  factory _MenuDraft.empty() => _MenuDraft(type: 'postback');

  factory _MenuDraft.from(MenuAction a) => _MenuDraft(
        type: a.type,
        title: a.title,
        payload: a.payload,
        url: a.url,
      );

  String type;
  final TextEditingController title;
  final TextEditingController payload;
  final TextEditingController url;

  /// Null when incomplete. The URL variant is validated for a scheme because
  /// the server requires a real one and answers 422 for `example.com`.
  MenuAction? build() {
    final String t = title.text.trim();
    if (t.isEmpty) return null;

    if (type == 'web_url') {
      final String u = url.text.trim();
      final Uri? parsed = Uri.tryParse(u);
      if (u.isEmpty || parsed == null || !parsed.hasScheme) return null;
      return MenuAction(type: type, title: t, url: u);
    }

    final String p = payload.text.trim();
    if (p.isEmpty) return null;
    return MenuAction(type: type, title: t, payload: p);
  }

  void dispose() {
    title.dispose();
    payload.dispose();
    url.dispose();
  }
}

class _IceDraft {
  _IceDraft({String? question, String? payload})
      : question = TextEditingController(text: question),
        payload = TextEditingController(text: payload);

  factory _IceDraft.empty() => _IceDraft();

  factory _IceDraft.from(IceBreaker b) =>
      _IceDraft(question: b.question, payload: b.payload);

  final TextEditingController question;
  final TextEditingController payload;

  /// Both are required here — unlike the menu, an ice breaker's payload is not
  /// optional server-side.
  IceBreaker? build() {
    final String q = question.text.trim();
    final String p = payload.text.trim();
    if (q.isEmpty || p.isEmpty) return null;
    return IceBreaker(question: q, payload: p);
  }

  void dispose() {
    question.dispose();
    payload.dispose();
  }
}
