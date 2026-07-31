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
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/instagram_repository.dart';

/// Meta's two button behaviours, held as the wire strings [IgButton.type]
/// actually sends rather than a local enum — one mapping fewer between the
/// segmented control and the request body.
const String _kPostback = 'postback';
const String _kWebUrl = 'web_url';

/// Compose one of Instagram's three structured messages.
///
/// The composer exists for its limits. Meta **trims** over-long text instead of
/// rejecting it: a button reading "Track my order now" reaches the customer
/// shortened, the API answers 200, and nothing anywhere says a character was
/// lost. Everything capped by [IgLimits] is therefore enforced twice — a
/// `maxLength` that stops typing at the cap and shows a live counter, and a
/// validator on send that catches text the keyboard never touched (a template
/// prefill writes straight to the controller, where input formatters do not
/// reach).
///
/// Counts are enforced the other way round: adding past the maximum is refused
/// at the tap so the agent never fills in a row that cannot be sent.
class InstagramSendScreen extends ConsumerStatefulWidget {
  const InstagramSendScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<InstagramSendScreen> createState() =>
      _InstagramSendScreenState();
}

class _InstagramSendScreenState extends ConsumerState<InstagramSendScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Doubles as the composer's mode and as the template list's filter — the
  /// three send endpoints and the three saved-template kinds are the same three
  /// things, so a second selector would only be able to disagree with this one.
  IgTemplateKind _kind = IgTemplateKind.quickReply;

  /// Shared by quick replies and buttons, which both wrap the same message.
  /// Cards carry no message at all.
  final TextEditingController _message = TextEditingController();

  /// All three drafts stay alive across a kind switch: flipping to Cards to see
  /// what they look like must not throw away a half-written set of buttons.
  final List<_OptionDraft> _quickReplies = <_OptionDraft>[_OptionDraft()];
  final List<_ButtonDraft> _buttons = <_ButtonDraft>[_ButtonDraft()];
  final List<_CardDraft> _cards = <_CardDraft>[_CardDraft()];

  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    for (final _OptionDraft d in _quickReplies) {
      d.dispose();
    }
    for (final _ButtonDraft d in _buttons) {
      d.dispose();
    }
    for (final _CardDraft d in _cards) {
      d.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---- Adding and removing rows ---------------------------------------------

  /// Refuses rather than disables. A greyed-out Add button states that no more
  /// fit but never says how many that is, and the cap is Meta's, not ours.
  void _add<T>(List<T> into, int max, T Function() make) {
    if (into.length >= max) {
      _toast(AppLocalizations.of(context).igMax(max));
      return;
    }
    setState(() => into.add(make()));
  }

  void _removeQuickReply(_OptionDraft draft) {
    setState(() => _quickReplies.remove(draft));
    draft.dispose();
  }

  void _removeButton(List<_ButtonDraft> from, _ButtonDraft draft) {
    setState(() => from.remove(draft));
    draft.dispose();
  }

  void _removeCard(_CardDraft draft) {
    setState(() => _cards.remove(draft));
    draft.dispose();
  }

  // ---- Saved templates -------------------------------------------------------

  Future<void> _pickTemplate() async {
    final IgTemplate? picked = await showModalBottomSheet<IgTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext _) => _TemplateSheet(kind: _kind),
    );
    if (!mounted || picked == null) return;
    setState(() => _applyTemplate(picked));
  }

  /// Loads a saved template into the form.
  ///
  /// [IgTemplate.payload] is the raw body the send endpoints already accept, so
  /// it would ideally be posted back untouched; the repository exposes no
  /// raw-payload send, so it is read into the drafts instead. Read is the
  /// operative word — values the form does not render, such as a quick reply's
  /// `contentType`, are carried on the draft and put back verbatim, because
  /// rebuilding the body from only the fields on screen is exactly how a field
  /// disappears between the saved template and the customer.
  ///
  /// A template that carries more rows than [IgLimits] allows is loaded whole
  /// and refused on send. Quietly dropping the overflow here would repeat
  /// Meta's own trick of removing content without saying so.
  void _applyTemplate(IgTemplate t) {
    final Map<String, dynamic> p = t.payload;
    _kind = t.kind;

    switch (t.kind) {
      case IgTemplateKind.quickReply:
        _message.text = _text(p, 'message');
        _swap<_OptionDraft>(
          _quickReplies,
          _rows(p['quickReplies'])
              .map((Map<String, dynamic> j) => _OptionDraft(
                    title: _text(j, 'title'),
                    payload: _text(j, 'payload'),
                    contentType: j['contentType'] as String?,
                  ))
              .toList(),
        );
      case IgTemplateKind.button:
        _message.text = _text(p, 'message');
        _swap<_ButtonDraft>(
          _buttons,
          _rows(p['buttons']).map(_buttonDraft).toList(),
        );
      case IgTemplateKind.generic:
        _swap<_CardDraft>(
          _cards,
          _rows(p['elements'])
              .map((Map<String, dynamic> j) => _CardDraft(
                    title: _text(j, 'title'),
                    subtitle: _text(j, 'subtitle'),
                    imageUrl: _text(j, 'imageUrl'),
                    buttons: _rows(j['buttons']).map(_buttonDraft).toList(),
                  ))
              .toList(),
        );
    }
  }

  /// Replaces a draft list in place and disposes what it displaced. The rows
  /// are keyed by draft identity in the tree, so the old fields are gone by the
  /// time the frame is built.
  void _swap<T extends _Disposable>(List<T> target, List<T> next) {
    for (final T old in target) {
      old.dispose();
    }
    target
      ..clear()
      ..addAll(next);
  }

  // ---- Sending ---------------------------------------------------------------

  /// The count and emptiness checks a field validator cannot see. Returns the
  /// message to show, or null when the draft is sendable.
  String? _countProblem(AppLocalizations l10n) {
    switch (_kind) {
      case IgTemplateKind.quickReply:
        if (_quickReplies.isEmpty) return l10n.igAtLeastOne;
        if (_quickReplies.length > IgLimits.maxQuickReplies) {
          return l10n.igMax(IgLimits.maxQuickReplies);
        }
      case IgTemplateKind.button:
        if (_buttons.isEmpty) return l10n.igAtLeastOne;
        if (_buttons.length > IgLimits.maxButtons) {
          return l10n.igMax(IgLimits.maxButtons);
        }
      case IgTemplateKind.generic:
        if (_cards.isEmpty) return l10n.igAtLeastOne;
        if (_cards.length > IgLimits.maxCards) {
          return l10n.igMax(IgLimits.maxCards);
        }
        for (final _CardDraft c in _cards) {
          if (c.buttons.length > IgLimits.maxButtons) {
            return l10n.igMax(IgLimits.maxButtons);
          }
        }
    }
    return null;
  }

  Future<void> _send() async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (!(_formKey.currentState?.validate() ?? false)) return;
    final String? problem = _countProblem(l10n);
    if (problem != null) {
      _toast(problem);
      return;
    }

    setState(() => _sending = true);
    final InstagramRepository repo = ref.read(instagramRepositoryProvider);

    try {
      switch (_kind) {
        case IgTemplateKind.quickReply:
          await repo.sendQuickReplies(
            contactUid: widget.contactUid,
            message: _message.text.trim(),
            quickReplies: _quickReplies
                .map((_OptionDraft d) => IgQuickReply(
                      title: d.title.text.trim(),
                      payload: d.payload.text.trim(),
                      contentType: d.contentType,
                    ))
                .toList(),
          );
        case IgTemplateKind.button:
          await repo.sendButtonTemplate(
            contactUid: widget.contactUid,
            message: _message.text.trim(),
            buttons: _buttons.map(_toButton).toList(),
          );
        case IgTemplateKind.generic:
          await repo.sendGenericTemplate(
            contactUid: widget.contactUid,
            elements: _cards
                .map((_CardDraft c) => IgCard(
                      title: c.title.text.trim(),
                      subtitle: c.subtitle.text.trim(),
                      imageUrl: c.imageUrl.text.trim(),
                      buttons: c.buttons.map(_toButton).toList(),
                    ))
                .toList(),
          );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.igSent)));
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(e.message);
    }
  }

  /// Only the field the chosen type uses travels. The other one still holds
  /// whatever was typed before the type was switched, and sending it would put
  /// a link on a button the agent had already converted to a payload.
  IgButton _toButton(_ButtonDraft d) => IgButton(
        type: d.type,
        title: d.title.text.trim(),
        payload: d.type == _kPostback ? d.payload.text.trim() : null,
        url: d.type == _kWebUrl ? d.url.text.trim() : null,
      );

  // ---- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.igTitle),
      body: Column(
        children: <Widget>[
          // Stated once, at the top, before anything is typed. Without it the
          // 20-character stop reads as the app being fussy, and the agent works
          // around it instead of writing a title that fits.
          AppBanner(
            message: l10n.igTruncWarn,
            tone: BannerTone.warning,
            icon: Icons.content_cut,
          ),
          SectionLabel(l10n.igKind),
          FilterChipBar(
            options: <FilterOption>[
              FilterOption(
                id: IgTemplateKind.quickReply.name,
                label: l10n.igQuickReplies,
              ),
              FilterOption(
                id: IgTemplateKind.button.name,
                label: l10n.igButtons,
              ),
              FilterOption(
                id: IgTemplateKind.generic.name,
                label: l10n.igCards,
              ),
            ],
            selectedId: _kind.name,
            onSelected: (String id) => setState(
              () => _kind = IgTemplateKind.values.byName(id),
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              // Scrolled as one Column rather than a lazy list on purpose:
              // Form.validate only reaches fields that currently have an
              // element, so with a builder-backed list an over-long title eight
              // rows down would scroll off screen and sail through the very
              // check this screen exists to run.
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(
                  bottom: AppDimens.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AppListTile(
                      title: l10n.igFromTemplate,
                      leading: const IconTile(
                        icon: Icons.bookmark_outline,
                        color: AppColor.info,
                      ),
                      showChevron: false,
                      onTap: _sending ? null : _pickTemplate,
                    ),
                    ..._body(l10n),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.igSend),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(AppLocalizations l10n) => switch (_kind) {
        IgTemplateKind.quickReply => <Widget>[
            _messageField(l10n),
            SectionLabel(l10n.igQuickReplies),
            for (final _OptionDraft d in _quickReplies)
              _QuickReplyEditor(
                key: ObjectKey(d),
                draft: d,
                onRemove: () => _removeQuickReply(d),
              ),
            _addRow(
              l10n,
              () => _add<_OptionDraft>(
                _quickReplies,
                IgLimits.maxQuickReplies,
                _OptionDraft.new,
              ),
            ),
          ],
        IgTemplateKind.button => <Widget>[
            _messageField(l10n),
            SectionLabel(l10n.igButtons),
            for (final _ButtonDraft d in _buttons)
              _ButtonEditor(
                key: ObjectKey(d),
                draft: d,
                onRemove: () => _removeButton(_buttons, d),
                onTypeChanged: (String type) => setState(() => d.type = type),
              ),
            _addRow(
              l10n,
              () => _add<_ButtonDraft>(
                _buttons,
                IgLimits.maxButtons,
                _ButtonDraft.new,
              ),
            ),
          ],
        IgTemplateKind.generic => <Widget>[
            SectionLabel(l10n.igCards),
            for (final _CardDraft c in _cards)
              _CardEditor(
                key: ObjectKey(c),
                draft: c,
                onRemove: () => _removeCard(c),
                onAddButton: () => _add<_ButtonDraft>(
                  c.buttons,
                  IgLimits.maxButtons,
                  _ButtonDraft.new,
                ),
                onRemoveButton: (_ButtonDraft b) => _removeButton(c.buttons, b),
                onButtonTypeChanged: (_ButtonDraft b, String type) =>
                    setState(() => b.type = type),
              ),
            _addRow(
              l10n,
              () => _add<_CardDraft>(_cards, IgLimits.maxCards, _CardDraft.new),
            ),
          ],
      };

  Widget _messageField(AppLocalizations l10n) => Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AppDimens.gutter,
          end: AppDimens.gutter,
          top: 16,
        ),
        child: TextFormField(
          controller: _message,
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: l10n.igMessage,
            hintText: l10n.igMessageHint,
          ),
          validator: (String? v) =>
              (v == null || v.trim().isEmpty) ? l10n.igMessageRequired : null,
        ),
      );

  Widget _addRow(AppLocalizations l10n, VoidCallback onAdd) => Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AppDimens.gutter,
          end: AppDimens.gutter,
          top: 4,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _sending ? null : onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.igAdd),
          ),
        ),
      );
}

