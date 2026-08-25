// ============================================================
// batch_h_h1_regression_test.dart — LinTho App
//
// Regression coverage for H-1 (Batch H): chat-room squatting/impersonation.
// ChatService.createOrGetChat() (lib/chat_screen.dart) no longer writes
// chats/{bookingId}_chat (Firestore) or chats/{bookingId}_chat/meta (RTDB)
// directly — it now calls the server-validated initializeBookingChat Cloud
// Function (functions/index.js), which is covered by
// functions/test/initialize-booking-chat.test.js. This file only verifies
// the Dart-side wiring: the client truly stopped writing directly, calls
// the right callable, and the two call sites that previously had zero
// error handling for this now-fallible operation do handle it.
//
// Source-text regression guard, same convention as
// test/critical_fixes_test.dart's CRIT-4 group — does not prove runtime
// behavior (no Firebase emulator in this test harness), only that the
// source contains the expected shape.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('H-1: ChatService.createOrGetChat() no longer writes directly', () {
    final source = _read('lib/chat_screen.dart');
    final start = source.indexOf('class ChatService {');
    final end = source.indexOf('\n}', start);
    late final String block;

    setUpAll(() {
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      block = source.substring(start, end);
    });

    test('calls the initializeBookingChat callable', () {
      expect(block, contains("httpsCallable('initializeBookingChat')"));
    });

    test('sends only bookingId to the server, not customerId/providerId/'
        'members/chatId', () {
      final callIdx = block.indexOf("httpsCallable('initializeBookingChat')");
      final callBlock = block.substring(callIdx, callIdx + 200);
      expect(callBlock, contains("'bookingId': bookingId"));
      expect(callBlock, isNot(contains("'customerId'")));
      expect(callBlock, isNot(contains("'providerId'")));
      expect(callBlock, isNot(contains("'members'")));
      expect(callBlock, isNot(contains("'chatId'")));
    });

    test('no longer writes chats/{chatId} to Firestore directly', () {
      expect(block, isNot(contains("collection('chats').doc(chatId)")));
      expect(block, isNot(contains('chatRef.set(')));
    });

    test('no longer writes chats/{chatId}/meta to RTDB directly', () {
      expect(block, isNot(contains("ref('chats/\$chatId/meta')")));
    });

    test('catches FirebaseFunctionsException and rethrows for the caller '
        'to handle', () {
      expect(block, contains('on FirebaseFunctionsException catch (e)'));
    });
  });

  group('H-1: call sites handle the now-fallible createOrGetChat()', () {
    test('job_workflow_Screen.dart\'s _openChat wraps createOrGetChat in '
        'try/catch with a user-visible error', () {
      final source = _read('lib/job_workflow_Screen.dart');
      final start = source.indexOf('Future<void> _openChat(BuildContext context, WidgetRef ref, Booking b)');
      final end = source.indexOf('\n  }', start);
      expect(start, greaterThan(-1));
      final block = source.substring(start, end);
      expect(block, contains('try {'));
      expect(block, contains('createOrGetChat('));
      expect(block, contains('} catch (e) {'));
      expect(block, contains('ScaffoldMessenger.of(context).showSnackBar('));
    });

    test('tracking_screen.dart\'s _openChat wraps createOrGetChat in '
        'try/catch with a user-visible error', () {
      final source = _read('lib/tracking_screen.dart');
      final start = source.indexOf('Future<void> _openChat() async {');
      final end = source.indexOf('\n  }', start);
      expect(start, greaterThan(-1));
      final block = source.substring(start, end);
      expect(block, contains('try {'));
      expect(block, contains('createOrGetChat('));
      expect(block, contains('} catch (e) {'));
      expect(block, contains('ScaffoldMessenger.of(context).showSnackBar('));
    });
  });

  group('H-1: provider_details_screen.dart (the ad-hoc, non-booking direct-'
      'chat path) is deliberately untouched — out of H-1 scope', () {
    test('still opens ChatScreen directly with receiverId, not chatId', () {
      final source = _read('lib/provider_details_screen.dart');
      expect(source, contains('receiverId:   provider.uid'));
    });
  });

  group('H-1: Firestore/RTDB rules deny direct client creation', () {
    test('firestore.rules: chats/{chatId} create is fully client-denied', () {
      final rules = _read('firestore.rules');
      final start = rules.indexOf('match /chats/{chatId}');
      final end = rules.indexOf('allow delete: if false;', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('allow create: if false;'));
    });

    test('database.rules.json: chats/\$chatId/meta .write is false', () {
      final dbRules = _read('database.rules.json');
      expect(dbRules, contains('".write": false'));
    });
  });
}
