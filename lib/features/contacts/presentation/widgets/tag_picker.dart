/// Tag picking, shared by Contact detail and Conversation info.
///
/// Both screens render the same customer record and both write through the
/// same replace-not-append field, so the safety rules that make that write
/// survivable live here once rather than in each screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// Pick this contact's tags from the workspace's vocabulary, or type a new one.
///
/// Free text alone was the wrong affordance. `/contacts/meta` carries the
/// workspace's label list and the add flow ignored it, so every tag was typed
/// blind — which makes `vip`, `VIP` and `Vip` three separate labels and erodes
/// the vocabulary one typo at a time. Existing labels are offered first and a
/// new one is still possible, because a picker with no escape hatch cannot
/// name something that has never been named.
///
/// Returns the **full** tag list, not a delta: `contact_tags` is
/// replace-not-append, so the caller writes what comes back verbatim. Returns
/// null when dismissed.
class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.applied, required this.vocabulary});

  final List<String> applied;
  final List<String> vocabulary;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late final Set<String> _selected = <String>{...widget.applied};
  final TextEditingController _input = TextEditingController();

  /// Everything offerable: the workspace's labels plus anything already on
  /// this contact that is not in that list. A tag applied here but absent from
  /// the vocabulary would otherwise be invisible in the picker and silently
  /// dropped on save.
  late final List<String> _options = <String>[
    ...widget.vocabulary,
    ...widget.applied.where((String a) => !widget.vocabulary
        .any((String v) => v.toLowerCase() == a.toLowerCase())),
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool _isOn(String tag) =>
      _selected.any((String s) => s.toLowerCase() == tag.toLowerCase());

  void _toggle(String tag) => setState(() {
        if (_isOn(tag)) {
          _selected.removeWhere((String s) => s.toLowerCase() == tag.toLowerCase());
        } else {
          _selected.add(tag);
        }
      });

  void _addTyped() {
    final String tag = _input.text.trim().replaceAll(',', '');
    if (tag.isEmpty || _isOn(tag)) {
      _input.clear();
      return;
    }
    setState(() {
      _selected.add(tag);
      _options.add(tag);
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        // Lifts the sheet clear of the keyboard while the new-tag field has
        // focus; without it the input sits under the keys.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.cdTagsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.toList()),
                    child: Text(l10n.actionSave),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_options.isEmpty)
                      Text(
                        l10n.cdNoTagsYet,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final String tag in _options)
                            FilterChip(
                              label: Text(tag),
                              selected: _isOn(tag),
                              onSelected: (_) => _toggle(tag),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _input,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.cdNewTag,
                        hintText: l10n.acTagsPlaceholder,
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addTyped,
                        ),
                      ),
                      onSubmitted: (_) => _addTyped(),
                    ),
                    const SizedBox(height: AppDimens.gutter),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+ Add" chip in the tags row. Adds a tag in place.
///
/// It used to open the edit form, which was safe but made a one-word change a
/// five-step trip. Adding here is only safe because the write carries
/// everything the endpoint would otherwise destroy:
///
///  * `contact_tags` is replace-not-append, so the **whole** list goes, not
///    the new tag.
///  * `contact_city` is rewritten from the request on every update and is not
///    seeded from the current row, so omitting it stores null.
///  * `contact_groups` removals are `array_diff(existing, sent)`, so omitting
///    it unfiles the contact from every group.
///
/// Groups also have to be translated: the contact's own payload lists them as
/// `{uid, title}` with no numeric id, while `contact_groups` matches on `_id`.
/// `/contacts/meta` is the only place carrying both, so it is awaited before
/// writing — and if a group cannot be resolved the write is **abandoned**
/// rather than sent without it, because sending a partial list is what removes
/// the rest.
class AddTagChip extends ConsumerStatefulWidget {
  const AddTagChip({required this.contact, super.key});

  final Contact contact;

  @override
  ConsumerState<AddTagChip> createState() => _AddTagChipState();
}

class _AddTagChipState extends ConsumerState<AddTagChip> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Metadata first: the picker needs the workspace's label vocabulary, and
    // the write needs the group ids. One await covers both.
    setState(() => _busy = true);
    late final ContactMeta meta;
    try {
      meta = await ref.read(contactMetaProvider.future);
    } on Failure catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final List<String>? chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => _TagPickerSheet(
        applied: widget.contact.labels,
        vocabulary:
            meta.labels.map((NamedRef l) => l.name).where((String s) => s.isNotEmpty).toList(),
      ),
    );

    if (chosen == null || !mounted) return;

    // Nothing moved — skip the round trip entirely rather than writing an
    // identical list back.
    final Set<String> before =
        widget.contact.labels.map((String s) => s.toLowerCase()).toSet();
    final Set<String> after = chosen.map((String s) => s.toLowerCase()).toSet();
    if (before.length == after.length && before.containsAll(after)) return;

    setState(() => _busy = true);
    try {
      final List<String> groupIds = <String>[];
      for (final NamedRef g in widget.contact.groups) {
        final GroupRef? match = meta.groups
            .cast<GroupRef?>()
            .firstWhere((GroupRef? m) => m?.uid == g.id || m?.id == g.id,
                orElse: () => null);
        if (match == null) {
          // Writing now would drop this group. Say so and change nothing.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.cdAddTagUnsafe)),
            );
          }
          return;
        }
        groupIds.add(match.id);
      }

      await ref.read(contactRepositoryProvider).update(
            widget.contact.uid,
            tags: chosen.join(','),
            city: widget.contact.city ?? '',
            groupIds: groupIds,
            customFields: <String, String>{
              for (final ContactCustomValue f in widget.contact.customFields)
                f.fieldUid: f.value,
            },
          );

      ref.invalidate(contactDetailProvider(widget.contact.uid));
      ref.invalidate(contactListProvider);
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: _busy
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColor.brandDeep,
              ),
            )
          : const Icon(Icons.add, size: 15, color: AppColor.brandDeep),
      label: Text(AppLocalizations.of(context).cdAddTag),
      labelStyle: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: AppColor.brandDeep),
      backgroundColor: AppColor.brandWash,
      side: const BorderSide(color: AppColor.brandWash),
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _add,
    );
  }
}
