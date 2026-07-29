import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// Add contact — Figma 290:137.
///
/// Bottom-pinned CTA per the handoff: a Column with a Spacer before the button,
/// mirroring the flex spacer in the Figma frame.
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();

  bool _saving = false;
  ValidationFailure? _validation;

  @override
  void dispose() {
    _name.dispose();
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
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
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
      appBar: AppHeader.back(title: l10n.acTitle),
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
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.acName,
                        errorText: _validation?.forField('name'),
                      ),
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? l10n.acNameRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.acPhone,
                        hintText: '+20 100 234 5678',
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
                    // Groups come from /contacts/meta. Surface a hint while it
                    // loads rather than an empty area that looks broken.
                    if (meta.isLoading) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        l10n.acLoadingGroups,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
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
