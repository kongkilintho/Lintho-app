// ============================================================
// app_navigation_state.dart — LinTho
// ▸ Tab index ຂອງ MainShell (Home=0 / Booking=1 / Profile=2) ຍົກອອກມາເປັນ
//   Riverpod provider ແຍກຕ່າງຫາກ — ໃຫ້ໜ້າຈໍອື່ນທີ່ຢູ່ຄົນລະໄຟລ໌ (ເຊັ່ນ
//   booking_form_screen.dart ຕອນກົດ "ແກ້ໄຂ" ເບີໂທ) ສາມາດພາຜູ້ໃຊ້ໄປໜ້າ
//   Profile ໄດ້ໂດຍບໍ່ຕ້ອງ import main.dart ໂດຍກົງ (main.dart import
//   booking_form_screen.dart/quick_booking_screen.dart ຢູ່ແລ້ວ — ຈະເກີດ
//   circular import ຖ້າ import ກັບຄືນ).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final mainShellTabIndexProvider = StateProvider<int>((ref) => 0);

const int kProfileTabIndex = 2;
const int kBookingTabIndex = 1;

/// ✅ ພາຜູ້ໃຊ້ໄປໜ້າ Profile (MainShell tab 2) — pop stack ກັບຄືນຫາ root ກ່ອນ
/// (ຮູບແບບດຽວກັນກັບ customer_register_flow.dart's _finish()) ແລ້ວສະຫຼັບ tab.
void goToProfileTab(BuildContext context, WidgetRef ref) {
  ref.read(mainShellTabIndexProvider.notifier).state = kProfileTabIndex;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

// 🔒 [PHASE0 P0-1] review_screen.dart's "ເບິ່ງປະຫວັດການຈອງ" (View History)
// ເຄີຍ Navigator.popUntil(isFirst) ອย่างດຽວ — ພາຜູ້ໃຊ້ໄປ Home tab, ບໍ່ແມ່ນ
// ປະຫວັດການຈອງແທ້ (BookingScreen, MainShell tab 1). ໃຊ້ pattern ດຽວກັນກັບ
// goToProfileTab() ຂ້າງເທິງ.
void goToBookingTab(BuildContext context, WidgetRef ref) {
  ref.read(mainShellTabIndexProvider.notifier).state = kBookingTabIndex;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
