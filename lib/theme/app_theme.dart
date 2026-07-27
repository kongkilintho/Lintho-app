// ============================================================
// lib/theme/app_theme.dart — LinTho ລະບົບການອອກແບບກາງ (Design System)
//
// ▸ ບ່ອນດຽວທີ່ກຳນົດ: ສີ, type scale, spacing, radius, ແລະ ThemeData ຂອງ
//   ທັງແອັບ. ກ່ອນໜ້ານີ້ ThemeData ໃນ main.dart ກຳນົດແຕ່ colorScheme +
//   primaryColor + scaffoldBackgroundColor — AppBar/Card/Button/TextField/
//   BottomSheet/Dialog ບໍ່ມີ theme ກາງ, ແຕ່ລະໜ້າຈໍຈຶ່ງຂຽນ style ຂອງຕົນເອງ
//   ຊ້ຳໆ (15+ ຄັ້ງສຳລັບ AppBar ຢ່າງດຽວ) ແລະ drift ອອກຈາກກັນເທື່ອລະໜ້ອຍ.
// ▸ lib/app_colors.dart's `C` class ຍັງຄົງໄວ້ (ໃຊ້ຢູ່ 40+ ໄຟລ໌ທົ່ວແອັບ) ແຕ່
//   ຕອນນີ້ mirror ຄ່າຈາກ AppColors ຢູ່ນີ້ ແທນທີ່ຈະປະກາດຄ່າຂອງຕົນເອງ —
//   ແກ້ໄຂຢູ່ບ່ອນດຽວນີ້ ຈະສະທ້ອນໄປທົ່ວແອັບໂດຍບໍ່ຕ້ອງແກ້ 32 ໄຟລ໌ພ້ອມກັນ.
//   ໜ້າຈໍໃໝ່/ຖືກ refactor ຄວນອ້າງອີງ AppColors/AppTypography/AppSpacing
//   ໂດຍກົງ ບໍ່ຕ້ອງຜ່ານ C.
// ============================================================

import 'package:flutter/material.dart';
import '../Booking.dart' show JobStatus;

// ════════════════════════════════════════════════════════════
// COLOR SYSTEM
// ════════════════════════════════════════════════════════════

class AppColors {
  AppColors._();

  // ── ແບຣນ (primary palette) ──────────────────────────────────
  static const navy  = Color(0xFF001B4B);
  static const green = Color(0xFF14B87A); // ✅ [Brand color audit 2026-07-27] ອັດເດດເປັນສີຂຽວແບຣນທາງການ (ແທນ #22C55E)
  static const gold  = Color(0xFFFBBF24); // ✅ ລວມ C.yellow/C.gold (hex ດຽວກັນ, 2 ຊື່) ເປັນຊື່ດຽວ
  // ✅ [Brand color audit 2026-07-27 v2] ink #0F172A → #1F2937 ຕາມ Brand
  // System ໃໝ່ (Primary Text) — contrast ເທິງພື້ນຂາວ ~12.6:1, ຍັງຜ່ານ WCAG AAA
  static const ink   = Color(0xFF1F2937); // primary text
  static const bg    = Color(0xFFF8FAFF); // ✅ ລວມ C.bg/C.cream (hex ດຽວກັນ, 2 ຊື່)

  // ✅ [Brand color audit 2026-07-27 v2] Background/Surface — token ໃໝ່ຕາມ
  // Brand System (Background=ໜ້າຈໍ, Surface=Card/AppBar/Dialog/BottomSheet).
  // ບົດບາດສະຫຼັບກັບ `bg`/`white` ເກົ່າ: ດຽວນີ້ໜ້າຈໍເປັນຂາວແທ້, surface ເປັນ
  // ສີແຕ້ມອ່ອນໆ — ເບິ່ງ AppTheme.light ສຳລັບບ່ອນທີ່ໃຊ້ແທນ `bg`/`white` ເກົ່າ.
  static const background = Color(0xFFFFFFFF);
  static const surface    = Color(0xFFF8FAF8);