// ---- Row editors -------------------------------------------------------------

/// Frame around one repeated row, so a quick reply, a button and a card all
/// read as the same kind of unit.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.children, this.inset = true});

  final List<Widget> children;

  /// Off for a card's own buttons, which already sit inside a [_RowCard] — the
  /// screen gutter applied a second time would leave them a narrow strip down
  /// the middle.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsetsDirectional.only(
        start: inset ? AppDimens.gutter : 0,
        end: inset ? AppDimens.gutter : 0,
        bottom: 12,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColor.hairline),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A capped text field: hard stop at [max] plus the live counter that makes the
/// cap visible before it bites.
class _CappedField extends StatelessWidget {
  const _CappedField({
    required this.controller,
    required this.label,
    required this.max,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final int max;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TextFormField(
      controller: controller,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      validator: (String? v) {
        final String value = (v ?? '').trim();
        if (required && value.isEmpty) return l10n.igTitleRequired;
        // Reachable despite maxLength: input formatters only police typing, and
        // a saved template's title is written straight into the controller.
        if (value.length > max) return l10n.igTitleTooLong(max);
        return null;
      },
    );
  }
}

class _QuickReplyEditor extends StatelessWidget {
  const _QuickReplyEditor({
    required this.draft,
    required this.onRemove,
    super.key,
  });

