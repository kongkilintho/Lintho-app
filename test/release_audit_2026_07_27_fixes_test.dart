// ============================================================
// release_audit_2026_07_27_fixes_test.dart — LinTho App
//
// Regression tests for the Critical + High findings from the
// 2026-07-27 full release-readiness audit (7-specialist pass):
//   C-1  — booking status transitions / payment linkage were not
//          validated server-side (fraud vector: claim + self-pay a
//          pending booking in one write).
//   H-1  — provider identity (name/phone/rating/jobs/photo) was never
//          denormalized onto the booking on accept.
//   H-2  — sentTo (top-3 targeting) was enforced client-side only.
//   H-3  — BCEL customerConfirmedPayment gate was enforced client-side
//          only (same root cause as C-1, from the payment side).
//   H-4  — malformed free-text booking fields could throw inside
//          Booking.fromFirestore and take down an entire job-board list.
//   H-5  — photo pickers uploaded at full camera resolution for small
//          thumbnails.
//   H-6  — match_screen searching/waiting states had no scroll
//          fallback, risking an unreachable Cancel button.
//
// ໝາຍເຫດ: ບໍ່ມີ @firebase/rules-unit-testing / emulator ຢູ່ໃນ repo ນີ້
// (ເບິ່ງ header ຂອງ rules_fixes_test.dart/critical_fixes_test.dart) —
// ໃຊ້ pattern ດຽວກັນ: source-text regression guard ສຳລັບ firestore.rules,
// ແລະ ຄັດລອກ logic ມາທົດສອບຜ່ານ fake_cloud_firestore ສຳລັບ transaction
// contracts (booking_repository.dart ໃຊ້ FirebaseFirestore.instance ໂດຍກົງ,
// inject ບໍ່ໄດ້).
// ============================================================

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart';

// ✅ normalize CRLF -> LF so embedded '\n' expectations below match on
// Windows checkouts too (git may check this repo out with CRLF line endings)
String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

// ── Dart port of firestore.rules' isValidBookingStatusTransition() ──
// ▸ ຄັດລອກ logic ຈາກ firestore.rules ໂດຍກົງ — ຖ້າແກ້ transition table ໃນ
//   rules, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
bool isValidBookingStatusTransition(String oldStatus, String newStatus) {
  if (oldStatus == newStatus) return true; // no-op / other-field-only write
  return switch (oldStatus) {
    'pending' => ['accepted', 'cancelled', 'rejected'].contains(newStatus),
    'accepted' => ['onTheWay', 'cancelled'].contains(newStatus),
    'onTheWay' => ['arrived', 'cancelled'].contains(newStatus),
    'arrived' => ['inProgress', 'cancelled'].contains(newStatus),
    'inProgress' => ['completed', 'cancelled'].contains(newStatus),
    _ => false, // completed/cancelled/rejected are terminal
  };
}

// ── Dart port of firestore.rules' isValidPaymentTransition() ──
bool isValidPaymentTransition({
  required String? oldPaymentStatus,
  required String newPaymentStatus,
  required String paymentMethod,
  required bool customerConfirmedPayment,
}) {
  if (newPaymentStatus == oldPaymentStatus) return true; // unchanged
  if (newPaymentStatus != 'paid') return true;
  return paymentMethod == 'cash' || customerConfirmedPayment == true;
}

