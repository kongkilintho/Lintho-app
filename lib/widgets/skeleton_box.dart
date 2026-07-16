// ============================================================
// lib/widgets/skeleton_box.dart — LinTho
// ▸ ກ່ອນໜ້ານີ້ ~20 ຈຸດທົ່ວແອັບຂຽນ AnimationController + Tween<double> +
//   dispose() ຂອງຕົນເອງສຳລັບ skeleton/shimmer ດຽວກັນ, ຄົນລະໄລຍະເວລາ
//   (600/700/800/900/1000ms) — ທັງໆທີ່ lib/widgets/pulsing_fade.dart ມີແລ້ວ.
//   SkeletonBox ນີ້ຄື primitive ດຽວທີ່ຄວນໃຊ້ແທນ: ສ້າງຈາກ PulsingFade,
//   ໄລຍະເວລາ/ຄ່າ opacity ຄົງທີ່ດຽວກັນທົ່ວແອັບ.
// ============================================================

import 'package:flutter/material.dart';
import 'pulsing_fade.dart';
import '../theme/app_theme.dart';

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color? color;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppRadius.chip,
    this.color,
  });

  const SkeletonBox.circle({super.key, required double diameter, this.color})
      : width = diameter, height = diameter, radius = 9999;

  @override
  Widget build(BuildContext context) {
    return PulsingFade(
      duration: const Duration(milliseconds: 900),
      begin: 0.35,
      end: 0.85,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AppColors.border,
          borderRadius: radius >= 9999
              ? null
              : BorderRadius.circular(radius),
          shape: radius >= 9999 ? BoxShape.circle : BoxShape.rectangle,
        ),
      ),
    );
  }
}

/// ແຖວ skeleton card ທົ່ວໄປ — ຮູບ + ບັນທັດຂໍ້ຄວາມ 2 ແຖວ, ຮູບແບບການ໌ໃຊ້ຫຼາຍ
/// ທີ່ສຸດ (booking card / job card / transaction row).
class SkeletonListTile extends StatelessWidget {
  final double leadingSize;
  const SkeletonListTile({super.key, this.leadingSize = 50});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Row(children: [
        SkeletonBox(width: leadingSize, height: leadingSize, radius: AppRadius.chip),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 140, height: 13, radius: 4),
            SizedBox(height: 7),
            SkeletonBox(width: 90, height: 10, radius: 4),
          ],
        )),
      ]),
    );
  }
}
