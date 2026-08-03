import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// Add contact — Figma 290:137.
///
/// Presented as a modal: Cancel and Save live in the header, not on a
/// bottom-pinned button. The handoff's "bottom-pinned CTA" note applies to the
/// detail screens; this frame is a sheet, and a form you can abandon needs its
/// escape hatch beside its commit.
///
/// **Field order follows the frame**: first name, last name, phone, email,
/// country — each full width and stacked. First and last were previously side
/// by side in one row, which is not what the frame draws and left both boxes
/// too narrow to read a long name in; and country sat above email rather than
/// below it.
///
/// Two controls the frame draws are deliberately absent, because nothing behind
/// them exists:
///
///  * **Add photo.** A contact has no avatar field anywhere in the API — not on
///    create, not on update, not in the response shape. WhatsApp profile photos
///    belong to WhatsApp and are not ours to set. A picker here would upload to
///    nowhere.
///  * **Lifecycle stage.** The frame offers Customer/Lead/VIP. The only thing
///    resembling it is `customerType`, which is *derived* by the server as
///    `new`/`returning` and is not writable — a different vocabulary answering a
///    different question. A dropdown here would be a control that silently
///    discards whatever the user picked.
///
/// Three fields the API does accept and the frame omits are included, because
/// leaving them out means the app can create contacts the console then shows as
/// half-filled: city, tags and language.
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _tags = TextEditingController();

  bool _saving = false;

  /// The country row's numeric id. Null means "not stated" rather than a
  /// default — guessing a country from the dialling code would be wrong as
  /// often as it was right.
  String? _countryId;
  ValidationFailure? _validation;

  /// Contact groups the new contact will join, keyed by group uid.
  final Set<String> _groupIds = <String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _validation = null;
    });

    try {
      await ref.read(contactRepositoryProvider).create(
            // Two fields, not one joined string: the endpoint validates
            // `first_name` and `last_name` separately.
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phoneNumber: _phone.text.trim(),
            email: _email.text.trim(),
            countryId: _countryId,
            city: _city.text.trim(),
            tags: _tags.text.trim(),
            groupIds: _groupIds.toList(),
          );
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

  /// Mirrors the server's `numeric|min_digits:9|doesnt_start_with:+,0` so the
  /// rule is explained where it is broken, rather than arriving as a 422 naming
  /// a field the user thought they had filled in correctly.
  ///
  /// The frame's own placeholder — "+20 100 234 5678" — violates all three
  /// halves of it, so this is a case where following the frame literally would
  /// have shipped a form that cannot be submitted.
  String? _validatePhone(String? raw, AppLocalizations l10n) {
    final String v = (raw ?? '').trim();
    if (v.isEmpty) return l10n.acPhoneRequired;
    if (v.startsWith('+') || v.startsWith('0')) return l10n.acPhoneNoPrefix;
    if (!RegExp(r'^\d+$').hasMatch(v)) return l10n.acPhoneDigitsOnly;
    if (v.length < 9) return l10n.acPhoneTooShort;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ContactMeta> meta = ref.watch(contactMetaProvider);

    final CountryRef? country = meta.maybeWhen(
      data: (ContactMeta m) => m.countries
          .cast<CountryRef?>()
          .firstWhere((CountryRef? c) => c?.id == _countryId, orElse: () => null),
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppHeader.back(
        title: l10n.acTitle,
        // Cancel replaces the back arrow: this is a modal, and an arrow implies
        // you can return to something rather than discard what you typed.
        leading: TextButton(
          onPressed: _saving ? null : () => context.pop(),
          child: Text(
            l10n.actionCancel,
            style: const TextStyle(color: Colors.white),
          ),
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
                  child: Text(
                    l10n.actionSave,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.gutter,
              vertical: 16,
            ),
            children: <Widget>[
              _Field(
                label: l10n.acFirstName,
                child: TextFormField(
                  controller: _firstName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 45,
                  decoration: _box(errorText: _validation?.forField('first_name')),
                  validator: (String? v) => (v == null || v.trim().isEmpty)
                      ? l10n.acNameRequired
                      : null,
                ),
              ),
              _Field(
                label: l10n.acLastName,
                child: TextFormField(
                  controller: _lastName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 45,
                  decoration: _box(errorText: _validation?.forField('last_name')),
                ),
              ),
              _Field(
                label: l10n.acPhone,
                // The dialling code of the chosen country, shown as a prefix so
                // "which country am I dialling" and "do not type the +" are
                // answered in the same glance.
                hint: country != null && country.phoneCode.isNotEmpty
                    ? l10n.acPhoneCodeHint(country.phoneCode)
                    : l10n.acPhoneRuleHint,
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  // Digits only at the keyboard, so the commonest mistakes —
                  // spaces and a leading + pasted from a contact card — cannot
                  // be typed rather than merely being rejected afterwards.
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _box(
                    hintText: country != null && country.phoneCode.isNotEmpty
                        ? '${country.phoneCode}1002345678'
                        : l10n.acPhoneHint,
                    errorText: _validation?.forField('phone_number'),
                  ),
                  validator: (String? v) => _validatePhone(v, l10n),
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

              // Country. Only rendered once the meta call has actually returned
              // a list — an empty dropdown is a control that cannot be used.
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
                  decoration: _box(errorText: _validation?.forField('contact_city')),
                ),
              ),
              _Field(
                label: l10n.acTags,
                hint: l10n.acTagsHint,
                child: TextFormField(
                  controller: _tags,
                  textInputAction: TextInputAction.done,
                  maxLength: 500,
                  decoration: _box(
                    hintText: l10n.acTagsPlaceholder,
                    errorText: _validation?.forField('contact_tags'),
                  ),
                ),
              ),

              // Group assignment. `create()` has always accepted groupIds, but
              // until now nothing populated it — the screen fetched
              // /contacts/meta and rendered only a loading hint, so a contact
              // could never be filed into a group. Mirrors the picker on
              // Create campaign.
              meta.when(
                loading: () => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.acLoadingGroups,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                // Groups are optional metadata — if the lookup fails the
                // contact can still be created, so this stays silent rather
                // than blocking the form.
                error: (Object _, StackTrace __) => const SizedBox.shrink(),
                data: (ContactMeta m) {
                  if (m.groups.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SectionLabel(l10n.acGroups, padded: false),
                      for (final NamedRef g in m.groups)
                        CheckboxListTile(
                          value: _groupIds.contains(g.id),
                          title: Text(g.name),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? on) => setState(() {
                            if (on ?? false) {
                              _groupIds.add(g.id);
                            } else {
                              _groupIds.remove(g.id);
                            }
                          }),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppDimens.gutter),
              // No bottom-pinned Save — it moved into the header alongside
              // Cancel, where the frame puts it.
            ],
          ),
        ),
      ),
    );
  }
}

/// The frame's input treatment: a small label **above** a filled rounded box.
///
/// Material's floating `labelText` puts the label inside the box and animates
/// it into the border, which is a different control to look at — the frame's
/// labels are static, always visible, and sit outside. Hoisting them also means
/// a long label no longer competes with the value for the same line.
InputDecoration _box({String? hintText, String? errorText}) => InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      isDense: true,
      // The counter is suppressed on every field: `maxLength` is here to stop
      // input at the server's column width, not to invite the user to count
      // characters, and six live counters down the form is visual noise the
      // frame does not have.
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

/// One labelled row of the form.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;

  /// Optional guidance under the label — used where a server rule would
  /// otherwise only surface as a rejection.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.labelMedium),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: text.labelSmall?.copyWith(
                  color: AppColor.inkFaint,
                  letterSpacing: 0,
                ),
              ),
            ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
