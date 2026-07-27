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
  // ✅ [Brand color audit 2026-07-27 v2] Background/Surface/Success — token
  // ໃໝ່ຕາມ Brand System, ເບິ່ງ AppColors ສຳລັບຄຳອະທິບາຍ
  static const background = AppColors.background;
  static const surface    = AppColors.surface;
  static const success    = AppColors.success;

  // ✅ [Brand color audit 2026-07-27 v2] category/decorative accents — ຍົກ
  // ອອກຈາກ booking_form_screen.dart/main.dart/fcm_service.dart, ເບິ່ງ AppColors
  static const categoryAcBg           = AppColors.categoryAcBg;
  static const categoryAcAccent       = AppColors.categoryAcAccent;
  static const categoryCleanBg        = AppColors.categoryCleanBg;
  static const categoryCleanAccent    = AppColors.categoryCleanAccent;
  static const categoryAddonBg        = AppColors.categoryAddonBg;
  static const categoryAddonBorder    = AppColors.categoryAddonBorder;
  static const categoryAddonLabelText = AppColors.categoryAddonLabelText;
  static const categoryAddonValueText = AppColors.categoryAddonValueText;
  static const categoryPestBg         = AppColors.categoryPestBg;
  static const noteWarningBg          = AppColors.noteWarningBg;
  static const noteWarningText        = AppColors.noteWarningText;
  static const noteWarningTextDark    = AppColors.noteWarningTextDark;
  static const mutedLight             = AppColors.mutedLight;
  static const promoBannerBlue        = AppColors.promoBannerBlue;
  static const promoBannerGreen       = AppColors.promoBannerGreen;
  static const promoBannerOrange      = AppColors.promoBannerOrange;
  static const homeCardAcTint         = AppColors.homeCardAcTint;
  static const homeCardOtherTint      = AppColors.homeCardOtherTint;
  static const splashGradientStart    = AppColors.splashGradientStart;
  static const splashSubtext          = AppColors.splashSubtext;
  static const vipDark                = AppColors.vipDark;
  static const vipGold                = AppColors.vipGold;
  static const primaryDeepWash        = AppColors.primaryDeepWash;
  static const notifBooking           = AppColors.notifBooking;
  static const notifPayment           = AppColors.notifPayment;
  static const notifCharge            = AppColors.notifCharge;
  static const notifChat              = AppColors.notifChat;
  static const notifDefault           = AppColors.notifDefault;

  // ── Aliases ─────────────────────────────────────────────
  static const primary       = green;  // C.primary
  static const textPrimary   = text;   // C.textPrimary
  static const textSecondary = muted;  // C.textSecondary
}