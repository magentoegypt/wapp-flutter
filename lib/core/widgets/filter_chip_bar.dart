import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// One option in a [FilterChipBar].
class FilterOption {
  const FilterOption({required this.id, required this.label, this.count});

  final String id;
  final String label;

  /// Rendered inline after the label ("All 24"), matching the inbox frame.
  final int? count;
}

/// Single-select filter row. Brand fill marks the active option; the rest sit
/// on the neutral surface.
class FilterChipBar extends StatelessWidget {
  const FilterChipBar({
    required this.options,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<FilterOption> options;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.gutter,
          vertical: 6,
        ),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final FilterOption o = options[i];
          final bool selected = o.id == selectedId;

          return GestureDetector(
            onTap: () => onSelected(o.id),
            child: Semantics(
              selected: selected,
              button: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColor.brand : AppColor.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  o.count == null ? o.label : '${o.label} ${o.count}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColor.inkMuted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
