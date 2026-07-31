import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/conversation.dart';
import '../../domain/message_payload.dart';

/// Renders the structured half of a message — everything the body text is not.
///
/// Built for the types that actually occur on this install, per the handoff's
/// own advice: `sticker` and WhatsApp Flows are drawn in Figma with zero live
/// rows, and AUTHENTICATION templates never occur, so none of them get bespoke
/// treatment they would only bit-rot in.
///
/// Nothing here is interactive. These are records of what a customer was sent
/// or what they sent back — tapping a reply button in an agent's transcript
/// would either do nothing or, worse, send something.
Widget? messagePayloadView(
  BuildContext context,
  ChatMessage m,
  String locale,
) {
  switch (m.kind) {
    case MessageKind.order:
      final MessageOrder? o = m.order;
      return o == null ? null : _Cart(order: o, locale: locale);

    case MessageKind.image:
    case MessageKind.video:
    case MessageKind.audio:
    case MessageKind.document:
    case MessageKind.sticker:
      final MessageMedia? md = m.media;
      return md == null ? null : _Media(media: md, kind: m.kind);

    case MessageKind.interactiveButtons:
      final List<InteractiveButton> b =
          m.interactive?.buttons ?? const <InteractiveButton>[];
      return b.isEmpty
          ? null
          : _Chips(labels: b.map((InteractiveButton e) => e.title).toList());

    case MessageKind.interactiveList:
      final MessageInteractive? i = m.interactive;
      return i == null ? null : _ListPreview(interactive: i);

    case MessageKind.ctaUrl:
      final CtaUrl? c = m.interactive?.ctaUrl;
      return c == null
          ? null
          : _Chips(labels: <String>[c.displayText ?? c.url], icon: Icons.open_in_new);

    case MessageKind.location:
      final MessageLocation? l = m.interactive?.location;
      return l == null ? null : _Location(location: l);

    case MessageKind.contacts:
      final List<ContactCard> c = m.interactive?.contacts ?? const <ContactCard>[];
      return c.isEmpty ? null : _Contacts(cards: c);

    case MessageKind.catalog:
    case MessageKind.product:
    case MessageKind.productList:
      return _Products(interactive: m.interactive, kind: m.kind);

    case MessageKind.template:
      final MessageTemplate? t = m.template;
      return t == null ? null : _Template(template: t);

    case MessageKind.unsupported:
      final String? why = m.unsupportedReason;
      return why == null ? null : _Muted(text: why);

    case MessageKind.text:
    case MessageKind.locationRequest:
      return null;
  }
}

/// Inbound cart.
///
/// The reason this whole file exists: fifteen real customer orders on this
/// workspace, one of them SAR 31,500, rendered as empty bubbles because the
/// payload never reached the client.
class _Cart extends StatelessWidget {
  const _Cart({required this.order, required this.locale});

  final MessageOrder order;
  final String locale;

  String _money(double v, String? currency) => NumberFormat.currency(
        locale: locale,
        // The symbol is whatever Meta sent. Passing null lets intl guess from
        // the locale, which would label a SAR cart in EGP for an Arabic agent.
        name: currency ?? '',
        decimalDigits: 2,
      ).format(v);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final OrderItem it in order.items)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (it.quantity != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Text('${it.quantity}×', style: small),
                  ),
                Expanded(
                  child: Text(
                    it.name.isEmpty ? l10n.mtProduct : it.name,
                    style: small,
                  ),
                ),
                if (it.lineTotal != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      _money(it.lineTotal!, it.currency ?? order.currency),
                      style: small?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.mtOrderItems(order.count),
                style: small?.copyWith(color: AppColor.inkMuted),
              ),
            ),
            // A total is shown only when the server gave one. It withholds it
            // for a mixed-currency cart, and summing the lines ourselves would
            // add SAR to USD and print a confident wrong number.
            if (order.total != null)
              Text(
                _money(order.total!, order.currency),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              )
            else
              Text(
                l10n.mtOrderMixed,
                style: small?.copyWith(color: AppColor.warning),
              ),
          ],
        ),
      ],
    );
  }
}

/// Image, video, audio or document.
///
/// Images render inline; the rest get a file tile. Everything degrades to the
/// tile when there is no link, which is common — `mediaLink` is frequently an
/// empty string.
class _Media extends StatelessWidget {
  const _Media({required this.media, required this.kind});

  final MessageMedia media;
  final MessageKind kind;

