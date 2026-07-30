import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
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

  /// Null means send now. The repository has always accepted `scheduledAt`;
  /// there was simply no way to set it, so every campaign created from the app
  /// went out immediately whether or not that was the intent.
  DateTime? _scheduledAt;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }


  /// Comma-joined names of the chosen groups, or null for "all contacts".
  String? _audienceLabel(List<NamedRef> groups) {
    if (_groupIds.isEmpty) return null;
    final List<String> names = groups
        .where((NamedRef g) => _groupIds.contains(g.id))
        .map((NamedRef g) => g.name)
        .toList();
    return names.isEmpty ? null : names.join(', ');
  }

  Future<void> _pickTemplate(List<NamedRef> templates) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) {
        final AppLocalizations l10n = AppLocalizations.of(c);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SectionLabel(l10n.ccTemplate),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    // A plain tile rather than a radio: the sheet closes on the
                    // first tap, so there is no intermediate state for a radio
                    // group to represent.
                    for (final NamedRef t in templates)
                      ListTile(
                        title: Text(t.name),
                        trailing: t.name == _templateName
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: AppColor.brandDeep,
                              )
                            : null,
                        onTap: () => Navigator.of(c).pop(t.name),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => _templateName = picked);
  }

  /// Multi-select, so the sheet edits a local copy and only commits on close —
  /// otherwise dismissing it would silently keep half-made changes.
  Future<void> _pickAudience(List<NamedRef> groups) async {
    final Set<String> draft = <String>{..._groupIds};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) {
        final AppLocalizations l10n = AppLocalizations.of(c);
        return SafeArea(
          child: StatefulBuilder(
            builder: (BuildContext c, void Function(void Function()) setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SectionLabel(l10n.ccAudience),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final NamedRef g in groups)
                          CheckboxListTile(
                            value: draft.contains(g.id),
                            title: Text(g.name),
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
                  Padding(
                    padding: const EdgeInsets.all(AppDimens.gutter),
                    child: FilledButton(
                      onPressed: () => Navigator.of(c).pop(),
                      child: Text(l10n.actionSave),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    setState(() {
      _groupIds
        ..clear()
        ..addAll(draft);
    });
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
            scheduledAt: _scheduledAt,
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
                      // A summary card with Change, per the frame, rather than
                      // an inline dropdown. Only approved templates can be
                      // broadcast, so the list can be long and is worth a sheet
                      // of its own instead of a cramped menu.
                      _SummaryCard(
                        icon: Icons.description_outlined,
                        tint: AppColor.info,
                        label: l10n.ccTemplate,
                        value: _templateName,
                        placeholder: l10n.ccNotSelected,
                        onChange: () => _pickTemplate(m.templates),
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
                        _SummaryCard(
                          icon: Icons.groups_outlined,
                          tint: AppColor.warning,
                          label: l10n.ccAudience,
                          value: _audienceLabel(m.groups),
                          placeholder: l10n.ccAllContacts,
                          // No recipient count. The frame shows one, but
                          // CampaignMeta's groups carry only id and name, and
                          // counting the loaded contacts page would understate
                          // it — a number that undersells a broadcast's reach is
                          // worse than no number at all.
                          onChange: () => _pickAudience(m.groups),
                        ),
                      SectionLabel(l10n.ccSchedule),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.gutter,
                        ),
                        child: _ScheduleChoice(
                          scheduledAt: _scheduledAt,
                          onChanged: (DateTime? at) =>
                              setState(() => _scheduledAt = at),
                        ),
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

/// Send now / Schedule, plus the chosen time once scheduling is picked.
///
/// A campaign that goes out the instant you tap Save is a one-way door, so the
/// frame puts this choice in front of the user rather than defaulting silently.
/// The date picker is bounded to the next year — a broadcast scheduled beyond
/// that is far more likely a mis-tap than an intent.
class _ScheduleChoice extends StatelessWidget {
  const _ScheduleChoice({required this.scheduledAt, required this.onChanged});

  final DateTime? scheduledAt;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null) return;

    if (!context.mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        scheduledAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null) return;

    onChanged(
      DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final bool later = scheduledAt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<bool>(
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text(l10n.ccSendNow)),
            ButtonSegment<bool>(value: true, label: Text(l10n.ccScheduleLater)),
          ],
          selected: <bool>{later},
          showSelectedIcon: false,
          onSelectionChanged: (Set<bool> s) {
            if (s.first) {
              _pick(context);
            } else {
              onChanged(null);
            }
          },
        ),
        if (later) ...<Widget>[
          const SizedBox(height: 10),
          // Tapping the chosen time reopens the picker — the segment is already
          // selected, so it cannot serve as the edit affordance too.
          InkWell(
            onTap: () => _pick(context),
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColor.brandWash,
                borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: AppColor.brandDeep,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMEd(locale)
                          .add_jm()
                          .format(scheduledAt!),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColor.brandDeep,
                      ),
                    ),
                  ),
                  Text(
                    l10n.actionEdit,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColor.brandDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Selected-value card with a Change action, as the frame renders template and
/// audience. Shows [placeholder] in muted ink until something is chosen, so an
/// unset required field is visibly unset rather than looking like a default.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onChange,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool chosen = value != null && value!.isNotEmpty;

    // Label is the constant, value the variable — so the label is the title and
    // the value the subtitle. That also makes an unset field read as unset: the
    // subtitle is already muted, where the title slot rendered the placeholder
    // in bold ink and made "not chosen yet" look like a choice.
    return AppListTile(
      title: label,
      subtitle: chosen ? value! : placeholder,
      leading: IconTile(icon: icon, color: tint),
      showChevron: false,
      trailing: Text(
        l10n.ccChange,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColor.brandDeep,
        ),
      ),
      onTap: onChange,
    );
  }
}
