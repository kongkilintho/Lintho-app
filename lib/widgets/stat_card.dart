// ============================================================
// lib/widgets/stat_card.dart — LinTho
// ▸ "icon + ໂຕເລກໃຫຍ່ + label" ຖືກສ້າງແຍກກັນ 3 ບ່ອນ: home_tab.dart's
//   _StatCard, profile_tab.dart's _Stat, ແລະ main.dart's inline _stat() —
//   ຄົນລະ radius/padding/font. ນີ້ຄື component ດຽວ, ໃຊ້ໄດ້ທັງແບບເຕັມສີ
//   (solid, ໃຊ້ໃນ wallet/earnings) ແລະ ແບບໂປ່ງໃສເທິງພື້ນຂາວ (outline).
//
// ▸ main.dart's _stat() ແມ່ນຮູບຮ່າງແຕກຕ່າງອອກໄປແທ້ (icon ຢູ່ໃນ badge ວົງມົນ
//   ໂປ່ງໃສ, tap ripple, ບໍ່ມີ card background) — ບໍ່ໄດ້ລວມເຂົ້ານີ້, ປະໄວ້
//   ເປັນ widget ຂອງມັນເອງ.
//
// ▸ home_tab.dart / profile_tab.dart ຄົນລະໜ້າຕາກັນ (ຂະໜາດ font/icon, ສີພື້ນ,
//   shadow, ການຈັດແຖວ) — override parameter ຂ້າງລຸ່ມນີ້ຖືກເພີ່ມສະເພາະໃຫ້ທັງ
//   2 ບ່ອນນັ້ນຄົງໜ້າຕາເກົ່າໄວ້ຄັກໆ ຫຼັງລວມເຂົ້າ widget ດຽວ (ບໍ່ປ່ຽນ visual).
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

  // Overrides — win over the style/color-derived defaults below. Added so
  // home_tab.dart's and profile_tab.dart's differently-styled stat tiles
  // could adopt this widget without changing how they actually look.
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? valueColor;
  final Color? labelColor;
  final double? iconSize;
  final double? valueFontSize;
  final double? labelFontSize;
  final FontWeight? valueFontWeight;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final List<BoxShadow>? boxShadow;
  final CrossAxisAlignment crossAxisAlignment;
  final double? iconSpacing;
  final double? valueLabelSpacing;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.style = StatCardStyle.solid,
    this.onTap,
    this.actionLabel,
    this.backgroundColor,
    this.iconColor,
    this.valueColor,
    this.labelColor,
    this.iconSize,
    this.valueFontSize,
    this.labelFontSize,
    this.valueFontWeight,
    this.padding,
    this.borderRadius,
    this.boxShadow,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.iconSpacing,
    this.valueLabelSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final solid = style == StatCardStyle.solid;
    final fg = solid ? Colors.white : color;
    final bg = backgroundColor ?? (solid ? color : AppColors.white);
    final radius = borderRadius ?? AppRadius.card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: solid ? null : Border.all(color: AppColors.border),
            boxShadow: boxShadow,
          ),
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Icon(icon, color: iconColor ?? fg.withValues(alpha: solid ? 0.85 : 1),
                  size: iconSize ?? 20),
              SizedBox(height: iconSpacing ?? AppSpacing.sm),
              Text(value, style: TextStyle(
                  color: valueColor ?? fg, fontSize: valueFontSize ?? 22,
                  fontWeight: valueFontWeight ?? FontWeight.w900)),
              SizedBox(height: valueLabelSpacing ?? 2),
              Text(label, style: TextStyle(
                  color: labelColor ?? (solid ? fg.withValues(alpha: 0.75) : AppColors.muted),
                  fontSize: labelFontSize ?? 11)),
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
