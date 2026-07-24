// ============================================================
// rules_fixes_test.dart — LinTho App
//
// Regression tests for the follow-up firestore.rules hardening pass
// (2026-07-24 re-audit), locking in fixes that had no dedicated coverage:
//   FOLLOWUP-1 — transactions/{txId} create is Admin-SDK-only (if false)
//   FOLLOWUP-2 — notifications/{notifId} create is Admin-SDK-only (if false)
//   FOLLOWUP-3 — users/{uid} update protects 'status' from self-edit
//   FOLLOWUP-4 — coupons/{couponId} update requires ownerId match when set
//   FOLLOWUP-5 — fcm_queue/{queueId} has a scoped create rule
//   FOLLOWUP-6 — the dead top-level reviews/{reviewId} match block is gone
//
// ໝາຍເຫດ: firestore.rules ບໍ່ມີ rules-emulator test harness ຢູ່ໃນ repo ນີ້
// (ບໍ່ມີ @firebase/rules-unit-testing wired ຂຶ້ນ) — ໃຊ້ pattern ດຽວກັນກັບ
// medium_fixes_test.dart's ME-3/ME-4: source-text regression guard ອ່ານ
// firestore.rules ໂດຍກົງ.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  final rules = _read('firestore.rules');

  group('FOLLOWUP-1: transactions/{txId} create is Admin-SDK-only', () {
    test('the transactions match block has create: if false', () {
      final start = rules.indexOf('match /transactions/{txId}');
      final end = rules.indexOf('match /schedules/{uid}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('allow create: if false;'),
          reason: 'any authenticated provider could previously inject '
              'fabricated earning/bonus ledger entries for themselves');
    });
  });

  group('FOLLOWUP-2: notifications/{notifId} create is Admin-SDK-only', () {
    test('the notifications match block has create: if false', () {
      final start = rules.indexOf('match /notifications/{notifId}');
      final end = rules.indexOf('match /kyc/{uid}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('allow create: if false;'),
          reason: 'create previously had no toUid check at all — any '
              'authenticated user could write into any other feed');
    });
  });

  group("FOLLOWUP-3: users/{uid} update protects 'status'", () {
    test("the users update rule blocks self-editing 'status'", () {
      final start = rules.indexOf('match /users/{uid}');
      final end = rules.indexOf('match /settings/{docId}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains("!('status' in request.resource.data.diff(resource.data).affectedKeys())"),
          reason: 'an unverified provider could otherwise flip their own '
              'status to active, skipping PendingApprovalScreen');
    });
  });

  group('FOLLOWUP-4: coupons update requires ownerId match when set', () {
    test('the coupons update rule checks ownerId == request.auth.uid', () {
      final start = rules.indexOf('match /coupons/{couponId}');
      final end = rules.indexOf('match /rewardRedemptions/{reqId}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains("resource.data.ownerId == request.auth.uid"),
          reason: 'a personal reward-redeemed coupon (ownerId set) could '
              'previously be redeemed by anyone who obtained the code');
    });
  });

  group('FOLLOWUP-5: fcm_queue has a scoped create rule', () {
    test('the fcm_queue match block requires sent==false and targetUserId', () {
      expect(rules, contains('match /fcm_queue/{queueId}'),
          reason: 'this collection previously had no rule at all and fell '
              'to default-deny, silently breaking all client-triggered '
              'push notifications (review-received, chat-message, '
              'additional-charges)');
      final start = rules.indexOf('match /fcm_queue/{queueId}');
      final end = rules.indexOf('match /chats/{chatId}');
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('request.resource.data.sent == false'));
      expect(block, contains('request.resource.data.targetUserId is string'));
      expect(block, contains('allow read, update, delete: if false;'));
    });
  });

  group('FOLLOWUP-6: the dead top-level reviews block is removed', () {
    test('reviews/{reviewId} only exists nested under providers/{providerId}',
        () {
      // The nested, properly-secured subcollection rule must still exist.
      expect(rules, contains('match /reviews/{reviewId} {'),
          reason: 'the subcollection rule under providers/{providerId} '
              'must still be present');
      // But there must be exactly one occurrence — the top-level dead
      // block (which previously had `allow create: if isAuth();` with no
      // ownership/rating/booking checks) must be gone.
      final occurrences =
          'match /reviews/{reviewId} {'.allMatches(rules).length;
      expect(occurrences, 1,
          reason: 'a second, unsecured top-level reviews/{reviewId} block '
              'was found — it should have been deleted, not left alongside '
              'the properly-scoped subcollection rule');
    });
  });
}
