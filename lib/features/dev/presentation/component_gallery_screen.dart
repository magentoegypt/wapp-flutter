import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/error/failure.dart';
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
import '../../../l10n/app_localizations.dart';
import '../../automation/data/bot_flow_repository.dart';
import '../../automation/data/bot_reply_repository.dart';
import '../../automation/presentation/screens/bot_replies_screen.dart'
    show kindLabel, triggerLabel;
import '../../inbox/data/conversation_repository.dart';
import '../../inbox/domain/conversation.dart';
import '../../inbox/domain/reply_lock.dart';
import '../../inbox/presentation/widgets/message_kind_style.dart';
import '../../inbox/presentation/widgets/message_payload_view.dart';
import '../../inbox/presentation/widgets/reply_lock_strip.dart';
import '../../teams/data/team_repository.dart';

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

                // Every payload family, including the four with no live rows in
                // any thread on this workspace: location, contact card, CTA URL
                // and multi-product. Fixtures go through the real mapper rather
                // than being hand-built model objects, so this exercises the
                // parsers too — a gallery of hand-made objects would keep
                // rendering happily after the wire shape moved under it.
                _group('Message payloads', <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.gutter,
                    ),
                    child: Column(children: _payloadSamples()),
                  ),
                ]),

                // All four reply-lock states. Three of them need a second agent
                // holding the lock on the same conversation, which cannot be
                // arranged from one device — and the "someone else is replying"
                // case is precisely the one that used to render nothing at all.
                _group('Reply lock', <Widget>[
                  const ReplyLockBanner(lock: ReplyLock.free),
                  const SizedBox(height: 8),
                  const ReplyLockBanner(
                    lock: ReplyLock(locked: true, lockedByCurrentUser: true),
                  ),
                  const SizedBox(height: 8),
                  const ReplyLockBanner(
                    lock: ReplyLock(locked: true, lockedByName: 'Sara Mahmoud'),
                  ),
                  const SizedBox(height: 8),
                  ReplyLockBanner(
                    lock: const ReplyLock(
                      locked: true,
                      lockedByName: 'Sara Mahmoud',
                      canTakeover: true,
                    ),
                    onTakeover: () {},
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

                // No fixed heights. Both of these size to their content, and
                // the 190/170 boxes they used to sit in clipped the button off
                // the bottom as soon as the device's text scale nudged the
                // column past them — the gallery reported an overflow that the
                // widgets themselves do not have.
                // Teams and bot replies have no frame and no safe live path —
                // every write is destructive against production. Same treatment
                // as the payloads above: wire-shaped JSON through the real
                // `fromJson`, so a change to the parser shows up here.
                _group('Teams', <Widget>[
                  Column(children: _teamRows()),
                ]),

                _group('Bot replies', <Widget>[
                  Column(children: _botReplyRows()),
                ]),

                _group('Bot flows', <Widget>[
                  Column(children: _botFlowRows()),
                ]),

                _group('Empty and error states', <Widget>[
                  EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No conversations yet',
                    message: 'New messages from customers will appear here.',
                    action: FilledButton(
                      onPressed: () {},
                      child: const Text('Start a conversation'),
                    ),
                  ),
                  FailureMessage(
                    message: 'No connection. Check your network and try again.',
                    onRetry: () {},
                  ),
                  // Both 403s, side by side. They are the same status code and
                  // used to be the same red box; the point of this pair is that
                  // one offers a retry and the other deliberately does not.
                  const FailureMessage(
                    message: 'You do not have access to this.',
                  ),
                  const PlanLimitMessage(
                    failure: PlanLimitFailure(
                      'Bot replies are not included in your current '
                          'subscription plan.',
                      'bot_reply',
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

  /// One bubble per payload family, built from wire-shaped JSON.
  List<Widget> _payloadSamples() {
    final List<Map<String, dynamic>> fixtures = <Map<String, dynamic>>[
      <String, dynamic>{
        'uid': 'g-location',
        'type': 'location',
        'body': '',
        'isIncoming': true,
        'interactive': <String, dynamic>{
          'location': <String, dynamic>{
            'name': 'Kingdom Centre',
            'address': 'Olaya, Riyadh 12214',
            'lat': 24.7118,
            'lng': 46.6745,
          },
        },
      },
      <String, dynamic>{
        'uid': 'g-location-bare',
        'type': 'location',
        'body': '',
        'isIncoming': true,
        // No name and no address, so the coordinates are all there is — the
        // only case in which they are shown at all.
        'interactive': <String, dynamic>{
          'location': <String, dynamic>{'lat': 30.0444, 'lng': 31.2357},
        },
      },
      <String, dynamic>{
        'uid': 'g-contacts',
        'type': 'contacts',
        'body': '',
        'isIncoming': true,
        'interactive': <String, dynamic>{
          'contacts': <dynamic>[
            <String, dynamic>{
              // Meta's nested shape.
              'name': <String, dynamic>{'formatted_name': 'Amira Hassan'},
              'phones': <dynamic>[
                <String, dynamic>{'phone': '+20 100 000 0000'},
                <String, dynamic>{'phone': '+20 122 222 2222'},
              ],
              'emails': <dynamic>[
                <String, dynamic>{'email': 'amira@example.com'},
              ],
            },
            // The flattened shape, which the API has also been seen to send.
            <String, dynamic>{'name': 'Omar Khaled'},
          ],
        },
      },
      <String, dynamic>{
        'uid': 'g-cta',
        'type': 'cta_url',
        'body': 'Track your delivery here.',
        'isIncoming': false,
        'interactive': <String, dynamic>{
          'ctaUrl': <String, dynamic>{
            'url': 'https://example.com/track/10432',
            'displayText': 'Track order',
          },
        },
      },
      <String, dynamic>{
        'uid': 'g-productlist',
        'type': 'product_list',
        'body': 'This week’s picks',
        'isIncoming': false,
        'interactive': <String, dynamic>{
          'products': <dynamic>[
            <String, dynamic>{'retailerId': 'SOFA-118', 'section': 'Living room'},
            <String, dynamic>{'retailerId': 'CHAIR-22', 'section': 'Living room'},
            <String, dynamic>{'retailerId': 'LAMP-07', 'section': 'Lighting'},
          ],
        },
      },
      <String, dynamic>{
        'uid': 'g-order',
        'type': 'order',
        'body': '',
        'isIncoming': true,
        'order': <String, dynamic>{
          'itemCount': 2,
          'currency': 'SAR',
          'total': 31500,
          'items': <dynamic>[
            <String, dynamic>{
              'name': 'Louis XVI Marquetry Coffee Table',
              'quantity': 1,
              'lineTotal': 31000,
              'currency': 'SAR',
            },
            <String, dynamic>{
              'name': 'Brass Mounts',
              'quantity': 2,
              'lineTotal': 500,
              'currency': 'SAR',
            },
          ],
        },
      },
      <String, dynamic>{
        'uid': 'g-order-mixed',
        'type': 'order',
        'body': '',
        'isIncoming': true,
        // Total withheld because the cart mixes currencies. Summing it would
        // add SAR to USD and print a confident wrong number.
        'order': <String, dynamic>{
          'itemCount': 2,
          'total': null,
          'items': <dynamic>[
            <String, dynamic>{
              'name': 'Abaya',
              'quantity': 1,
              'lineTotal': 900,
              'currency': 'SAR',
            },
            <String, dynamic>{
              'name': 'Shipping',
              'quantity': 1,
              'lineTotal': 25,
              'currency': 'USD',
            },
          ],
        },
      },
      <String, dynamic>{
        'uid': 'g-unsupported',
        'type': 'unsupported',
        'body': '',
        'isIncoming': true,
        'unsupportedReason':
            'Message type is not supported on WhatsApp Business API.',
      },
    ];

    return <Widget>[
      for (final Map<String, dynamic> f in fixtures)
        Builder(
          builder: (BuildContext c) {
            final ChatMessage m = chatMessageFromJson(f);
            final MessageKindStyle style =
                MessageKindStyle.of(m.kind, AppLocalizations.of(c));
            final Widget? content = messagePayloadView(c, m, 'en');
            final bool labelRedundant = content != null &&
                const <MessageKind>{
                  MessageKind.order,
                  MessageKind.template,
                  MessageKind.interactiveButtons,
                  MessageKind.interactiveList,
                }.contains(m.kind);

            return MessageBubble(
              kindIcon: labelRedundant ? null : style.icon,
              kindLabel: labelRedundant ? null : style.label,
              text: m.body,
              content: content,
              timeLabel: '10:30',
              isOutgoing: !m.isIncoming,
            );
          },
        ),
    ];
  }

  /// Team rows, covering the two shapes the API answers with.
  ///
  /// The list sends `memberCount` and no roster; the detail sends a roster and
  /// no count. A row that read only one of them would show "0 members" on half
  /// the screens in the app.
  List<Widget> _teamRows() {
    final List<WorkTeam> teams = <WorkTeam>[
      WorkTeam.fromJson(<String, dynamic>{
        'uid': 'g-t1',
        'title': 'Support',
        'memberCount': 6,
      }),
      WorkTeam.fromJson(<String, dynamic>{
        'uid': 'g-t2',
        // The other spelling — both occur.
        'name': 'Sales',
        'members': <dynamic>[
          <String, dynamic>{'uid': 'u1', 'name': 'Sara Mahmoud', 'role': 'Agent'},
          <String, dynamic>{'uid': 'u2', 'name': 'Omar Khaled'},
          // Nameless, and dropped — nothing renders for it.
          <String, dynamic>{'uid': 'u3'},
        ],
      }),
      WorkTeam.fromJson(<String, dynamic>{'uid': 'g-t3', 'title': 'Escalations'}),
    ];

    return <Widget>[
      for (final WorkTeam t in teams)
        Builder(
          builder: (BuildContext c) => AppListTile(
            title: t.title,
            subtitle: AppLocalizations.of(c).tmMembers(t.displayCount),
            leading: const IconTile(
              icon: Icons.groups_outlined,
              color: AppColor.success,
            ),
            onTap: () {},
          ),
        ),
    ];
  }

  /// One row per trigger family, plus the two that cannot be edited here.
  List<Widget> _botReplyRows() {
    // The live read shape: `triggerType` for the enum, `trigger` for the
    // keyword, `inFlow` as a boolean, and **no message-type field** — the kind
    // is inferred from `data.interaction_message`.
    final List<BotReply> replies = <BotReply>[
      BotReply.fromJson(<String, dynamic>{
        'uid': 'g-b1',
        'name': 'Greeting',
        'triggerType': 'welcome',
        'replyText': 'Hi! How can we help?',
      }),
      BotReply.fromJson(<String, dynamic>{
        'uid': 'g-b2',
        'name': 'Pricing',
        'triggerType': 'contains',
        'trigger': 'price',
        'replyText': 'Our price list is attached.',
        // The empty strings the API really sends on a plain reply. If these
        // counted as a payload, every simple reply would lock itself.
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{
            'body_text': 'Our price list is attached.',
            'footer_text': '',
            'header_text': '',
            'media_link': '',
            'cta_url': null,
            'list_data': null,
          },
        },
      }),
      BotReply.fromJson(<String, dynamic>{
        'uid': 'g-b3',
        'name': 'Order status',
        'triggerType': 'starts_with',
        'trigger': 'order',
        'replyText': 'Send your order number and we will check.',
        // Switched off. Identical to a live reply everywhere else, and it
        // answers nobody.
        'active': false,
      }),
      // Rich replies. These carry a payload this form has no fields for, so
      // they open read-only — the row says so before it is tapped, which is the
      // difference between a locked row and one that silently flattens.
      BotReply.fromJson(<String, dynamic>{
        'uid': 'g-b4',
        'name': 'Main menu',
        'triggerType': 'is',
        'trigger': 'menu',
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{
            'interactive_type': 'button',
            'buttons': <String, dynamic>{'1': 'Track', '2': 'Talk to an agent'},
            'header_type': 'image',
            'media_link': 'https://example.com/menu.jpg',
          },
        },
      }),
      BotReply.fromJson(<String, dynamic>{
        'uid': 'g-b5',
        'name': 'Catalogue',
        'triggerType': 'contains_word',
        'trigger': 'catalogue',
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{
            'header_type': 'document',
            'media_link': 'https://example.com/catalogue.pdf',
          },
        },
      }),
    ];

    return <Widget>[
      for (final BotReply r in replies)
        Builder(
          builder: (BuildContext c) {
            final AppLocalizations l10n = AppLocalizations.of(c);
            return AppListTile(
              title: r.name,
              subtitle: triggerLabel(l10n, r.trigger) +
                  (r.keyword == null ? '' : ' · ${r.keyword}'),
              subtitleMaxLines: 2,
              leading: const IconTile(
                icon: Icons.smart_toy_outlined,
                color: AppColor.info,
              ),
              showChevron: r.messageKind.isEditable,
              trailing: !r.active
                  ? StatusPill(
                      label: l10n.brInactive,
                      tone: StatusTone.neutral,
                    )
                  : (r.messageKind.isEditable
                      ? null
                      : StatusPill(
                          label: kindLabel(l10n, r.messageKind),
                          tone: StatusTone.info,
                          showDot: false,
                        )),
              onTap: () {},
            );
          },
        ),
    ];
  }

  /// Flow rows, including the state the pill exists for.
  ///
  /// A flow switched on with no steps triggers and then sends nothing. It is
  /// the only row here that looks healthy and answers nobody, so it gets its
  /// own amber pill rather than the green one — this is the case worth being
  /// able to see without a live workspace that happens to contain one.
  List<Widget> _botFlowRows() {
    final List<BotFlow> flows = <BotFlow>[
      BotFlow.fromJson(<String, dynamic>{
        'uid': 'g-f1',
        'title': 'Onboarding',
        'triggerType': 'welcome',
        // tinyint, not a bool — the shape that used to read as stopped.
        'active': 1,
        'stepCount': 4,
      }),
      // Running, and known to have nothing to send. The only row that earns the
      // amber pill.
      BotFlow.fromJson(<String, dynamic>{
        'uid': 'g-f2',
        'title': 'Order tracking',
        'triggerType': 'starts_with',
        'startTrigger': 'track',
        'active': 1,
        'stepCount': 0,
      }),
      BotFlow.fromJson(<String, dynamic>{
        'uid': 'g-f3',
        'name': 'Returns',
        'triggerType': 'contains_word',
        'startTrigger': 'refund',
        'active': 0,
        'botReplies': <dynamic>[<String, dynamic>{}, <String, dynamic>{}],
      }),
      // The shape the live list actually sends: no step count at all. Nothing
      // may be claimed about its steps — this row is here so that stays true.
      BotFlow.fromJson(<String, dynamic>{
        'uid': 'g-f4',
        'title': 'Ads Welcome Flow',
        'triggerType': 'ads_welcome',
        'startTrigger': 'Test Ad',
        'active': true,
      }),
    ];

    return <Widget>[
      for (final BotFlow f in flows)
        Builder(
          builder: (BuildContext c) {
            final AppLocalizations l10n = AppLocalizations.of(c);
            final int? steps = f.stepCount;
            return AppListTile(
              title: f.title,
              subtitle: <String>[
                triggerLabel(l10n, f.startTrigger),
                if (f.keyword != null) f.keyword!,
                if (steps != null) l10n.bfSteps(steps),
              ].join(' · '),
              subtitleMaxLines: 2,
              leading: const IconTile(
                icon: Icons.account_tree_outlined,
                color: AppColor.brandDeep,
              ),
              trailing: StatusPill(
                label: f.active
                    ? (f.isKnownEmpty ? l10n.bfActiveEmpty : l10n.bfActive)
                    : l10n.bfInactive,
                tone: f.active
                    ? (f.isKnownEmpty
                        ? StatusTone.warning
                        : StatusTone.success)
                    : StatusTone.neutral,
              ),
              onTap: () {},
            );
          },
        ),
    ];
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
