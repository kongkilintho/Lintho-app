// ============================================================
// lib/widgets/app_icon_button.dart — LinTho
// ▸ "Container ສີ່ຫຼ່ຽມສີ + icon ກາງ" (ໂທ/ນຳທາງ/ແຊັດ) ຖືກສ້າງແຍກກັນ 4+
//   ບ່ອນ (job_workflow, tracking_screen, provider_map_screen,
//   provider_dashboard) ຄົນລະຂະໜາດ (36–44px), ບາງບ່ອນຕ່ຳກວ່າ 44dp tap
//   target ຂັ້ນຕ່ຳ, ແລະ ບໍ່ມີໜ່ວຍໃດມີ Semantics label. ນີ້ຄື component ດຽວ —
//   ບັງຄັບຂະໜາດຂັ້ນຕ່ຳ 44dp ແລະ tooltip/Semantics ສະເໝີ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String label; // ✅ ບັງຄັບໃສ່ — ໃຊ້ເປັນ Semantics + Tooltip
  final double size;
  final bool filled;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.label,
    this.size = 44,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final tapSize = size < 44 ? 44.0 : size;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Container(
              width: tapSize, height: tapSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? color.withValues(alpha: 0.1) : null,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: filled ? null : Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: color, size: size * 0.45),
            ),
          ),
        ),
      ),
    );
  }
}
