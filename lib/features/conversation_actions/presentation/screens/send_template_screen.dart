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
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Send an approved template to a contact.
///
/// Two steps on one route — choose, then fill — rather than two pushed screens.
/// The placeholders cannot be known until a template is chosen, so the second
/// step has no meaning without the first, and pushing it separately would make
/// correcting a mis-tap a two-screen journey.
///
/// The form for step two is built entirely from the detail's `fields` list. Its
/// keys are derived per template server-side (`field_1`, `header_field_1`,
/// `button_0`) and any key the API does not recognise is dropped without an
/// error, so a hard-coded field set would send a template with empty slots and
/// report success.
class SendTemplateScreen extends ConsumerStatefulWidget {
  const SendTemplateScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<SendTemplateScreen> createState() => _SendTemplateScreenState();
}

class _SendTemplateScreenState extends ConsumerState<SendTemplateScreen> {
  /// Which step is on screen: null is the chooser, set is the fill form.
  String? _templateUid;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? uid = _templateUid;

    return Scaffold(
      appBar: AppHeader.back(
        title: l10n.tpTitle,
        // On step two the arrow walks back to the list instead of out of the
        // screen. Picking the wrong template is the mistake this flow invites,
        // and the default pop would drop the agent back into the chat to start
        // the whole action over.
        onBack: uid == null ? null : () => setState(() => _templateUid = null),
      ),
      body: Column(
        children: <Widget>[
          // The reason this screen exists. Once the 24-hour service window
          // closes a free-form reply is refused by WhatsApp, and an approved
          // template is the only way back to the customer — nothing else in the
          // app says so at the moment the agent needs to know it.
          AppBanner(message: l10n.tpPrompt, tone: BannerTone.warning),
          Expanded(
            child: uid == null
                ? _ChooseStep(
                    onPick: (String picked) =>
                        setState(() => _templateUid = picked),
                  )
                : _FillStep(
                    contactUid: widget.contactUid,
                    templateUid: uid,
                    onChangeTemplate: () => setState(() => _templateUid = null),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Step one — the approved templates this workspace can send.
class _ChooseStep extends ConsumerWidget {
  const _ChooseStep({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<MessageTemplate>> templates =
        ref.watch(templatesProvider);

    return AsyncValueView<List<MessageTemplate>>(
      value: templates,
      onRetry: () => ref.invalidate(templatesProvider),
      builder: (List<MessageTemplate> items) {
        // Empty is not a fault state: approval happens in the web console and a
        // new workspace legitimately has none yet.
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.description_outlined,
            title: l10n.tpEmpty,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionLabel(l10n.tpChoose),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: AppDimens.gutter),
                itemCount: items.length,
                separatorBuilder: (BuildContext context, int i) =>
                    const Divider(indent: 68),
                itemBuilder: (BuildContext context, int i) {
                  final MessageTemplate t = items[i];
                  return AppListTile(
                    title: t.name,
                    subtitle: t.category,
                    leading: const IconTile(
                      icon: Icons.description_outlined,
                      color: AppColor.info,
                    ),
                    // Language is server data, not copy — a template approved
                    // in one language is a different template from its sibling,
                    // and two rows with the same name are otherwise
                    // indistinguishable.
                    trailing: t.language == null
                        ? null
                        : StatusPill(
                            label: t.language!,
                            tone: StatusTone.neutral,
                            showDot: false,
                          ),
                    onTap: () => onPick(t.uid),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Step two — resolves the chosen template's detail, which is what carries the
/// derived field keys. The list endpoint does not return them, so this second
/// read is what makes the form possible at all.
class _FillStep extends ConsumerWidget {
  const _FillStep({
    required this.contactUid,
    required this.templateUid,
    required this.onChangeTemplate,
  });

  final String contactUid;
  final String templateUid;
  final VoidCallback onChangeTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MessageTemplate> detail =
        ref.watch(templateDetailProvider(templateUid));

    return AsyncValueView<MessageTemplate>(
      value: detail,
      onRetry: () => ref.invalidate(templateDetailProvider(templateUid)),
      builder: (MessageTemplate t) => _TemplateForm(
        // Keyed by uid so changing template rebuilds the form from scratch.
        // Without it Flutter reuses the element, and the controllers — which
        // are created once in initState — would keep the previous template's
        // text under the new template's labels.
        key: ValueKey<String>(t.uid),
        contactUid: contactUid,
        template: t,
        onChangeTemplate: onChangeTemplate,
      ),
    );
  }
}

/// The placeholder form and the send action.
///
/// Owns one controller per field, so it is a stateful widget rather than part
/// of the screen: the field set is only known once the detail resolves, and
/// tying the controllers' lifetime to this widget is what lets them be disposed
/// when the agent switches template.
class _TemplateForm extends ConsumerStatefulWidget {
  const _TemplateForm({
    required this.contactUid,
    required this.template,
    required this.onChangeTemplate,
    super.key,
  });

  final String contactUid;
  final MessageTemplate template;
  final VoidCallback onChangeTemplate;

  @override
  ConsumerState<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends ConsumerState<_TemplateForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Controllers keyed by [TemplateField.key], built from the template's own
  /// field list. The map is the payload's shape too — sending anything not
  /// derived from this list means sending a key the API silently discards.
  late final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
    for (final TemplateField f in widget.template.fields)
      f.key: TextEditingController(),
  };

  bool _sending = false;

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    // Every placeholder is mandatory: WhatsApp substitutes what it is given, so
    // a blank slot arrives at the customer as a literal hole in the sentence.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _sending = true);

    try {
      await ref.read(conversationActionRepositoryProvider).sendTemplate(
            contactUid: widget.contactUid,
            templateUid: widget.template.uid,
            fields: _controllers.map(
              (String key, TextEditingController c) =>
                  MapEntry<String, String>(key, c.text.trim()),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.tpDone)));
      // The screen's job is done — the message itself belongs to the chat.
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MessageTemplate t = widget.template;
    final List<TemplateField> fields = t.fields;
    final String body = t.body?.trim() ?? '';

    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppDimens.gutter),
              children: <Widget>[
                AppListTile(
                  title: t.name,
                  subtitle: t.category,
                  leading: const IconTile(
                    icon: Icons.description_outlined,
                    color: AppColor.info,
                  ),
                  // No chevron: this row goes back to the list, and a forward
                  // chevron would promise a push in the wrong direction.
                  showChevron: false,
                  trailing: const Icon(
                    Icons.swap_horiz,
                    size: 20,
                    color: AppColor.inkMuted,
                  ),
                  onTap: _sending ? null : widget.onChangeTemplate,
                ),
                if (body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                      vertical: 4,
                    ),
                    // A plain card, not a chat bubble: the body still holds its
                    // raw placeholders at this point, and dressing it as a sent
                    // message — ticks, timestamp — would claim this is exactly
                    // what the customer receives when it is not.
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColor.surfaceAlt,
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusCard),
                      ),
                      child: Text(
                        body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                if (fields.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppDimens.gutter,
                      end: AppDimens.gutter,
                      top: 20,
                    ),
                    child: Text(
                      l10n.tpNoFields,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...<Widget>[
                  SectionLabel(l10n.tpFields),
                  for (int i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppDimens.gutter,
                        end: AppDimens.gutter,
                        bottom: 12,
                      ),
                      child: TextFormField(
                        controller: _controllers[fields[i].key],
                        textInputAction: i == fields.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        decoration: InputDecoration(
                          // `field_1` names a position, not a meaning — this is
                          // the best label available when the server sends none.
                          labelText: fields[i].displayLabel,
                          hintText: fields[i].example,
                        ),
                        validator: (String? v) => (v == null || v.trim().isEmpty)
                            ? l10n.tpFieldRequired
                            : null,
                      ),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: Row(
                children: <Widget>[
                  // Cancel leaves the action entirely. The header arrow now
                  // only steps back to the list, so without this there is no
                  // one-tap way out of a send the agent has changed their mind
                  // about.
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending ? null : () => context.pop(),
                      child: Text(l10n.actionCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                          : Text(l10n.tpSubmit),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
