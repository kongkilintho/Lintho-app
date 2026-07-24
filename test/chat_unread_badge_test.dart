// ============================================================
// chat_unread_badge_test.dart — LinTho App
//
// Regression test for FOLLOWUP-E: the chat "unread" badge was permanently
// stuck at 0 — neither side of the app ever incremented a counter
// (_markAsRead() only ever reset it to 0), and the list screen read a
// Firestore field that nothing wrote to in the first place (unread was
// tracked, if at all, in Realtime Database via a different key shape).
//
// ໝາຍເຫດ: widget-level stream behavior (StreamBuilder rendering) ບໍ່ມີ
// widget test harness ຢູ່ໃນ repo ນີ້ — ໃຊ້ source-text regression guard
// ຢືນຢັນວ່າ: (1) _sendMessage() ຂຽນ increment ໃສ່ RTDB, (2) ChatListScreen
// ບໍ່ອ່ານ unread_ ຈາກ Firestore map ອີກຕໍ່ໄປ, ອ່ານຈາກ RTDB ແທນ.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  final source = _read('lib/chat_screen.dart');

  group('FOLLOWUP-E: chat unread badge is actually incremented and read',
      () {
    test('_sendMessage() increments unread_<receiverId> in Realtime '
        'Database on every send', () {
      final start = source.indexOf('Future<void> _sendMessage()');
      final end = source.indexOf('} catch (e) {', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('ServerValue.increment(1)'),
          reason: 'previously neither side of the app ever incremented an '
              'unread counter at all — only _markAsRead() reset it to 0');
      expect(block, contains("unread_\${widget.receiverId}"));
    });

    test('the unread increment is best-effort (its own try/catch) so a '
        'failure here does not roll back a message that already sent', () {
      final sendStart = source.indexOf('Future<void> _sendMessage()');
      final incrementIdx = source.indexOf('ServerValue.increment(1)', sendStart);
      expect(incrementIdx, greaterThan(-1));
      final tryIdx = source.lastIndexOf('try {', incrementIdx);
      final catchIdx = source.indexOf('} catch (e) {', incrementIdx);
      expect(tryIdx, greaterThan(-1));
      expect(catchIdx, greaterThan(incrementIdx));
      final scoped = source.substring(tryIdx, catchIdx + 150);
      expect(scoped, contains('unread increment failed'));
    });

    test('ChatListScreen no longer reads unread_ from the Firestore chat '
        'document map', () {
      final start = source.indexOf('class ChatListScreen');
      final end = source.indexOf('class _ChatListTile');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, isNot(contains("chat['unread_")),
          reason: 'this Firestore field is never written by any code path '
              '— reading it always yields 0');
    });

    test('_ChatListTile reads the unread count from Realtime Database', () {
      final start = source.indexOf('class _ChatListTile');
      final end = source.indexOf('class ChatScreen');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('FirebaseDatabase.instance'));
      expect(block, contains("meta/unread_\$myUid"));
      expect(block, contains('StreamBuilder<DatabaseEvent>'));
    });
  });
}
