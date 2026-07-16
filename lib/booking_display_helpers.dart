// ============================================================
// booking_display_helpers.dart — LinTho
// ▸ ໂຕຊ່ວຍສະແດງຜົນ booking ຮ່ວມກັນລະຫວ່າງ BookingScreen (list) ແລະ
//   BookingDetailScreen — ຮັບປະກັນວ່າຊື່ບໍລິການ / ລາຄາ / ປ້າຍສະຖານະ
//   ສະແດງຄືກັນທຸກບ່ອນ ບໍ່ drift ອອກຈາກກັນ.
// ▸ ຄ່າ status ຈິງໃນ Firestore ('bookings.status') ແມ່ນມາຈາກ
//   JobStatus.name (ເບິ່ງ Booking.dart): pending / accepted / onTheWay /
//   arrived / inProgress / completed / cancelled / rejected.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_locale.dart';
import 'provider_model.dart';

// ── ສະຖານະ ──────────────────────────────────────────────────

// ▸ ຈັດກຸ່ມ status ຈິງທັງໝົດເຂົ້າ 3 tab ສຳລັບຝັ່ງລູກຄ້າ
enum BookingTab { ongoing, completed, cancelled }

BookingTab bookingTabOf(String status) => switch (status) {
  'completed'              => BookingTab.completed,
  'cancelled' || 'rejected' => BookingTab.cancelled,
  _                         => BookingTab.ongoing,
};

class BookingStatusStyle {
  final Color bg;
  final Color fg;
  const BookingStatusStyle(this.bg, this.fg);
}

BookingStatusStyle bookingStatusStyle(String status) => switch (status) {
  'pending'    => const BookingStatusStyle(Color(0xFFFEF3C7), Color(0xFF92400E)),
  'accepted'   => const BookingStatusStyle(Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'onTheWay' || 'arrived' || 'inProgress' =>
      const BookingStatusStyle(Color(0xFFDCFCE7), Color(0xFF15803D)),
  'completed'  => const BookingStatusStyle(Color(0xFFDCFCE7), Color(0xFF15803D)),
  'cancelled' || 'rejected' =>
      const BookingStatusStyle(Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  _            => const BookingStatusStyle(Color(0xFFF1F5F9), Color(0xFF64748B)),
};

String bookingStatusLabel(String status) => switch (status) {
  'pending'    => tr('pending'),
  'accepted'   => tr('status_accepted_full'),
  'onTheWay'   => tr('on_the_way'),
  'arrived'    => tr('arrived'),
  'inProgress' => tr('status_ongoing'),
  'completed'  => tr('completed'),
  'cancelled'  => tr('cancelled'),
  'rejected'   => tr('rejected'),
  _            => status,
};

// ▸ booking ຍັງ active ຢູ່ໃນມືຊ່າງ (ຮັບແລ້ວ→ກຳລັງເຮັດ) — ໃຊ້ຕັດສິນວ່າ
// ຈະສະແດງປຸ່ມ "ຕິດຕາມ" (live map) ຢູ່ໜ້າລາຍລະອຽດບໍ່
bool bookingIsTrackable(String status) =>
    status == 'accepted' || status == 'onTheWay' ||
    status == 'arrived'  || status == 'inProgress';

// ▸ ຍົກເລີກໄດ້ສະເພາະຕອນຍັງ "ລໍຖ້າຊ່າງ" ເທົ່ານັ້ນ — ຫຼັງຈາກຊ່າງຮັບງານແລ້ວ
// ຕ້ອງໂທ/ແຊັດຫາຊ່າງໂດຍກົງ ເພື່ອປ້ອງກັນການເຜີກົດຍົກເລີກທ່າມກາງວຽກ
bool bookingIsCancelable(String status) => status == 'pending';

// ── ຂໍ້ມູນການສະແດງຜົນ ───────────────────────────────────────

// ▸ ລະຫັດອ້າງອິງແບບອ່ານງ່າຍ — derive ຈາກ doc.id ຈິງ (ບໍ່ຊ້ຳກັນລະຫວ່າງ
// booking ຄົນລະໃບ) ຕ່າງຈາກ id ເຕັມ (ໃຊ້ສະແດງເພີ່ມຢູ່ໜ້າລາຍລະອຽດ)
String bookingCode(String id) =>
    '#BK-${id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase()}';

String bookingScheduleLabel(Map<String, dynamic> b) {
  final ts = b['scheduledAt'] as Timestamp? ?? b['createdAt'] as Timestamp?;
  if (ts == null) return '';
  return DateFormat('dd/MM/yyyy · HH:mm').format(ts.toDate());
}

// ▸ ຊື່ບໍລິການຫຼັກ — ໃຊ້ serviceName/serviceType ກ່ອນ, ຖ້າບໍ່ມີໃຫ້ derive
// ຈາກ category/cleanType ເພື່ອບໍ່ໃຫ້ກາດໃດໜຶ່ງສະແດງຊື່ວ່າງເປົ່າ
String bookingServiceName(Map<String, dynamic> b) {
  final fromDoc = b['serviceName'] as String? ?? b['serviceType'] as String?;
  if (fromDoc != null && fromDoc.trim().isNotEmpty) return fromDoc;
  final category  = b['category'] as String?;
  final cleanType = b['cleanType'] as String?;
  if (category == 'ac_clean') return tr('service_ac_install_repair');
  if (category == 'house_clean') {
    return switch (cleanType) {
      'deep'       => tr('service_house_deep'),
      'specialist' => tr('service_house_specialist'),
      _            => tr('service_house_general'),
    };
  }
  return tr('service_generic');
}

String bookingQuantityLabel(Map<String, dynamic> b) {
  if (b['acQty'] != null) return '${b['acQty']} ${tr('unit_device')}';
  if (b['roomType'] != null) return '1 ${tr('unit_room')}';
  return '1 ${tr('unit_item')}';
}

String bookingTotalLabel(Map<String, dynamic> b) {
  final total = b['grandTotal'] ?? b['priceDisplay'] ?? b['price'];
  if (total is num) {
    return '₭ ${NumberFormat('#,###').format(total)}';
  }
  return '₭ ${total ?? 0}';
}

ProviderModel providerFromBooking(Map<String, dynamic> b) {
  return ProviderModel.fromMap(
    b['providerId'] as String? ?? '',
    {
      'displayName':     b['providerName']   ?? tr('provider'),
      'phone':           b['providerPhone']  ?? '',
      'rating':          b['providerRating'] ?? 0,
      'totalJobs':       b['providerJobs']   ?? 0,
      'photoUrl':        b['providerPhoto']  ?? '',
      'isOnline':        false,
      'serviceTypes':    <String>[],
      'fcmTokens':       <String>[],
      'bio':             '',
      'email':           '',
      'gender':          '',
      'kycStatus':       'none',
      'completionRate':  0,
      'experienceYears': 0,
    },
  );
}
