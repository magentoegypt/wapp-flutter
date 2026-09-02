import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// Add contact.
///
/// Two sections, matching the handoff: **CONTACT** for the fixed columns the
/// endpoint declares, and **OTHER INFORMATION** for the workspace's own custom
/// fields, which are rendered from `/contacts/meta` and never hard-coded —
/// every vendor defines a different set and some of them are required.
///
/// The avatar is generated initials, not an upload. A contact has no avatar
/// field anywhere in the API — not on create, not on update, not in the
/// response — because WhatsApp owns customer profile photos. Deriving the disc
/// from the name gives the frame's shape without a picker that would upload to
/// nowhere.
///
/// Field-level notes worth keeping:
///
///  * **Phone.** `numeric|min_digits:9|doesnt_start_with:+,0`. The rule is
///    stated under the field and enforced as you type, because it rejects the
///    single most natural thing to enter — a number copied from a contact card
///    with its `+` and spaces intact.
///  * **Contact city is a text field, not a dropdown.** The handoff draws a
///    select, but `/contacts/meta` returns countries, groups, labels, custom
///    fields and assignable users — no cities. A select with nothing to select
///    from is worse than a box you can type in.
///  * **Required-ness on custom fields comes from the `required` flag**, never
///    from the field's name, and the API does not enforce it — `store()`
///    forwards custom values unvalidated. The client is the only thing keeping
///    those columns populated.
class ContactFormScreen extends ConsumerStatefulWidget {
  const ContactFormScreen({this.uid, super.key});

  /// The contact being edited. Null creates a new one.
  final String? uid;

  bool get isEdit => uid != null;

  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _language = TextEditingController();
  final TextEditingController _tagInput = TextEditingController();

  bool _saving = false;

  /// The country row's numeric id. Null means "not stated" rather than a
  /// default — guessing a country from the dialling code would be wrong as
  /// often as it was right.
  String? _countryId;
  ValidationFailure? _validation;

  /// Turning this on costs a second request: `enableAiBot` is accepted by
  /// `PUT /contacts/{uid}` but **not** by create, so it is applied as a
  /// follow-up only when the agent actually switched it on. Defaulting to off
  /// keeps the common path to one call.
  bool _aiBot = false;

  final List<String> _tags = <String>[];

  /// Groups the new contact will join, keyed by the group's **numeric id** —
  /// `contact_groups` is resolved with `whereIn('_id', …)`. See [GroupRef].
  final Set<String> _groupIds = <String>{};

  /// Vendor-defined values, keyed by field uid.
  final Map<String, TextEditingController> _customText =
      <String, TextEditingController>{};
  final Map<String, String> _customChoice = <String, String>{};

  /// Edit mode fills the form from the contact exactly once. Re-seeding on
  /// every rebuild would fight the user for the cursor, and the providers here
  /// are autoDispose so a rebuild is not rare.
  bool _seeded = false;

  /// The phone as it exists. `wa_id` is the conversation key and the update
  /// endpoint does not accept `phone_number` at all, so in edit mode the field
  /// is shown read-only rather than offered and silently ignored.
  String _existingPhone = '';

