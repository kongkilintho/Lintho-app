// ============================================================
// coupon_repository.dart — LinTho Customer App
// ກວດ/ໃຊ້ coupon code ຕອນຈອງ — `coupons/{code}` doc ID = code ເລີຍ
// (admin ສ້າງຜ່ານ lintho-admin Promotions page), ເບິ່ງ
// lintho-admin/src/types/index.ts → `Coupon`.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyCoupon {
  final String code;
  final String type; // 'percentage' | 'fixed'
  final num value;
  final num? maxDiscount;
  final String status;
  final DateTime? validUntil;

  const MyCoupon({
    required this.code,
    required this.type,
    required this.value,
    required this.status,
    this.maxDiscount,
    this.validUntil,
  });

  factory MyCoupon.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return MyCoupon(
      code: doc.id,
      type: d['type'] as String? ?? 'fixed',
      value: (d['value'] as num?) ?? 0,
      maxDiscount: d['maxDiscount'] as num?,
      status: d['status'] as String? ?? 'inactive',
      validUntil: (d['validUntil'] as Timestamp?)?.toDate(),
    );
  }
}

/// ລາຍການຄູປອງຂອງ user ນີ້ (ownerId == uid) — ໃຊ້ໃນ [CouponListScreen]
/// ແລະ badge ຢູ່ໜ້າ Profile.
final myCouponsProvider = StreamProvider<List<MyCoupon>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('coupons')
      .where('ownerId', isEqualTo: uid)
      .snapshots()
      .map((snap) => snap.docs.map(MyCoupon.fromDoc).toList());
});

/// ຈຳນວນຄູປອງທີ່ຍັງໃຊ້ໄດ້ (active ແລະ ຍັງບໍ່ໝົດອາຍຸ) — ໃຊ້ສະແດງເລກ badge.
final myCouponCountProvider = Provider<int>((ref) {
  final coupons = ref.watch(myCouponsProvider).value ?? const [];
  final now = DateTime.now();
  return coupons.where((c) =>
      c.status == 'active' &&
      (c.validUntil == null || now.isBefore(c.validUntil!))).length;
});

class CouponResult {
  final String code;
  final String type; // 'percentage' | 'fixed'
  final num value;
  final num? maxDiscount;
  final num discountAmount;

  const CouponResult({
    required this.code,
    required this.type,
    required this.value,
    required this.discountAmount,
    this.maxDiscount,
  });
}

class CouponRepository {
  CouponRepository._();
  static final CouponRepository instance = CouponRepository._();

  final _db = FirebaseFirestore.instance;

  /// ກວດ coupon code — return `null` ຖ້າບໍ່ຖືກຕ້ອງ/ໝົດອາຍຸ/ໃຊ້ໝົດແລ້ວ/
  /// ບໍ່ກົງເງື່ອນໄຂຍອດສັ່ງຊື້ຂັ້ນຕ່ຳ, ບໍ່ throw (offline-safe).
  Future<CouponResult?> validate(String code, num orderAmount) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    try {
      final doc = await _db.collection('coupons').doc(normalized).get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;

      final status = d['status'] as String? ?? 'inactive';
      if (status != 'active') return null;

      final now = DateTime.now();
      final validFrom = (d['validFrom'] as Timestamp?)?.toDate();
      final validUntil = (d['validUntil'] as Timestamp?)?.toDate();
      if (validFrom != null && now.isBefore(validFrom)) return null;
      if (validUntil != null && now.isAfter(validUntil)) return null;

      final usageLimit = d['usageLimit'] as num?;
      final usedCount = (d['usedCount'] as num?) ?? 0;
      if (usageLimit != null && usedCount >= usageLimit) return null;

      final minOrderAmount = d['minOrderAmount'] as num?;
      if (minOrderAmount != null && orderAmount < minOrderAmount) return null;

      final type = d['type'] as String? ?? 'fixed';
      final value = (d['value'] as num?) ?? 0;
      final maxDiscount = d['maxDiscount'] as num?;

      num discount;
      if (type == 'percentage') {
        discount = orderAmount * value / 100;
        if (maxDiscount != null && discount > maxDiscount) discount = maxDiscount;
      } else {
        discount = value;
      }
      if (discount > orderAmount) discount = orderAmount;

      return CouponResult(
        code: normalized,
        type: type,
        value: value,
        maxDiscount: maxDiscount,
        discountAmount: discount,
      );
    } catch (_) {
      return null;
    }
  }

  /// ເພີ່ມ `usedCount` ຂອງ coupon +1 — ໃຊ້ໃນ WriteBatch ດຽວກັນກັບການ
  /// ສ້າງ booking (atomic, ບໍ່ໃຫ້ coupon ຖືກນັບໃຊ້ໂດຍບໍ່ມີ booking ຄູ່ກັນ).
  void incrementUsage(WriteBatch batch, String code) {
    final ref = _db.collection('coupons').doc(code.trim().toUpperCase());
    batch.update(ref, {'usedCount': FieldValue.increment(1)});
  }
}