void main() {
  final rules = _read('firestore.rules');

  // ══════════════════════════════════════════════════════════
  // C-1 — booking status transition must be a real state machine
  // ══════════════════════════════════════════════════════════
  group('C-1: isValidBookingStatusTransition() exists and is wired in', () {
    test('firestore.rules defines the transition-guard function', () {
      expect(rules, contains('function isValidBookingStatusTransition()'),
          reason: 'previously nothing validated the OLD status before '
              'allowing a status write — pending could jump straight to '
              'completed in one write');
      expect(rules, contains('isValidBookingStatusTransition()'));
    });

    test('the bookings update rule requires the transition guard '
        'unconditionally (not just inside one branch)', () {
      final start = rules.indexOf('match /bookings/{bookingId}');
      final end = rules.indexOf('match /providers/{providerId}');
      final block = rules.substring(start, end);
      expect(
          block,
          contains('allow update: if isAuth() && isValidCompletionPayment() &&\n'
              '        isValidBookingStatusTransition() && isValidPaymentTransition() && ('),
          reason: 'the transition + payment guards must gate every update '
              'branch (customer AND provider), not just the completion check');
    });

    test('direct pending -> completed is rejected by the state machine',
        () {
      expect(isValidBookingStatusTransition('pending', 'completed'), isFalse,
          reason: 'this is the exact exploit: claim + self-complete a '
              'booking in one write, skipping onTheWay/arrived/inProgress');
    });

    test('the real multi-step job progression is allowed', () {
      expect(isValidBookingStatusTransition('pending', 'accepted'), isTrue);
      expect(isValidBookingStatusTransition('accepted', 'onTheWay'), isTrue);
      expect(isValidBookingStatusTransition('onTheWay', 'arrived'), isTrue);
      expect(isValidBookingStatusTransition('arrived', 'inProgress'), isTrue);
      expect(isValidBookingStatusTransition('inProgress', 'completed'), isTrue);
    });

    test('cancellation is allowed from every active status', () {
      for (final s in ['pending', 'accepted', 'onTheWay', 'arrived', 'inProgress']) {
        expect(isValidBookingStatusTransition(s, 'cancelled'), isTrue,
            reason: '$s -> cancelled must remain possible');
      }
    });

    test('terminal statuses cannot be changed again', () {
      for (final terminal in ['completed', 'cancelled', 'rejected']) {
        expect(isValidBookingStatusTransition(terminal, 'accepted'), isFalse);
        expect(isValidBookingStatusTransition(terminal, 'pending'), isFalse);
      }
    });

    test('skipping a step (e.g. accepted -> arrived) is rejected', () {
      expect(isValidBookingStatusTransition('accepted', 'arrived'), isFalse);
      expect(isValidBookingStatusTransition('accepted', 'completed'), isFalse);
      expect(isValidBookingStatusTransition('pending', 'onTheWay'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // C-1 / H-3 — paymentStatus:'paid' must be tied to a real confirmation
  // ══════════════════════════════════════════════════════════
  group('C-1/H-3: isValidPaymentTransition() exists and is wired in', () {
    test('firestore.rules defines the payment-transition guard function',
        () {
      expect(rules, contains('function isValidPaymentTransition()'));
      expect(
          rules,
          contains('resource.data.paymentMethod == \'cash\' ||\n'
              '        resource.data.customerConfirmedPayment == true;'),
          reason: 'paymentStatus can only become paid if the booking is '
              'cash (self-attested, accepted limitation) or the customer '
              'already confirmed a BCEL transfer');
    });

    test('a cash booking can be self-attested as paid by the provider', () {
      expect(
          isValidPaymentTransition(
              oldPaymentStatus: 'pending',
              newPaymentStatus: 'paid',
              paymentMethod: 'cash',
              customerConfirmedPayment: false),
          isTrue);
    });

    test('a BCEL (bank-transfer) booking cannot be marked paid without '
        'customer confirmation — this is the exact H-3 exploit', () {
      expect(
          isValidPaymentTransition(
              oldPaymentStatus: 'pending',
              newPaymentStatus: 'paid',
              paymentMethod: 'bcel',
              customerConfirmedPayment: false),
          isFalse);
    });

    test('a BCEL booking CAN be marked paid once the customer has '
        'confirmed', () {
      expect(
          isValidPaymentTransition(
              oldPaymentStatus: 'pending',
              newPaymentStatus: 'paid',
              paymentMethod: 'bcel',
              customerConfirmedPayment: true),
          isTrue);
    });

    test('writes that do not touch paymentStatus are unaffected', () {
      expect(
          isValidPaymentTransition(
              oldPaymentStatus: 'pending',
              newPaymentStatus: 'pending',
              paymentMethod: 'bcel',
              customerConfirmedPayment: false),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // H-2 — sentTo (top-3 targeting) enforced server-side too
  // ══════════════════════════════════════════════════════════
  group('H-2: isValidSentToTargeting() gates both read and claim', () {
    test('firestore.rules defines the sentTo-targeting guard function', () {
      expect(rules, contains('function isValidSentToTargeting()'),
          reason: 'previously sentTo was only checked in the Dart client '
              '(isJobVisibleToProvider) — any verified provider could read '
              'and claim jobs never routed to them via a direct query');
    });

    test('the pending-job read rule requires isValidSentToTargeting()', () {
      final bookingsStart = rules.indexOf('match /bookings/{bookingId}');
      final bookingsEnd = rules.indexOf('match /providers/{providerId}');
      expect(bookingsStart, greaterThan(-1));
      expect(bookingsEnd, greaterThan(bookingsStart));
      final bookingsBlock = rules.substring(bookingsStart, bookingsEnd);

      final start = bookingsBlock.indexOf('allow read: if isAuth() && (');
      final end = bookingsBlock.indexOf('allow create: if isAuth() &&');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = bookingsBlock.substring(start, end);
      expect(block, contains('isValidSentToTargeting()'));
    });

    test('the claim branch requires isValidSentToTargeting()', () {
      final start = rules.indexOf("resource.data.status == 'pending' &&\n"
          "             request.resource.data.providerId == request.auth.uid");
      expect(start, greaterThan(-1),
          reason: 'the claim branch condition must still exist');
      final block = rules.substring(start, start + 300);
      expect(block, contains('isValidSentToTargeting()'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H-4 — server-side validation of free-text booking fields
  // ══════════════════════════════════════════════════════════
  group('H-4: isValidBookingTextFields() validates address/landmark/'
      'specialInstructions on create', () {
    test('firestore.rules defines and wires in the text-field guard', () {
      expect(rules, contains('function isValidBookingTextFields()'));
      final start = rules.indexOf('function isValidNewBookingShape()');
      final end = rules.indexOf('match /{document=**}');
      final block = rules.substring(start, end);
      expect(block, contains('isValidBookingTextFields()'),
          reason: 'the new-booking shape guard must call the text-field '
              'guard, otherwise a modified client can still write a '
              'non-string address');
    });
  });

  group('H-4: Booking.fromFirestore no longer throws on malformed '
      'free-text fields', () {
    test('a non-string address/landmark/specialInstructions falls back '
        'to empty string instead of throwing', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('bad1').set({
        'customerId': 'c1',
        'address': 12345, // malformed: number instead of string
        'landmark': {'not': 'a string'}, // malformed: map instead of string
        'specialInstructions': ['also', 'wrong'], // malformed: list
        'status': 'pending',
        'price': 100000,
      });
      final snap = await db.collection('bookings').doc('bad1').get();

      expect(() => Booking.fromFirestore(snap), returnsNormally,
          reason: 'a single malformed document must not throw — this used '
              'to take down the entire provider job-board stream');

      final b = Booking.fromFirestore(snap);
      expect(b.address, '');
      expect(b.landmark, '');
      expect(b.specialInstructions, '');
      expect(b.customerId, 'c1', reason: 'well-formed fields must still '
          'parse correctly alongside the malformed ones');
    });

    test('a well-formed document still round-trips exactly as before',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('good1').set({
        'customerId': 'c1',
        'address': '123 ຖະໜົນ',
        'landmark': 'ໃກ້ຕະຫຼາດ',
        'specialInstructions': 'ມີໝາ',
        'status': 'pending',
        'price': 100000,
      });
      final snap = await db.collection('bookings').doc('good1').get();
      final b = Booking.fromFirestore(snap);
      expect(b.address, '123 ຖະໜົນ');
      expect(b.landmark, 'ໃກ້ຕະຫຼາດ');
      expect(b.specialInstructions, 'ມີໝາ');
    });
  });

  group('H-4: provider-identity fields round-trip through Booking model '
      '(needed by H-1)', () {
    test('providerName/providerPhone/providerRating/providerJobs/'
        'providerPhoto parse from Firestore', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'customerId': 'c1',
        'status': 'accepted',
        'price': 100000,
        'providerName': 'ທ້າວ ສົມ',
        'providerPhone': '02012345678',
        'providerRating': 4.5,
        'providerJobs': 12,
        'providerPhoto': 'https://example.com/p.jpg',
      });
      final snap = await db.collection('bookings').doc('b1').get();
      final b = Booking.fromFirestore(snap);
      expect(b.providerName, 'ທ້າວ ສົມ');
      expect(b.providerPhone, '02012345678');
      expect(b.providerRating, 4.5);
      expect(b.providerJobs, 12);
      expect(b.providerPhoto, 'https://example.com/p.jpg');
    });

    test('missing provider-identity fields default to null, not a throw',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b2').set({
        'customerId': 'c1',
        'status': 'pending',
        'price': 100000,
      });
      final snap = await db.collection('bookings').doc('b2').get();
      final b = Booking.fromFirestore(snap);
      expect(b.providerName, isNull);
      expect(b.providerPhone, isNull);
      expect(b.providerRating, isNull);
      expect(b.providerJobs, isNull);
      expect(b.providerPhoto, isNull);
    });
  });

  group('H-4: booking_repository.dart isolates one malformed document '
      'per stream instead of failing the whole list', () {
    test('watchActiveBookings/watchJobHistory/watchOpenJobs use the '
        'per-document safe mapper', () {
      final source = _read('lib/booking_repository.dart');
      expect(source, contains('List<Booking> _safeMapBookings('),
          reason: 'a helper that skips unparseable documents instead of '
              'letting one throw kill the whole stream must exist');
      final occurrences = '.map(_safeMapBookings)'.allMatches(source).length;
      expect(occurrences, 3,
          reason: 'watchActiveBookings, watchJobHistory, and watchOpenJobs '
              'must all use the safe mapper');
      expect(source, isNot(contains('.map((s) => s.docs.map(Booking.fromFirestore).toList())')),
          reason: 'the old unsafe inline mapper should be fully replaced');
    });
  });

  // ══════════════════════════════════════════════════════════
  // H-1 — provider identity denormalized on accept
  // ══════════════════════════════════════════════════════════
  group('H-1: acceptBooking() denormalizes provider identity onto the '
      'booking', () {
    // ▸ ຄັດລອກ logic ຈາກ BookingRepository.acceptBooking() ຂຶ້ນມາໃໝ່ (ຄືກັນ
    //   ກັບ CRIT-1 ໃນ critical_fixes_test.dart) — ຖ້າແກ້ logic ໃນ source,
    //   ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<void> acceptBooking(
        FakeFirebaseFirestore db, String uid, String bookingId) async {
      final ref = db.collection('bookings').doc(bookingId);
      final providerRef = db.collection('providers').doc(uid);
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data()!;
        if (data['status'] != 'pending') {
          throw Exception('ງານນີ້ມີຄົນຮັບໄປແລ້ວ');
        }
        final sentTo = List<String>.from(data['sentTo'] ?? const []);
        if (sentTo.isNotEmpty && !sentTo.contains(uid)) {
          throw Exception('ງານນີ້ບໍ່ໄດ້ຖືກສົ່ງໃຫ້ທ່ານ');
        }
        final providerSnap = await tx.get(providerRef);
        final p = providerSnap.data() ?? const <String, dynamic>{};
        tx.update(ref, {
          'status': 'accepted',
          'providerId': uid,
          'providerName': p['displayName'] as String? ?? '',
          'providerPhone': p['phone'] as String? ?? '',
          'providerRating': (p['rating'] as num?)?.toDouble() ?? 0.0,
          'providerJobs': p['totalJobs'] as int? ?? 0,
          'providerPhoto': p['photoUrl'] as String? ?? '',
        });
      });
    }

    test('accepting a booking copies the provider\'s displayName/phone/'
        'rating/totalJobs/photoUrl onto the booking document', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('providers').doc('prov-1').set({
        'displayName': 'ທ້າວ ບຸນມີ',
        'phone': '02099998888',
        'rating': 4.8,
        'totalJobs': 42,
        'photoUrl': 'https://example.com/bunmee.jpg',
      });
      await db.collection('bookings').doc('b1').set({
        'customerId': 'c1',
        'status': 'pending',
        'price': 100000,
      });

      await acceptBooking(db, 'prov-1', 'b1');

      final after = await db.collection('bookings').doc('b1').get();
      expect(after.data()?['status'], 'accepted');
      expect(after.data()?['providerId'], 'prov-1');
      expect(after.data()?['providerName'], 'ທ້າວ ບຸນມີ',
          reason: 'this is the H-1 fix — match_screen.dart / '
              'tracking_screen.dart / booking_display_helpers.dart all read '
              'this field directly off the booking and used to see it '
              'empty on every real booking');
      expect(after.data()?['providerPhone'], '02099998888',
          reason: 'an empty providerPhone is what made the "call '
              'provider" button a silent no-op');
      expect(after.data()?['providerRating'], 4.8);
      expect(after.data()?['providerJobs'], 42);
      expect(after.data()?['providerPhoto'], 'https://example.com/bunmee.jpg');
    });

    test('a provider cannot accept a job that was sent to other '
        'providers only (H-2, client-side pre-check)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('providers').doc('prov-2').set({
        'displayName': 'ຊ່າງ 2',
      });
      await db.collection('bookings').doc('b2').set({
        'customerId': 'c1',
        'status': 'pending',
        'price': 100000,
        'sentTo': ['prov-1', 'prov-3'],
      });

      expect(
        () => acceptBooking(db, 'prov-2', 'b2'),
        throwsA(isA<Exception>()),
      );
    });

    test('a targeted provider (in sentTo) can accept normally', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('providers').doc('prov-1').set({
        'displayName': 'ຊ່າງ 1',
        'phone': '020111',
      });
      await db.collection('bookings').doc('b3').set({
        'customerId': 'c1',
        'status': 'pending',
        'price': 100000,
        'sentTo': ['prov-1', 'prov-3'],
      });

      await acceptBooking(db, 'prov-1', 'b3');
      final after = await db.collection('bookings').doc('b3').get();
      expect(after.data()?['status'], 'accepted');
      expect(after.data()?['providerName'], 'ຊ່າງ 1');
    });

    test('firestore.rules allow-list for the provider claim branch '
        'includes the new provider-identity fields', () {
      final start = rules.indexOf('isProvider() && isVerifiedProvider() &&');
      final end = rules.indexOf('AUDIT H7', start);
      final block = rules.substring(start, end);
      for (final field in [
        'providerName',
        'providerPhone',
        'providerRating',
        'providerJobs',
        'providerPhoto',
      ]) {
        expect(block, contains("'$field'"),
            reason: 'the claim branch whitelist must allow $field, or the '
                'rule will reject acceptBooking()\'s write');
      }
    });
  });

  // ══════════════════════════════════════════════════════════
  // H-5 — photo pickers cap dimensions
  // ══════════════════════════════════════════════════════════
  group('H-5: remaining photo pickers now constrain dimensions', () {
    test('job_workflow_Screen.dart before/after photo picker sets '
        'maxWidth/maxHeight', () {
      final source = _read('lib/job_workflow_Screen.dart');
      final start = source.indexOf('Future<void> _pickPhoto({required bool isBefore})');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 800).clamp(0, source.length));
      expect(body, contains('maxWidth: 1600'));
      expect(body, contains('maxHeight: 1600'));
    });

    test('profile_tab.dart avatar picker sets maxWidth/maxHeight', () {
      final source = _read('lib/profile_tab.dart');
      final start = source.indexOf('Future<void> _pickPhoto() async {');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 300).clamp(0, source.length));
      expect(body, contains('maxWidth: 800'));
      expect(body, contains('maxHeight: 800'));
    });

    test('main.dart customer photo picker sets maxWidth/maxHeight', () {
      final source = _read('lib/main.dart');
      expect(
          source,
          contains('source: source, imageQuality: 75, maxWidth: 800, maxHeight: 800);'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // H-6 — match_screen scroll fallback
  // ══════════════════════════════════════════════════════════
  group('H-6: match_screen searching/waiting states scroll instead of '
      'overflowing', () {
    test('_buildSearching() wraps its content in SingleChildScrollView '
        'and no longer uses Spacer()', () {
      final source = _read('lib/match_screen.dart');
      final start = source.indexOf('Widget _buildSearching()');
      final end = source.indexOf('Widget _buildWaiting()');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('SingleChildScrollView'),
          reason: 'without a scroll container, small screens / large text '
              'can push the only Cancel button off-screen with no way to '
              'back out (PopScope intercepts the OS back gesture too)');
      expect(body, isNot(contains('Spacer()')),
          reason: 'Spacer()/Expanded cannot be used inside a Column that '
              'is the child of a scroll view (unbounded height)');
    });

    test('_buildWaiting() wraps its content in SingleChildScrollView and '
        'no longer uses Spacer()', () {
      final source = _read('lib/match_screen.dart');
      final start = source.indexOf('Widget _buildWaiting()');
      final end = source.indexOf('Widget _buildMatched()');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('SingleChildScrollView'));
      expect(body, isNot(contains('Spacer()')));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-1 — duplicate additional-charges notification
  // ══════════════════════════════════════════════════════════
  group('M-1: additional-charges notification no longer fires twice', () {
    test('job_workflow_Screen.dart no longer calls '
        'NotificationSender.additionalCharges directly (the repository '
        'already sends it)', () {
      final source = _read('lib/job_workflow_Screen.dart');
      expect(source, isNot(contains('NotificationSender.additionalCharges')));
    });

    test('booking_repository.dart requestAdditionalCharges still sends '
        'the notification exactly once', () {
      final source = _read('lib/booking_repository.dart');
      final start = source.indexOf('Future<void> requestAdditionalCharges(');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 900).clamp(0, source.length));
      final occurrences =
          'NotificationSender.additionalCharges'.allMatches(body).length;
      expect(occurrences, 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-3 — Terms & Privacy reachable pre-auth
  // ══════════════════════════════════════════════════════════
  group('M-3: settings/legal is readable before sign-in', () {
    test('firestore.rules has a public-read carve-out scoped to '
        'settings/legal only', () {
      expect(rules, contains('match /settings/legal {'));
      final start = rules.indexOf('match /settings/legal {');
      final end = rules.indexOf('match /bookings/{bookingId}');
      final block = rules.substring(start, end);
      expect(block, contains('allow read: if true;'));
    });

    test('the general settings/{docId} rule is unchanged (still '
        'isAuth()-gated) for every other document', () {
      final start = rules.indexOf('match /settings/{docId} {');
      final end = rules.indexOf('match /settings/legal {');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('allow read: if isAuth();'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-4 — contactPhone cross-checked against the auth token
  // ══════════════════════════════════════════════════════════
  group('M-4: contactPhone must match the caller\'s verified auth phone', () {
    test('firestore.rules defines and wires in isValidContactPhone()', () {
      expect(rules, contains('function isValidContactPhone()'));
      expect(rules, contains('request.resource.data.contactPhone == request.auth.token.phone_number'));
      final start = rules.indexOf('function isValidNewBookingShape()');
      final end = rules.indexOf('match /{document=**}');
      final block = rules.substring(start, end);
      expect(block, contains('isValidContactPhone()'),
          reason: 'the new-booking guard must call isValidContactPhone(), '
              'otherwise a modified client can still write an arbitrary '
              'phone number into a field the customer\'s own booking form '
              'always sources from FirebaseAuth.currentUser.phoneNumber');
    });

    test('the check is skipped when the account has no phone_number claim '
        '(non-phone-auth accounts are not blocked)', () {
      final start = rules.indexOf('function isValidContactPhone()');
      final block = rules.substring(start, start + 400);
      expect(block, contains('request.auth.token.phone_number == null'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-5 / L-6 — Bank Info sheet: double-tap guard + controller disposal
  // ══════════════════════════════════════════════════════════
  group('M-5/L-6: Bank Info sheet has a submitting guard and disposes its '
      'controllers', () {
    test('_showBankSheet uses the same submitting-flag pattern as the '
        'withdrawal sheet', () {
      final source = _read('lib/earnings_tab.dart');
      final start = source.indexOf('void _showBankSheet(');
      final end = source.indexOf('\n}', start);
      final block = source.substring(start, end);
      expect(block, contains('bool submitting = false;'));
      expect(block, contains('onPressed: submitting ? null : () async {'),
          reason: 'without this guard a fast double-tap fires two '
              'updateBankInfo() calls and the second Navigator.pop() can '
              'close an unrelated route once the sheet is already gone');
    });

    test('both bottom sheets dispose their TextEditingControllers once '
        'closed', () {
      final source = _read('lib/earnings_tab.dart');
      final occurrences = '.whenComplete('.allMatches(source).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: 'expected a .whenComplete(...dispose...) on both the '
              'withdrawal sheet and the bank-info sheet');
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-6 — sentTo write failure no longer shown as success
  // ══════════════════════════════════════════════════════════
  group('M-6: _sendRequestToTop3 reports success/failure instead of '
      'swallowing errors', () {
    test('_sendRequestToTop3 returns a bool and retries once on failure', () {
      final source = _read('lib/match_screen.dart');
      expect(source, contains('Future<bool> _sendRequestToTop3('));
      final start = source.indexOf('Future<bool> _sendRequestToTop3(');
      final end = source.indexOf('\n  }', start + 40);
      final body = source.substring(start, end);
      expect(body, contains('if (await attempt()) return true;'));
    });

    test('_findAndSendTop3 does not transition to "waiting" when the send '
        'failed', () {
      final source = _read('lib/match_screen.dart');
      final start = source.indexOf('final sent = await _sendRequestToTop3(_top3);');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 1000).clamp(0, source.length));
      expect(body, contains('if (!sent) {'));
      expect(body, contains('_scheduleRetry();'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-8 — match-retry redundant reads eliminated
  // ══════════════════════════════════════════════════════════
  group('M-8: match_screen caches booking category instead of re-fetching '
      'it on every retry', () {
    test('a _cachedCategory field exists and is set by _loadBookingMeta()',
        () {
      final source = _read('lib/match_screen.dart');
      expect(source, contains('String? _cachedCategory;'));
      expect(source, contains('_cachedCategory = category;'));
    });

    test('_findAndSendTop3 reads from the cache instead of unconditionally '
        're-querying the booking document', () {
      final source = _read('lib/match_screen.dart');
      final start = source.indexOf('Future<void> _findAndSendTop3(');
      final body = source.substring(start, (start + 700).clamp(0, source.length));
      expect(body, contains('_cachedCategory ?? '));
      expect(body, contains('if (_cachedCategory == null) {'),
          reason: 'the booking doc should only be re-fetched as a fallback '
              'when the cache was never populated, not on every retry');
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-13 — saved-addresses sheet: scroll + delete confirmation
  // ══════════════════════════════════════════════════════════
  group('M-13: saved-addresses sheet scrolls and confirms before delete', () {
    test('the address list is wrapped in a bounded, scrollable container',
        () {
      final source = _read('lib/main.dart');
      final start = source.indexOf('void _showAddr(BuildContext context)');
      expect(start, greaterThan(-1));
      final body = source.substring(start, (start + 5000).clamp(0, source.length));
      expect(body, contains('SingleChildScrollView'));
      expect(body, contains('ConstrainedBox'));
    });

    test('deleting a saved address requires confirmation first', () {
      final source = _read('lib/main.dart');
      final start = source.indexOf('void _showAddr(BuildContext context)');
      final body = source.substring(start, (start + 5000).clamp(0, source.length));
      expect(body, contains('showDialog<bool>'),
          reason: 'a single accidental tap on the trash icon used to '
              'delete the address immediately and irreversibly');
      expect(body, contains("collection('addresses').doc(a.id).delete()"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-15 — referral info no longer re-queries on unrelated writes
  // ══════════════════════════════════════════════════════════
  group('M-15: referralInfoProvider listens to vouchers directly instead '
      'of piggybacking on the users/{uid} doc stream', () {
    test('the provider streams the vouchers subcollection, not '
        'users/{uid}', () {
      final source = _read('lib/referral_provider.dart');
      final start = source.indexOf('final referralInfoProvider =');
      final end = source.indexOf('Future<String> _ensureReferralCode');
      final block = source.substring(start, end);
      expect(
          block,
          contains("collection('wallets').doc(uid).collection('vouchers')"));
      expect(block, contains('.snapshots()'));
      // the users/{uid} doc must now be a one-shot .get(), not a live listener
      expect(block, contains("collection('users').doc(uid).get()"));
      expect(block, isNot(contains("collection('users').doc(uid).snapshots()")));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-10 — emoji → Material icon migration (ratings/status/photo icons)
  // ══════════════════════════════════════════════════════════
  group('M-10: remaining functional emoji replaced with Material icons', () {
    test('provider_details_screen.dart stats use icons, not emoji', () {
      final source = _read('lib/provider_details_screen.dart');
      expect(source, isNot(contains("_StatItem('⭐'")));
      expect(source, isNot(contains("_StatItem('✅'")));
      expect(source, isNot(contains("_StatItem('🏆'")));
      expect(source, contains('Icons.star_rounded'));
      expect(source, contains('Icons.emoji_events_rounded'));
      final classStart = source.indexOf('class _StatItem extends StatelessWidget');
      final body = source.substring(classStart, (classStart + 500).clamp(0, source.length));
      expect(body, contains('final IconData icon;'));
    });

    test('tracking_screen.dart status badge/map-marker use an icon getter, '
        'not the emoji getter', () {
      final source = _read('lib/tracking_screen.dart');
      expect(source, contains('IconData get icon => switch (this) {'));
      expect(source, isNot(contains('Text(_status.emoji')),
          reason: 'both the map-marker badge and the status pill used to '
              'render _status.emoji as text');
      final occurrences = '_status.icon'.allMatches(source).length;
      expect(occurrences, greaterThanOrEqualTo(2));
    });

    test('job_workflow_Screen.dart photo slots take an IconData, not an '
        'emoji string', () {
      final source = _read('lib/job_workflow_Screen.dart');
      final start = source.indexOf('class _PhotoSlot extends StatelessWidget');
      final body = source.substring(start, (start + 400).clamp(0, source.length));
      expect(body, contains('final IconData       icon;'));
      expect(source, contains('icon: Icons.camera_alt_outlined'));
      expect(source, contains('icon: Icons.auto_awesome_outlined'));
    });

    test('pending_approval_screen.dart uses an Icon, not the hourglass '
        'emoji', () {
      final source = _read('lib/pending_approval_screen.dart');
      expect(source, isNot(contains("Text('⏳'")));
      expect(source, contains('Icons.hourglass_top_rounded'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-12 — hardcoded Lao text routed through tr()
  // ══════════════════════════════════════════════════════════
  group('M-12: previously-hardcoded screens now route through tr()', () {
    test('every new M-12 key is defined in all 4 locales', () {
      final source = _read('lib/app_locale.dart');
      const keys = [
        'chat_title', 'chat_book_first_hint', 'rewards_title',
        'redeem_points_title', 'points_history_title',
        'points_history_load_failed', 'no_points_history', 'coupons_title',
        'no_coupons', 'referral_succeeded_count', 'referral_total_earned',
        'enter_friend_code', 'your_referral_code',
      ];
      for (final key in keys) {
        final occurrences = "'$key':".allMatches(source).length;
        expect(occurrences, 4,
            reason: '$key should be defined once per language (lo/en/th/zh)');
      }
    });

    test('chat_screen.dart no longer hardcodes its title/hint text', () {
      final source = _read('lib/chat_screen.dart');
      expect(source, isNot(contains("Text('ຂໍ້ຄວາມ'")));
      expect(source, isNot(contains("Text('ຈອງບໍລິການກ່ອນ")));
      expect(source, contains("tr('chat_title')"));
      expect(source, contains("tr('chat_book_first_hint')"));
    });

    test('rewards_screen.dart / coupon_list_screen.dart / '
        'referral_screen.dart no longer hardcode their titles', () {
      final rewards = _read('lib/rewards_screen.dart');
      expect(rewards, contains("tr('rewards_title')"));
      expect(rewards, contains("tr('no_points_history')"));

      final coupons = _read('lib/coupon_list_screen.dart');
      expect(coupons, contains("tr('coupons_title')"));
      expect(coupons, contains("tr('no_coupons')"));

      final referral = _read('lib/referral_screen.dart');
      expect(referral, contains("tr('referral_succeeded_count')"));
      expect(referral, contains("tr('your_referral_code')"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // M-9 — rewards/referral error states now use ErrorStateView (partial)
  // ══════════════════════════════════════════════════════════
  group('M-9: rewards_screen/referral_screen error states have a retry '
      'action instead of raw error text', () {
    test('rewards_screen.dart uses ErrorStateView/EmptyStateView for its '
        'points-history error/empty branches', () {
      final source = _read('lib/rewards_screen.dart');
      expect(source, contains('ErrorStateView('));
      expect(source, contains('EmptyStateView('));
      expect(source, contains('onRetry: () => ref.invalidate(rewardHistoryProvider)'));
    });

    test('referral_screen.dart uses ErrorStateView for its top-level '
        'error branch', () {
      final source = _read('lib/referral_screen.dart');
      expect(source, contains('ErrorStateView('));
      expect(source, contains('onRetry: () => ref.invalidate(referralInfoProvider)'));
    });
  });
}
