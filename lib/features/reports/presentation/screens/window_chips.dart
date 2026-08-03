import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/report_repository.dart';

/// The shared from/to picker for the two range-scoped reports.
///
/// Presets plus a custom range. The presets exist because the useful windows
/// are few and a two-step date picker for "last 7 days" is friction; the custom
/// option exists because month-end reporting needs exact boundaries.
///
/// Sits outside the async body on every screen that uses it, so it stays usable
/// while the next window loads — a slow request must not strand the user on a
/// filter they are trying to leave.
class WindowChips extends ConsumerWidget {
  const WindowChips({required this.provider, super.key});

  final StateProvider<DateWindow> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateWindow current = ref.watch(provider);

    Future<void> pickRange() async {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        // 2000 matches the server's own lower bound on the year fields; there
        // is no data before the workspace existed anyway.
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange:
            DateTimeRange(start: current.from, end: current.to),
      );
      if (picked == null) return;
      ref.read(provider.notifier).state =
          DateWindow(from: picked.start, to: picked.end);
    }

    // A preset is "selected" when the window it describes is the one in force.
    // Compared by day count rather than by identity so the chip stays lit after
    // a rebuild reconstructs an equal window.
    bool isPreset(int days) =>
        current.days == days &&
        current.to.difference(DateTime.now()).inHours.abs() < 24;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.stripGutter,
        vertical: 10,
      ),
      child: Row(
        children: <Widget>[
          for (final (int days, String label) preset in <(int, String)>[
            (7, l10n.rpLast7),
            (30, l10n.rpLast30),
            (90, l10n.rpLast90),
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(preset.$2),
                selected: isPreset(preset.$1),
                onSelected: (_) => ref.read(provider.notifier).state =
                    DateWindow.lastDays(preset.$1),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.date_range_outlined, size: 16),
            label: Text(
              isPreset(7) || isPreset(30) || isPreset(90)
                  ? l10n.rpCustomRange
                  : l10n.rpRangeLabel(_ymd(current.from), _ymd(current.to)),
            ),
            onPressed: pickRange,
          ),
        ],
      ),
    );
  }
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
