// ============================================================
// lib/widgets/app_section.dart — LinTho
// ▸ [PHASE1] ທຸກໜ້າຈໍຂຽນ section header (ຫົວຂໍ້ + "ເບິ່ງທັງໝົດ" ບາງບ່ອນ) ດ້ວຍ
//   Row/Text ຂອງຕົນເອງຊ້ຳໆ, ບາງບ່ອນໃຊ້ emoji ເປັນ icon ປະກອບ (ເບິ່ງ
//   home_tab.dart's "🔔"/"📋"/"⚡" — ບັນຫາທີ່ Re-Audit ລະບຸ). AppSection ຮັກສາ
//   spacing ລະຫວ່າງຫົວຂໍ້/ເນື້ອຫາໃຫ້ຄົງທີ່ (AppSpacing.md) ແລະ ບໍ່ໃຫ້ emoji ເປັນ
//   ທາງເລືອກງ່າຍອີກ — trailing icon ຮັບ IconData ເທົ່ານັ້ນ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_text.dart';

class AppSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.ink),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(child: AppText.heading(title)),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  minimumSize: const Size(44, 44),
                ),
                child: AppText.label(actionLabel!, color: AppColors.navy),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}
