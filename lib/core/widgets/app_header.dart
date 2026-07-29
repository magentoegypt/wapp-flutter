import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// The brand-green header, in the handoff's two variants.
///
/// Both implement [PreferredSizeWidget] so they drop straight into
/// `Scaffold.appBar`, and both declare the exact heights from the layout
/// constants table — 96 for back-nav, 182 for title+search — rather than
/// letting content size them.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Back-nav variant: leading back affordance, title, optional actions.
  const AppHeader.back({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.onBack,
    super.key,
  })  : searchHint = null,
        onSearchChanged = null,
        trailing = null;

  /// Title + search variant, used by the tab roots that own a list.
  const AppHeader.search({
    required this.title,
    required this.searchHint,
    this.onSearchChanged,
    this.trailing,
    super.key,
  })  : subtitle = null,
        actions = null,
        leading = null,
        onBack = null;

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;

  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;

  /// Trailing element on the search variant — the frames put the signed-in
  /// agent's avatar here.
  final Widget? trailing;

  bool get _isSearch => searchHint != null;

  @override
  Size get preferredSize => Size.fromHeight(
        _isSearch ? AppDimens.headerSearch : AppDimens.headerBack,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColor.brand,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppDimens.gutter,
          ),
          child: _isSearch ? _buildSearch(context) : _buildBack(context),
        ),
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    return Row(
      children: <Widget>[
        leading ??
            IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              // Directional: points left in LTR, right in RTL.
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
            ],
          ),
        ),
        ...?actions,
      ],
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: onSearchChanged,
          style: const TextStyle(fontSize: 14, color: AppColor.ink),
          decoration: InputDecoration(
            hintText: searchHint,
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(
              Icons.search,
              size: 18,
              color: AppColor.inkFaint,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
