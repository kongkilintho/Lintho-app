// ============================================================
// lao_phone.dart — LinTho App
// Validation + E.164 normalization ສຳລັບເບີໂທລາວ
//   '020XXXXXXXX' (11 ຫຼັກ, ນຳໜ້າດ້ວຍ 0)  → +85620XXXXXXXX
//   '20XXXXXXXX'  (10 ຫຼັກ, ບໍ່ມີ 0 ນຳໜ້າ) → +85620XXXXXXXX
// ============================================================

/// ຕັດທຸກຕົວອັກສອນທີ່ບໍ່ແມ່ນເລກ 0-9 ອອກ (ຊ່ອງຫວ່າງ, ຂີດ, ...)
String laoPhoneDigitsOnly(String input) =>
    input.replaceAll(RegExp(r'[^0-9]'), '');

/// ກວດສອບເບີໂທລາວ — ຮັບທັງ 11 ຫຼັກ (ນຳໜ້າ 0) ແລະ 10 ຫຼັກ (ບໍ່ນຳໜ້າ 0)
/// ✅ [FIX Low-3] ເບີມືຖືລາວທຸກຄ້າຍ/ທຸກ operator ຂຶ້ນຕົ້ນດ້ວຍ 020 ສະເໝີ —
/// ກ່ອນໜ້ານີ້ພຽງແຕ່ນັບຈຳນວນຫຼັກ ບໍ່ກວດ prefix ແທ້ ເຮັດໃຫ້ເບີທີ່ບໍ່ມີຢູ່ຈິງ
/// (ເຊັ່ນ 01234567890) ຜ່ານ client-side validation ໄດ້ ແລ້ວມາລົ້ມເຫຼວຢູ່
/// Firebase Auth ດ້ວຍ error code ທົ່ວໄປແທນ
bool isValidLaoPhone(String input) {
  final digits = laoPhoneDigitsOnly(input);
  return RegExp(r'^0?20\d{8}$').hasMatch(digits);
}

/// ແປງເບີໂທລາວ (ບໍ່ວ່າຈະນຳໜ້າດ້ວຍ 0 ຫຼືບໍ່) ໃຫ້ເປັນ E.164 (+856...)
/// ສຳລັບສົ່ງໃຫ້ Firebase Auth verifyPhoneNumber()
String toE164LaoPhone(String input) {
  final digits = laoPhoneDigitsOnly(input);
  final local  = digits.startsWith('0') ? digits.substring(1) : digits;
  return '+856$local';
}
