import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';
import '../domain/messenger_profile.dart';

/// Instagram's Messenger profile — the persistent menu and the ice breakers.
///
/// Workspace-level and admin-gated: every route here answers 403 to a
/// non-admin. The server returns that rather than aborting precisely so a
/// client can hide the screen, which is what [InstagramSettingsScreen] does.
///
/// There is no draft state. A save writes straight through to the live Meta
/// profile and every Instagram customer sees the result on their next message.
abstract interface class MessengerProfileRepository {
  Future<MessengerProfile> profile();

  /// Replaces the persistent menu wholesale.
  Future<void> saveMenu(List<LocaleBlock<MenuAction>> menu);

  /// Removes the persistent menu entirely.
  Future<void> clearMenu();

  Future<void> saveIceBreakers(List<LocaleBlock<IceBreaker>> breakers);

  Future<void> clearIceBreakers();
}

class MessengerProfileRepositoryImpl implements MessengerProfileRepository {
  MessengerProfileRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<MessengerProfile> profile() async {
    final dynamic body = await _api.get('/instagram/profile');

    // Both keys are read off the same response rather than through
    // `envelopeRecord`: the engine returns them as siblings of `success`, not
    // nested under a domain key.
    return MessengerProfile(
      menu: envelopeRows(body, 'persistent_menu')
          .map((Map<String, dynamic> j) =>
              LocaleBlock.fromJson<MenuAction>(j, MenuAction.fromJson))
          .toList(growable: false),
      iceBreakers: envelopeRows(body, 'ice_breakers')
          .map((Map<String, dynamic> j) =>
              LocaleBlock.fromJson<IceBreaker>(j, IceBreaker.fromJson))
          .toList(growable: false),
    );
  }

  @override
  Future<void> saveMenu(List<LocaleBlock<MenuAction>> menu) => _api.put(
        '/instagram/persistent-menu',
        body: <String, dynamic>{
          'persistent_menu': menu
              .map((LocaleBlock<MenuAction> b) =>
                  b.toJson((MenuAction a) => a.toJson()))
              .toList(growable: false),
        },
      );

  @override
  Future<void> clearMenu() => _api.delete('/instagram/persistent-menu');

  @override
  Future<void> saveIceBreakers(List<LocaleBlock<IceBreaker>> breakers) =>
      _api.put(
        '/instagram/ice-breakers',
        body: <String, dynamic>{
          'ice_breakers': breakers
              .map((LocaleBlock<IceBreaker> b) =>
                  b.toJson((IceBreaker a) => a.toJson()))
              .toList(growable: false),
        },
      );

  @override
  Future<void> clearIceBreakers() => _api.delete('/instagram/ice-breakers');
}

/// Rebuilds the full list to send, replacing one locale and preserving the rest.
///
/// The save endpoints take the whole profile and replace it, so sending only
/// the block this screen edits would **delete every other locale** the
/// workspace has configured. Nothing in either the API or the UI would report
/// that — the request succeeds and the other locales are simply gone from Meta.
///
/// The screen edits [kDefaultLocale] only, so every other block is carried
/// through untouched, in its original order and position.
List<LocaleBlock<T>> replaceLocale<T>(
  List<LocaleBlock<T>> existing,
  String locale,
  List<T> actions,
) {
  final List<LocaleBlock<T>> out = <LocaleBlock<T>>[];
  bool replaced = false;

  for (final LocaleBlock<T> block in existing) {
    if (block.locale == locale) {
      // An empty edited block is dropped rather than sent: the server requires
      // `call_to_actions` to have at least one row, so an empty one fails the
      // whole request and takes the other locales down with it. Clearing the
      // last locale is what the delete endpoint is for.
      if (actions.isNotEmpty) {
        out.add(LocaleBlock<T>(locale: locale, actions: actions));
      }
      replaced = true;
    } else {
      out.add(block);
    }
  }

  if (!replaced && actions.isNotEmpty) {
    out.add(LocaleBlock<T>(locale: locale, actions: actions));
  }
  return out;
}

final messengerProfileRepositoryProvider = Provider<MessengerProfileRepository>(
  (Ref ref) => MessengerProfileRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Not autoDispose: the screen refetches after every save so the form always
/// reflects what Meta is actually serving, and a dispose between the save and
/// the refetch would show a spinner over a form the user just submitted.
final messengerProfileProvider = FutureProvider<MessengerProfile>(
  (Ref ref) => ref.watch(messengerProfileRepositoryProvider).profile(),
);
