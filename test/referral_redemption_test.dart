// ============================================================
// referral_redemption_test.dart — LinTho App
//
// Regression test for FOLLOWUP-G: redeemReferralCode() (referral_provider.dart)
// did a plain get()-then-set() with no transaction — two concurrent calls
// could both read referredBy==null before either wrote, letting a user
// redeem twice (only one write "wins" but neither call sees the other's
// result at check time, so both report success).
//
// ໝາຍເຫດ: redeemReferralCode() ໃຊ້ FirebaseFirestore.instance/FirebaseAuth.instance
// ໂດຍກົງ (ບໍ່ໄດ້ inject) — ຄືກັນກັບ CouponRepository — ຈຶ່ງ reproduce ພຽງແຕ່
// transaction logic ຂຶ້ນມາທົດສອບແທນ (ຖ້າແກ້ logic ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ).
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  // ▸ ຄັດລອກ transaction body ຈາກ redeemReferralCode() (referral_provider.dart)
  Future<String?> redeemInTransaction(
      FakeFirebaseFirestore db, String uid, String code) async {
    final userRef = db.collection('users').doc(uid);
    String? error;
    await db.runTransaction((tx) async {
      final userDoc = await tx.get(userRef);
      if (userDoc.data()?['referredBy'] != null) {
        error = 'ທ່ານໃຊ້ໂຄ້ດແນະນຳໄປແລ້ວ';
        return;
      }
      tx.set(userRef, {'referredBy': code}, SetOptions(merge: true));
    });
    return error;
  }

  group('FOLLOWUP-G: redeemReferralCode() is transaction-guarded', () {
    test('first redemption succeeds and sets referredBy', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('user-1').set({});

      final result = await redeemInTransaction(db, 'user-1', 'LINTHOABCDE');
      expect(result, isNull);

      final doc = await db.collection('users').doc('user-1').get();
      expect(doc.data()?['referredBy'], 'LINTHOABCDE');
    });

    test('a second redemption after the first is committed is rejected '
        'and does not overwrite the original code', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('user-1').set({});

      final first = await redeemInTransaction(db, 'user-1', 'LINTHOABCDE');
      expect(first, isNull);

      final second = await redeemInTransaction(db, 'user-1', 'LINTHOZZZZZ');
      expect(second, 'ທ່ານໃຊ້ໂຄ້ດແນະນຳໄປແລ້ວ');

      final doc = await db.collection('users').doc('user-1').get();
      expect(doc.data()?['referredBy'], 'LINTHOABCDE',
          reason: 'the original code must not be overwritten by a later, '
              'rejected redemption attempt');
    });

    test('source still wraps the check-then-write in runTransaction', () {
      final source = _read('lib/referral_provider.dart');
      final start = source.indexOf('Future<String?> redeemReferralCode(');
      expect(start, greaterThan(-1));
      final block = source.substring(start);
      expect(block, contains('db.runTransaction('));
      expect(block, contains('tx.get(userRef)'));
      expect(block, contains('tx.set(userRef,'));
    });
  });
}
