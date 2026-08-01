import 'package:clickalize/features/inbox/domain/reply_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reply lock.
///
/// The whole point of this strip is to stop two agents answering the same
/// customer at once, and every way it can be wrong is silent: it shows the
/// wrong person, or nobody, or offers a button the server will refuse. Nothing
/// throws in any of those cases.
Map<String, dynamic> _locked({
  bool mine = false,
  bool canTakeover = false,
  String? name = 'Sara Mahmoud',
  String? until,
}) =>
    <String, dynamic>{
      'locked': true,
      'lockUid': 'lock-1',
      'lockedByUserId': 7,
      'lockedByName': name,
      'lockedByCurrentUser': mine,
      'lockedUntil': until,
      'canTakeover': canTakeover,
      'message': 'Sara Mahmoud is replying now.',
    };

void main() {
  group('parsing', () {
    test('gates on `locked`, not on the holder being named', () {
      // Every key is present and null when nothing holds the lock, so reading
      // lockedByName == null as "unlocked" happens to work and reading
      // lockedByName != null as "locked" does not. Gate on the flag.
      final ReplyLock free = ReplyLock.fromJson(<String, dynamic>{
        'locked': false,
        'lockUid': null,
        'lockedByName': null,
        'lockedByCurrentUser': false,
        'lockedUntil': null,
        'canTakeover': false,
      });

      expect(free.locked, isFalse);
      expect(free.heldByOther, isFalse);
      expect(free.canTakeover, isFalse);
    });

    test('a garbage or missing payload is free, not locked', () {
      // Failing open matters: failing closed would show "someone is replying"
      // over a conversation nobody is touching, and agents would stop trusting
      // the strip entirely.
      expect(ReplyLock.fromJson(null).locked, isFalse);
      expect(ReplyLock.fromJson('nope').locked, isFalse);
      expect(ReplyLock.fromJson(<String, dynamic>{}).locked, isFalse);
    });

    test('an empty holder name reads as null rather than blank', () {
      final ReplyLock l = ReplyLock.fromJson(_locked(name: '   '));
      expect(l.locked, isTrue);
      expect(l.lockedByName, isNull, reason: '"  is replying now." is worse');
    });
  });

  group('who holds it', () {
    test('held by someone else is the state the strip exists for', () {
      final ReplyLock l = ReplyLock.fromJson(_locked(canTakeover: true));
      expect(l.heldByOther, isTrue);
      expect(l.lockedByName, 'Sara Mahmoud');
    });

    test('held by me is not held by another', () {
      final ReplyLock l = ReplyLock.fromJson(_locked(mine: true));
      expect(l.locked, isTrue);
      expect(l.heldByOther, isFalse);
    });

    test('canTakeover is read, never derived', () {
      // The server rule is admin OR one of three team-structure permissions,
      // and it already accounts for the lock being your own. A client that
      // re-derived it from a role string would offer a button the API refuses.
      expect(ReplyLock.fromJson(_locked(canTakeover: false)).canTakeover,
          isFalse);
      expect(
          ReplyLock.fromJson(_locked(mine: true, canTakeover: false))
              .canTakeover,
          isFalse);
    });
  });

  group('local expiry', () {
    final DateTime now = DateTime(2026, 8, 1, 12, 0);

    test('a lapsed lock reads as free without asking the server', () {
      // The hold is five minutes, so the common way this strip goes stale is
      // that it simply ran out while the chat sat open.
      final ReplyLock l = ReplyLock.fromJson(
        _locked(until: now.subtract(const Duration(minutes: 1)).toIso8601String()),
      );

      expect(l.locked, isTrue, reason: 'as the server sent it');
      expect(l.atNow(now).locked, isFalse, reason: 'but not any more');
    });

    test('a live lock survives', () {
      final ReplyLock l = ReplyLock.fromJson(
        _locked(until: now.add(const Duration(minutes: 3)).toIso8601String()),
      );
      expect(l.atNow(now).locked, isTrue);
      expect(l.atNow(now).lockedByName, 'Sara Mahmoud');
    });

    test('a lock with no deadline is left alone', () {
      // The engine can report "until released" with a null timestamp. Expiring
      // that immediately would hide a lock that is genuinely held.
      final ReplyLock l = ReplyLock.fromJson(_locked(until: null));
      expect(l.lockedUntil, isNull);
      expect(l.atNow(now).locked, isTrue);
    });

    test('free stays free', () {
      expect(ReplyLock.free.atNow(now).locked, isFalse);
    });
  });
}
