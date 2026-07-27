// ============================================================
// lib/widgets/empty_state_view.dart — LinTho
// ▸ ຮູບແບບ icon-in-tinted-circle + title + subtitle ຖືກຄັດລອກຢູ່ 5+ ໜ້າຈໍ
//   (home_tab, jobs_tab, main.dart booking list, favorites...) ດ້ວຍຄຸນນະພາບ
//   ບໍ່ເທົ່າກັນ — ບາງບ່ອນມີ icon+illustration (chat_screen), ບາງບ່ອນເປັນ
//   ຂໍ້ຄວາມສີເທົາທຳມະດາ (rewards, coupons, earnings). ນີ້ຄືມາດຕະຖານດຽວ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color accent;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    // ✅ [Brand color audit 2026-07-27] ຄ່າ default ປ່ຽນຈາກ AppColors.sky
    // (ສີຟ້າ) ເປັນ AppColors.muted — empty state ບໍ່ແມ່ນ CTA, ຄວນເປັນສີກາງ
    // ບໍ່ດຶງດູດສາຍຕາຄືສີແບຣນ/ສີແຈ້ງເຕືອນ
    this.accent = AppColors.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 34, color: accent),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                  color: AppColors.muted, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.caption),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    ));
  }
}
