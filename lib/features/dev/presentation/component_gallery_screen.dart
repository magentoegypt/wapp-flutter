import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/filter_chip_bar.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/message_bubble.dart';
import '../../../core/widgets/message_composer.dart';
import '../../../core/widgets/note_card.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/weekly_bar_chart.dart';

/// Every shared component on one page, under a live brightness × direction
/// toggle.
///
/// This exists so a token or RTL mistake is caught once here rather than
/// twenty times across the screen inventory. Walk all four combinations after
/// touching the theme or any widget in `core/widgets/`.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  Brightness _brightness = Brightness.light;
  TextDirection _direction = TextDirection.ltr;
  String _filter = 'all';

  bool get _isDark => _brightness == Brightness.dark;
  bool get _isRtl => _direction == TextDirection.rtl;

  @override
  Widget build(BuildContext context) {
    // Arabic drives the Cairo font, so pair RTL with 'ar' to preview the real
    // pairing rather than Inter-in-RTL.
    final ThemeData theme = _isDark
        ? AppTheme.dark(_isRtl ? 'ar' : 'en')
        : AppTheme.light(_isRtl ? 'ar' : 'en');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Component gallery'),
        actions: <Widget>[
          IconButton(
            tooltip: _isDark ? 'Switch to light' : 'Switch to dark',
            icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => setState(
              () => _brightness = _isDark ? Brightness.light : Brightness.dark,
            ),
          ),
          IconButton(
            tooltip: _isRtl ? 'Switch to LTR' : 'Switch to RTL',
            icon: Text(
              _isRtl ? 'RTL' : 'LTR',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            onPressed: () => setState(
              () => _direction = _isRtl ? TextDirection.ltr : TextDirection.rtl,
            ),
          ),
        ],
      ),
      body: Theme(
        data: theme,
        child: Directionality(
          textDirection: _direction,
          child: Container(
            color: theme.scaffoldBackgroundColor,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: <Widget>[
                _group('Headers', <Widget>[
                  SizedBox(
                    height: AppDimens.headerBack,
                    child: AppHeader.back(
                      title: 'Amira Khalifa',
                      subtitle: '+20 100 234 5678',
                      onBack: () {},
                      actions: <Widget>[
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.call, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The header sizes itself now, so the gallery lets it —
                  // pinning a height here would show a size the app never uses.
                  SizedBox(
                    height: const AppHeader.search(
                      title: '',
                      searchHint: '',
                    ).preferredSize.height,
                    child: AppHeader.search(
                      title: 'Inbox',
                      searchHint: 'Search conversations',
                      trailing: const InitialsAvatar(name: 'Hassan Ali', size: 34),
                    ),
                  ),
                ]),

                _group('Section labels', <Widget>[
                  const SectionLabel('Conversations'),
                  SectionHeader(
                    title: 'My queue',
                    actionLabel: 'See all',
                    onAction: () {},
                  ),
                ]),

                _group('Status pills', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const <Widget>[
                        StatusPill(label: 'Open', tone: StatusTone.success),
                        StatusPill(label: 'Pending', tone: StatusTone.warning),
                        StatusPill(label: 'Scheduled', tone: StatusTone.info),
                        StatusPill(label: 'Failed', tone: StatusTone.danger),
                        StatusPill(label: 'Solved', tone: StatusTone.neutral),
                      ],
                    ),
                  ),
                ]),

                _group('Filter chips', <Widget>[
                  FilterChipBar(
                    options: const <FilterOption>[
                      FilterOption(id: 'all', label: 'All', count: 24),
                      FilterOption(id: 'new', label: 'New', count: 3),
                      FilterOption(id: 'unassigned', label: 'Unassigned', count: 5),
                    ],
                    selectedId: _filter,
                    onSelected: (String id) => setState(() => _filter = id),
                  ),
                ]),

                _group('List rows', <Widget>[
                  AppListTile(
                    title: 'Amira Khalifa',
                    subtitle: 'Perfect, thank you so much!',
                    leading: const InitialsAvatar(name: 'Amira Khalifa'),
                    trailing: const StatusPill(
                      label: '3',
                      tone: StatusTone.success,
                      showDot: false,
                    ),
                    onTap: () {},
                  ),
                  const Divider(),
                  AppListTile(
                    title: 'Quick replies',
                    subtitle: '12 saved',
                    leading: const IconTile(
                      icon: Icons.bolt_outlined,
                      color: AppColor.info,
                    ),
                    onTap: () {},
                  ),
                ]),

                _group('Action sheet rows', <Widget>[
                  ActionSheetRow(
                    label: 'Internal Note',
                    icon: Icons.sticky_note_2_outlined,
                    tint: AppColor.warning,
                    onTap: () {},
                  ),
                  ActionSheetRow(
                    label: 'Transfer conversation',
                    icon: Icons.swap_horiz,
                    tint: AppColor.success,
                    onTap: () {},
                  ),
                  ActionSheetRow(
                    label: 'Clear Chat History',
                    icon: Icons.delete_outline,
                    destructive: true,
                    onTap: () {},
                  ),
                ]),

                _group('Stat cards', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: Column(
                      children: const <Widget>[
                        StatCardRow(
                          cards: <StatCard>[
                            StatCard(
                              value: '18',
                              label: 'Open',
                              icon: Icons.forum_outlined,
                            ),
                            StatCard(
                              value: '42',
                              label: 'Resolved today',
                              icon: Icons.check_circle_outline,
                              iconColor: AppColor.success,
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        StatCardRow(
                          cards: <StatCard>[
                            StatCard(
                              value: '2m 14s',
                              label: 'Avg. response',
                              icon: Icons.timer_outlined,
                              iconColor: AppColor.info,
                            ),
                            StatCard(
                              value: '94%',
                              label: 'CSAT',
                              icon: Icons.star_outline,
                              iconColor: AppColor.warning,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),

                _group('Weekly chart', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: const ChartCard(
                      title: 'Conversations this week',
                      child: WeeklyBarChart(
                        data: <BarDatum>[
                          BarDatum(label: 'M', value: 12),
                          BarDatum(label: 'T', value: 18),
                          BarDatum(label: 'W', value: 9),
                          BarDatum(label: 'T', value: 22),
                          BarDatum(label: 'F', value: 27),
                          BarDatum(label: 'S', value: 14),
                          BarDatum(label: 'S', value: 6),
                        ],
                      ),
                    ),
                  ),
                ]),

                _group('Banners', <Widget>[
                  const AppBanner(
                    message: 'Service window closes in 2h — reply to keep it open.',
                    tone: BannerTone.warning,
                  ),
                  const SizedBox(height: 8),
                  const AppBanner(
                    message: 'No one is replying now — reply first to lock this chat.',
                    tone: BannerTone.neutral,
                  ),
                  const SizedBox(height: 8),
                  const AppBanner(
                    message: 'Private to your team — never shared with customers.',
                    tone: BannerTone.brand,
                  ),
                ]),

                _group('Chat bubbles', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: Column(
                      children: const <Widget>[
                        ChatDayDivider(label: 'Today'),
                        MessageBubble(
                          text: "Hi! I'd like to know about my order status.",
                          timeLabel: '10:20',
                          isOutgoing: false,
                        ),
                        MessageBubble(
                          text: 'Hello Amira! Let me check that for you.',
                          timeLabel: '10:24',
                          isOutgoing: true,
                          status: MessageStatus.read,
                        ),
                        MessageBubble(
                          text: 'Your order #10432 has shipped. Arriving tomorrow 10am–2pm.',
                          timeLabel: '10:25',
                          isOutgoing: true,
                          status: MessageStatus.delivered,
                        ),
                        MessageBubble(
                          text: 'Could not deliver.',
                          timeLabel: '10:26',
                          isOutgoing: true,
                          status: MessageStatus.failed,
                        ),
                      ],
                    ),
                  ),
                ]),

                _group('Composer', <Widget>[
                  QuickReplyChips(
                    replies: const <String>['Thanks!', 'Anything else?', 'Share tracking'],
                    onSelected: (_) {},
                  ),
                  MessageComposer(hintText: 'Message', onSend: (_) {}, onAttach: () {}),
                ]),

                _group('Internal notes', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: Column(
                      children: <Widget>[
                        NoteCard(
                          author: 'Sara Mahmoud',
                          timeLabel: 'Today 6:41 PM',
                          body:
                              'Prefers delivery after 6 PM. Confirmed the new address in Maadi over a call today.',
                          onEdit: () {},
                          onDelete: () {},
                        ),
                        const SizedBox(height: 10),
                        NoteCard(
                          author: 'Hassan Ali',
                          timeLabel: 'Yesterday',
                          edited: true,
                          body:
                              'VIP customer — 9 orders this quarter. Approved a 10% loyalty discount on her next purchase.',
                          onEdit: () {},
                          onDelete: () {},
                        ),
                      ],
                    ),
                  ),
                ]),

                _group('Empty and error states', <Widget>[
                  SizedBox(
                    height: 190,
                    child: EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No conversations yet',
                      message: 'New messages from customers will appear here.',
                      action: FilledButton(
                        onPressed: () {},
                        child: const Text('Start a conversation'),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 170,
                    child: FailureMessage(
                      message: 'No connection. Check your network and try again.',
                      onRetry: () {},
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppDimens.gutter,
            top: 26,
            bottom: 10,
          ),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColor.inkFaint,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
