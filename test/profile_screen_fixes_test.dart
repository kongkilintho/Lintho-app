// ============================================================
// profile_screen_fixes_test.dart — LinTho App
//
// Regression tests for the Profile-screen no-op fixes:
//   FOLLOWUP-I1 — the "bookings" stat is a real aggregate count, not the
//                 literal '5'
//   FOLLOWUP-I2 — "Manage Addresses" reads/writes the real
//                 users/{uid}/addresses subcollection via
//                 savedAddressesProvider, instead of two hardcoded entries
//   FOLLOWUP-I3 — notification toggles persist to users/{uid}.notifPrefs
//   FOLLOWUP-I4 — "Delete Account" calls the new deleteOwnAccount callable
//                 Cloud Function and actually signs the user out
// ============================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('FOLLOWUP-I1: customerBookingCountProvider counts real bookings',
      () {
    // ▸ ຄັດລອກ query logic ຈາກ customerBookingCountProvider
    //   (booking_provider.dart) — ຖ້າແກ້ logic ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<int> countBookings(FakeFirebaseFirestore db, String uid) async {
      final agg = await db
          .collection('bookings')
          .where('customerId', isEqualTo: uid)
          .count()
          .get();
      return agg.count ?? 0;
    }

    test('counts only the current customer\'s bookings', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').add({'customerId': 'user-1'});
      await db.collection('bookings').add({'customerId': 'user-1'});
      await db.collection('bookings').add({'customerId': 'user-2'});

      expect(await countBookings(db, 'user-1'), 2);
      expect(await countBookings(db, 'user-2'), 1);
      expect(await countBookings(db, 'user-3'), 0);
    });

    test('main.dart no longer hardcodes the literal bookings count', () {
      final source = _read('lib/main.dart');
      expect(source, isNot(contains("'5', tr('bookings_count_label')")));
      expect(source, contains('customerBookingCountProvider'));
    });
  });

  group('FOLLOWUP-I2: Manage Addresses reads/writes real data', () {
    final source = _read('lib/main.dart');

    test('_showAddr no longer shows the two hardcoded fake addresses', () {
      final start = source.indexOf('void _showAddr(');
      final end = source.indexOf('void _showNotif(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, isNot(contains('ບ້ານໂພນສິມ')));
      expect(block, isNot(contains('ດາວຄຳ')));
      expect(block, contains('savedAddressesProvider'));
    });

    test('"add new address" actually writes to Firestore instead of just '
        'popping the sheet', () {
      final start = source.indexOf('void _showAddr(');
      final end = source.indexOf('void _showNotif(');
      final block = source.substring(start, end);
      expect(block, contains("collection('addresses').add("));
      expect(block, contains('MapPickerScreen'));
    });
  });

  group('FOLLOWUP-I3: notification toggles persist to notifPrefs', () {
    final source = _read('lib/main.dart');

    test('_showNotif no longer has a no-op onChanged', () {
      final start = source.indexOf('void _showNotif(');
      final end = source.indexOf('void _showHelp(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, isNot(contains('onChanged: (_) {}')));
      expect(block, contains("'notifPrefs'"));
    });

    test('toggle writes merge into users/{uid} without clobbering other '
        'prefs (fake_cloud_firestore reproduction)', () async {
      final db = FakeFirebaseFirestore();
      final userRef = db.collection('users').doc('user-1');
      await userRef.set({'notifPrefs': {'newBooking': true}});

      await userRef.set({'notifPrefs': {'promo': true}}, SetOptions(merge: true));

      final doc = await userRef.get();
      final prefs = doc.data()?['notifPrefs'] as Map<String, dynamic>;
      expect(prefs['newBooking'], true,
          reason: 'a merge-set on a nested map key must not drop sibling keys');
      expect(prefs['promo'], true);
    });
  });

  group('FOLLOWUP-I4: Delete Account calls the real deletion flow', () {
    test('_confirmDeleteAccount calls deleteOwnAccount and signs out '
        '(not just Navigator.pop)', () {
      final source = _read('lib/main.dart');
      final start = source.indexOf('void _confirmDeleteAccount(');
      final end = source.indexOf('void _showSecurity(');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains("httpsCallable('deleteOwnAccount')"));
      expect(block, contains('FirebaseAuth.instance.signOut()'));
    });

    test('functions/index.js defines deleteOwnAccount, self-scoped via '
        'context.auth.uid', () {
      final source = _read('functions/index.js');
      final start = source.indexOf('exports.deleteOwnAccount');
      expect(start, greaterThan(-1));
      final end = source.indexOf('\n});', start);
      final block = source.substring(start, end);
      expect(block, contains('context.auth.uid'));
      expect(block, contains('admin.auth().deleteUser('));
      expect(block, contains("collection('addresses')"),
          reason: 'must clean up the addresses subcollection too, not just '
              'the top-level user doc');
    });
  });
}
