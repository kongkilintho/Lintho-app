// ============================================================
// lib/widgets/stat_card.dart — LinTho
// ▸ "icon + ໂຕເລກໃຫຍ່ + label" ຖືກສ້າງແຍກກັນ 3 ບ່ອນ: home_tab.dart's
//   _StatCard, profile_tab.dart's _Stat, ແລະ main.dart's inline _stat() —
//   ຄົນລະ radius/padding/font. ນີ້ຄື component ດຽວ, ໃຊ້ໄດ້ທັງແບບເຕັມສີ
//   (solid, ໃຊ້ໃນ wallet/earnings) ແລະ ແບບໂປ່ງໃສເທິງພື້ນຂາວ (outline).
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatCardStyle { solid, outline }

class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final StatCardStyle style;
  final VoidCallback? onTap;
  final String? actionLabel;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.style = StatCardStyle.solid,
    this.onTap,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final solid = style == StatCardStyle.solid;
    final fg = solid ? Colors.white : color;
    final bg = solid ? color : AppColors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: solid ? null : Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(
              color: (solid ? color : Colors.black).withValues(alpha: solid ? 0.22 : 0.04),
              blurRadius: 12, offset: const Offset(0, 6),
            )],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg.withValues(alpha: solid ? 0.85 : 1), size: 20),
              const SizedBox(height: AppSpacing.sm),
              Text(value, style: TextStyle(
                  color: fg, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                  color: solid ? fg.withValues(alpha: 0.75) : AppColors.muted,
                  fontSize: 11)),
              if (actionLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: solid ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(actionLabel!, style: TextStyle(
                      color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
