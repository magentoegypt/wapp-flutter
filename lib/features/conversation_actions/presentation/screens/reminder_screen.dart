import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Set reminder — the ⋮ sheet's "Set reminder" action.
///
/// A list and a form on one screen: what is already queued has to be visible
/// before another is added, or the same contact gets two template sends an hour
/// apart and nobody finds out until they reply.
///
/// The warning banner is the load-bearing part of this screen. "Reminder" in
/// every other tool means a private nudge to the agent; here it dispatches a
/// real approved template to the customer, and nothing else on screen says so.
class ReminderScreen extends ConsumerStatefulWidget {
  const ReminderScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends ConsumerState<ReminderScreen> {
  String? _templateUid;

  /// The chosen moment as a **local wall clock**, not an instant.
  ///
  /// The repository serialises it as `Y-m-d\TH:i` with no zone marker and the
  /// engine re-reads it in the *workspace* timezone. Converting to UTC anywhere
  /// on the way out shifts every reminder by the offset, and the symptom — a
  /// send that lands three hours off — reads as a scheduling bug rather than a
  /// timezone one, so it survives a long time before anyone traces it here.
  DateTime? _scheduleAt;

  /// One controller per placeholder key.
  ///
  /// The keys are derived server-side and are unknown until
  /// [templateDetailProvider] resolves, so these cannot be built in initState;
  /// they are created on demand and kept for the life of the screen. Building a
  /// controller inline in the field builder instead would hand the TextField a
  /// fresh one on every rebuild — and picking a date rebuilds — dropping
  /// whatever had been typed.
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _fields.putIfAbsent(key, () => TextEditingController());

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickTemplate(List<MessageTemplate> templates) async {
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
              SectionLabel(l10n.tpChoose),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final MessageTemplate t in templates)
                      ListTile(
                        title: Text(t.name),
                        trailing: t.uid == _templateUid
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: AppColor.brandDeep,
                              )
                            : null,
                        onTap: () => Navigator.of(c).pop(t.uid),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked == null || picked == _templateUid) return;