  // ── ຂະຫຍາຍ (ຍັງໃຊ້ຢູ່ທົ່ວແອັບ, ຄົງໄວ້ບໍ່ປ່ຽນ hex) ──────────────
  static const blue      = Color(0xFF1E40AF);
  static const sky       = Color(0xFF3B82F6);
  static const teal      = Color(0xFF14B8A6);
  static const mint      = Color(0xFFECFDF5);
  static const red       = Color(0xFFEF4444);
  static const dangerRed = Color(0xFFFF6B6B);
  // ✅ [Brand color audit 2026-07-27 v2] orange #F97316 → #F59E0B ຕາມ Brand
  // System ໃໝ່ (Warning)
  static const orange    = Color(0xFFF59E0B);
  static const white     = Colors.white;
  // ✅ [Brand color audit 2026-07-27 v2] border #E2E8F0 → #E5E7EB ຕາມ Brand
  // System ໃໝ່
  static const border    = Color(0xFFE5E7EB);

  // ✅ [Brand color audit 2026-07-27 v2] success ແຍກຈາກ green (Primary) ຕາມ
  // Brand System ໃໝ່ — Primary (#14B87A) = ປຸ່ມ/ແທັບ/ການກະທຳຫຼັກ, Success
  // (#22C55E) = feedback ວ່າ "ສຳເລັດ" (SnackBar/checkmark/status completed)
  static const success = Color(0xFF22C55E);

  // ✅ [FIX] #94A3B8 ເທິງພື້ນຂາວ/bg ແມ່ນ contrast ~2.8:1 — ບໍ່ຜ່ານ WCAG AA
  // (4.5:1) ສຳລັບ caption/hint/timestamp ທີ່ token ນີ້ຂັບເຄື່ອນເກືອບທຸກໜ້າຈໍ.
  // ✅ [Brand color audit 2026-07-27 v2] muted #5D6572 → #6B7280 ຕາມ Brand
  // System ໃໝ່ (Secondary Text) — contrast ~4.8:1 ເທິງພື້ນຂາວ, ຍັງຜ່ານ WCAG AA
  static const muted = Color(0xFF6B7280);

  // ════════════════════════════════════════════════════════════
  // ✅ [Brand color audit 2026-07-27 v2] Category/decorative accents — hex
  // ຍົກອອກຈາກ booking_form_screen.dart/main.dart/fcm_service.dart (ເຄີຍ
  // hardcode ຢູ່ widget ໂດຍກົງ). ຄ່າ hex ບໍ່ປ່ຽນ (ບໍ່ມີຜົນສາຍຕາ) — ນີ້ຄື
  // ລະບົບແຍກສີຕາມໝວດບໍລິການ/ເນື້ອຫາ (ບໍ່ແມ່ນ 9-token core brand), ຈົງໃຈ
  // ບໍ່ແມ່ນສີຂຽວ (ເບິ່ງລາຍງານກວດ Brand §4 "ບ່ອນທີ່ບໍ່ຄວນໃຊ້ສີຂຽວ")
  // ════════════════════════════════════════════════════════════

  // ── ໝວດ "ແອ" (Booking Form/Home quick-book) ─────────────────
  static const categoryAcBg     = Color(0xFFEFF6FF);
  static const categoryAcAccent = Color(0xFF1D4ED8);

  // ── ໝວດ "ທຳຄວາມສະອາດ" ────────────────────────────────────────
  static const categoryCleanBg     = Color(0xFFF0FDF4);
  static const categoryCleanAccent = Color(0xFF15803D);

  // ── ໝວດ "ບໍລິການເສີມ/Deep-clean" (ມ່ວງ) ──────────────────────
  static const categoryAddonBg        = Color(0xFFF5F3FF);
  static const categoryAddonBorder    = Color(0xFF7C3AED);
  static const categoryAddonLabelText = Color(0xFF6D28D9);
  static const categoryAddonValueText = Color(0xFF5B21B6);

