// ============================================================
// bcel_payment_confirmation_test.dart — LinTho App
//
// Regression test for FOLLOWUP-K: payment confirmation was fully
// self-attested by the provider (confirmPaymentReceived()) with no
// counter-signature from the customer, even for BCEL (bank transfer)
// bookings — a provider could unilaterally claim a transfer was received
// to trigger their own wallet credit. Cash stays self-attested (accepted
// limitation, no payment gateway); BCEL now requires the customer to tap
// "confirm payment sent" first.
// ============================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  // ▸ ຄັດລອກ logic ຈາກ BookingRepository.confirmPaymentReceived()
  //   (booking_repository.dart) — ຖ້າແກ້ logic ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
  Future<void> confirmPaymentReceived(
      FakeFirebaseFirestore db, String bookingId, String providerUid) async {
    final ref = db.collection('bookings').doc(bookingId);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final b = snap.data()!;
      if (b['providerId'] != providerUid) {
        throw Exception('ທ່ານບໍ່ແມ່ນຊ່າງທີ່ຮັບຜິດຊອບງານນີ້');
      }
      if (b['paymentStatus'] == 'paid') return;
      final paymentMethod = b['paymentMethod'] as String? ?? 'cash';
      final customerConfirmedPayment =
          b['customerConfirmedPayment'] as bool? ?? false;
      if (paymentMethod != 'cash' && !customerConfirmedPayment) {
        throw Exception('ລໍຖ້າລູກຄ້າຢືນຢັນການໂອນເງິນກ່ອນຈຶ່ງຈະປິດງານໄດ້');
      }
      tx.update(ref, {'paymentStatus': 'paid'});
    });
  }

  group('FOLLOWUP-K: confirmPaymentReceived() requires customer '
      'counter-confirmation for non-cash bookings', () {
    test('a BCEL booking without customerConfirmedPayment is rejected',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'providerId': 'provider-1',
        'paymentMethod': 'bcel',
        'paymentStatus': 'pending',
        'customerConfirmedPayment': false,
      });

      await expectLater(
          confirmPaymentReceived(db, 'b1', 'provider-1'), throwsException);

      final doc = await db.collection('bookings').doc('b1').get();
      expect(doc.data()?['paymentStatus'], 'pending',
          reason: 'the provider must not be able to unilaterally mark a '
              'BCEL payment as paid');
    });

    test('a BCEL booking with customerConfirmedPayment succeeds', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'providerId': 'provider-1',
        'paymentMethod': 'bcel',
        'paymentStatus': 'pending',
        'customerConfirmedPayment': true,
      });

      await confirmPaymentReceived(db, 'b1', 'provider-1');

      final doc = await db.collection('bookings').doc('b1').get();
      expect(doc.data()?['paymentStatus'], 'paid');
    });

    test('a cash booking succeeds regardless of customerConfirmedPayment '
        '(accepted limitation — no payment gateway)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'providerId': 'provider-1',
        'paymentMethod': 'cash',
        'paymentStatus': 'pending',
        'customerConfirmedPayment': false,
      });

      await confirmPaymentReceived(db, 'b1', 'provider-1');

      final doc = await db.collection('bookings').doc('b1').get();
      expect(doc.data()?['paymentStatus'], 'paid');
    });
  });

  group('FOLLOWUP-K: source and rules wiring', () {
    test('booking_repository.dart still contains the gate', () {
      final source = _read('lib/booking_repository.dart');
      final start = source.indexOf('Future<void> confirmPaymentReceived(');
      final end = source.indexOf('Future<void> updateStatus(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains("b.paymentMethod != 'cash'"));
      expect(block, contains('!b.customerConfirmedPayment'));
    });

    test('CustomerBookingRepository exposes confirmPaymentSent()', () {
      final source = _read('lib/booking_repository.dart');
      expect(source, contains('Future<void> confirmPaymentSent('));
      expect(source, contains("'customerConfirmedPayment': true"));
    });

    test('firestore.rules allows the customer to write '
        'customerConfirmedPayment on their own booking', () {
      final rules = _read('firestore.rules');
      final start = rules.indexOf('match /bookings/{bookingId}');
      final end = rules.indexOf('match /providers/{providerId}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(block, contains('customerConfirmedPayment'));
    });

    test('Booking model round-trips paymentMethod and '
        'customerConfirmedPayment', () {
      final booking = Booking(
        id: 'b1', customerId: 'c1', customerName: 'x', customerPhone: 'x',
        providerId: 'p1', serviceType: 'x', serviceEmoji: '🔧',
        address: 'x', location: const GeoPoint(0, 0),
        scheduledAt: DateTime.now(), status: JobStatus.inProgress,
        price: 0, createdAt: DateTime.now(), expiresAt: DateTime.now(),
        paymentMethod: 'bcel', customerConfirmedPayment: true,
      );
      final map = booking.toMap();
      expect(map['paymentMethod'], 'bcel');
      expect(map['customerConfirmedPayment'], true);
    });
  });
}