  final _OptionDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return _RowCard(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _CappedField(
                controller: draft.title,
                label: l10n.igOptionTitle,
                max: IgLimits.title,
                required: true,
              ),
            ),
            _RemoveButton(onRemove: onRemove),
          ],
        ),
        TextFormField(
          controller: draft.payload,
          decoration: InputDecoration(labelText: l10n.igOptionPayload),
        ),
      ],
    );
  }
}

class _ButtonEditor extends StatelessWidget {
  const _ButtonEditor({
    required this.draft,
    required this.onRemove,
    required this.onTypeChanged,
    this.inset = true,
    super.key,
  });

  final _ButtonDraft draft;
  final VoidCallback onRemove;
  final ValueChanged<String> onTypeChanged;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isLink = draft.type == _kWebUrl;

    return _RowCard(
      inset: inset,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _CappedField(
                controller: draft.title,
                label: l10n.igOptionTitle,
                max: IgLimits.title,
                required: true,
              ),
            ),
            _RemoveButton(onRemove: onRemove),
          ],
        ),
        // The segments are named for what the agent then fills in rather than
        // for Meta's `postback` / `web_url`, which are wire values with no
        // translations and no meaning outside the API docs.
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: _kPostback,
              label: Text(l10n.igOptionPayload),
            ),
            ButtonSegment<String>(
              value: _kWebUrl,
              label: Text(l10n.igOptionUrl),
            ),
          ],
          selected: <String>{draft.type},
          onSelectionChanged: (Set<String> s) => onTypeChanged(s.first),
        ),
        const SizedBox(height: 10),
        // One field, swapped by type. A missing url is not validated here: the
        // API rejects that outright with a message worth reading, unlike an
        // over-long title, which it accepts and quietly shortens.
        TextFormField(
          controller: isLink ? draft.url : draft.payload,
          keyboardType: isLink ? TextInputType.url : TextInputType.text,
          decoration: InputDecoration(
            labelText: isLink ? l10n.igOptionUrl : l10n.igOptionPayload,
          ),
        ),
      ],
    );
  }
}

