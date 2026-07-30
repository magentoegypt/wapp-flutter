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
    this.subtitleTrailing,
    this.avatar,
    this.actions,
    this.leading,
    this.onBack,
    this.onTitleTap,
    super.key,
  })  : searchHint = null,
        onSearchChanged = null,
        onSearchTap = null,
        trailing = null,
        showBack = false,
        _titleOnly = false;

  /// Large title with an optional trailing widget, and no search field.
  ///
  /// For a tab root that owns a title but nothing to search — More is the only
  /// one today. Without this the screen had to borrow the search variant and
  /// carry a field the frame does not have.
  const AppHeader.title({
    required this.title,
    this.trailing,
    super.key,
  })  : subtitle = null,
        subtitleTrailing = null,
        avatar = null,
        actions = null,
        leading = null,
        onBack = null,
        onTitleTap = null,
        searchHint = null,
        onSearchChanged = null,
        onSearchTap = null,
        showBack = false,
        _titleOnly = true;

  /// Title + search variant, used by the tab roots that own a list.
  ///
  /// Supply [onSearchTap] to turn the field into a button that opens a
  /// dedicated search screen instead of filtering in place — that is what the
  /// inbox does, matching the handoff's navigation graph (Chats → Search).
  const AppHeader.search({
    required this.title,
    required this.searchHint,
    this.onSearchChanged,
    this.onSearchTap,
    this.trailing,
    this.showBack = false,
    super.key,
  })  : subtitle = null,
        subtitleTrailing = null,
        avatar = null,
        actions = null,
        leading = null,
        onBack = null,
        onTitleTap = null,
        _titleOnly = false;

  final bool _titleOnly;

  final String title;
  final String? subtitle;

  /// Sits beside [subtitle] on the back variant. Chat puts the conversation
  /// status pill here, which the frame shows on the same line as the presence
  /// text rather than in the actions slot.
  final Widget? subtitleTrailing;

  /// Between the back affordance and the title on the back variant — the
  /// contact's avatar, per the chat frame.
  final Widget? avatar;

  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;

  /// Opens the contact behind a back-nav header. The frames put the contact
  /// name in the app bar and expect a tap there to reach conversation info.
  final VoidCallback? onTitleTap;

  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;

  /// When set, the search field becomes a tap target rather than an input.
  final VoidCallback? onSearchTap;

  /// Renders a back affordance on the search variant. Required whenever this
  /// header is used on a **pushed** route - the tab roots don't need it, but
  /// without it a pushed screen has no way back and strands the user.
  final bool showBack;

  /// Trailing element on the search variant — the frames put the signed-in
  /// agent's avatar here.
  final Widget? trailing;

  bool get _isSearch => searchHint != null;

  @override
  Size get preferredSize => Size.fromHeight(
        _titleOnly
            ? AppDimens.headerTitle
            : _isSearch
                ? AppDimens.headerSearch
                : AppDimens.headerBack,
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
          child: _titleOnly
              ? _buildTitleOnly(context)
              : _isSearch
                  ? _buildSearch(context)
                  : _buildBack(context),
        ),
      ),
    );
  }

  Widget _buildTitleOnly(BuildContext context) {
    return Row(
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
        const SizedBox(width: 4),
        if (avatar != null) ...<Widget>[
          avatar!,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: GestureDetector(
            onTap: onTitleTap,
            // Opaque so the whole title block is tappable, not just the glyphs.
            behavior: HitTestBehavior.opaque,
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
                if (subtitle != null || subtitleTrailing != null)
                  Row(
                    children: <Widget>[
                      if (subtitle != null)
                        Flexible(
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      if (subtitleTrailing != null) ...<Widget>[
                        const SizedBox(width: 8),
                        subtitleTrailing!,
                      ],
                    ],
                  ),
              ],
            ),
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
            if (showBack) ...<Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                color: Colors.white,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              const SizedBox(width: 8),
            ],
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
        _SearchField(
          hint: searchHint!,
          onChanged: onSearchChanged,
          onTap: onSearchTap,
        ),
      ],
    );
  }
}

/// The header's search input.
///
/// Split out of [AppHeader] so the header itself can stay stateless: the clear
/// affordance has to appear and disappear as the user types, which needs local
/// state. Without it a typed query could only be cleared by backspacing, and on
/// the tab roots the filter stays applied until you do.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, this.onChanged, this.onTap});

  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    // Notify the owner too, or the list stays filtered by a query that is no
    // longer on screen.
    widget.onChanged?.call('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // A tap-to-navigate field never holds text, so it never needs the clear
    // button.
    final bool showClear =
        widget.onTap == null && _controller.text.isNotEmpty;

    return TextField(
      controller: _controller,
      onChanged: (String v) {
        widget.onChanged?.call(v);
        setState(() {});
      },
      readOnly: widget.onTap != null,
      onTap: widget.onTap,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14, color: AppColor.ink),
      decoration: InputDecoration(
        hintText: widget.hint,
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
        suffixIcon: showClear
            ? IconButton(
                onPressed: _clear,
                icon: const Icon(Icons.close, size: 17),
                color: AppColor.inkFaint,
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
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
    );
  }
}
