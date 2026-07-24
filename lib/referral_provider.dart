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

final referralInfoProvider = StreamProvider<ReferralInfo?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  final db = FirebaseFirestore.instance;

  return db.collection('users').doc(uid).snapshots().asyncMap((snap) async {
    var code = snap.data()?['referralCode'] as String?;
    code ??= await _ensureReferralCode(uid);

    final vouchers = await db
        .collection('wallets').doc(uid).collection('vouchers')
        .where('reason', isEqualTo: 'referral_reward')
        .get();
    final total = vouchers.docs.fold<double>(
        0, (acc, d) => acc + (d.data()['amount'] as num).toDouble());

    return ReferralInfo(
      code: code,
      referredCount: vouchers.docs.length,
      totalEarnedFromReferrals: total,
    );
  });
});

Future<String> _ensureReferralCode(String uid) async {
  final db = FirebaseFirestore.instance;
  final code = 'LINTHO${_randomSuffix()}';
  await db.runTransaction((tx) async {
    tx.set(db.collection('users').doc(uid), {'referralCode': code},
        SetOptions(merge: true));
    tx.set(db.collection('referralCodes').doc(code), {'ownerUid': uid});
  });
  return code;
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
