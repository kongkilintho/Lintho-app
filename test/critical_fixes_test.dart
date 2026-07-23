// ============================================================
// critical_fixes_test.dart — LinTho App
//
// Regression tests for the 5 Critical findings from the production
// readiness audit (2026-07-22) and their fixes:
//   CRIT-1: job completion was unreachable (confirmPaymentReceived
//           was never called from any UI).
//   CRIT-2: users/{uid} was readable in full by any authenticated user.
//   CRIT-3: missing composite Firestore index for the nearest-technician
//           query silently broke provider matching.
//   CRIT-4: tapping a push notification always crashed (pushNamed with
//           no registered routes).
//   CRIT-5: almost no Firestore/network call had a timeout, so a flaky
//           connection left buttons loading forever with no recovery.
//
// ໝາຍເຫດ: BookingRepository/EarningsRepository/CloudinaryService ເອີ້ນ
// FirebaseFirestore.instance ໂດຍກົງ (ບໍ່ໄດ້ inject) ຄືກັນກັບ
// register_flow_test.dart — ຈຶ່ງບໍ່ສາມາດ swap ເປັນ Fake instance ຜ່ານ
// unit test ໄດ້ໂດຍກົງ ສຳລັບ CRIT-1 group. ພາກນັ້ນຈຳລອງ transaction logic
// ດຽວກັນກັບ source ຂຶ້ນມາໃໝ່ (fake_cloud_firestore) ເພື່ອພິສູດ contract —
// ຖ້າແກ້ logic ໃນ booking_repository.dart, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
// ພາກອື່ນ (CRIT-2/3/4/5) ເປັນ source-text regression guard — ງ່າຍ, ບໍ່ຕ້ອງ
// ຕິດຕັ້ງ dependency ໃໝ່ (ບໍ່ມີ @firebase/rules-unit-testing / emulator ໃນ
// repo ນີ້), ແຕ່ຈັບໄດ້ຖ້າມີໃຜແກ້ໄຂ/ຖອນການແກ້ໄຂຄືນໂດຍບໍ່ຕັ້ງໃຈ.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════
  // CRIT-1 — payment confirmation gates job completion
  // ══════════════════════════════════════════════════════════
  group('CRIT-1: confirmPaymentReceived gates updateStatus(completed)', () {
    // ▸ ຄັດລອກ logic ຈາກ BookingRepository.confirmPaymentReceived() /
    //   .updateStatus() (booking_repository.dart) — ຖ້າແກ້ logic ໃນ source,
    //   ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<void> confirmPaymentReceived(
        FakeFirebaseFirestore db, String uid, String bookingId) async {
      final ref = db.collection('bookings').doc(bookingId);
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('ບໍ່ພົບຂໍ້ມູນການຈອງນີ້');
        final data = snap.data()!;
        if (data['providerId'] != uid) {
          throw Exception('ທ່ານບໍ່ແມ່ນຊ່າງທີ່ຮັບຜິດຊອບງານນີ້');
        }
        final status = data['status'] as String;
        if (['completed', 'cancelled', 'rejected'].contains(status)) {
          throw Exception('ບໍ່ສາມາດຢືນຢັນໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
        }
        if (data['paymentStatus'] == 'paid') return; // idempotent
        tx.update(ref, {'paymentStatus': 'paid'});
      });
    }

    Future<void> updateStatusToCompleted(
        FakeFirebaseFirestore db, String bookingId) async {
      final ref = db.collection('bookings').doc(bookingId);
      final doc = await ref.get();
      final paymentStatus = doc.data()?['paymentStatus'] as String?;
      if (paymentStatus != 'paid') {
        throw Exception('ກະລຸນາຢືນຢັນການຮັບເງິນກ່ອນປິດງານ');
      }
      await ref.update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
    }

    Future<FakeFirebaseFirestore> seedBooking({
      String status = 'inProgress',
      String paymentStatus = 'pending',
      String providerId = 'provider-1',
    }) async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'customerId': 'customer-1',
        'providerId': providerId,
        'status': status,
        'paymentStatus': paymentStatus,
        'price': 100000,
      });
      return db;
    }

    test(
        'BUG (pre-fix behavior): completing a job with paymentStatus '
        'still pending must be rejected', () async {
      final db = await seedBooking(paymentStatus: 'pending');
      expect(
        () => updateStatusToCompleted(db, 'b1'),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'FIX: confirmPaymentReceived() sets paymentStatus=paid, then '
        'completion succeeds', () async {
      final db = await seedBooking(paymentStatus: 'pending');

      await confirmPaymentReceived(db, 'provider-1', 'b1');
      final afterConfirm = await db.collection('bookings').doc('b1').get();
      expect(afterConfirm.data()?['paymentStatus'], 'paid');

      await updateStatusToCompleted(db, 'b1');
      final afterComplete = await db.collection('bookings').doc('b1').get();
      expect(afterComplete.data()?['status'], 'completed');
    });

    test(
        'a provider who does not own the booking cannot confirm payment '
        'on it', () async {
      final db = await seedBooking(providerId: 'provider-1');
      expect(
        () => confirmPaymentReceived(db, 'provider-2', 'b1'),
        throwsA(isA<Exception>()),
      );
    });

    test('confirming payment twice is idempotent (no error, no crash)',
        () async {
      final db = await seedBooking(paymentStatus: 'pending');
      await confirmPaymentReceived(db, 'provider-1', 'b1');
      await confirmPaymentReceived(db, 'provider-1', 'b1'); // should not throw
      final doc = await db.collection('bookings').doc('b1').get();
      expect(doc.data()?['paymentStatus'], 'paid');
    });

    test('cannot confirm payment on an already-finished booking', () async {
      final db = await seedBooking(status: 'cancelled');
      expect(
        () => confirmPaymentReceived(db, 'provider-1', 'b1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════
  // CRIT-2 — users/{uid} Firestore read rule
  // ══════════════════════════════════════════════════════════
  group('CRIT-2: firestore.rules users/{uid} read rule', () {
    test('read rule requires ownership or admin, not bare isAuth()',
        () {
      final rules = _read('firestore.rules');
      final usersBlockStart = rules.indexOf('match /users/{uid} {');
      expect(usersBlockStart, greaterThan(-1),
          reason: 'users/{uid} match block must exist');

      final block = rules.substring(
          usersBlockStart, (usersBlockStart + 1500).clamp(0, rules.length));

      expect(block, contains('allow read: if isAuth() && (isOwner(uid) || isAdmin());'),
          reason: 'users/{uid} read must be restricted to the owner or an '
              'admin — a bare `allow read: if isAuth();` lets any signed-in '
              'account dump every user\'s phone/GPS/name via a direct '
              'Firestore query.');
    });
  });

  // ══════════════════════════════════════════════════════════
  // CRIT-3 — missing composite index for provider matching
  // ══════════════════════════════════════════════════════════
  group('CRIT-3: firestore.indexes.json has the providers composite index',
      () {
    test('an index exists for providers: isOnline + serviceTypes + geohash',
        () {
      final json = jsonDecode(_read('firestore.indexes.json'))
          as Map<String, dynamic>;
      final indexes = (json['indexes'] as List).cast<Map<String, dynamic>>();

      final providerIndexes =
          indexes.where((i) => i['collectionGroup'] == 'providers').toList();
      expect(providerIndexes, isNotEmpty,
          reason: 'match_screen.dart queries the providers collection with '
              'isOnline + serviceTypes(array-contains) + geohash(whereIn) — '
              'without a matching composite index this throws '
              'FAILED_PRECONDITION on every real invocation.');

      bool hasFullIndex = providerIndexes.any((i) {
        final fields = (i['fields'] as List).cast<Map<String, dynamic>>();
        final paths = fields.map((f) => f['fieldPath']).toList();
        return paths.contains('isOnline') &&
            paths.contains('serviceTypes') &&
            paths.contains('geohash');
      });
      expect(hasFullIndex, isTrue,
          reason: 'expected a providers index covering isOnline + '
              'serviceTypes + geohash together');
    });

    test('the serviceTypes field uses array-contains config, not a plain order',
        () {
      final json = jsonDecode(_read('firestore.indexes.json'))
          as Map<String, dynamic>;
      final indexes = (json['indexes'] as List).cast<Map<String, dynamic>>();
      final providerIndexes =
          indexes.where((i) => i['collectionGroup'] == 'providers').toList();

      for (final index in providerIndexes) {
        final fields = (index['fields'] as List).cast<Map<String, dynamic>>();
        final serviceTypesField = fields
            .where((f) => f['fieldPath'] == 'serviceTypes')
            .cast<Map<String, dynamic>?>()
            .firstWhere((_) => true, orElse: () => null);
        if (serviceTypesField != null) {
          expect(serviceTypesField['arrayConfig'], 'CONTAINS');
        }
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // CRIT-4 — push notification navigation
  // ══════════════════════════════════════════════════════════
  group('CRIT-4: fcm_service.dart no longer uses unregistered named routes',
      () {
    test('does not call pushNamed for /job-workflow, /chat, /earnings', () {
      final source = _read('lib/fcm_service.dart');
      expect(source, isNot(contains("pushNamed('/job-workflow'")));
      expect(source, isNot(contains("pushNamed('/chat'")));
      expect(source, isNot(contains("pushNamed('/earnings'")));
    });

    test('navigates via direct MaterialPageRoute pushes to real screens', () {
      final source = _read('lib/fcm_service.dart');
      expect(source, contains('JobWorkflowScreen('));
      expect(source, contains('BookingDetailScreen('));
      expect(source, contains('ChatScreen('));
      expect(source, contains('ProviderDashboard('));
      expect(source, contains('MaterialPageRoute'));
    });

    test('main.dart still declares no routes table (confirms the fix does '
        'not rely on one existing)', () {
      final source = _read('lib/main.dart');
      expect(source, isNot(contains('routes:')));
    });
  });

  // ══════════════════════════════════════════════════════════
  // CRIT-5 — network timeouts
  // ══════════════════════════════════════════════════════════
  group('CRIT-5: previously timeout-less calls now have .timeout(...)', () {
    test('booking_repository.dart key methods have timeouts', () {
      final source = _read('lib/booking_repository.dart');
      // crude but effective: count timeout() occurrences added around the
      // methods flagged by the audit (acceptBooking, rejectBooking,
      // confirmPaymentReceived, updateStatus, requestAdditionalCharges,
      // requestWithdrawal, updateBankInfo, uploadProfilePhoto, uploadKyc).
      final occurrences = '.timeout('.allMatches(source).length;
      expect(occurrences, greaterThanOrEqualTo(9),
          reason: 'expected at least one .timeout() per previously '
              'unguarded write method in BookingRepository / '
              'EarningsRepository / ProfileRepository');
    });

    test('cloudinary_service.dart upload path has timeouts', () {
      final source = _read('lib/cloudinary_service.dart');
      expect(source, contains('.timeout('));
    });

    test('chat_screen.dart _sendMessage has a timeout on the RTDB write', () {
      final source = _read('lib/chat_screen.dart');
      final sendMessageStart = source.indexOf('Future<void> _sendMessage()');
      final sendMessageBody =
          source.substring(sendMessageStart, sendMessageStart + 1200);
      expect(sendMessageBody, contains('.timeout('));
    });

    test('match_screen.dart status-write methods have timeouts', () {
      final source = _read('lib/match_screen.dart');
      // ✅ [FIX H8] _updateStatus() (the old raw-write cancel path) was removed
      // entirely and replaced by CustomerBookingRepository.cancelBooking(),
      // which has its own .timeout() (see booking_repository.dart) — so it's
      // no longer expected to exist here as a separate method.
      for (final signature in [
        'Future<void> _sendRequestToTop3',
        'Future<void> _markMatchConfirmed',
      ]) {
        final start = source.indexOf(signature);
        expect(start, greaterThan(-1),
            reason: '$signature should still exist');
        final body = source.substring(start, (start + 800).clamp(0, source.length));
        expect(body, contains('.timeout('),
            reason: '$signature should wrap its Firestore write with .timeout()');
      }
      expect(source, isNot(contains('Future<void> _updateStatus')),
          reason: 'cancel actions should go through CustomerBookingRepository now');
    });
  });
}
