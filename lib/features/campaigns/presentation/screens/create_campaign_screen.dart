import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../contacts/domain/contact.dart' show NamedRef;
import '../../data/campaign_repository.dart';

/// Create campaign — Figma 291:67. Bottom-pinned CTA.
///
/// Only approved WhatsApp templates can be broadcast, so the template picker is
/// driven entirely by `/campaigns/meta` — there is no free-text option.
class CreateCampaignScreen extends ConsumerStatefulWidget {
  const CreateCampaignScreen({super.key});

  @override
  ConsumerState<CreateCampaignScreen> createState() =>
      _CreateCampaignScreenState();
}

class _CreateCampaignScreenState extends ConsumerState<CreateCampaignScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();

  String? _templateName;
  final Set<String> _groupIds = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_templateName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).ccChooseTemplate)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(campaignRepositoryProvider).create(
            title: _title.text.trim(),
            templateName: _templateName!,
            groupIds: _groupIds.toList(),
          );
      ref.invalidate(campaignListProvider);
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<CampaignMeta> meta = ref.watch(campaignMetaProvider);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.ccTitle),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Expanded(
                child: AsyncValueView<CampaignMeta>(
                  value: meta,
                  onRetry: () => ref.invalidate(campaignMetaProvider),
                  builder: (CampaignMeta m) => ListView(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(AppDimens.gutter),
                        child: TextFormField(
                          controller: _title,
                          decoration:
                              InputDecoration(labelText: l10n.ccName),
                          validator: (String? v) =>
                              (v == null || v.trim().isEmpty)
                                  ? l10n.ccNameRequired
                                  : null,
                        ),
                      ),
                      SectionLabel(l10n.cpTemplate),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: DropdownButtonFormField<String>(
                          initialValue: _templateName,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.ccTemplate,
                          ),
                          items: <DropdownMenuItem<String>>[
                            for (final NamedRef t in m.templates)
                              DropdownMenuItem<String>(
                                value: t.name,
                                child: Text(t.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (String? v) =>
                              setState(() => _templateName = v),
                        ),
                      ),
                      SectionLabel(l10n.ccAudience),
                      if (m.groups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimens.gutter,
                          ),
                          child: Text(
                            l10n.ccNoGroups,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      else
                        for (final NamedRef g in m.groups)
                          CheckboxListTile(
                            value: _groupIds.contains(g.id),
                            title: Text(g.name),
                            contentPadding: const EdgeInsetsDirectional.symmetric(
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
                      const SizedBox(height: 12),
                    ],
                  ),
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
