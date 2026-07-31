import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/data/conversation_repository.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Snooze — hide a conversation from the inbox until a moment the agent picks.
///
/// The value the API takes is an **absolute** local date and time, not a
/// duration, so the date and the time pickers are the primary controls and the
/// preset chips only prefill them. Presets are deliberately labelled with the
/// absolute value they set rather than with words like "tomorrow": the wording
/// would hide what is actually being sent, and it is the sent value the agent
/// has to be able to check before tapping Snooze.
class SnoozeScreen extends ConsumerStatefulWidget {
  const SnoozeScreen({required this.contactUid, this.current, super.key});

  final String contactUid;

  /// The snooze already in force, when the caller happens to know it.
  ///
  /// No read endpoint exposes snooze state today, so this is null on every
  /// route that exists right now and the unsnooze block simply does not render.
  /// It is a parameter rather than a `ref.watch` so that the day the state does
  /// arrive on the conversation payload, the caller can pass it without this
  /// screen having to grow a provider that would 404 in the meantime.
  final SnoozeState? current;

  @override
  ConsumerState<SnoozeScreen> createState() => _SnoozeScreenState();
}

class _SnoozeScreenState extends ConsumerState<SnoozeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reason = TextEditingController();

  /// The single source of truth for what gets sent. Both pickers and every
  /// preset write here; nothing else is retained.
  DateTime? _until;

  /// Covers snooze *and* unsnooze — both are on screen at once when there is a
  /// current snooze, and a second tap during either would fire a second request.
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Quick prefills, recomputed on every build so they never go stale while the
  /// screen sits open.
  ///
  /// `DateTime` normalises overflow, so hour 25 rolls into tomorrow and day 38
  /// into next month — which is exactly right for "three hours from now" late in
  /// the evening, where clamping to 23:59 would be a lie.
  List<DateTime> _presets(DateTime now) => <DateTime>[
        DateTime(now.year, now.month, now.day, now.hour + 3),
        DateTime(now.year, now.month, now.day + 1, 9),
        DateTime(now.year, now.month, now.day + 7, 9),
      ];

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime base = _until ?? now.add(const Duration(hours: 1));
    final DateTime? day = await showDatePicker(
      context: context,
      // A value chosen earlier can have gone stale while the screen was open,
      // and an initialDate before firstDate asserts.
      initialDate: base.isBefore(now) ? now : base,
      firstDate: now,
      // A year out is the far end of plausible; beyond that it is a mis-tap.
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;

    setState(() {
      // Carry the time across. Correcting the date must not silently reset an
      // hour the agent already chose.
      _until = DateTime(day.year, day.month, day.day, base.hour, base.minute);
    });
  }

  Future<void> _pickTime() async {
    final DateTime base = _until ?? DateTime.now().add(const Duration(hours: 1));
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;

    // With no date picked yet this lands on today, which is the only sensible
    // reading of a bare time — and if that hour has already passed, the guard in
    // [_submit] says so rather than snoozing into the past.
    setState(() {
      _until = DateTime(base.year, base.month, base.day, time.hour, time.minute);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime? until = _until;
    // The button is disabled in this state; this only keeps the type promotion.
    if (until == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Catches both a past date and an hour that has already gone by today. The
    // API would reject it, but with a message written for an integrator.
    if (!until.isAfter(DateTime.now())) {
      _toast(l10n.snPastTime);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(conversationActionRepositoryProvider).snooze(
            contactUid: widget.contactUid,
            until: until,
            // Dart ships no tz database, so this is the platform's abbreviation
            // ("EET", "Eastern European Standard Time") and not an IANA name.
            // It stays advisory: the server re-reads `until` as a wall clock in
            // the **workspace** timezone, so what the agent typed is what gets
            // scheduled regardless of what this string says.
            timezone: DateTime.now().timeZoneName,
            reason: _reason.text.trim(),
          );
      // Snoozing takes the conversation out of the inbox, so a list left in
      // cache would still show a row that no longer belongs there.
      ref.invalidate(inboxListProvider);
      if (!mounted) return;
      _toast(l10n.snDone);
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unsnooze() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(conversationActionRepositoryProvider)
          .unsnooze(widget.contactUid);
      ref.invalidate(inboxListProvider);
      if (!mounted) return;
      _toast(l10n.snUnsnoozed);
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime now = DateTime.now();

    final List<DateTime> presets = _presets(now);
    final DateFormat chipFormat = DateFormat.MMMEd(locale).add_jm();
    final int selectedPreset = _until == null
        ? -1
        : presets.indexWhere((DateTime d) => d == _until);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.snTitle),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsetsDirectional.only(bottom: 12),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppDimens.gutter,
                        end: AppDimens.gutter,
                        top: 16,
                      ),
                      child: Text(l10n.snPrompt, style: text.bodyMedium),
                    ),
                    if (widget.current != null)
                      _CurrentSnoozeCard(
                        state: widget.current!,
                        locale: locale,
                        onUnsnooze: _busy ? null : _unsnooze,
                      ),
                    SectionLabel(l10n.snUntil),
                    AppListTile(
                      title: l10n.snPickDate,
                      subtitle: _until == null
                          ? null
                          : DateFormat.yMMMEd(locale).format(_until!),
                      leading: const IconTile(
                        icon: Icons.event_outlined,
                        color: AppColor.info,
                      ),
                      onTap: _busy ? null : _pickDate,
                    ),
                    AppListTile(
                      title: l10n.snPickTime,
                      subtitle: _until == null
                          ? null
                          : DateFormat.jm(locale).format(_until!),
                      leading: const IconTile(
                        icon: Icons.schedule_outlined,
                        color: AppColor.info,
                      ),
                      onTap: _busy ? null : _pickTime,
                    ),
                    const SizedBox(height: 6),
                    FilterChipBar(
                      options: <FilterOption>[
                        for (int i = 0; i < presets.length; i++)
                          FilterOption(
                            id: '$i',
                            label: chipFormat.format(presets[i]),
                          ),
                      ],
                      // Index as id, so a hand-picked value that happens to land
                      // on a preset lights that chip up instead of leaving the
                      // row looking unrelated to the fields above it.
                      selectedId:
                          selectedPreset < 0 ? '' : '$selectedPreset',
                      onSelected: (String id) => setState(
                        () => _until = presets[int.parse(id)],
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppBanner(
                      message: l10n.snTimezoneNote,
                      tone: BannerTone.neutral,
                      icon: Icons.public,
                    ),
                    SectionLabel(l10n.snReason),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppDimens.gutter,
                        end: AppDimens.gutter,
                      ),
                      child: TextFormField(
                        controller: _reason,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: l10n.snReasonHint,
                        ),
                        // Optional to the API for an admin, mandatory for
                        // everyone else — and the client cannot see the role.
                        // Asking every agent for one line costs a sentence;
                        // omitting it costs a 422 whose body the agent has no
                        // way to act on.
                        validator: (String? v) => (v == null || v.trim().isEmpty)
                            ? l10n.snReasonRequired
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppDimens.gutter),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    // Nothing picked means nothing to send, and there is no key
                    // for "choose a time first" — an inert button says it
                    // without inventing copy.
                    onPressed: (_busy || _until == null) ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.snSubmit),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The snooze already in force, with the way out of it.
///
/// Only built when the caller supplied a state, so it never has to render an
/// "not snoozed" variant.
class _CurrentSnoozeCard extends StatelessWidget {
  const _CurrentSnoozeCard({
    required this.state,
    required this.locale,
    this.onUnsnooze,
  });

  final SnoozeState state;
  final String locale;
  final VoidCallback? onUnsnooze;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime? until = state.until;

    return Container(
      margin: const EdgeInsetsDirectional.only(
        start: AppDimens.gutter,
        end: AppDimens.gutter,
        top: 16,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surfaceAlt,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A snooze with no end time cannot fill the {when} placeholder, so the
          // line is dropped rather than printed with a fabricated date — the
          // unsnooze action below is the part that still has to work.
          if (until != null)
            Row(
              children: <Widget>[
                const Icon(
                  Icons.bedtime_outlined,
                  size: AppDimens.glyph,
                  color: AppColor.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.snCurrently(
                      DateFormat.yMMMEd(locale).add_jm().format(until),
                    ),
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColor.ink,
                    ),
                  ),
                ),
              ],
            ),
          // The agent's own words from when it was snoozed. Shown unlabelled
          // because it reads as the sentence it is; the author's name is left
          // out entirely, since there is no key to label it with.
          if (state.reason != null && state.reason!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(state.reason!.trim(), style: text.bodyMedium),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: onUnsnooze,
              child: Text(l10n.snUnsnooze),
            ),
          ),
        ],
      ),
    );
  }
}
