import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../routes.dart';

/// Chrome for the four tab roots: the persistent bottom bar plus the Android
/// back policy.
///
/// Wraps a [StatefulNavigationShell], so each tab keeps its own navigation
/// stack — switching away from a half-explored tab and back returns you where
/// you were. The handoff requires this ("everything else is pushed onto the
/// active tab's stack"), which is why this app uses StatefulShellRoute rather
/// than the flat `context.go` pattern used elsewhere in the codebase family.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    // Tapping the already-active tab pops that branch back to its root, which
    // is the platform convention on both iOS and Android.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return PopScope(
      // Only the Home tab may exit the app. Any other tab absorbs the back
      // gesture and returns Home first.
      canPop: navigationShell.currentIndex == AppTab.home.index,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _onTap(AppTab.home.index);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: _BottomBar(
          currentIndex: navigationShell.currentIndex,
          onTap: _onTap,
          labels: <String>[
            l10n.navHome,
            l10n.navChats,
            l10n.navContacts,
            l10n.navMore,
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentIndex,
    required this.onTap,
    required this.labels,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;

  static const List<IconData> _icons = <IconData>[
    Icons.dashboard_outlined,
    Icons.chat_bubble_outline,
    Icons.people_outline,
    Icons.grid_view_outlined,
  ];

  static const List<IconData> _activeIcons = <IconData>[
    Icons.dashboard,
    Icons.chat_bubble,
    Icons.people,
    Icons.grid_view,
  ];

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF141C17),
        border: Border(
          top: BorderSide(
            color: isLight ? AppColor.hairline : const Color(0xFF243029),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppDimens.tabBar,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < labels.length; i++)
                Expanded(
                  child: _BarItem(
                    icon: i == currentIndex ? _activeIcons[i] : _icons[i],
                    label: labels[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColor.brandDeep : AppColor.inkFaint;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