class _CardEditor extends StatelessWidget {
  const _CardEditor({
    required this.draft,
    required this.onRemove,
    required this.onAddButton,
    required this.onRemoveButton,
    required this.onButtonTypeChanged,
    super.key,
  });

  final _CardDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onAddButton;
  final ValueChanged<_ButtonDraft> onRemoveButton;
  final void Function(_ButtonDraft draft, String type) onButtonTypeChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return _RowCard(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _CappedField(
                controller: draft.title,
                label: l10n.igOptionTitle,
                // Cards get the roomier cap — the same field on a button would
                // be cut at 20.
                max: IgLimits.cardText,
                required: true,
              ),
            ),
            _RemoveButton(onRemove: onRemove),
          ],
        ),
        _CappedField(
          controller: draft.subtitle,
          label: l10n.igCardSubtitle,
          max: IgLimits.cardText,
        ),
        TextFormField(
          controller: draft.imageUrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: l10n.igCardImage),
        ),
        // Headed rather than left to the reader: a card's buttons are capped at
        // three of their own, independently of the three a button template
        // gets, and unlabelled editors nested inside a card do not say so.
        SectionLabel(l10n.igButtons, padded: false),
        for (final _ButtonDraft b in draft.buttons)
          _ButtonEditor(
            key: ObjectKey(b),
            draft: b,
            inset: false,
            onRemove: () => onRemoveButton(b),
            onTypeChanged: (String type) => onButtonTypeChanged(b, type),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: onAddButton,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.igAdd),
          ),
        ),
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onRemove,
      icon: const Icon(Icons.close, size: 20),
      color: AppColor.inkMuted,
      tooltip: AppLocalizations.of(context).igRemove,
    );
  }
}

