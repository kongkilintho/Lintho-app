// ============================================================
// coupon_list_screen.dart — LinTho Customer App
// ສະແດງລາຍການຄູປອງສ່ວນຫຼຸດຂອງ user ນີ້ (query `coupons` where
// ownerId == uid) — ຄູປອງຖືກສ້າງໂດຍ Cloud Function
// `onRewardRedemptionRequested` (functions/index.js) ຕອນແລກແຕ້ມ.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'coupon_repository.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/error_state_view.dart';
import 'widgets/skeleton_box.dart';

class CouponListScreen extends ConsumerWidget {
  const CouponListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(myCouponsProvider);

    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        title: Text(tr('coupons_title')),
      ),
      body: couponsAsync.when(
        // ✅ [FIX — shared components] ເຄີຍ CircularProgressIndicator ດຽວ,
        // ບໍ່ກົງກັບຮູບແບບ skeleton ທີ່ອື່ນໆໃນແອັບໃຊ້; error ເຄີຍເປັນຂໍ້ຄວາມ
        // ດິບ ('ໂຫລດຄູປອງບໍ່ໄດ້: $e') ບໍ່ມີປຸ່ມລອງໃໝ່; empty ເຄີຍເປັນ
        // ຂໍ້ຄວາມສີເທົາທຳມະດາ ອ່ອນກວ່າໜ້າອື່ນໆໃນແອັບຫຼາຍ.
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 4,
          itemBuilder: (_, __) => const SkeletonListTile(leadingSize: 40),
        ),
        error: (_, __) => ErrorStateView(
            onRetry: () => ref.invalidate(myCouponsProvider)),
        data: (coupons) {
          if (coupons.isEmpty) {
            return EmptyStateView(
              icon: Icons.local_offer_outlined,
              title: tr('no_coupons'),
              accent: C.orange,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: coupons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _CouponCard(coupon: coupons[i]),
          );
        },
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final MyCoupon coupon;
  const _CouponCard({required this.coupon});

  bool get _expired =>
      coupon.validUntil != null && DateTime.now().isAfter(coupon.validUntil!);

  String get _valueLabel => coupon.type == 'percentage'
      ? 'ຫຼຸດ ${coupon.value}%'
      : 'ຫຼຸດ ${coupon.value.toStringAsFixed(0)} ກີບ';

  @override
  Widget build(BuildContext context) {
    final active = coupon.status == 'active' && !_expired;
    return Opacity(
      opacity: active ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.border, width: 1)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: C.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.local_offer_rounded, color: C.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_valueLabel, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
            const SizedBox(height: 2),
            Text(
              _expired ? 'ໝົດອາຍຸແລ້ວ' : (coupon.status != 'active' ? 'ໃຊ້ໄປແລ້ວ' : 'ໃຊ້ໄດ້ຈົນຮອດ ${coupon.validUntil != null ? '${coupon.validUntil!.day}/${coupon.validUntil!.month}/${coupon.validUntil!.year}' : '-'}'),
              style: const TextStyle(fontSize: 12, color: C.muted),
            ),
          ])),
          const SizedBox(width: 8),
          InkWell(
            onTap: active ? () {
              Clipboard.setData(ClipboardData(text: coupon.code));
              ScaffoldMessenger.of(context).showSnackBar(
                  // 🔒 [AUDIT UI-10 / 2026-08-02]
                  SnackBar(content: Text(tr('copied_to_clipboard'))));
            } : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: C.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(coupon.code, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: C.navy, letterSpacing: 1)),
            ),
          ),
        ]),
      ),
    );
  }
}
