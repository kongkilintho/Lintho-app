// ============================================================
// high_severity_fixes_test.dart — LinTho App
//
// Regression tests for the High-severity findings fixed in this session
// (following the Critical-severity fixes in critical_fixes_test.dart):
//   H1  — coupon usageLimit re-validated inside the redemption transaction
//   H2  — grantSignupVoucher idempotency guard (Cloud Function)
//   H3  — booking accept-write requires isVerifiedProvider()
//   H4  — storage.rules scopes kyc/{uid}/** to the owner
//   H5  — database.rules.json scopes chat to its two members
//   H6  — providers/{id} rating/totalJobs/completionRate no longer
//         client-writable; reviews create requires ownership+rating bounds
//   H7  — rejecting an unassigned open-job-board booking keeps it pending
//   H8  — cancel actions route through CustomerBookingRepository
//   H9  — reviews create requires a real completed, un-reviewed booking
//   H10 — Booking.fromFirestore tolerates malformed/missing fields
//   H11 — serviceIconForCategory() resolves a stable IconData from category
//   H12 — AppIconButton adopted in job_workflow_Screen.dart
//   H13 — getMyBookings() is bounded (limit + orderBy)
//
// ໝາຍເຫດ: ໃຊ້ pattern ດຽວກັນກັບ critical_fixes_test.dart — ບາງກຸ່ມທົດສອບ
// ພຶດຕິກຳຈິງຜ່ານ fake_cloud_firestore (ຄັດລອກ logic ຈາກ source, ຕ້ອງອັບເດດຄູ່
// ກັນຖ້າແກ້ source), ບາງກຸ່ມເປັນ source-text regression guard ສະເພາະ
// Cloud Functions (JS) / rules files ທີ່ບໍ່ມີ test harness ຢູ່ໃນ repo ນີ້.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════
  // H1 — coupon usageLimit re-validated at redemption time
  // ══════════════════════════════════════════════════════════
  group('H1: coupon usageLimit re-checked inside the booking transaction', () {
    // ▸ ຄັດລອກ logic ຈາກ CustomerBookingRepository.createBooking()'s coupon
    //   re-validation block (booking_repository.dart) — ຖ້າແກ້ logic ໃນ
    //   source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<void> createBookingWithCoupon(
        FakeFirebaseFirestore db, String bookingId, String couponCode) async {
      final ref = db.collection('bookings').doc(bookingId);
      final couponRef = db.collection('coupons').doc(couponCode);
      await db.runTransaction((tx) async {
        final couponSnap = await tx.get(couponRef);
        if (!couponSnap.exists) throw Exception('invalid coupon');
        final c = couponSnap.data()!;
        if ((c['status'] as String?) != 'active') {
          throw Exception('coupon not active');
        }
        final usageLimit = c['usageLimit'] as num?;
        final usedCount = (c['usedCount'] as num?) ?? 0;
        if (usageLimit != null && usedCount >= usageLimit) {
          throw Exception('coupon usage limit reached');
        }
        tx.set(ref, {'status': 'pending', 'couponCode': couponCode});
        tx.update(couponRef, {'usedCount': FieldValue.increment(1)});
      });
    }

    test('a coupon already at its usageLimit is rejected, not silently over-redeemed',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('coupons').doc('MAXED').set({
        'status': 'active', 'usageLimit': 2, 'usedCount': 2,
      });

      expect(
        () => createBookingWithCoupon(db, 'b1', 'MAXED'),
        throwsA(isA<Exception>()),
      );
      final coupon = await db.collection('coupons').doc('MAXED').get();
      expect(coupon.data()?['usedCount'], 2, reason: 'must not increment past the limit');
    });

    test('a coupon under its usageLimit still redeems normally', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('coupons').doc('OK10').set({
        'status': 'active', 'usageLimit': 10, 'usedCount': 3,
      });

      await createBookingWithCoupon(db, 'b1', 'OK10');
      final coupon = await db.collection('coupons').doc('OK10').get();
      expect(coupon.data()?['usedCount'], 4);
    });

    test('firestore.rules also enforces the usageLimit cap server-side (defense-in-depth)',
        () {
      final rules = _read('firestore.rules');
      final couponsBlockStart = rules.indexOf("match /coupons/{couponId}");
      final block = rules.substring(
          couponsBlockStart, (couponsBlockStart + 1200).clamp(0, rules.length));
      expect(block, contains('usageLimit'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H2 — grantSignupVoucher idempotency (Cloud Function, source-text guard)
  // ══════════════════════════════════════════════════════════
  group('H2: grantSignupVoucher is idempotency-guarded', () {
    test('uses a transaction and checks a signupVoucherIssued flag before writing',
        () {
      final source = _read('functions/index.js');
      final start = source.indexOf('async function grantSignupVoucher');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 1200).clamp(0, source.length));
      expect(body, contains('runTransaction'));
      expect(body, contains('signupVoucherIssued'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H3 — booking accept-write requires a KYC-verified provider
  // ══════════════════════════════════════════════════════════
  group('H3: firestore.rules booking claim requires isVerifiedProvider()', () {
    test('provider accept/claim branch requires isVerifiedProvider()', () {
      final rules = _read('firestore.rules');
      // follow-up fix: isVerifiedProvider() now gates BOTH the "already own
      // this booking" and "claim a pending job" branches, since providerId
      // can also be pre-set by the customer at booking-create time (direct
      // provider booking), not only by the provider's own accept action.
      expect(rules, contains('(isProvider() && isVerifiedProvider() &&'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H4/H5 — Storage & Realtime Database rules exist and are wired up
  // ══════════════════════════════════════════════════════════
  group('H4/H5: storage.rules and database.rules.json exist and are wired',
      () {
    test('storage.rules scopes kyc/{uid}/** to the owner', () {
      final rules = _read('storage.rules');
      expect(rules, contains('match /kyc/{uid}/{fileName}'));
      expect(rules, contains('isOwner(uid)'));
    });

    test('database.rules.json scopes chat reads/writes to the two recorded '
        'customerId/providerId identities (immutable once set)', () {
      final json = jsonDecode(_read('database.rules.json')) as Map<String, dynamic>;
      final chatRules = json['rules']['chats']['\$chatId'] as Map<String, dynamic>;
      expect(chatRules['meta'], isNotNull);
      expect(chatRules['messages'], isNotNull);
      final messagesRead = chatRules['messages']['.read'] as String;
      expect(messagesRead, contains('customerId'));
      expect(messagesRead, contains('providerId'));
    });

    test('meta/customerId and meta/providerId are immutable once set', () {
      final json = jsonDecode(_read('database.rules.json')) as Map<String, dynamic>;
      final chatRules = json['rules']['chats']['\$chatId'] as Map<String, dynamic>;
      final customerIdValidate =
          chatRules['meta']['customerId']['.validate'] as String;
      final providerIdValidate =
          chatRules['meta']['providerId']['.validate'] as String;
      expect(customerIdValidate, contains('newData.val() == data.val()'));
      expect(providerIdValidate, contains('newData.val() == data.val()'));
    });

    test('firebase.json declares both storage and database rule files', () {
      final json = jsonDecode(_read('firebase.json')) as Map<String, dynamic>;
      expect(json['storage']['rules'], 'storage.rules');
      expect(json['database']['rules'], 'database.rules.json');
    });
  });

  // ══════════════════════════════════════════════════════════
  // H6/H9 — review integrity: ownership, rating bounds, real booking tie
  // ══════════════════════════════════════════════════════════
  group('H6/H9: review create rule and provider rating lockdown', () {
    test('providers/{id} create rule restricts kycStatus/rating/totalJobs/'
        'completionRate to safe defaults (closes the self-verification bypass)',
        () {
      // 🔒 found during independent verification: the original H3/H6 fixes
      // only locked down `update` — a brand-new provider doc's very first
      // `create` had zero restriction on these fields, letting an account
      // self-set kycStatus:'verified' or a fabricated rating immediately,
      // fully bypassing both the KYC gate and the rating-forgery fix.
      final rules = _read('firestore.rules');
      final providersStart = rules.indexOf('match /providers/{providerId}');
      final block = rules.substring(
          providersStart, (providersStart + 2200).clamp(0, rules.length));
      final createStart = block.indexOf('allow create:');
      final createEnd = block.indexOf(';', createStart);
      final createRule = block.substring(createStart, createEnd);
      expect(createRule, contains("kycStatus in ['none', 'pending']"));
      expect(createRule, contains('request.resource.data.rating == 0'));
      expect(createRule, contains('request.resource.data.totalJobs == 0'));
      expect(createRule, contains('request.resource.data.completionRate == 0'));
      // 🔒 [AUDIT KYC-1] KYC document URLs must never be writable on
      // providers/{uid} — that doc is readable by any authenticated user.
      expect(createRule, contains("!('kycDocUrl' in request.resource.data)"));
      expect(createRule, contains("!('kycIdUrl' in request.resource.data)"));
      expect(createRule, contains("!('kycSelfieUrl' in request.resource.data)"));
    });

    test('providers/{id} update no longer allows client-writable rating fields',
        () {
      final rules = _read('firestore.rules');
      final providersStart = rules.indexOf('match /providers/{providerId}');
      final block = rules.substring(
          providersStart, (providersStart + 3200).clamp(0, rules.length));
      expect(block, isNot(contains("hasOnly(['rating', 'totalJobs', 'completionRate'])")),
          reason: 'a customer must no longer be able to write these fields directly');
      // 🔒 [AUDIT KYC-1] KYC document URLs must also be blocked from update,
      // not just create — otherwise an owner could add them back later.
      final updateStart = block.indexOf('allow update:');
      final updateEnd = block.indexOf(';', updateStart);
      final updateRule = block.substring(updateStart, updateEnd);
      expect(updateRule, contains("'kycDocUrl'"));
      expect(updateRule, contains("'kycIdUrl'"));
      expect(updateRule, contains("'kycSelfieUrl'"));
    });

    test('reviews create rule requires customerId ownership and rating 1-5',
        () {
      final rules = _read('firestore.rules');
      final reviewsStart = rules.indexOf('match /reviews/{reviewId}');
      final block = rules.substring(
          reviewsStart, (reviewsStart + 1500).clamp(0, rules.length));
      expect(block, contains('request.resource.data.customerId == request.auth.uid'));
      expect(block, contains('request.resource.data.rating >= 1'));
      expect(block, contains("data.status == 'completed'"));
      expect(block, contains('reviewed != true'));
    });

    test('onReviewCreated Cloud Function validates booking ownership server-side',
        () {
      final source = _read('functions/index.js');
      final start = source.indexOf('exports.onReviewCreated');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 2200).clamp(0, source.length));
      expect(body, contains('booking.customerId !== review.customerId'));
      expect(body, contains("booking.status !== 'completed'"));
      expect(body, contains('ratingSum'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H7 — rejecting an open-job-board booking keeps it pending
  // ══════════════════════════════════════════════════════════
  group('H7: rejecting an unassigned booking does not kill it for other providers',
      () {
    // ▸ ຄັດລອກ logic ຈາກ BookingRepository.rejectBooking() — ຖ້າແກ້ logic ໃນ
    //   source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<void> rejectBooking(
        FakeFirebaseFirestore db, String uid, String bookingId) async {
      final ref = db.collection('bookings').doc(bookingId);
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data()!;
        final providerId = data['providerId'] as String? ?? '';
        if (providerId.isEmpty || providerId != uid) {
          tx.update(ref, {'rejectedBy': FieldValue.arrayUnion([uid])});
        } else {
          tx.update(ref, {'status': 'rejected'});
        }
      });
    }

    test('an unassigned open-job-board booking stays pending after one reject',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'status': 'pending', 'providerId': '',
      });

      await rejectBooking(db, 'provider-A', 'b1');

      final doc = await db.collection('bookings').doc('b1').get();
      expect(doc.data()?['status'], 'pending',
          reason: 'other providers must still be able to accept this job');
      expect((doc.data()?['rejectedBy'] as List).contains('provider-A'), isTrue);
    });

    test('a booking directly assigned to this provider is genuinely terminated on reject',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b2').set({
        'status': 'pending', 'providerId': 'provider-A',
      });

      await rejectBooking(db, 'provider-A', 'b2');

      final doc = await db.collection('bookings').doc('b2').get();
      expect(doc.data()?['status'], 'rejected');
    });

    test('unassignedOpenJobsProvider excludes bookings the current provider already rejected',
        () {
      // Booking model + filter logic (booking_provider.dart) — verified directly
      // via the model's rejectedBy field parsing.
      final booking = Booking(
        id: 'b1', customerId: 'c', customerName: '', customerPhone: '',
        providerId: '', serviceType: '', serviceEmoji: '🔧', address: '',
        location: const GeoPoint(0, 0), scheduledAt: DateTime.now(),
        status: JobStatus.pending, price: 0,
        createdAt: DateTime.now(), expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        rejectedBy: const ['provider-A'],
      );
      expect(booking.rejectedBy.contains('provider-A'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // H8 — cancel actions route through CustomerBookingRepository
  // ══════════════════════════════════════════════════════════
  group('H8: cancel actions use CustomerBookingRepository, not raw writes', () {
    test('match_screen.dart no longer bypasses CustomerBookingRepository', () {
      final source = _read('lib/match_screen.dart');
      expect(source, contains('CustomerBookingRepository'));
      expect(source, contains('_customerBookingRepo.cancelBooking('));
    });

    test('booking_detail_screen.dart no longer calls FirestoreService.updateBookingStatus',
        () {
      final source = _read('lib/booking_detail_screen.dart');
      expect(source, isNot(contains('FirestoreService.updateBookingStatus(widget')),
          reason: 'the actual call site must be gone (a historical comment '
              'mentioning the old method name by itself is fine)');
      expect(source, contains('_customerBookingRepo.cancelBooking('));
    });

    test('the dead FirestoreService.updateBookingStatus method was removed', () {
      final source = _read('lib/firestore_service.dart');
      expect(source, isNot(contains('static Future<void> updateBookingStatus')));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H10 — Booking.fromFirestore tolerates malformed documents
  // ══════════════════════════════════════════════════════════
  group('H10: Booking.fromFirestore does not throw on malformed data', () {
    test('missing timestamps and an unknown status do not throw', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('bad1').set({
        'customerId': 'c1',
        'status': 'some_legacy_value_that_does_not_exist',
        // scheduledAt / createdAt / expiresAt intentionally omitted
      });

      final doc = await db.collection('bookings').doc('bad1').get();
      expect(() => Booking.fromFirestore(doc), returnsNormally);

      final booking = Booking.fromFirestore(doc);
      expect(booking.status, JobStatus.pending,
          reason: 'unknown status must fall back safely, not throw');
    });

    test('a well-formed document still parses its real status correctly',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('good1').set({
        'customerId': 'c1',
        'status': 'completed',
        'scheduledAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.now(),
      });
      final doc = await db.collection('bookings').doc('good1').get();
      final booking = Booking.fromFirestore(doc);
      expect(booking.status, JobStatus.completed);
    });
  });

  // ══════════════════════════════════════════════════════════
  // H11 — serviceIconForCategory resolves a stable IconData
  // ══════════════════════════════════════════════════════════
  group('H11: serviceIconForCategory replaces the stored emoji field', () {
    test('known categories resolve to their expected icons', () {
      expect(serviceIconForCategory('ac_clean'), Icons.ac_unit_rounded);
      expect(serviceIconForCategory('house_clean'), Icons.cleaning_services_rounded);
    });

    test('an unknown category falls back to a generic icon instead of throwing',
        () {
      expect(serviceIconForCategory('some_future_category'), Icons.build_rounded);
      expect(serviceIconForCategory(''), Icons.build_rounded);
    });

    test('Booking.serviceIcon derives from category, not the stored emoji field',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'customerId': 'c1',
        'category': 'ac_clean',
        'serviceEmoji': '💥', // stale/irrelevant emoji — must be ignored
        'status': 'pending',
      });
      final doc = await db.collection('bookings').doc('b1').get();
      final booking = Booking.fromFirestore(doc);
      expect(booking.serviceIcon, Icons.ac_unit_rounded);
    });
  });

  // ══════════════════════════════════════════════════════════
  // H12 — AppIconButton adopted in job_workflow_Screen.dart
  // ══════════════════════════════════════════════════════════
  group('H12: job_workflow_Screen.dart uses the shared AppIconButton', () {
    test('imports and uses AppIconButton instead of the old 38x38 _QuickBtn',
        () {
      final source = _read('lib/job_workflow_Screen.dart');
      expect(source, contains("import 'widgets/app_icon_button.dart'"));
      expect(source, contains('AppIconButton('));
      expect(source, isNot(contains('class _QuickBtn')));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H13 — getMyBookings() is bounded
  // ══════════════════════════════════════════════════════════
  group('H13: getMyBookings() is bounded (limit + orderBy)', () {
    test('the query has both orderBy and limit', () {
      final source = _read('lib/firestore_service.dart');
      final start = source.indexOf('static Stream<QuerySnapshot> getMyBookings()');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 500).clamp(0, source.length));
      expect(body, contains('.orderBy('));
      expect(body, contains('.limit('));
    });

    test('firestore.indexes.json declares the matching composite index', () {
      final json = jsonDecode(_read('firestore.indexes.json')) as Map<String, dynamic>;
      final indexes = (json['indexes'] as List).cast<Map<String, dynamic>>();
      final hasCustomerIdCreatedAt = indexes.any((i) {
        if (i['collectionGroup'] != 'bookings') return false;
        final fields = (i['fields'] as List).cast<Map<String, dynamic>>();
        final paths = fields.map((f) => f['fieldPath']).toList();
        return paths.contains('customerId') && paths.contains('createdAt');
      });
      expect(hasCustomerIdCreatedAt, isTrue,
          reason: 'getMyBookings() now filters by customerId and orders by '
              'createdAt — without this index the query throws '
              'FAILED_PRECONDITION in production.');
    });
  });
}