    setState(() {
      _templateUid = picked;
      // Placeholder keys are positional (`field_1`, `header_field_1`), so they
      // repeat across templates. Reusing the controllers would silently carry
      // the previous template's values into the new one's form, and the agent
      // would only see it after the customer did.
      for (final TextEditingController c in _fields.values) {
        c.dispose();
      }
      _fields.clear();
    });
  }

  Future<void> _pickWhen() async {
    final DateTime now = DateTime.now();
    final DateTime seed = _scheduleAt ?? now.add(const Duration(hours: 1));

    final DateTime? day = await showDatePicker(
      context: context,
      // A previously chosen day can fall behind [firstDate] while the form sits
      // open; showDatePicker asserts on that rather than clamping.
      initialDate: seed.isBefore(now) ? now : seed,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || day == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
    );
    if (!mounted || time == null) return;

    final DateTime at =
        DateTime(day.year, day.month, day.day, time.hour, time.minute);
    // Today is a legal date and every hour is a legal time, so neither picker
    // can rule out a past moment on its own — only the pair can.
    if (at.isBefore(DateTime.now())) {
      _toast(AppLocalizations.of(context).snPastTime);
      return;
    }
    setState(() => _scheduleAt = at);
  }

  Future<void> _submit(MessageTemplate? template) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String? templateUid = _templateUid;
    // A uid without loaded detail means the placeholder list is still unknown,
    // and sending then would post an empty `fields` map for a template that
    // needs one.
    if (templateUid == null || template == null) {
      _toast(l10n.tpChoose);
      return;
    }

    final DateTime? at = _scheduleAt;
    if (at == null) {
      _toast(l10n.snPickDate);
      return;
    }
    // Re-checked here and not only at pick time: this form can stay open long
    // past the minute that was chosen, and the API accepts a past timestamp by
    // firing it immediately.
    if (at.isBefore(DateTime.now())) {
      _toast(l10n.snPastTime);
      return;
    }

    final Map<String, String> fields = <String, String>{};
    for (final TemplateField f in template.fields) {
      final String value = _controllerFor(f.key).text.trim();
      // An unfilled placeholder is not dropped by Meta, it is rendered as a gap
      // in the customer's sentence — so it is refused here rather than queued.
      if (value.isEmpty) {
        _toast(l10n.tpFieldRequired);
        return;
      }
      fields[f.key] = value;
    }

    setState(() => _saving = true);
    try {
      await ref.read(conversationActionRepositoryProvider).createReminder(
            contactUid: widget.contactUid,
            templateUid: templateUid,
            scheduleAt: at,
            fields: fields,
          );
      ref.invalidate(remindersProvider(widget.contactUid));
      if (!mounted) return;
      _toast(AppLocalizations.of(context).rmDone);

      // Deliberately no pop: this screen is also the queue, and the row that
      // appears is the only confirmation that the send landed on the minute the
      // agent meant. Clearing the schedule and the fields leaves the form ready
      // for the next one while keeping the template selected.
      setState(() {
        _scheduleAt = null;
        for (final TextEditingController c in _fields.values) {
          c.clear();
        }
      });
    } on Failure catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Reminder reminder, String title, String? when) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(l10n.rmDelete),
        // Names the reminder being dropped. Two reminders on one contact often
        // share a template, so the time has to be in the confirm as well or the
        // dialog cannot tell them apart.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title),
            if (when != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(when, style: Theme.of(c).textTheme.bodyMedium),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(l10n.rmDelete),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .deleteReminder(reminder.uid);
      ref.invalidate(remindersProvider(widget.contactUid));
      if (!mounted) return;
      _toast(AppLocalizations.of(context).rmDeleted);
    } on Failure catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  /// The catalogue name for [uid], or null while the list is still loading.
  String? _nameOf(List<MessageTemplate> templates, String? uid) {
    if (uid == null) return null;
    for (final MessageTemplate t in templates) {
      if (t.uid == uid) return t.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateFormat stamp = DateFormat.yMMMEd(locale).add_jm();

    final AsyncValue<List<MessageTemplate>> templates =
        ref.watch(templatesProvider);
    final AsyncValue<List<Reminder>> reminders =
        ref.watch(remindersProvider(widget.contactUid));

    final String? templateUid = _templateUid;
    final AsyncValue<MessageTemplate>? detail = templateUid == null
        ? null
        : ref.watch(templateDetailProvider(templateUid));

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rmTitle),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Above the prompt and the form, not beside the submit button: an
            // agent who reads this screen as a private note-to-self has to be
            // corrected before they start filling it in, not after.
            AppBanner(
              message: l10n.rmSendsReal,
              tone: BannerTone.warning,
              icon: Icons.campaign_outlined,
            ),
            Expanded(
              child: ListView(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppDimens.gutter,
                      end: AppDimens.gutter,
                      top: 14,
                    ),
                    child: Text(
                      l10n.rmPrompt,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  SectionLabel(l10n.tpChoose),
                  AsyncValueView<List<MessageTemplate>>(
                    value: templates,
                    onRetry: () => ref.invalidate(templatesProvider),
                    builder: (List<MessageTemplate> items) {
                      if (items.isEmpty) {
                        return _Note(text: l10n.tpEmpty);
                      }
                      // The row's title is the instruction until something is
                      // chosen. The title slot is the only bold ink on the row,
                      // so a placeholder in the muted subtitle instead made an
                      // unpicked template look like a picked one.
                      return AppListTile(
                        title: _nameOf(items, templateUid) ?? l10n.tpChoose,
                        leading: const IconTile(
                          icon: Icons.description_outlined,
                          color: AppColor.info,
                        ),
                        onTap: () => _pickTemplate(items),
                      );
                    },
                  ),
                  SectionLabel(l10n.rmWhen),
                  AppListTile(
                    title: _scheduleAt == null
                        ? l10n.snPickDate
                        : stamp.format(_scheduleAt!),
                    leading: const IconTile(
                      icon: Icons.schedule_outlined,
                      color: AppColor.warning,
                    ),
                    onTap: _pickWhen,
                  ),
                  // The user-facing half of the wall-clock note on [_scheduleAt]:
                  // an agent in a different country picks a time on their own
                  // clock and gets the workspace's, so the screen has to say
                  // which clock it means.
                  _Note(text: l10n.snTimezoneNote),
                  if (detail != null && templateUid != null) ...<Widget>[
                    SectionLabel(l10n.tpFields),
                    AsyncValueView<MessageTemplate>(
                      value: detail,
                      onRetry: () =>
                          ref.invalidate(templateDetailProvider(templateUid)),
                      builder: (MessageTemplate t) {
                        if (t.fields.isEmpty) {
                          return _Note(text: l10n.tpNoFields);
                        }
                        return Column(
                          children: <Widget>[
                            for (final TemplateField f in t.fields)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: AppDimens.gutter,
                                  end: AppDimens.gutter,
                                  bottom: 12,
                                ),
                                child: TextField(
                                  controller: _controllerFor(f.key),
                                  decoration: InputDecoration(
                                    labelText: f.displayLabel,
                                    hintText: f.example,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  SectionLabel(l10n.rmScheduled),
                  AsyncValueView<List<Reminder>>(
                    value: reminders,
                    onRetry: () =>
                        ref.invalidate(remindersProvider(widget.contactUid)),
                    builder: (List<Reminder> items) {
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.notifications_none,
                          title: l10n.rmEmpty,
                        );
                      }
                      return Column(
                        children: <Widget>[
                          for (final Reminder r in items)
                            _reminderRow(
                              l10n: l10n,
                              stamp: stamp,
                              reminder: r,
                              templates: templates.valueOrNull ??
                                  const <MessageTemplate>[],
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: FilledButton(
                onPressed:
                    _saving ? null : () => _submit(detail?.valueOrNull),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.rmSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reminderRow({
    required AppLocalizations l10n,
    required DateFormat stamp,
    required Reminder reminder,
    required List<MessageTemplate> templates,
  }) {
    final String? name = reminder.templateName;
    // Rows created by the web client come back without templateName, so the
    // loaded catalogue is the second source before the row would otherwise show
    // a bare uid — or nothing at all.
    final String title = (name != null && name.trim().isNotEmpty)
        ? name
        : _nameOf(templates, reminder.templateUid) ?? l10n.rmScheduled;
    final String? when = reminder.scheduleAt == null
        ? null
        : stamp.format(reminder.scheduleAt!);

    return AppListTile(
      title: title,
      subtitle: when,
      showChevron: false,
      leading: const IconTile(
        icon: Icons.schedule_send_outlined,
        color: AppColor.brandDeep,
      ),
      trailing: IconButton(
        onPressed: () => _delete(reminder, title, when),
        icon: const Icon(Icons.delete_outline, size: 20, color: AppColor.danger),
        tooltip: l10n.rmDelete,
      ),
    );
  }
}

/// Gutter-aligned body copy. Three of these carry the screen's advisory lines,
/// and inlining the padding each time is where a stray `EdgeInsets.only(left:)`
/// creeps into an RTL build.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppDimens.gutter,
        end: AppDimens.gutter,
        top: 4,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