  @override
  Widget build(BuildContext context) {
    final bool inlineImage =
        (kind == MessageKind.image || kind == MessageKind.sticker) &&
            media.link != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (inlineImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              media.link!,
              fit: BoxFit.cover,
              // A broken image must not take the bubble down with it. The
              // media endpoint is authenticated and Image.network sends no
              // token, so this fires routinely rather than exceptionally.
              errorBuilder: (_, __, ___) => _FileTile(media: media, kind: kind),
              loadingBuilder: (BuildContext c, Widget child, ImageChunkEvent? p) =>
                  p == null
                      ? child
                      : const SizedBox(
                          height: 90,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
            ),
          )
        else
          _FileTile(media: media, kind: kind),
        if (media.caption != null) ...<Widget>[
          const SizedBox(height: 5),
          Text(media.caption!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.media, required this.kind});

  final MessageMedia media;
  final MessageKind kind;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // fileName, never storedFileName — the latter is the on-disk name and
    // means nothing to an agent.
    final String name = media.fileName ?? l10n.mtDocument;
    final String? size = media.readableSize;

    return Container(
      padding: const EdgeInsetsDirectional.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_glyph, size: 22, color: AppColor.inkMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (size != null)
                  Text(
                    size,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColor.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _glyph => switch (kind) {
        MessageKind.audio => Icons.play_circle_outline,
        MessageKind.video => Icons.play_circle_outline,
        MessageKind.image => Icons.image_outlined,
        _ => Icons.insert_drive_file_outlined,
      };
}

/// Reply buttons and CTA links, drawn as the inert records they are.
class _Chips extends StatelessWidget {
  const _Chips({required this.labels, this.icon});

  final List<String> labels;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String label in labels)
          Container(
            margin: const EdgeInsetsDirectional.only(top: 4),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: AppColor.hairline),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: AppColor.info),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColor.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A list message, collapsed to its section titles and a row count.
///
/// The frame opens a bottom sheet on tap, but that is the customer's
/// interaction. In a transcript the agent needs to see what was offered, so
/// the rows are shown inline instead of hidden behind a control that would
/// imply the agent can choose one.
class _ListPreview extends StatelessWidget {
  const _ListPreview({required this.interactive});

  final MessageInteractive interactive;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final ListSection s in interactive.listSections) ...<Widget>[
          if (s.title != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4, bottom: 2),
              child: Text(
                s.title!,
                style: small?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColor.inkMuted,
                ),
              ),
            ),
          for (final ListRow r in s.rows)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 2),
              child: Text('•  ${r.title}', style: small),
            ),
        ],
        if (interactive.listButtonText != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 5),
            child: Text(
              '${interactive.listButtonText}  ·  '
              '${l10n.mtListRows(interactive.listRowCount)}',
              style: small?.copyWith(
                color: AppColor.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.location});

  final MessageLocation location;

  @override
  Widget build(BuildContext context) {
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;
    final List<String> lines = <String>[
      if (location.name != null) location.name!,
      if (location.address != null) location.address!,
      // Coordinates only when there is nothing readable — a lat/lng pair is a
      // poor substitute for a name, not an addition to it.
      if (location.name == null && location.address == null && location.hasPoint)
        '${location.latitude!.toStringAsFixed(5)}, '
            '${location.longitude!.toStringAsFixed(5)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String l in lines) Text(l, style: small),
      ],
    );
  }
}

class _Contacts extends StatelessWidget {
  const _Contacts({required this.cards});

  final List<ContactCard> cards;

  @override
  Widget build(BuildContext context) {
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final ContactCard c in cards) ...<Widget>[
          Text(
            c.name,
            style: small?.copyWith(fontWeight: FontWeight.w600),
          ),
          for (final String p in c.phones)
            Text(p, style: small?.copyWith(color: AppColor.inkMuted)),
          for (final String e in c.emails)
            Text(e, style: small?.copyWith(color: AppColor.inkMuted)),
        ],
      ],
    );
  }
}

/// Catalog, single product and multi-product.
class _Products extends StatelessWidget {
  const _Products({required this.interactive, required this.kind});

  final MessageInteractive? interactive;
  final MessageKind kind;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;
    final List<ProductRef> products =
        interactive?.products ?? const <ProductRef>[];

    if (kind == MessageKind.catalog && products.isEmpty) {
      // 18 of 29 live catalog messages carry no catalog id. The generic line
      // is the whole content in that case — assuming the id is there is how
      // this bubble ends up empty.
      return _Muted(text: l10n.mtCatalogGeneric);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final ProductRef p in products)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 2),
            child: Text(
              p.section == null ? p.retailerId : '${p.section} · ${p.retailerId}',
              style: small,
            ),
          ),
      ],
    );
  }
}

/// A template message, rendered from its components.
///
/// Only the components seen live are given treatment: BODY, BUTTONS,
/// HEADER:TEXT, FOOTER, HEADER:IMAGE, HEADER:PRODUCT and CAROUSEL. An unknown
/// component is skipped rather than guessed at.
class _Template extends StatelessWidget {
  const _Template({required this.template});

  final MessageTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle? small = Theme.of(context).textTheme.bodyMedium;
    final TemplateComponent? header = template.header;
    final TemplateComponent? body = template.body;
    final TemplateComponent? footer = template.footer;
    final List<TemplateButton> buttons = template.buttons;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 4),
            child: Text(
              // A TEXT header has its own text; an IMAGE or PRODUCT header has
              // none, so it is named rather than rendered as a blank line.
              header.text ??
                  (header.format == 'IMAGE'
                      ? l10n.mtImage
                      : header.format == 'PRODUCT'
                          ? l10n.mtProduct
                          : ''),
              style: small?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        if (body?.text != null)
          Text(body!.text!, style: Theme.of(context).textTheme.bodyLarge),
        if (footer?.text != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Text(
              footer!.text!,
              style: small?.copyWith(color: AppColor.inkFaint),
            ),
          ),
        if (buttons.isNotEmpty)
          _Chips(labels: buttons.map((TemplateButton b) => b.text).toList()),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppColor.inkMuted, fontStyle: FontStyle.italic),
    );
  }
}
