import 'theme/app_theme.dart';

// ✅ [Phase 2] `C` ຍັງຖືກໃຊ້ຢູ່ 40+ ໄຟລ໌ທົ່ວແອັບ — ຄົງໄວ້ເປັນ compatibility
// layer ບໍ່ໃຫ້ໜ້າຈໍເກົ່າພັງ, ແຕ່ຕອນນີ້ mirror ຄ່າຈາກ lib/theme/app_theme.dart's
// AppColors (single source of truth) ແທນທີ່ຈະປະກາດ hex ຂອງຕົນເອງຄືເກົ່າ —
// ແກ້ຄ່າຢູ່ AppColors ຈຸດດຽວ ຈະສະທ້ອນທົ່ວແອັບໂດຍບໍ່ຕ້ອງແກ້ໄຟລ໌ອື່ນ.
// ໜ້າຈໍໃໝ່/ຖືກ refactor ຄວນອ້າງອີງ AppColors ໂດຍກົງ, ບໍ່ຕ້ອງຜ່ານ C.
class C {
  static const navy   = AppColors.navy;
  static const blue   = AppColors.blue;
  static const sky    = AppColors.sky;
  static const yellow = AppColors.gold;      // ✅ ເຄີຍແຍກຊື່ ແຕ່ hex ດຽວກັນ — ລວມແລ້ວ
  static const green  = AppColors.green;
  static const teal   = AppColors.teal;
  static const mint   = AppColors.mint;
  static const red    = AppColors.red;
  static const dangerRed = AppColors.dangerRed;
  static const orange = AppColors.orange;
  static const bg     = AppColors.bg;
  static const white  = AppColors.white;
  static const text   = AppColors.ink;
  static const muted  = AppColors.muted;     // ✅ ປັບ contrast ໃຫ້ຜ່ານ WCAG AA — ເບິ່ງ AppColors.muted
  static const border = AppColors.border;
  static const cream  = AppColors.bg;        // ✅ ເຄີຍແຍກຊື່ ແຕ່ hex ດຽວກັນ — ລວມແລ້ວ
  static const gold   = AppColors.gold;
  static const brown  = AppColors.navy;      // ✅ ເຄີຍແຍກຊື່ ແຕ່ hex ດຽວກັນ — ລວມແລ້ວ
  static const dark   = AppColors.navy;

  // ── Aliases ─────────────────────────────────────────────
  static const primary       = green;  // C.primary
  static const textPrimary   = text;   // C.textPrimary
  static const textSecondary = muted;  // C.textSecondary
}