import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_locale.dart';
import 'booking_provider.dart' show currentUidProvider;

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
// 🔒 [ADDR-1, Batch K, 2026-08-25] see savedAddressesProvider
// (saved_address.dart) for the full rationale — ref.watch(currentUidProvider)
// forces a rebuild (fresh uid, old vouchers listener torn down) on a
// same-process account switch.
//
// Residual, accepted characteristic (not a cross-user leak): if
// _ensureReferralCode(uid) below is already mid-flight (awaiting its
// Firestore transaction) when the uid changes, Dart's Future has no
// cancellation primitive — that write completes regardless of whether this
// provider has since rebuilt. It is harmless because `uid` is captured by
// value in that specific builder invocation's closure and never mutates:
// the write can only ever land on that SAME (now-previous) user's own
// users/{uid}/referralCodes documents — it can never be misattributed to
// whichever user is signed in by the time it completes.
final referralInfoProvider = StreamProvider<ReferralInfo?>((ref) {
  ref.watch(currentUidProvider);
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
  throw Exception(tr('referral_code_gen_failed'));
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
  if (uid == null) return tr('referral_login_required');
  final db = FirebaseFirestore.instance;
  final code = inputCode.trim().toUpperCase();
  if (code.isEmpty) return tr('referral_enter_code_required');

  final lookup = await db.collection('referralCodes').doc(code).get();
  if (!lookup.exists) return tr('referral_code_invalid');
  if (lookup.data()?['ownerUid'] == uid) return tr('referral_cannot_use_own_code');

  final userRef = db.collection('users').doc(uid);
  String? error;
  await db.runTransaction((tx) async {
    final userDoc = await tx.get(userRef);
    if (userDoc.data()?['referredBy'] != null) {
      error = tr('referral_already_used');
      return;
    }
    tx.set(userRef, {'referredBy': code}, SetOptions(merge: true));
  });
  return error;
}