  /// Fills the form from the loaded contact, resolving its groups to the
  /// numeric ids the update endpoint needs.
  ///
  /// The contact's own payload lists groups as `{uid, title}` with **no
  /// numeric id**, while `contact_groups` is matched on `_id`. The two are
  /// joined here through `/contacts/meta`, which is the only place carrying
  /// both. A group that cannot be resolved is dropped rather than sent as a
  /// uid — sending one would not merely fail to match, it would make the
  /// server treat that group as removed.
  void _seed(Contact c, ContactMeta meta) {
    if (_seeded) return;
    _seeded = true;

    final List<String> parts = c.name.trim().split(RegExp(r'\s+'));
    _firstName.text = parts.isNotEmpty ? parts.first : '';
    _lastName.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    _email.text = c.email ?? '';
    _city.text = c.city ?? '';
    _language.text = c.language ?? '';
    _existingPhone = c.phone;
    _tags
      ..clear()
      ..addAll(c.labels);

    for (final NamedRef g in c.groups) {
      for (final GroupRef m in meta.groups) {
        if (m.uid == g.id || m.id == g.id) {
          _groupIds.add(m.id);
          break;
        }
      }
    }

    // Country arrives as a display name, not an id — match it back to the
    // list so the dropdown opens on the value the contact already has.
    final String country = (c.countryCode ?? '').trim().toLowerCase();
    if (country.isNotEmpty) {
      for (final CountryRef ref in meta.countries) {
        if (ref.name.toLowerCase() == country ||
            ref.isoCode.toLowerCase() == country) {
          _countryId = ref.id;
          break;
        }
      }
    }

    for (final ContactCustomValue v in c.customFields) {
      final CustomField? def = meta.customFields
          .cast<CustomField?>()
          .firstWhere((CustomField? f) => f?.uid == v.fieldUid, orElse: () => null);
      if (def == null) continue;
      if (def.isDropdown) {
        _customChoice[def.uid] = v.value;
      } else {
        _customText.putIfAbsent(def.uid, TextEditingController.new).text = v.value;
      }
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _language.dispose();
    _tagInput.dispose();
    for (final TextEditingController c in _customText.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Custom-field values to send, keyed by field uid.
  ///
  /// Blank entries are dropped rather than sent as "": an empty value writes a
  /// row saying the field was answered with nothing, which is not the same as
  /// leaving it unanswered.
  Map<String, String> _customValues() {
    final Map<String, String> out = <String, String>{};
    _customText.forEach((String uid, TextEditingController c) {
      final String v = c.text.trim();
      if (v.isNotEmpty) out[uid] = v;
    });
    _customChoice.forEach((String uid, String v) {
      if (v.isNotEmpty) out[uid] = v;
    });
    return out;
  }

  void _addTag([String? raw]) {
    final String t = (raw ?? _tagInput.text).trim().replaceAll(',', '');
    if (t.isEmpty || _tags.contains(t)) {
      _tagInput.clear();
      return;
    }
    setState(() {
      _tags.add(t);
      _tagInput.clear();
    });
  }

  Future<void> _save() async {
    // Commit whatever is sitting in the tag box but not yet turned into a
    // chip — otherwise a tag the agent typed and did not "enter" is silently
    // dropped on save.
    if (_tagInput.text.trim().isNotEmpty) _addTag();

    // A failed validation used to return in silence. The offending field is
    // routinely below the fold on a form this long — the required custom
    // fields sit at the very bottom — so Save appeared to do nothing at all,
    // with the reason several screens away. Say so.
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).acFixErrors)),
      );
      return;
    }
    setState(() {
      _saving = true;
      _validation = null;
    });

    try {
      if (widget.isEdit) {
        await _saveEdit();
        return;
      }
      final Contact created = await ref.read(contactRepositoryProvider).create(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phoneNumber: _phone.text.trim(),
            email: _email.text.trim(),
            countryId: _countryId,
            languageCode: _language.text.trim(),
            city: _city.text.trim(),
            // The column is a single string; the chips are its comma list.
            tags: _tags.join(','),
            groupIds: _groupIds.toList(),
            customFields: _customValues(),
          );

      // Create cannot carry the AI-bot flag, so it goes as an update. A failure
      // here must not read as "the contact was not created" — it was.
      if (_aiBot && created.uid.isNotEmpty) {
        try {
          await ref
              .read(contactRepositoryProvider)
              .update(created.uid, enableAiBot: true);
        } on Failure {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).acAiBotFailed)),
            );
          }
        }
      }

      ref.invalidate(contactListProvider);
      if (mounted) context.pop();
    } on ValidationFailure catch (e) {
      setState(() => _validation = e);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves an edit.
  ///
  /// **Every field is sent on every save, including the ones the user did not
  /// touch.** That is not laziness — three of them are destructive when
  /// omitted, and each fails silently:
  ///
  ///  * `contact_city` — `processContactUpdate()` calls
  ///    `storeContactContext()`, which rewrites the `__data` blob from
  ///    `$inputData['contact_city'] ?? ''` and stores null when it is absent.
  ///    Unlike first name, email, language and country, the controller does
  ///    **not** seed it from the current row. Renaming a contact would
  ///    therefore erase their city.
  ///  * `contact_tags` — `syncContactTags(..., replaceExisting: true)`, so an
  ///    omitted value clears every tag.
  ///  * `contact_groups` — removals are derived as
  ///    `array_diff(existingIds, sent)`, so anything not resent is unfiled.
  ///
  /// `enableAiBot` is deliberately **not** sent. The contact payload does not
  /// expose the current state, so the form cannot show it truthfully; omitting
  /// the key makes the controller preserve whatever is set, whereas sending a
  /// toggle that defaulted to off would silently disable the bot.
  Future<void> _saveEdit() async {
    await ref.read(contactRepositoryProvider).update(
          widget.uid!,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
          languageCode: _language.text.trim(),
          city: _city.text.trim(),
          tags: _tags.join(','),
          groupIds: _groupIds.toList(),
          customFields: _customValues(),
        );

    ref.invalidate(contactListProvider);
    ref.invalidate(contactDetailProvider(widget.uid!));
    if (mounted) context.pop();
  }

  /// Mirrors the server's `numeric|min_digits:9|doesnt_start_with:+,0`.
  String? _validatePhone(String? raw, AppLocalizations l10n) {
    final String v = (raw ?? '').trim();
    if (v.isEmpty) return l10n.acPhoneRequired;
    if (v.startsWith('0')) return l10n.acPhoneNoPrefix;
    if (!RegExp(r'^\d+$').hasMatch(v)) return l10n.acPhoneDigitsOnly;
    if (v.length < 9) return l10n.acPhoneTooShort;
    return null;
  }

  Future<void> _pickGroups(List<GroupRef> groups) async {
    final Set<String> draft = <String>{..._groupIds};
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setSheet) {
          final AppLocalizations l = AppLocalizations.of(ctx);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l.acSelectGroups,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l.actionSave),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final GroupRef g in groups)
                        CheckboxListTile(
                          value: draft.contains(g.id),
                          title: Text(g.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? on) => setSheet(() {
                            if (on ?? false) {
                              draft.add(g.id);
                            } else {
                              draft.remove(g.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok ?? false) {
      setState(() {
        _groupIds
          ..clear()
          ..addAll(draft);
      });
    }
  }

  /// One vendor-defined field, rendered by its declared type.
  Widget _custom(CustomField f, AppLocalizations l10n) {
    // Required is enforced on **create only**.
    //
    // The API does not enforce it at all — `store()` forwards custom values
    // unvalidated — so this is the client's rule, and on an existing contact
    // it is the wrong one. Contacts predate the fields a workspace later marks
    // required, so enforcing it on edit refuses to let an agent fix a typo in
    // a city until they have also answered questions about a customer they may
    // have no answers for. Worse, it invites them to invent one.
    //
    // On create the contact does not exist yet, nobody is blocked from fixing
    // anything, and the field is the workspace's stated requirement — so it
    // still applies there.
    String? validate(String? v) =>
        f.required && !widget.isEdit && (v == null || v.trim().isEmpty)
            ? l10n.acFieldRequired
            : null;

    if (f.isDropdown) {
      return _Field(
        label: f.name,
        required: f.required,
        badge: f.type,
        child: DropdownButtonFormField<String>(
          initialValue: _customChoice[f.uid]?.isEmpty ?? true
              ? null
              : _customChoice[f.uid],
          isExpanded: true,
          decoration: _box(),
          hint: Text(l10n.acSelectValue),
          items: <DropdownMenuItem<String>>[
            for (final String o in f.options)
              DropdownMenuItem<String>(
                value: o,
                child: Text(o, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (String? v) =>
              setState(() => _customChoice[f.uid] = v ?? ''),
          validator: validate,
        ),
      );
    }

    final TextEditingController c =
        _customText.putIfAbsent(f.uid, TextEditingController.new);

    return _Field(
      label: f.name,
      required: f.required,
      badge: f.type,
      child: TextFormField(
        controller: c,
        // datetime-local gets a plain keyboard rather than a picker: the API
        // stores whatever string it is handed, and a picker would impose a
        // format the console may not read back the same way.
        keyboardType: f.isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : f.isUrl
                ? TextInputType.url
                : TextInputType.text,
        textInputAction: TextInputAction.next,
        autocorrect: !f.isUrl,
        decoration: _box(
          hintText: f.isUrl
              ? 'https://…'
              : f.isDateTime
                  ? l10n.acDateTimeHint
                  : null,
          errorText: _validation?.forField('custom_input_fields.${f.uid}'),
        ),
        validator: validate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ContactMeta> meta = ref.watch(contactMetaProvider);

    // Edit mode needs both the contact and the metadata before it can fill the
    // form — the groups and the country only resolve against the meta lists.
    if (widget.isEdit) {
      final Contact? c = ref.watch(contactDetailProvider(widget.uid!)).valueOrNull;
      final ContactMeta? m = meta.valueOrNull;
      if (c != null && m != null) _seed(c, m);
    }

    final String displayName =
        <String>[_firstName.text.trim(), _lastName.text.trim()]
            .where((String s) => s.isNotEmpty)
            .join(' ');

    return Scaffold(
      appBar: AppHeader.back(
        title: widget.isEdit ? l10n.acEditTitle : l10n.acTitle,
        // Cancel replaces the back arrow: this is a modal, and an arrow implies
        // you can return to something rather than discard what you typed.
        leading: TextButton(
          onPressed: _saving ? null : () => context.pop(),
          style: AppHeader.actionStyle,
          child: Text(l10n.actionCancel),
        ),
        actions: <Widget>[
          _saving
              ? const Padding(
                  padding: EdgeInsetsDirectional.only(end: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  style: AppHeader.actionStyle,
                  child: Text(
                    l10n.actionSave,
                    // Weight is the one thing Save keeps of its own: it is the
                    // affirmative half of the pair.
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.gutter,
              18,
              AppDimens.gutter,
              AppDimens.gutter,
            ),
            children: <Widget>[
              // Generated initials, updating as the name is typed. No upload —
              // the API has no avatar field for a contact.
              Center(
                child: Column(
                  children: <Widget>[
                    InitialsAvatar(
                      name: displayName.isEmpty ? '?' : displayName,
                      size: 72,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.acInitialsNote,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColor.inkFaint,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                ),
              ),
              SectionLabel(l10n.acSectionContact, padded: false),

              _Field(
                label: l10n.acFirstName,
                required: true,
                child: TextFormField(
                  controller: _firstName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 45,
                  decoration:
                      _box(errorText: _validation?.forField('first_name')),
                  // Redraws the initials disc as the name is typed.
                  onChanged: (_) => setState(() {}),
                  validator: (String? v) => (v == null || v.trim().isEmpty)
                      ? l10n.acNameRequired
                      : null,
                ),
              ),
              _Field(
                label: l10n.acLastName,
                // Required by the form though `nullable` server-side. Stricter
                // than the API on purpose: the initials disc and every list row
                // read better with both halves, and a contact saved with one
                // name cannot be corrected from this screen.
                required: true,
                child: TextFormField(
                  controller: _lastName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 45,
                  decoration:
                      _box(errorText: _validation?.forField('last_name')),
                  onChanged: (_) => setState(() {}),
                  validator: (String? v) => (v == null || v.trim().isEmpty)
                      ? l10n.acLastNameRequired
                      : null,
                ),
              ),

              meta.maybeWhen(
                data: (ContactMeta m) => m.countries.isEmpty
                    ? const SizedBox.shrink()
                    : _Field(
                        label: l10n.acCountry,
                        child: DropdownButtonFormField<String>(
                          initialValue: _countryId,
                          isExpanded: true,
                          decoration: _box(),
                          hint: Text(l10n.acCountryHint),
                          items: <DropdownMenuItem<String>>[
                            for (final CountryRef c in m.countries)
                              DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (String? v) =>
                              setState(() => _countryId = v),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

              _Field(
                label: l10n.acCity,
                child: TextFormField(
                  controller: _city,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration:
                      _box(errorText: _validation?.forField('contact_city')),
                ),
              ),

              // `wa_id` is the conversation key and `PUT /contacts/{uid}` does
              // not accept `phone_number` at all, so in edit mode the number is
              // shown rather than offered. An editable box here would take a
              // change, save cleanly, and leave the number untouched.
              if (widget.isEdit)
                _Field(
                  label: l10n.acPhoneNumber,
                  footnote: l10n.acPhoneNotEditable,
                  child: InputDecorator(
                    decoration: _box(),
                    child: Text(
                      _existingPhone,
                      style: TextStyle(color: AppColor.inkMuted),
                    ),
                  ),
                )
              else
              _Field(
                label: l10n.acPhoneNumber,
                required: true,
                footnote: l10n.acPhoneRuleHint,
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  // Digits only at the keyboard, so the two commonest mistakes
                  // — spaces and a `+` pasted from a contact card — cannot be
                  // typed rather than merely being rejected afterwards.
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _box(
                    hintText: l10n.acPhoneHint,
                    errorText: _validation?.forField('phone_number'),
                  ),
                  validator: (String? v) => _validatePhone(v, l10n),
                ),
              ),

              _Field(
                label: l10n.acLanguage,
                child: TextFormField(
                  controller: _language,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  maxLength: 45,
                  decoration: _box(
                    hintText: l10n.acLanguagePlaceholder,
                    errorText: _validation?.forField('language_code'),
                  ),
                ),
              ),

              _Field(
                label: l10n.acEmail,
                child: TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: _box(
                    hintText: l10n.acEmailHint,
                    errorText: _validation?.forField('email'),
                  ),
                ),
              ),

              meta.maybeWhen(
                data: (ContactMeta m) => m.groups.isEmpty
                    ? const SizedBox.shrink()
                    : _Field(
                        label: l10n.acGroups,
                        badge: l10n.acMulti,
                        child: InkWell(
                          onTap: () => _pickGroups(m.groups),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusCard),
                          child: InputDecorator(
                            decoration: _box(),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _groupIds.isEmpty
                                        ? l10n.acSelectGroups
                                        : m.groups
                                            .where((GroupRef g) =>
                                                _groupIds.contains(g.id))
                                            .map((GroupRef g) => g.name)
                                            .join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _groupIds.isEmpty
                                        ? TextStyle(color: AppColor.inkFaint)
                                        : null,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

              _Field(
                label: l10n.acTags,
                child: _TagsField(
                  tags: _tags,
                  controller: _tagInput,
                  decoration: _box(hintText: l10n.acTagsPlaceholder),
                  onAdd: _addTag,
                  onRemove: (String t) => setState(() => _tags.remove(t)),
                ),
              ),

              // Create only. On edit this is hidden rather than shown, because
              // it could not be shown honestly: the contact payload does not
              // expose the current AI-bot state, so the switch would always
              // open in the "off" position regardless of the truth. Sending
              // that on save would silently disable a bot that was on; not
              // sending it — which is what the edit path does, so the server
              // preserves the value — would leave a switch that moves and
              // changes nothing. Neither is acceptable, so it is absent until
              // the API returns the flag.
              //
              // On create it is applied by a follow-up PUT, since create does
              // not accept it either.
              if (!widget.isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColor.warningWash,
                    borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.acAiBot,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              l10n.acAiBotHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _aiBot,
                        onChanged: (bool v) => setState(() => _aiBot = v),
                      ),
                    ],
                  ),
                ),
              ),

              // The workspace's own fields. Rendered from /contacts/meta,
              // never hard-coded — the definitions differ per vendor.
              meta.maybeWhen(
                data: (ContactMeta m) => m.customFields.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SectionLabel(l10n.acSectionOther, padded: false),
                          for (final CustomField f in m.customFields)
                            _custom(f, l10n),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

              meta.maybeWhen(
                loading: () => Text(
                  l10n.acLoadingGroups,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              // No bottom-pinned Save — it lives in the header beside Cancel.
            ],
          ),
        ),
      ),
    );
  }
}

/// The form's input treatment: a filled, borderless rounded box.
///
/// Material's floating `labelText` puts the label inside the box and animates
/// it into the border. The handoff's labels are static, always visible and sit
/// outside, which is a different control to look at — so labels are hoisted
/// into [_Field] and the decoration carries no label of its own.
InputDecoration _box({String? hintText, String? errorText}) => InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      isDense: true,
      // Suppressed on every field: `maxLength` is here to stop input at the
      // server's column width, not to invite the user to count characters, and
      // a column of live counters is noise the handoff does not have.
      counterText: '',
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        borderSide: BorderSide.none,
      ),
    );

/// One labelled row: label, optional required marker and type badge, then the
/// control, then an optional footnote.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.child,
    this.required = false,
    this.badge,
    this.footnote,
  });

  final String label;
  final Widget child;

  /// Draws the red asterisk. On custom fields this comes from the field's own
  /// `required` flag — never from its name.
  final bool required;

  /// The custom field's declared type, shown as a small chip so an agent can
  /// tell a NUMBER from a TEXT before typing into it.
  final String? badge;

  /// Guidance under the control, for rules the server would otherwise only
  /// reveal by rejecting the form.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
              if (required)
                Text(
                  ' *',
                  style: text.labelMedium?.copyWith(color: AppColor.danger),
                ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: AppColor.inkMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          child,
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                footnote!,
                style: text.labelSmall?.copyWith(
                  color: AppColor.inkFaint,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tags as removable chips over a free-text box.
///
/// `contact_tags` is a single comma-separated string of at most 500 characters,
/// so the chips are a presentation of one column, not a relation. Committing on
/// comma as well as on submit matters because the placeholder invites a list.
class _TagsField extends StatelessWidget {
  const _TagsField({
    required this.tags,
    required this.controller,
    required this.decoration,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final TextEditingController controller;
  final InputDecoration decoration;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String t in tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () => onRemove(t),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        TextField(
          controller: controller,
          decoration: decoration,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onAdd(),
          // A comma ends a tag, matching how the value is stored and how the
          // placeholder reads.
          onChanged: (String v) {
            if (v.endsWith(',')) onAdd();
          },
        ),
      ],
    );
  }
}
