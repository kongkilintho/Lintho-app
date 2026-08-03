import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReferralInfo {
  final String code;
  final int    referredCount;
  final double totalEarnedFromReferrals;

  const ReferralInfo({
    required this.code,
    this.referredCount = 0,
    this.totalEarnedFromReferrals = 0,
  });
}

// 🔒 [AUDIT M-15 / 2026-07-27] ກ່ອນໜ້ານີ້ provider ນີ້ listen
// users/{uid}.snapshots() ແລ້ວ re-query vouchers sub-collection ທຸກຄັ້ງທີ່
// doc ນັ້ນປ່ຽນ — ບໍ່ວ່າຈະປ່ຽນຍ້ອນເຫດຜົນຫຍັງກໍຕາມ (ຕົວຢ່າງ: rewardPoints
// ອັບເດດຈາກ booking ອື່ນທີ່ບໍ່ກ່ຽວກັບ referral ເລີຍ). ຕອນນີ້ listen
// vouchers sub-collection ໂດຍກົງແທນ (ຍິງສະເພາະຕອນມີ referral voucher ໃໝ່
// ຈິງໆ), ແລ້ວອ່ານ referralCode ຄັ້ງດຽວຕໍ່ event ນັ້ນ (ບໍ່ແມ່ນ live-listen
// users/{uid} ອີກຕໍ່ໄປ) — ໄດ້ຜົນດີກວ່າເກົ່ານຳ: ຍອດຮວມຈະອັບເດດແທ້ຕອນມີ
// voucher ໃໝ່ (ບໍ່ແມ່ນອາໄສ side-effect ບັງເອີນຂອງ user-doc write ຄືເກົ່າ).
final referralInfoProvider = StreamProvider<ReferralInfo?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  final db = FirebaseFirestore.instance;

  return db
      .collection('wallets').doc(uid).collection('vouchers')
      .where('reason', isEqualTo: 'referral_reward')
      .limit(500)
      .snapshots()
      .asyncMap((vouchers) async {
    final userDoc = await db.collection('users').doc(uid).get();
    var code = userDoc.data()?['referralCode'] as String?;
    code ??= await _ensureReferralCode(uid);

    final total = vouchers.docs.fold<double>(
        0, (acc, d) => acc + (d.data()['amount'] as num).toDouble());

    return ReferralInfo(
      code: code,
      referredCount: vouchers.docs.length,
      totalEarnedFromReferrals: total,
    );
  });
});

// 🔒 [AUDIT BE-7 / 2026-08-02 — Low, fresh re-audit] referralCodes/{code} has
// no uniqueness pre-check — firestore.rules' `allow update, delete: if false`
// safely rejects a genuine collision (no silent overwrite of another user's
// code), but that rejection previously surfaced as a raw permission-denied
// exception straight to the caller, with no retry. At ~39M possible codes
// (33 chars ^ 5) a collision is rare but not impossible as the user base
// grows. Bounded retry with a freshly generated code on each collision.
Future<String> _ensureReferralCode(String uid) async {
  final db = FirebaseFirestore.instance;
  const maxAttempts = 5;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final code = 'LINTHO${_randomSuffix()}';
    try {
      await db.runTransaction((tx) async {
        tx.set(db.collection('users').doc(uid), {'referralCode': code},
            SetOptions(merge: true));
        tx.set(db.collection('referralCodes').doc(code), {'ownerUid': uid});
      });
      return code;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' || attempt == maxAttempts) rethrow;
      // collision — loop again with a new random suffix
    }
  }
  throw Exception('ບໍ່ສາມາດສ້າງລະຫັດແນະນຳໄດ້, ກະລຸນາລອງໃໝ່');
}

String _randomSuffix() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(5, (_) => chars[rnd.nextInt(chars.length)]).join();
}

/// ໃຊ້ໂຄ້ດໝູ່ — ບັນທຶກ referredBy ໃສ່ users/{uid}, Cloud Function ຈະອອກ voucher
/// ໃຫ້ຕອນສ້າງ booking ທຳອິດ (ເບິ່ງ functions/index.js: onNewBooking).
/// Return null = success, ບໍ່ດັ່ງນັ້ນ return error message.
///
/// 🔒 [FOLLOWUP-G] ກ່ອນໜ້ານີ້ check-then-act ນີ້ (get() referredBy ແລ້ວຄ່ອຍ set())
/// ບໍ່ໄດ້ຢູ່ໃນ transaction — ສອງການເອີ້ນພ້ອມກັນ (double-tap) ອາດອ່ານ
/// referredBy==null ພ້ອມກັນທັງສອງ ແລ້ວທັງສອງຂຽນທັບກັນໄດ້. ຕອນນີ້ໃຊ້
/// runTransaction ຄືກັນກັບ _ensureReferralCode() ຂ້າງເທິງ, re-read referredBy
/// ຢູ່ພາຍໃນ transaction ກ່ອນຂຽນ.
Future<String?> redeemReferralCode(String inputCode) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 'ກະລຸນາ login ກ່ອນ';
  final db = FirebaseFirestore.instance;
  final code = inputCode.trim().toUpperCase();
  if (code.isEmpty) return 'ກະລຸນາໃສ່ໂຄ້ດ';

  final lookup = await db.collection('referralCodes').doc(code).get();
  if (!lookup.exists) return 'Referral code ບໍ່ຖືກຕ້ອງ';
  if (lookup.data()?['ownerUid'] == uid) return 'ບໍ່ສາມາດໃຊ້ໂຄ້ດຂອງຕົນເອງໄດ້';

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
