// ============================================================
// rewards_provider.dart — LinTho Customer App
// ອ່ານ/ໃຊ້ rewardPoints ຂອງລູກຄ້າ — balance ຢູ່ `users/{uid}.rewardPoints`,
// ປະຫວັດຢູ່ collection `rewardTransactions`, ເງື່ອນໄຂ earn/redeem ຢູ່
// `settings/rewards` (admin ຕັ້ງຜ່ານ lintho-admin/src/app/rewards/page.tsx).
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'booking_provider.dart' show currentUidProvider;

class RewardSettings {
  final double earnRatePercent;
  final int    pointsExpiryDays;
  final num    redeemRate;      // ກີບຕໍ່ 1 ແຕ້ມ ຕອນແລກເປັນຄູປອງ
  final int    minRedeemPoints; // ຈຳນວນແຕ້ມຂັ້ນຕ່ຳທີ່ແລກໄດ້

  const RewardSettings({
    this.earnRatePercent  = 1,
    this.pointsExpiryDays = 365,
    this.redeemRate       = 100,
    this.minRedeemPoints  = 100,
  });

  factory RewardSettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const RewardSettings();
    return RewardSettings(
      earnRatePercent:  (d['earnRatePercent']  as num?)?.toDouble() ?? 1,
      pointsExpiryDays: (d['pointsExpiryDays'] as num?)?.toInt()    ?? 365,
      redeemRate:       (d['redeemRate']       as num?)             ?? 100,
      minRedeemPoints:  (d['minRedeemPoints']  as num?)?.toInt()    ?? 100,
    );
  }
}

class RewardTransaction {
  final String    id;
  final String    type; // 'earn' | 'redeem' | 'manual_add' | 'manual_subtract' | 'expire'
  final int       points;
  final String?   reason;
  final DateTime? createdAt;

  const RewardTransaction({
    required this.id,
    required this.type,
    required this.points,
    this.reason,
    this.createdAt,
  });

  factory RewardTransaction.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return RewardTransaction(
      id: doc.id,
      type: d['type'] as String? ?? 'earn',
      points: (d['points'] as num?)?.toInt() ?? 0,
      reason: d['reason'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// ແຕ້ມຄົງເຫຼືອແບບ real-time — ໃຊ້ໃນໜ້າ Profile stat ແລະ Rewards screen.
// 🔒 [ADDR-1, Batch K, 2026-08-25] see savedAddressesProvider (saved_address.dart)
// for the full rationale — ref.watch(currentUidProvider) forces a rebuild
// (fresh uid read, old listener torn down) on a same-process account switch.
final rewardPointsProvider = StreamProvider<int>((ref) {
  ref.watch(currentUidProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
      .map((s) => (s.data()?['rewardPoints'] as num?)?.toInt() ?? 0);
});

/// ເງື່ອນໄຂ earn/redeem ທີ່ admin ຕັ້ງໄວ້ — ໃຊ້ກວດກ່ອນອະນຸຍາດແລກຄູປອງ.
final rewardSettingsProvider = StreamProvider<RewardSettings>((ref) {
  return FirebaseFirestore.instance.collection('settings').doc('rewards')
      .snapshots().map((s) => RewardSettings.fromMap(s.data()));
});

// 🔒 [AUDIT PERF-2 / 2026-08-02 — Medium, fresh re-audit] ບໍ່ເຄີຍມີ .limit()
// ຢູ່ query ນີ້ — sort ຢູ່ client-side (list.sort()) ຫຼັງດຶງມາໝົດແລ້ວ. ລູກຄ້າ
// ທີ່ມີປະຫວັດແຕ້ມຫຼາຍຮ້ອຍລາຍການຈະດາວໂຫຼດ/hold ໄວ້ໃນ memory ໝົດທຸກຄັ້ງ, ແລະ ຖືກ
// sync ຄືນທຸກຄັ້ງທີ່ມີ doc ໃໝ່. ຍ້າຍ sort ໄປໃສ່ query ເອງ (orderBy + limit) —
// ຕ້ອງການ composite index (userId Asc, createdAt Desc), ເບິ່ງ
// firestore.indexes.json.
/// ປະຫວັດແຕ້ມ (earn/redeem/manual) ຮຽງລຳດັບໃໝ່ສຸດກ່ອນ.
// 🔒 [ADDR-1, Batch K, 2026-08-25] same rebuild-on-account-switch fix as
// rewardPointsProvider above.
final rewardHistoryProvider = StreamProvider<List<RewardTransaction>>((ref) {
  ref.watch(currentUidProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('rewardTransactions')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(RewardTransaction.fromDoc).toList());
});

class RedeemResult {
  final String? couponCode;
  final String? error;
  const RedeemResult({this.couponCode, this.error});
}

/// ແລກແຕ້ມເປັນຄູປອງສ່ວນຫຼຸດ — client ບໍ່ສາມາດສ້າງ coupon ຫຼື ຫັກແຕ້ມຕົນເອງໂດຍກົງ
/// (firestore.rules ປິດໄວ້ ກັນລູກຄ້າປອມຍອດ) ດັ່ງນັ້ນພຽງສ້າງ request doc ໃນ
/// `rewardRedemptions`, ແລ້ວ Cloud Function `onRewardRedemptionRequested`
/// (functions/index.js) ກວດ `settings/rewards` + ຍອດແຕ້ມ ແລະ ດຳເນີນການ
/// ແບບ atomic ດ້ວຍ Admin SDK ກ່ອນອັບເດດ doc ນີ້ກັບຜົນ.
Future<RedeemResult> redeemPointsForCoupon(int points) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const RedeemResult(error: 'ກະລຸນາ login ກ່ອນ');
  if (points <= 0) return const RedeemResult(error: 'ຈຳນວນແຕ້ມບໍ່ຖືກຕ້ອງ');

  final db = FirebaseFirestore.instance;
  final reqRef = db.collection('rewardRedemptions').doc();

  try {
    await reqRef.set({
      'userId': uid,
      'points': points,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ລໍຖ້າ Cloud Function ປະມວນຜົນ (ປະກິດໄວໃນວິນາທີ) — timeout 20s ປ້ອງກັນ
    // ກໍລະນີ function ລົ້ມເຫລວ/ຊ້າຜິດປົກກະຕິ
    final result = await reqRef.snapshots()
        .where((s) => s.data()?['status'] != 'pending')
        .first
        .timeout(const Duration(seconds: 20));

    final data = result.data();
    if (data?['status'] == 'completed') {
      return RedeemResult(couponCode: data?['couponCode'] as String?);
    }
    return RedeemResult(error: data?['error'] as String? ?? 'ແລກແຕ້ມບໍ່ສຳເລັດ');
  } catch (_) {
    return const RedeemResult(error: 'ໝົດເວລາລໍຖ້າ — ກະລຸນາກວດປະຫວັດແຕ້ມຄືນພາຍຫຼັງ');
  }
}
