// ============================================================
// lib/widgets/app_card.dart — LinTho
// ▸ [PHASE1] ThemeData.cardTheme ມີຢູ່ແລ້ວ (surface, flat, 6% shadow, card
//   radius) ແຕ່ຫຼາຍໜ້າຈໍບໍ່ໄດ້ໃຊ້ Card ກົງໆ — ຫຸ້ມ Container ດ້ວຍ radius/shadow
//   ຂອງຕົນເອງແທນ (ຕົວຢ່າງ: booking_detail_screen.dart's `_card()` helper —
//   radius 18, custom 4%-opacity shadow, ຄົນລະຄ່າກັບ theme). AppCard ຫຸ້ມ
//   Card ຄືເກົ່າ ບໍ່ໃຫ້ໜ້າຈໍໃໝ່ຄິດ radius/shadow ເອງອີກ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double? radius;
  final Border? border;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.radius,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
      side: border?.top ?? BorderSide.none,
    );

    return Card(
      color: color,
      shape: shape,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          // ✅ RULE: InkWell + Material ທຸກ tap target — ບໍ່ໃຊ້ GestureDetector
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}