  // ── ໝວດ "ກຳຈັດແມງໄມ້" (Pest control) ─────────────────────────
  static const categoryPestBg = Color(0xFFFDF4FF);

  // ── ໝາຍເຫດ/ຄຳເຕືອນ (ມັດຈຳ/deposit — ອຳພັນ) ───────────────────
  static const noteWarningBg       = Color(0xFFFFFBEB);
  static const noteWarningText     = Color(0xFF92400E);
  static const noteWarningTextDark = Color(0xFF78350F);

  static const mutedLight = Color(0xFFB0B8C4);

  // ── Home promo banner carousel (ບໍ່ກ່ຽວກັບໝວດບໍລິການ) ─────────
  static const promoBannerBlue   = Color(0xFF0EA5E9);
  static const promoBannerGreen  = Color(0xFF22C55E); // ✅ ຄ່າກົງກັບ `success` ໂດຍບັງເອີນ — ຄົງແຍກ token ເພື່ອບໍ່ໃຫ້ banner ຜູກກັບຄວາມໝາຍ "ສຳເລັດ"
  static const promoBannerOrange = Color(0xFFF97316);

  // ── Home quick-action card tint (AC vs ອື່ນໆ) ─────────────────
  static const homeCardAcTint    = Color(0xFFE3F2FD);
  static const homeCardOtherTint = Color(0xFFFFF3E0);

  // ── Splash screen ─────────────────────────────────────────────
  static const splashGradientStart = Color(0xFF0A2E6E);
  static const splashSubtext       = Color(0xFFD6E4FF);

  // ── VIP/referral card (dark+gold, ພິເສດແຍກຈາກ theme ຫຼັກ) ─────
  static const vipDark = Color(0xFF1A1D23);
  static const vipGold = Color(0xFFC9A84C);

  // ── Match screen "ກຳລັງຊອກຊ່າງ..." dark brand wash (derive ຈາກ green) ──
  static const primaryDeepWash = Color(0xFF07332B);

  // ── fcm_service.dart notification-channel colors (Android tint
  //    ເທົ່ານັ້ນ, ບໍ່ມີຜົນສາຍຕາໃນແອັບໂດຍກົງ) ────────────────────────
  static const notifBooking = Color(0xFF1565C0);
  static const notifPayment = Color(0xFF4A7C59);
  static const notifCharge  = Color(0xFFF97316);
  static const notifChat    = Color(0xFF7C3AED);
  static const notifDefault = Color(0xFF0D1B4B);
}

// ════════════════════════════════════════════════════════════
// STATUS COLOR — ແຜນທີ່ດຽວ, ບໍ່ໃຫ້ແຍກກຳນົດຄືນຢູ່ແຕ່ລະໜ້າຈໍ
// ════════════════════════════════════════════════════════════
//
// ✅ [FIX] ກ່ອນໜ້ານີ້ມີ 2 ລະບົບສີສະຖານະແຍກກັນ: booking_display_helpers.dart
// (bg/fg hex ກົງ) ແລະ home_tab.dart's StatusBadge (C.* switch ຕົວມັນເອງ) —
// booking ອັນດຽວກັນສະແດງຄົນລະສີໄດ້ຂຶ້ນກັບໜ້າຈໍໃດສະແດງ. ຕອນນີ້ທັງສອງ
// ໜ້າຈໍດຶງຈາກ AppStatus ບ່ອນດຽວ.
class AppStatus {
  AppStatus._();