// ---- Saved templates ---------------------------------------------------------

/// Picker for the saved templates of the kind currently being composed.
class _TemplateSheet extends ConsumerWidget {
  const _TemplateSheet({required this.kind});

  final IgTemplateKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<IgTemplate>> templates =
        ref.watch(igTemplatesProvider(kind));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(l10n.igFromTemplate),
          // Fixed height: the spinner, the failure message and the empty state
          // have no intrinsic size of their own, so without it the sheet jumps
          // to a different height as the fetch resolves.
          SizedBox(
            height: 300,
            child: AsyncValueView<List<IgTemplate>>(
              value: templates,
              onRetry: () => ref.invalidate(igTemplatesProvider(kind)),
              builder: (List<IgTemplate> items) {
                // Templates are authored in the web console, so a workspace
                // with none is ordinary rather than broken.
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.bookmark_outline,
                    title: l10n.igNoTemplates,
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (BuildContext context, int i) =>
                      const Divider(indent: AppDimens.gutter),
                  itemBuilder: (BuildContext context, int i) => AppListTile(
                    title: items[i].name,
                    // Picking fills the form behind the sheet rather than
                    // pushing anywhere, so no chevron.
                    showChevron: false,
                    onTap: () => Navigator.of(context).pop(items[i]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppDimens.gutter),
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionCancel),
            ),
          ),
        ],
      ),
    );
  }
}

/// A template payload is server data, not a parsed model — read defensively so
/// one unexpected shape prefills a blank field instead of throwing on a sheet
/// tap.
String _text(Map<String, dynamic> map, String key) => '${map[key] ?? ''}';

List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : const <Map<String, dynamic>>[];

_ButtonDraft _buttonDraft(Map<String, dynamic> j) => _ButtonDraft(
      type: _text(j, 'type') == _kWebUrl ? _kWebUrl : _kPostback,
      title: _text(j, 'title'),
      payload: _text(j, 'payload'),
      url: _text(j, 'url'),
    );

// ---- Drafts ------------------------------------------------------------------

/// Owns controllers, so the screen can dispose a row without knowing which
/// fields it holds.
abstract class _Disposable {
  void dispose();
}

class _OptionDraft implements _Disposable {
  _OptionDraft({String title = '', String payload = '', this.contentType})
      : title = TextEditingController(text: title),
        payload = TextEditingController(text: payload);

  final TextEditingController title;
  final TextEditingController payload;

  /// Not on screen anywhere. Instagram's quick replies carry a content type the
  /// composer has no reason to expose, and it is held here purely so a template
  /// that arrived with one is sent back with it.
  final String? contentType;

  @override
  void dispose() {
    title.dispose();
    payload.dispose();
  }
}

class _ButtonDraft implements _Disposable {
  _ButtonDraft({
    this.type = _kPostback,
    String title = '',
    String payload = '',
    String url = '',
  })  : title = TextEditingController(text: title),
        payload = TextEditingController(text: payload),
        url = TextEditingController(text: url);

  String type;
  final TextEditingController title;
  final TextEditingController payload;
  final TextEditingController url;

  @override
  void dispose() {
    title.dispose();
    payload.dispose();
    url.dispose();
  }
}

class _CardDraft implements _Disposable {
  _CardDraft({
    String title = '',
    String subtitle = '',
    String imageUrl = '',
    List<_ButtonDraft>? buttons,
  })  : title = TextEditingController(text: title),
        subtitle = TextEditingController(text: subtitle),
        imageUrl = TextEditingController(text: imageUrl),
        buttons = buttons ?? <_ButtonDraft>[];

  final TextEditingController title;
  final TextEditingController subtitle;
  final TextEditingController imageUrl;
  final List<_ButtonDraft> buttons;

  @override
  void dispose() {
    title.dispose();
    subtitle.dispose();
    imageUrl.dispose();
    for (final _ButtonDraft b in buttons) {
      b.dispose();
    }
  }
}
