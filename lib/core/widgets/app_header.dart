import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';

/// The brand-green header, in the frames' three variants.
///
/// All implement [PreferredSizeWidget] so they drop straight into
/// `Scaffold.appBar`, and all compose from one table of part metrics in
/// [AppDimens] — so a band measures the same on every screen that uses the
/// same variant, which is what CL037-TC17 failed on.
///
/// The parts are laid out in fixed-height boxes rather than left to size
/// themselves, so what [preferredSize] declares is what the header actually
/// draws. A declared height the content disagrees with is either dead green
/// under the field or an overflow when the clear button appears; this header
/// has shipped both.
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
        _titleOnly = false,
        _greeting = false;

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
        _titleOnly = true,
        _greeting = false;

  /// Dashboard's greeting block: an eyebrow line over the signed-in name,
  /// with the avatar trailing.
  ///
  /// This lived on Dashboard as a private widget with its own ground, its own
  /// inset and a rounded bottom edge no other header had — and no other frame
  /// draws. Folding it in is what makes "the same shape on every page" true
  /// rather than aspirational.
  const AppHeader.greeting({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  })  : subtitleTrailing = null,
        avatar = null,
        actions = null,
        leading = null,
        onBack = null,
        onTitleTap = null,
        searchHint = null,
        onSearchChanged = null,
        onSearchTap = null,
        showBack = false,
        _titleOnly = false,
        _greeting = true;

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
        _titleOnly = false,
        _greeting = false;

  final bool _titleOnly;
  final bool _greeting;

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

  /// White-on-green text action for the header's leading and action slots.
  ///
  /// The same Cancel/Save pair was rendering three ways — a shared
  /// `TextButton.styleFrom` in the quick-reply editor, a bare white
  /// `TextStyle` on contact form's Cancel, and that plus `w700` on its Save.
  /// One style, so a header action looks like a header action everywhere.
  static final ButtonStyle actionStyle = TextButton.styleFrom(
    foregroundColor: Colors.white,
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
  );

  bool get _isSearch => searchHint != null;

  bool get _isBack => !_isSearch && !_titleOnly && !_greeting;

  /// Whether the back variant centres its title.
  ///
  /// The frames centre a plain title and align the chat's identity block to
  /// the start — an avatar with a name and a presence line under it is one
  /// unit and reads as detached from the face when centred.
  bool get _centreTitle =>
      avatar == null && subtitle == null && subtitleTrailing == null;

  @override
  Size get preferredSize {
    if (_greeting) {
      return const Size.fromHeight(AppDimens.headerGreeting);
    }
    if (!_isSearch && !_titleOnly) {
      return const Size.fromHeight(AppDimens.headerBack);
    }
    final double content = AppDimens.headerTopPad +
        AppDimens.headerTitleLine +
        (_isSearch
            ? AppDimens.headerTitleToField + AppDimens.headerField
            : 0) +
        AppDimens.headerBottomPad;
    // Content only — no status-bar inset. Scaffold already grows the app bar
    // by the top padding, and the SafeArea inside applies it again to the
    // content, so adding it here counted it a third time: measured on device,
    // that left 60 logical px of dead green under the field where the frames
    // have 18-24.
    return Size.fromHeight(content);
  }

  @override
  Widget build(BuildContext context) {
    // The band is brand green on every screen, so the status bar sitting in it
    // always needs light icons. Declared here rather than per screen: the only
    // place that declared it was the call screen, so every other screen
    // inherited whatever the previously visited route had left set.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        color: AppColor.brand,
        child: SafeArea(
          bottom: false,
          child: Padding(
            // Two insets, because the frames draw two.
            //
            // A title is a text block and aligns to the app [AppDimens.gutter]
            // like every other text block on the screen — measured at 23.6 on
            // the dashboard, contacts, campaigns and more frames, and the
            // search field's own edges at 23.6/23.0. The back variant is
            // icon-led, and its chevron and overflow button carry 36dp touch
            // targets, so the full gutter stacked on top of those pushes the
            // glyphs a quarter-inch off each edge; the frames sit them close
            // in at [AppDimens.headerGutter].
            //
            // This header used the icon inset for all three, so every tall
            // title sat 10px further left than its frame — half of
            // CL037-TC17's "different size and shape".
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: _isBack ? AppDimens.headerGutter : AppDimens.gutter,
            ),
            child: _greeting
                ? _buildGreeting(context)
                : _titleOnly
                    ? _buildTitleOnly(context)
                    : _isSearch
                        ? _buildSearch(context)
                        : _buildBack(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        // Outside the Expanded, so a long name truncates rather than pushing
        // the avatar off the edge.
        if (trailing != null) trailing!,
      ],
    );
  }

  Widget _buildTitleOnly(BuildContext context) {
    // Top-anchored on the same rhythm as the search variant rather than
    // centred in whatever height is left over. Centring sat More's title ~7px
    // lower than Contacts' for no reason a reader could see; the frames draw
    // both the same distance below the status bar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppDimens.headerTopPad),
        SizedBox(
          height: AppDimens.headerTitleLine,
          child: Row(
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
        ),
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
              icon: const Icon(Icons.chevron_left, size: 30),
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
              // Centred on a plain title, where the frames centre it; aligned
              // to the start as soon as there is an avatar or a subtitle,
              // because the chat header is a stacked identity block and
              // centring that leaves the name floating away from the face it
              // belongs to.
              crossAxisAlignment: _centreTitle
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: _centreTitle ? TextAlign.center : TextAlign.start,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (subtitle != null || subtitleTrailing != null)
                  // The subtitle and the status pill scale as one unit.
                  // Flexing them against each other did not work: an even
                  // split truncated the subtitle, and weighting it 3:1 left
                  // the pill a quarter of its width and scaled "Solved" to
                  // illegible. Sized together, they keep their proportions and
                  // only shrink when the header is genuinely tight.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            softWrap: false,
                            // The FittedBox above scales this down to fit, but
                            // only so far — past that a long presence line was
                            // shrinking toward illegible instead of ending.
                            // Ellipsis is the honest failure.
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        if (subtitleTrailing != null) ...<Widget>[
                          const SizedBox(width: 8),
                          subtitleTrailing!,
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        ...?actions,
        // Counterweight for the back chevron. `Expanded` centres the title
        // inside whatever is left over, so with a 40dp leading affordance and
        // nothing trailing the text lands 20dp left of true centre — visibly
        // off on a short title like "Contact". Only added when the title is
        // actually centred and nothing else occupies the trailing slot.
        if (_centreTitle && (actions == null || actions!.isEmpty))
          const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppDimens.headerTopPad),
        SizedBox(
          height: AppDimens.headerTitleLine,
          child: Row(
            children: <Widget>[
              if (showBack) ...<Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left, size: 30),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
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
        ),
        const SizedBox(height: AppDimens.headerTitleToField),
        SizedBox(
          height: AppDimens.headerField,
          child: _SearchField(
            hint: searchHint!,
            onChanged: onSearchChanged,
            onTap: onSearchTap,
          ),
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
        // A plain sized tap target, not an IconButton: IconButton brings its
        // own minimum metrics and grew the field the moment the clear button
        // appeared, overflowing the header by 16px mid-typing. This matches the
        // prefix's 38x38 exactly, so the field is the same height in both
        // states.
        suffixIcon: showClear
            ? Semantics(
                button: true,
                label: MaterialLocalizations.of(context).deleteButtonTooltip,
                child: InkWell(
                  onTap: _clear,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.close,
                      size: 17,
                      color: AppColor.inkFaint,
                    ),
                  ),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        // Vertical padding inside the fixed 40px box the header gives this.
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
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