  /// ສີ accent ຕົ້ນຕໍຂອງແຕ່ລະສະຖານະ — ໃຊ້ທັງເປັນສີ badge ແລະ derive ເປັນ
  /// ຄູ່ (bg, fg) ຜ່ານ [styleOf].
  static Color colorOf(JobStatus status) => switch (status) {
        JobStatus.pending    => AppColors.gold,
        JobStatus.accepted   => AppColors.sky,
        JobStatus.onTheWay   => AppColors.teal,
        JobStatus.arrived    => AppColors.teal,
        JobStatus.inProgress => AppColors.teal,
        // ✅ [Brand color audit 2026-07-27 v2] completed = Success (#22C55E),
        // ແຍກຈາກ Primary (#14B87A)
        JobStatus.completed  => AppColors.success,
        JobStatus.cancelled  => AppColors.muted,
        JobStatus.rejected   => AppColors.red,
      };

  /// `bookings.status` ໃນ Firestore ເກັບເປັນ String (JobStatus.name) —
  /// overload ນີ້ໃຫ້ໜ້າຈໍທີ່ຍັງເຮັດວຽກກັບ Map<String,dynamic> ດິບ (ບໍ່ໄດ້
  /// parse ເປັນ Booking model ກ່ອນ) ໃຊ້ແຜນທີ່ດຽວກັນໄດ້ໂດຍບໍ່ຕ້ອງ refactor.
  static Color colorOfName(String status) {
    for (final s in JobStatus.values) {
      if (s.name == status) return colorOf(s);
    }
    return AppColors.muted; // ✅ fallback ສະຖານະບໍ່ຮູ້ຈັກ — ຄືເດີມ
  }

  /// ຄູ່ (bg, fg) ສຳລັບ pill/badge — bg = accent 12% alpha, fg = accent ເຕັມ.
  static ({Color bg, Color fg}) styleOf(JobStatus status) {
    final c = colorOf(status);
    return (bg: c.withValues(alpha: 0.12), fg: c);
  }

  static ({Color bg, Color fg}) styleOfName(String status) {
    final c = colorOfName(status);
    return (bg: c.withValues(alpha: 0.12), fg: c);
  }
}

// ════════════════════════════════════════════════════════════
// TYPOGRAPHY — 6 roles, ບໍ່ໃຫ້ແຕ່ລະໜ້າຈໍເລືອກ size/weight ເອງອີກ
// ════════════════════════════════════════════════════════════

class AppTypography {
  AppTypography._();

  static const display = TextStyle(
      fontSize: 32, fontWeight: FontWeight.w700,
      color: AppColors.ink, height: 1.15, letterSpacing: -0.3);
  static const title = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w600,
      color: AppColors.ink, height: 1.2);
  static const heading = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600,
      color: AppColors.ink, height: 1.3);
  static const body = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: AppColors.ink, height: 1.5);
  static const label = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: AppColors.ink, height: 1.3, letterSpacing: 0.1);
  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500,
      color: AppColors.muted, height: 1.3);

  /// ຫົວ AppBar — ຂະໜາດ/ນ້ຳໜັກທີ່ 15+ ໜ້າຈໍໃຊ້ຢູ່ແລ້ວ, ຍົກຂຶ້ນເປັນ theme
  /// ແທນທີ່ຈະໃຫ້ແຕ່ລະ AppBar ພິມ TextStyle ຊ້ຳ.
  static const appBarTitle = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink);
}

// ════════════════════════════════════════════════════════════
// SPACING — 8-point grid
// ════════════════════════════════════════════════════════════

class AppSpacing {
  AppSpacing._();
  static const xs   = 4.0;
  static const sm   = 8.0;
  static const md   = 12.0;
  static const lg   = 16.0;
  static const xl   = 24.0;
  static const xxl  = 32.0;
  static const xxxl = 48.0;
}

// ════════════════════════════════════════════════════════════
// RADIUS — 3 ລະດັບ
// ════════════════════════════════════════════════════════════

class AppRadius {
  AppRadius._();
  static const chip  = 8.0;  // pill/chip/badge/input ນ້ອຍ
  static const card  = 16.0; // card/button/input/dialog
  static const sheet = 24.0; // bottom sheet, modal ໃຫຍ່

  static final chipShape  = BorderRadius.circular(chip);
  static final cardShape  = BorderRadius.circular(card);
  static const sheetTop   = BorderRadius.vertical(top: Radius.circular(sheet));
}

