import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  // Split per the frame. The API still takes a single `name`, so the two are
  // joined at the call site rather than changing the contract.
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();

  bool _saving = false;
  ValidationFailure? _validation;

  /// Contact groups the new contact will join, keyed by group uid.
  final Set<String> _groupIds = <String>{};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
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
            // Single API field; the frame splits the input, not the contract.
            name: <String>[_firstName.text.trim(), _lastName.text.trim()]
                .where((String p) => p.isNotEmpty)
                .join(' '),
            phone: _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ContactMeta> meta = ref.watch(contactMetaProvider);

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
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _firstName,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l10n.acFirstName,
                              errorText: _validation?.forField('name'),
                            ),
                            validator: (String? v) =>
                                (v == null || v.trim().isEmpty)
                                    ? l10n.acNameRequired
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastName,
                            textInputAction: TextInputAction.next,
                            decoration:
                                InputDecoration(labelText: l10n.acLastName),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.acPhone,
                        hintText: l10n.acPhoneHint,
                        errorText: _validation?.forField('phone'),
                      ),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.acPhoneRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.acEmail,
                        errorText: _validation?.forField('email'),
                      ),
                    ),
                  ],
                ),
              ),

              // Group assignment. `create()` has always accepted groupIds, but
              // until now nothing populated it — the screen fetched
              // /contacts/meta and rendered only a loading hint, so a contact
              // could never be filed into a group. Mirrors the picker on
              // Create campaign.
              Flexible(
                child: meta.when(
                  loading: () => Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppDimens.gutter,
                      bottom: 8,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.acLoadingGroups,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                        SectionLabel(l10n.acGroups),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: <Widget>[
                              for (final NamedRef g in m.groups)
                                CheckboxListTile(
                                  value: _groupIds.contains(g.id),
                                  title: Text(g.name),
                                  dense: true,
                                  contentPadding:
                                      const EdgeInsetsDirectional.symmetric(
                                    horizontal: AppDimens.gutter,
                                  ),
                                  onChanged: (bool? on) => setState(() {
                                    if (on ?? false) {
                                      _groupIds.add(g.id);
                                    } else {
                                      _groupIds.remove(g.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // No bottom-pinned Save — it moved into the header alongside
              // Cancel, where the frame puts it.
            ],
          ),
        ),
      ),
    );
  }
}
