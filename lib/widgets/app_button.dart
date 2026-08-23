// ============================================================
// lib/widgets/app_button.dart — LinTho
// ▸ [PHASE1] ກ່ອນໜ້ານີ້ບໍ່ມີ shared button widget — ທຸກໜ້າຈໍເອີ້ນ
//   ElevatedButton/OutlinedButton/TextButton ໂດຍກົງ, ບາງບ່ອນອີງໃສ່
//   ElevatedButtonTheme (green) ແຕ່ບາງບ່ອນ override ເປັນ navy ດ້ວຍ style ຂອງ
//   ຕົນເອງ — ນີ້ຄືສາເຫດຫຼັກທີ່ CTA ສີບໍ່ຄົງທີ່ທົ່ວແອັບ (ເບິ່ງ Brand-Consistency
//   Re-Audit 2026-08-23, P1 "Primary CTA color flips between green and navy").
// ▸ AppButton ບໍ່ຮັບ `color`/`backgroundColor` parameter ໂດຍເຈດຕະນາ — ແຕ່ລະ
//   variant ຜູກກັບ role ໃນ Color System ຂອງ Master Prompt ("primary" ຕ້ອງ
//   ເປັນ LinTho Green ສະເໝີ, "secondary"/navy ຄື role ແຍກຕ່າງຫາກ) ບໍ່ໃຫ້ໜ້າຈໍ
//   ໃໝ່/ຖືກ migrate ຄືນສາມາດ override ສີເອງອີກ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ▸ primary   — ການກະທຳຫຼັກຂອງໜ້າຈໍ (ຈອງ/ຢືນຢັນ/ສົ່ງ/ຈ່າຍ/ຮັບ) — ສະເໝີເປັນ
///   LinTho Green (ຄ່າ default ຂອງ ElevatedButtonTheme ຢູ່ແລ້ວ)
/// ▸ secondary — filled ແຕ່ບໍ່ແມ່ນການກະທຳຫຼັກ (navy) — ໃຊ້ສຳລັບ "premium
///   surface"/brand context ຕາມ Color System hierarchy, ບໍ່ແມ່ນ CTA ຫຼັກ
/// ▸ outline   — secondary action ທົ່ວໄປ (navy border/text, ຄ່າ default ຂອງ
///   OutlinedButtonTheme)
/// ▸ ghost     — tertiary/text-only action (navy text, ບໍ່ມີພື້ນ/border)
/// ▸ destructive — ຍົກເລີກ/ລຶບ/action ທີ່ກັບຄືນບໍ່ໄດ້ (red)
enum AppButtonVariant { primary, secondary, outline, ghost, destructive }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
    this.loading = false,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
    this.loading = false,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
    this.loading = false,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
    this.loading = false,
  }) : variant = AppButtonVariant.outline;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.loading = false,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
    this.loading = false,
  }) : variant = AppButtonVariant.destructive;

  @override
  Widget build(BuildContext context) {
    final onTap = loading ? null : onPressed;
    final child = loading
        ? SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(_loadingColor),
            ),
          )
        : icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              );

    final button = switch (variant) {
      // ✅ ບໍ່ໃສ່ style override ເລີຍ — ອີງໃສ່ ElevatedButtonTheme (green) 100%
      AppButtonVariant.primary => ElevatedButton(onPressed: onTap, child: child),
      AppButtonVariant.secondary => ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.border,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
          ),
          child: child,
        ),
      // ✅ ບໍ່ໃສ່ style override — ອີງໃສ່ OutlinedButtonTheme (navy)
      AppButtonVariant.outline => OutlinedButton(onPressed: onTap, child: child),
      // ✅ ບໍ່ໃສ່ style override — ອີງໃສ່ TextButtonTheme (navy)
      AppButtonVariant.ghost => TextButton(onPressed: onTap, child: child),
      AppButtonVariant.destructive => ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.border,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
          ),
          child: child,
        ),
    };

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  Color get _loadingColor => switch (variant) {
        AppButtonVariant.primary ||
        AppButtonVariant.secondary ||
        AppButtonVariant.destructive =>
          AppColors.white,
        AppButtonVariant.outline || AppButtonVariant.ghost => AppColors.navy,
      };
}