// ════════════════════════════════════════════════════════════
// THEME DATA — ຝັງ sub-themes ທັງໝົດຢູ່ບ່ອນດຽວ
// ════════════════════════════════════════════════════════════

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
    ).copyWith(
      primary:   AppColors.green,
      secondary: AppColors.teal,
      tertiary:  AppColors.gold,
      error:     AppColors.red,
      // ✅ [Brand color audit 2026-07-27 v2] surface ຕອນນີ້ແມ່ນ AppColors.surface
      // (#F8FAF8, ບໍ່ແມ່ນ AppColors.white ອີກຕໍ່ໄປ) — ເບິ່ງ Background/Surface
      // role swap ໃນ AppColors
      surface:   AppColors.surface,
    );

    final outlineInput = OutlineInputBorder(
      borderRadius: AppRadius.cardShape,
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: AppColors.green,
      // ✅ [Brand color audit 2026-07-27 v2] Background/Surface role swap ຕາມ
      // Brand System ໃໝ່ — ໜ້າຈໍ (scaffold) ດຽວນີ້ຂາວແທ້ (background), Card/
      // AppBar/Dialog/BottomSheet ໃຊ້ surface (ສີແຕ້ມອ່ອນ) ແທນ
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: null, // system font — see design review §3 for the case to add a custom pairing later

      textTheme: const TextTheme(
        displayLarge:  AppTypography.display,
        headlineLarge: AppTypography.title,
        titleLarge:    AppTypography.heading,
        bodyLarge:     AppTypography.body,
        labelLarge:    AppTypography.label,
        bodySmall:     AppTypography.caption,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.appBarTitle,
        iconTheme: IconThemeData(color: AppColors.ink),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.border,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
          textStyle: AppTypography.label.copyWith(fontSize: 16, color: AppColors.white),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.navy),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.navy),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // ✅ [Brand color audit 2026-07-27 v2] ໃຊ້ surface (ບໍ່ແມ່ນ bg ເກົ່າ) —
        // ຮັກສາ intent ເດີມ (fill ຕ່າງຈາກພື້ນຫຼັງໜ້ອຍໜຶ່ງ) ພາຍໃຕ້ token ໃໝ່
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        border: outlineInput,
        enabledBorder: outlineInput,
        focusedBorder: outlineInput.copyWith(
            borderSide: const BorderSide(color: AppColors.sky, width: 1.6)),
        errorBorder: outlineInput.copyWith(
            borderSide: const BorderSide(color: AppColors.red, width: 1.4)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        showDragHandle: false, // ໃຊ້ _Handle ວັດເຈດຂອງແອັບເອງ (ດູ AppBottomSheet)
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardShape),
        titleTextStyle: AppTypography.title.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
        contentTextStyle: AppTypography.body.copyWith(color: AppColors.muted),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.navy.withValues(alpha: 0.08),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? AppColors.navy : AppColors.muted)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.navy : AppColors.muted)),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),

      // ✅ [Brand color audit 2026-07-27] Switch/Checkbox/Radio/FAB/Progress/Chip
      // ບໍ່ເຄີຍມີ theme ກາງ ມາກ່ອນ — ແຕ່ລະໜ້າຈໍທີ່ບໍ່ໄດ້ຕັ້ງ color ເອງ ຈະໄດ້ຮັບ
      // brand green ອັດຕະໂນມັດຈາກນີ້ (M3 default ອີງໃສ່ colorScheme.primary ຢູ່
      // ແລ້ວ, ແຕ່ປະກາດຢູ່ນີ້ໃຫ້ຊັດເຈນ ບໍ່ໃຫ້ໜ້າຈໍໃໝ່ hardcode ສີເອງອີກ).
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.green : AppColors.white),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.green
                : AppColors.border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.green : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(AppColors.white),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.green : AppColors.muted),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.green,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.green,
        labelStyle: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipShape),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}
