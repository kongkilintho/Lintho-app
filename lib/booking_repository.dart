// ============================================================
// booking_repository.dart — LinTho Provider App
// Fixes:
//   ✅ [FIX-1] _uid: currentUser?.uid ?? '' — ບໍ່ ! crash
//   ✅ [FIX-2] ລຶບ _storage ທີ່ບໍ່ໄດ້ໃຊ້ໃນ BookingRepository
// ── Rules (kept) ────────────────────────────────────────────
//   ✅ auto-notify ຕອນ status ປ່ຽນ
//   ✅ _updateWallet + transaction
//   ✅ SetOptions(merge: true)
// ============================================================

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'Booking.dart';
import 'fcm_service.dart';
import 'cloudinary_service.dart';

// 🔒 [AUDIT CRIT-5] ກ່ອນໜ້ານີ້ ມີແຕ່ createBooking()/redeemPointsForCoupon()
// ທີ່ມີ .timeout() — ທຸກ write/read ອື່ນໆໃນ repository ນີ້ ຖ້າອອບໄລນ໌ Firestore
// offline persistence ຄ້າງລໍຖ້າ sync ບໍ່ມີກຳນົດ, ປຸ່ມຈະ loading ຄ້າງຕະຫຼອດໄປ
// ໂດຍບໍ່ມີ error ໃຫ້ຜູ້ໃຊ້ເຫັນ. ຕອນນີ້ທຸກ method ຂ້າງລຸ່ມນີ້ ownership ຫຸ້ມດ້ວຍ
// .timeout() ອັນດຽວກັນ ໃຫ້ throw error ຊັດເຈນແທນ ຄ້າງຕະຫຼອດໄປ.
const Duration kNetworkOpTimeout = Duration(seconds: 15);

// 🔒 [AUDIT H-4 / 2026-07-27] Booking.fromFirestore() ຖືກ harden ໃຫ້ບໍ່ throw
// ໃສ່ type ຜິດປົກກະຕິແລ້ວ (ເບິ່ງ _str()/_strN() ໃນ Booking.dart), ແຕ່ນີ້ເປັນ
// defense-in-depth ຊັ້ນທີສອງ: ຖ້າ document ໃດຍັງ throw ຢູ່ (ເຫດຜົນອື່ນທີ່ຄາດ
// ບໍ່ເຖິງ) ໃຫ້ຂ້າມ document ນັ້ນອັນດຽວ ແທນທີ່ຈະໃຫ້ exception ນັ້ນກາຍເປັນ stream
// error ຂອງ "ທັງ list" — ກ່ອນໜ້ານີ້ doc ດຽວທີ່ parse ບໍ່ໄດ້ ຈະເຮັດໃຫ້ວຽກທັງໝົດ
// ຂອງ provider ທຸກຄົນຫາຍໄປຈາກ job board ແບບງຽບໆ (ເບິ່ງ H-4 ໃນ audit report).
List<Booking> _safeMapBookings(QuerySnapshot s) {
  final out = <Booking>[];
  for (final doc in s.docs) {
    try {
      out.add(Booking.fromFirestore(doc));
    } catch (_) {
      // ຂ້າມ document ນີ້ອັນດຽວ — ບໍ່ໃຫ້ affect ວຽກອື່ນໃນ list ດຽວກັນ
    }
  }
  return out;
}

// ════════════════════════════════════════════════════════════
// BOOKING REPOSITORY
// ════════════════════════════════════════════════════════════

class BookingRepository {
  final _db = FirebaseFirestore.instance;
  // ✅ [FIX-2] ລຶບ _storage ທີ່ບໍ່ໄດ້ໃຊ້ໃນ class ນີ້ອອກ
  // ✅ [FIX-1] ໃຊ້ ?? '' ແທນ ! — ປ້ອງກັນ crash ຕອນ logout
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<List<Booking>> watchActiveBookings() {
    // ✅ [FIX ME-1] ເພີ່ມ .limit() ໃຫ້ກົງກັນກັບ query ອື່ນໆໃນ repository ນີ້
    // (watchJobHistory limit 50, watchOpenJobs limit 50) — ວຽກ active ຕາມປົກກະຕິ
    // ມີໜ້ອຍ ແຕ່ນີ້ເປັນຂອບເຂດປ້ອງກັນຖ້າມີວຽກຄ້າງສະຖານະຜິດປົກກະຕິ
    return _db
        .collection('bookings')
        .where('providerId', isEqualTo: _uid)
        .where('status', whereIn: [
      JobStatus.pending.name,
      JobStatus.accepted.name,
      JobStatus.onTheWay.name,
      JobStatus.arrived.name,
      JobStatus.inProgress.name,
    ])
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(_safeMapBookings);
  }

  Stream<List<Booking>> watchJobHistory() {
    return _db
        .collection('bookings')
        .where('providerId', isEqualTo: _uid)
        .where('status', whereIn: [
      JobStatus.completed.name,
      JobStatus.cancelled.name,
      JobStatus.rejected.name,
    ])
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(_safeMapBookings);
  }

  // 🔒 [AUDIT BE-1 / 2026-07-30] ກ່ອນໜ້ານີ້ watchOpenJobs() ດຽວນີ້ filter ດ້ວຍ
  // status ຢ່າງດຽວ — ບໍ່ໄດ້ constrain sentTo ເລີຍ, ຂະນະທີ່ firestore.rules'
  // read rule ອ້າງອີງ resource.data.sentTo (ຜ່ານ isOpenOrTargeted()). Firestore
  // ຕ້ອງການໃຫ້ list-query rule ພິສູດໄດ້ຈາກ filter ຂອງ query ເອງເທົ່ານັ້ນ — query
  // ນີ້ຈຶ່ງຖືກປະຕິເສດທັງໝົດ (permission-denied) ສະເໝີ, ບໍ່ວ່າ provider ຄົນໃດ.
  // ແກ້ໂດຍແຍກເປັນ 2 query ທີ່ພິສູດໄດ້ແຍກກັນ (booking_provider.dart ລວມທັງສອງເຂົ້າ
  // ກັນ): ອັນໜຶ່ງ filter openToAll==true (ພິສູດຕໍ່ກັບ isOpenOrTargeted() ສາຂາ
  // ທຳອິດ), ອີກອັນ filter sentTo array-contains uid (ສາຂາທີສອງ). ບໍ່ໃຊ້ Filter.or()
  // ອັນດຽວ ເພາະ Firestore ບໍ່ໄດ້ຢືນຢັນ (documented) ວ່າ OR ຂ້າມ field ຄົນລະອັນຈະ
  // ພິສູດໄດ້ຄືກັນກັບ 2 query ແຍກ.
  Stream<List<Booking>> watchOpenJobsPublic() {
    return _db
        .collection('bookings')
        .where('status', isEqualTo: JobStatus.pending.name)
        .where('openToAll', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(_safeMapBookings);
  }

  Stream<List<Booking>> watchOpenJobsSentToMe() {
    return _db
        .collection('bookings')
        .where('status', isEqualTo: JobStatus.pending.name)
        .where('sentTo', arrayContains: _uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(_safeMapBookings);
  }

  Stream<Booking> watchBooking(String bookingId) {
    return _db
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .map(Booking.fromFirestore);
  }

  // ── ຮັບງານ ────────────────────────────────────────────────

  // 🔒 [AUDIT H-1 / 2026-07-27] ກ່ອນໜ້ານີ້ transaction ນີ້ຂຽນແຕ່ status/
  // acceptedAt/providerId — ບໍ່ເຄີຍ denormalize ຊື່/ເບີ/ຄະແນນ/ຮູບຊ່າງໃສ່ booking
  // doc ເລີຍ. ແຕ່ match_screen.dart (_onMatched), tracking_screen.dart
  // (_callProvider), booking_display_helpers.dart (providerFromBooking, ໃຊ້ໂດຍ
  // booking_detail_screen.dart/review_screen.dart) ທັງໝົດອ່ານ providerName/
  // providerPhone/providerRating/providerJobs/providerPhoto ໂດຍກົງຈາກ booking
  // doc, ຄາດວ່າມີຄ່າຢູ່ແລ້ວ — ເຮັດໃຫ້ທຸກ booking ຈິງສະແດງຊື່ຊ່າງວ່າງເປົ່າ ແລະ ປຸ່ມ
  // "ໂທຫາຊ່າງ" ບໍ່ເຮັດວຽກ (ເບີວ່າງ). ຕອນນີ້ອ່ານ providers/{uid} ຂອງຕົນເອງພາຍໃນ
  // transaction ດຽວກັນ (Firestore ບັງຄັບ get() ທັງໝົດເກີດກ່ອນ update()/set()
  // ຢູ່ແລ້ວ) ແລ້ວຂຽນ field ເຫຼົ່ານີ້ພ້ອມກັນ. firestore.rules whitelist ຖືກອັບເດດ
  // ໃຫ້ກົງກັນແລ້ວ (ເບິ່ງ isValidSentToTargeting() ນຳ — H-2, ຮັບງານໄດ້ສະເພາະຖ້າ
  // ບໍ່ໄດ້ຖືກຈຳກັດ sentTo ຫຼື ຕົນເອງຢູ່ໃນ sentTo).
  Future<void> acceptBooking(String bookingId) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final ref = _db.collection('bookings').doc(bookingId);
    final providerRef = _db.collection('providers').doc(_uid);
    late Booking b;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      b = Booking.fromFirestore(snap);
      if (b.status != JobStatus.pending) {
        throw Exception('ງານນີ້ມີຄົນຮັບໄປແລ້ວ');
      }
      // 🔒 [AUDIT H-2] ກົງກັບ isValidSentToTargeting() ໃນ firestore.rules —
      // ກວດຢູ່ client ນຳເພື່ອສະແດງ error ທີ່ເຂົ້າໃຈງ່າຍ ແທນ permission-denied ດິບ.
      if (b.sentTo.isNotEmpty && !b.sentTo.contains(_uid)) {
        throw Exception('ງານນີ້ບໍ່ໄດ້ຖືກສົ່ງໃຫ້ທ່ານ');
      }
      final providerSnap = await tx.get(providerRef);
      final p = providerSnap.data() ?? const <String, dynamic>{};
      tx.update(ref, {
        'status':         JobStatus.accepted.name,
        'acceptedAt':     FieldValue.serverTimestamp(),
        'providerId':     _uid,
        'providerName':   p['displayName'] as String? ?? '',
        'providerPhone':  p['phone']       as String? ?? '',
        'providerRating': (p['rating']     as num?)?.toDouble() ?? 0.0,
        'providerJobs':   p['totalJobs']   as int?    ?? 0,
        'providerPhoto':  p['photoUrl']    as String? ?? '',
      });
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));

    // ✅ Cloud Function `onBookingStatusChange` already notifies the customer
    // on every status write — no client-side notification here (was double-firing).
  }

  // ── ປະຕິເສດ ───────────────────────────────────────────────

  // 🔒 [AUDIT H7] ກ່ອນໜ້ານີ້ reject() ປ່ຽນ status ເປັນ 'rejected' (terminal)
  // ສະເໝີ — ບໍ່ວ່າ booking ນີ້ຈະຖືກມອບໝາຍໃຫ້ provider ຄົນນີ້ໂດຍສະເພາະ ຫຼື ຍັງເປັນ
  // ວຽກເປີດຢູ່ໃນ job board (providerId ຍັງວ່າງເປົ່າ, ສົ່ງໃຫ້ provider ຫຼາຍຄົນເບິ່ງ
  // ພ້ອມກັນ). ກໍລະນີຫຼັງ, provider ຄົນດຽວ reject ("ໄກເກີນໄປ") ຈະຂ້າ booking
  // ນັ້ນຖິ້ມທັນທີ ເຖິງແມ່ນ provider ອື່ນອາດຮັບໄດ້ພາຍໃນວິນາທີຕໍ່ມາ. ຕອນນີ້ແຍກ 2
  // ກໍລະນີ: (1) ບໍ່ມີ providerId ມາກ່ອນ → ບັນທຶກວ່າຕົນເອງ reject ໄປແລ້ວ
  // (rejectedBy) ແຕ່ຄົງ status='pending' ໄວ້ໃຫ້ provider ອື່ນຍັງເຫັນ/ຮັບໄດ້;
  // (2) ຖືກມອບໝາຍໂດຍສະເພາະ (providerId == ຕົນເອງ, ເຊັ່ນ ລູກຄ້າຈອງຊ່າງຄົນນີ້
  // ໂດຍກົງຜ່ານ provider_details_screen.dart) → ບໍ່ມີ "board" ໃຫ້ຖອຍໄປ, reject
  // ຈຶ່ງ terminal ແທ້ ຄືເກົ່າ.
  Future<void> rejectBooking(String bookingId, String reason) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final b = Booking.fromFirestore(snap);
      if (b.status == JobStatus.completed || b.status == JobStatus.cancelled) {
        throw Exception('ບໍ່ສາມາດປະຕິເສດໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
      }
      if (b.providerId.isEmpty || b.providerId != _uid) {
        // ວຽກເປີດຢູ່ໃນ job board — ບໍ່ໄດ້ຖືກມອບໝາຍໃຫ້ຕົນເອງໂດຍສະເພາະ
        tx.update(ref, {
          'rejectedBy': FieldValue.arrayUnion([_uid]),
          'updatedAt':  FieldValue.serverTimestamp(),
        });
      } else {
        // ຖືກມອບໝາຍໃຫ້ຕົນເອງໂດຍສະເພາະ (ຈອງກົງ) — reject ຈົບຈິງ
        tx.update(ref, {
          'status':       JobStatus.rejected.name,
          'cancelReason': reason,
        });
      }
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));

    // ✅ Cloud Function `onBookingStatusChange` already notifies the customer
    // on every status write — no client-side notification here (was double-firing).
    // ✅ onBookingStatusChange ຮັບຮູ້ສະເພາະ status change ຈິງ — ກໍລະນີ (1) ຂ້າງ
    // ເທິງບໍ່ໄດ້ປ່ຽນ status ເລີຍ ຈຶ່ງບໍ່ trigger notification ໃດ, ຖືກຕ້ອງແລ້ວ
    // (ລູກຄ້າບໍ່ຄວນຮູ້ວ່າມີ provider ຄົນໜຶ່ງປະຕິເສດ, ຕາບໃດທີ່ຍັງມີຄົນອື່ນຮັບໄດ້).
  }

  // ── ຍົກເລີກວຽກ (ຫຼັງຮັບງານໄປແລ້ວ) ──────────────────────────
  // 🔒 [AUDIT PROV-2 / 2026-07-30] ຊ່າງທີ່ຮັບງານໄປແລ້ວ (accepted/onTheWay/
  // arrived/inProgress) ບໍ່ເຄີຍມີທາງຍົກເລີກໄດ້ເລີຍຖ້າເຮັດຕໍ່ບໍ່ໄດ້ (ລົດເສຍ,
  // ສຸກເສີນ) — booking ຄ້າງຢູ່ນັ້ນຕະຫຼອດໄປ ຈົນກວ່າລູກຄ້າຈະສັງເກດເຫັນເອງແລ້ວຍົກເລີກ
  // ຝ່າຍລູກຄ້າ. firestore.rules ອະນຸຍາດ status→cancelled ຈາກ state ເຫຼົ່ານີ້ຢູ່ແລ້ວ
  // (isValidBookingStatusTransition) ແລະ ອະນຸຍາດໃຫ້ provider (ເຈົ້າຂອງ) ຂຽນ
  // status/cancelReason/cancelledBy ຢູ່ແລ້ວ (hasOnly list) — ພຽງແຕ່ບໍ່ເຄີຍມີ
  // method ໃດເອີ້ນມັນເລີຍ. ບໍ່ຕັ້ງ cancelFeeAmount ເລີຍ (ຕ່າງຈາກ
  // CustomerBookingRepository.cancelBooking()) — ຊ່າງຍົກເລີກເອງບໍ່ແມ່ນຄວາມຜິດ
  // ຂອງລູກຄ້າ, ບໍ່ຄວນມີຄ່າທຳນຽມ. updateProviderJobStats() (functions/index.js)
  // ຄິດໄລ່ completionRate ໃໝ່ໂດຍອັດຕະໂນມັດຢູ່ແລ້ວທຸກຄັ້ງທີ່ status ປ່ຽນເປັນ
  // cancelled — ບໍ່ຕ້ອງແກ້ໄຂຝັ່ງ Cloud Function ສຳລັບສ່ວນນີ້.
  Future<void> providerCancelBooking(String bookingId, String reason) async {
    if (_uid.isEmpty) return;
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Booking.fromFirestore(snap);

      if (b.providerId != _uid) {
        throw Exception('ບໍ່ແມ່ນວຽກຂອງທ່ານ');
      }
      if (b.status.isFinished) {
        throw Exception('ບໍ່ສາມາດຍົກເລີກໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
      }

      tx.update(ref, {
        'status':       JobStatus.cancelled.name,
        'cancelReason': reason,
        'cancelledBy':  'provider',
      });
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  // ── ອັບເດດ status ─────────────────────────────────────────

  // 🔒 [AUDIT CRIT-1] ນີ້ແມ່ນຊ່າງຢືນຢັນວ່າໄດ້ຮັບເງິນແລ້ວ (cash ໃນມື ຫຼື ເຫັນ BCEL
  // ໂອນເຂົ້າແທ້) ກ່ອນປິດງານ — ບໍ່ມີ payment gateway webhook ແທ້. ກ່ອນໜ້ານີ້
  // method ນີ້ບໍ່ມີ caller ຢູ່ໃນ UI ໃດເລີຍ (ບໍ່ມີປຸ່ມ/ໜ້າຈໍໃດເອີ້ນ) — ໝາຍຄວາມວ່າ
  // updateStatus(completed) ຂ້າງລຸ່ມນີ້ throw ຕະຫຼອດເວລາ ແລະ ບໍ່ມີວຽກໃດປິດ
  // ໄດ້ຈັກອັນ. ຕອນນີ້ເອີ້ນຈາກ job_workflow_Screen.dart ຜ່ານ
  // BookingNotifier.confirmPayment() (booking_provider.dart) ເປັນ step ກ່ອນ
  // "ສຳເລັດວຽກ" ຕອນ status == inProgress.
  Future<void> confirmPaymentReceived(String bookingId) async {
    if (_uid.isEmpty) return;
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('ບໍ່ພົບຂໍ້ມູນການຈອງນີ້');
      }
      final b = Booking.fromFirestore(snap);
      if (b.providerId != _uid) {
        throw Exception('ທ່ານບໍ່ແມ່ນຊ່າງທີ່ຮັບຜິດຊອບງານນີ້');
      }
      if (b.status.isFinished) {
        throw Exception('ບໍ່ສາມາດຢືນຢັນໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
      }
      if (b.paymentStatus == 'paid') return; // idempotent — already confirmed
      // 🔒 [FOLLOWUP-K] ກ່ອນໜ້ານີ້ຊ່າງຢືນຢັນຝ່າຍດຽວໄດ້ໝົດ, ບໍ່ວ່າຈະ cash ຫຼື BCEL
      // — ບໍ່ມີການກວດຄືນຈາກລູກຄ້າ. cash ຍັງຄົງ self-attested ຕໍ່ໄປ (ຍອມຮັບເປັນ
      // ຂໍ້ຈຳກັດ, ບໍ່ມີ payment gateway ແທ້), ແຕ່ BCEL (ໂອນເງິນ) ຕອນນີ້ຕ້ອງການໃຫ້
      // ລູກຄ້າກົດ "ຢືນຢັນວ່າໄດ້ໂອນເງິນແລ້ວ" (customerConfirmedPayment,
      // tracking_screen.dart) ກ່ອນ — ປ້ອງກັນຊ່າງປອມການຢືນຢັນເພື່ອດຶງ wallet
      // credit ຂອງຕົນເອງ.
      if (b.paymentMethod != 'cash' && !b.customerConfirmedPayment) {
        throw Exception('ລໍຖ້າລູກຄ້າຢືນຢັນການໂອນເງິນກ່ອນຈຶ່ງຈະປິດງານໄດ້');
      }
      tx.update(ref, {'paymentStatus': 'paid'});
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  Future<void> updateStatus(String bookingId, JobStatus status) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final ref = _db.collection('bookings').doc(bookingId);
    final doc = await ref.get().timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    final b   = Booking.fromFirestore(doc);

    if (status == JobStatus.completed && b.paymentStatus != 'paid') {
      throw Exception('ກະລຸນາຢືນຢັນການຮັບເງິນກ່ອນປິດງານ');
    }

    final data = <String, dynamic>{'status': status.name};
    if (status == JobStatus.completed) {
      data['completedAt'] = FieldValue.serverTimestamp();
    }
    await ref.update(data).timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));

    // ✅ Cloud Function `onBookingStatusChange` is the single source of truth
    // for side effects (notifications, wallet increment, transaction record)
    // on every status transition. Doing it here too was double-crediting the
    // provider's wallet on every completed booking.
  }

  // ── Photos ────────────────────────────────────────────────

  Future<String> uploadJobPhoto(
      String bookingId,
      File photo, {
        required bool isBefore,
      }) async {
    final url = await CloudinaryService.instance
        .uploadJobPhoto(bookingId, photo, isBefore: isBefore);
    if (url == null) throw Exception('Upload failed');
    return url;
  }

  // ── Additional charges ────────────────────────────────────

  Future<void> requestAdditionalCharges(
      String bookingId,
      double amount,
      String note,
      ) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    if (amount <= 0) throw Exception('ຈຳນວນເງິນຕ້ອງຫຼາຍກວ່າ 0');
    final ref = _db.collection('bookings').doc(bookingId);
    final doc = await ref.get().timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    final b   = Booking.fromFirestore(doc);

    await ref.update({
      'additionalCharges':         amount,
      'additionalChargesNote':     note,
      'additionalChargesApproved': false,
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));

    await NotificationSender.additionalCharges(
      customerId: b.customerId,
      bookingId:  bookingId,
      amount:     amount,
      note:       note,
    );
  }
}

// ════════════════════════════════════════════════════════════
// CUSTOMER BOOKING REPOSITORY (ຝັ່ງລູກຄ້າ — ສ້າງ booking ໃໝ່)
// ════════════════════════════════════════════════════════════

class CustomerBookingRepository {
  final _db = FirebaseFirestore.instance;

  // ✅ idempotent: ໃຊ້ clientRequestId ເປັນ doc id — ກົດຈອງຊໍ້າ/network retry
  // ຈະ overwrite doc ດຽວກັນ ບໍ່ສ້າງ booking ຊໍ້າ.
  //
  // 🔒 [AUDIT QA-1 / HI-7] ກ່ອນໜ້ານີ້ exists-check (`ref.get()`) ເກີດຂຶ້ນກ່ອນ
  // WriteBatch ຄົນລະ round-trip — ບໍ່ atomic. ຖ້າ submit ຖືກເອີ້ນຊ້ຳພ້ອມກັນ
  // (double-tap, retry ຫຼັງເນັດຂາດ) ທັງສອງ invocation ອາດອ່ານ
  // existing.exists==false ພ້ອມກັນກ່ອນອັນໃດຈະຂຽນ — booking doc converge ເປັນ
  // ອັນດຽວ (doc ID ດຽວກັນ) ແຕ່ coupon usedCount ຈະຖືກ increment ຊ້ຳສອງເທື່ອ
  // ສຳລັບ booking ດຽວ. ຕອນນີ້ໃຊ້ runTransaction ດຽວໃຫ້ exists-check + booking
  // write + coupon increment ເປັນ atomic ທັງໝົດ (Firestore ບັງຄັບໃຫ້ທຸກ get()
  // ໃນ transaction ເກີດກ່ອນ set()/update() ໃດໆ ຢູ່ແລ້ວ).
  Future<String> createBooking(Map<String, dynamic> data, {String? couponCode}) async {
    final clientRequestId = data['clientRequestId'] as String?;
    final ref = (clientRequestId == null || clientRequestId.isEmpty)
        ? _db.collection('bookings').doc()
        : _db.collection('bookings').doc(clientRequestId);

    // 🔒 [AUDIT BE-1 / 2026-07-30] openToAll ຕ້ອງຖືກຕັ້ງຄ່າຕອນສ້າງ booking ທຸກຄັ້ງ
    // ໃຫ້ firestore.rules' isValidOpenToAllFlag() ຜ່ານ, ແລະ ໃຫ້ provider ເຫັນວຽກນີ້
    // ຜ່ານ watchOpenJobsPublic() ກ່ອນຈະຖືກ match_screen.dart ຂຽນ sentTo. ຄິດໄລ່ຈາກ
    // *ຄ່າ* ຂອງ providerId (ບໍ່ແມ່ນແຕ່ data.containsKey('providerId')) ເພື່ອບໍ່ໃຫ້
    // ເກີດບັນຫາ undefined-vs-absent ຄືກັນກັບ BE-2 (onNewBooking, functions/index.js)
    // — ຖ້າ caller ໃນອະນາຄົດປ່ຽນມາສົ່ງ 'providerId': null ຫຼື '' ແທນທີ່ຈະ omit key
    // ໄປເລີຍ, ການກວດຄ່າແບບນີ້ຍັງຖືກຕ້ອງຢູ່. createBooking() ນີ້ເປັນຈຸດດຽວທີ່ທັງ
    // booking_form_screen.dart ແລະ quick_booking_provider.dart ຮຽກ — ບໍ່ຕ້ອງແກ້ໄຂ
    // ຈຸດອື່ນອີກ.
    final pid = data['providerId'];
    data['openToAll'] = !(pid is String && pid.isNotEmpty);

    // ✅ [AUDIT C5] ລວມ referral lookup ໄວ້ບ່ອນດຽວແທນທີ່ຈະໃຫ້ແຕ່ລະໜ້າຈໍຈອງ
    // (quick_booking_provider.dart, booking_form_screen.dart) ຂຽນແຍກກັນເອງ —
    // ກ່ອນໜ້ານີ້ມີແຕ່ Quick Booking flow ທີ່ໃສ່ field 'referralCode' ໃຫ້,
    // booking_form_screen.dart (ໜ້າຈອງຫຼັກ ໃຊ້ຫຼາຍທີ່ສຸດ) ບໍ່ໄດ້ໃສ່ເລີຍ —
    // ເຮັດໃຫ້ໂປຣແກຣມແນະນຳໝູ່ (onNewBooking ໃນ functions/index.js ອ່ານ field
    // ນີ້) ບໍ່ໄດ້ຜົນສຳລັບການຈອງສ່ວນຫຼາຍແບບງຽບໆ. ຕອນນີ້ createBooking() ດຶງ
    // users/{customerId}.referredBy ໃຫ້ອັດຕະໂນມັດ ຖ້າຜູ້ຮຽກຍັງບໍ່ໄດ້ໃສ່ມາເອງ.
    // (read-only lookup — ບໍ່ຕ້ອງການ atomicity ກັບການສ້າງ booking, ດຶງກ່ອນເຂົ້າ
    // transaction ໄດ້ຢ່າງປອດໄພ)
    if (!data.containsKey('referralCode')) {
      final customerId = data['customerId'] as String?;
      if (customerId != null && customerId.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(customerId).get();
        final referredBy = userDoc.data()?['referredBy'] as String?;
        if (referredBy != null && referredBy.isNotEmpty) {
          data['referralCode'] = referredBy;
        }
      }
    }

    final couponRef = (couponCode != null && couponCode.isNotEmpty)
        ? _db.collection('coupons').doc(couponCode.trim().toUpperCase())
        : null;

    // 🔒 [AUDIT QA-1 / HI-8] ກ່ອນໜ້ານີ້ບໍ່ມີ timeout ເລີຍ — ຖ້າອອບໄລນ໌ Firestore
    // offline persistence ຈະຄ້າງລໍຖ້າ sync ບໍ່ມີກຳນົດ, spinner ຄ້າງຕະຫຼອດໄປ, ບໍ່ມີ
    // error ໃຫ້ຜູ້ໃຊ້ເຫັນ. ຕອນນີ້ timeout ຫຼັງ 20 ວິນາທີ ແລ້ວ throw ໃຫ້ caller
    // (booking_form_screen.dart _submit() / quick_booking_provider.dart
    // confirmBooking()) ສະແດງ error ແລະ ປົດລ໋ອກປຸ່ມ — ຜູ້ໃຊ້ກົດ submit ຄືນໄດ້
    // ໂດຍໃຊ້ clientRequestId ດຽວກັນ (idempotent, ບໍ່ສ້າງ booking ຊ້ຳ) ແທນທີ່ຈະ
    // ອອກຈາກໜ້າແລ້ວເປີດໃໝ່ (ເຊິ່ງຈະໄດ້ order/draft ໃໝ່ ແລະ ID ໃໝ່).
    await _db.runTransaction((tx) async {
      if (clientRequestId != null && clientRequestId.isNotEmpty) {
        final existing = await tx.get(ref);
        if (existing.exists) return;
      }

      // 🔒 [AUDIT H1] ກ່ອນໜ້ານີ້ tx.update(couponRef, {usedCount: increment(1)})
      // ບໍ່ເຄີຍ re-check status/validUntil/usageLimit ພາຍໃນ transaction ເລີຍ —
      // CouponRepository.validate() ກວດຄ່າເຫຼົ່ານີ້ພຽງແຕ່ຕອນພິມລະຫັດ (ອາດຫ່າງ
      // ຈາກ submit ຫຼາຍນາທີ), ແລະ firestore.rules ອະນຸຍາດ increment ໂດຍບໍ່ກວດ
      // ຂອບເຂດຫຍັງເລີຍນອກຈາກ usedCount+1. Coupon usageLimit:100 ຈຶ່ງຖືກໃຊ້ໄດ້
      // ບໍ່ຈຳກັດພາຍໃຕ້ concurrent/serial redemption. ຕອນນີ້ re-read + re-validate
      // ພາຍໃນ transaction ດຽວກັນ (ກ່ອນ write ໃດໆ, ຕາມກົດ Firestore transaction)
      // ແລ້ວ abort ທັງ booking ນີ້ຖ້າ coupon ບໍ່ຖືກຕ້ອງອີກຕໍ່ໄປ — ຜູ້ໃຊ້ຈະເຫັນ
      // error ແລະ ຕ້ອງ submit ຄືນໃໝ່ (ອາດຕ້ອງແກ້/ຖອນ coupon code).
      if (couponRef != null) {
        final couponSnap = await tx.get(couponRef);
        if (!couponSnap.exists) {
          throw Exception('ລະຫັດສ່ວນຫຼຸດບໍ່ຖືກຕ້ອງ ຫຼື ຖືກລຶບໄປແລ້ວ');
        }
        final c = couponSnap.data()!;
        final status = c['status'] as String? ?? 'inactive';
        if (status != 'active') {
          throw Exception('ລະຫັດສ່ວນຫຼຸດນີ້ບໍ່ສາມາດໃຊ້ໄດ້ອີກຕໍ່ໄປ');
        }
        final now = DateTime.now();
        final validFrom = (c['validFrom'] as Timestamp?)?.toDate();
        final validUntil = (c['validUntil'] as Timestamp?)?.toDate();
        if (validFrom != null && now.isBefore(validFrom)) {
          throw Exception('ລະຫັດສ່ວນຫຼຸດນີ້ຍັງບໍ່ທັນເລີ່ມໃຊ້ໄດ້');
        }
        if (validUntil != null && now.isAfter(validUntil)) {
          throw Exception('ລະຫັດສ່ວນຫຼຸດນີ້ໝົດອາຍຸແລ້ວ');
        }
        final usageLimit = c['usageLimit'] as num?;
        final usedCount = (c['usedCount'] as num?) ?? 0;
        if (usageLimit != null && usedCount >= usageLimit) {
          throw Exception('ລະຫັດສ່ວນຫຼຸດນີ້ຖືກໃຊ້ຄົບຈຳນວນແລ້ວ');
        }
      }

      tx.set(ref, data);
      if (couponRef != null) {
        tx.update(couponRef, {'usedCount': FieldValue.increment(1)});
      }
    }).timeout(const Duration(seconds: 20));
    return ref.id;
  }

  // ── ຍົກເລີກ (ຝັ່ງລູກຄ້າ) ─────────────────────────────────────
  // fee = 0 ກ່ອນຊ່າງຮັບ ຫຼື ພາຍໃນ 2 ນາທີຫຼັງຮັບ; ຫຼັງຈາກນັ້ນ (onTheWay/arrived) = 20,000₭
  // ✅ Transaction: ກວດ status ໃໝ່ສຸດພາຍໃນ transaction ກ່ອນຂຽນ — ປ້ອງກັນ
  // overwrite booking ທີ່ provider ປິດເປັນ completed ໄປແລ້ວໃນຊ່ວງເວລາດຽວກັນ
  Future<void> cancelBooking(String bookingId, String reason) async {
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Booking.fromFirestore(snap);

      if (b.status == JobStatus.completed || b.status == JobStatus.cancelled) {
        throw Exception('ບໍ່ສາມາດຍົກເລີກໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
      }

      double fee = 0;
      if (b.status == JobStatus.onTheWay || b.status == JobStatus.arrived) {
        final acceptedAt = b.acceptedAt;
        final withinGrace = acceptedAt != null &&
            DateTime.now().difference(acceptedAt) < const Duration(minutes: 2);
        fee = withinGrace ? 0 : 20000;
      }

      tx.update(ref, {
        'status':          JobStatus.cancelled.name,
        'cancelReason':    reason,
        'cancelledBy':     'customer',
        'cancelFeeAmount': fee,
      });
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  // ── ອະນຸມັດ/ປະຕິເສດ ຄ່າໃຊ້ຈ່າຍເພີ່ມ (ຝັ່ງລູກຄ້າ) ──────────────
  Future<void> respondToAdditionalCharges(String bookingId, bool approve) async {
    final ref = _db.collection('bookings').doc(bookingId);
    if (approve) {
      await ref.update({'additionalChargesApproved': true});
    } else {
      await ref.update({
        'additionalChargesApproved': false,
        'additionalCharges':         null,
        'additionalChargesNote':     null,
      });
    }
  }

  // ── ຢືນຢັນວ່າໄດ້ໂອນເງິນແລ້ວ (ຝັ່ງລູກຄ້າ, BCEL) ─────────────
  // 🔒 [FOLLOWUP-K] counter-signature ກ່ອນຊ່າງຈະຢືນຢັນຮັບເງິນໄດ້
  // (confirmPaymentReceived() ຂ້າງເທິງ, ຝັ່ງ BookingRepository).
  Future<void> confirmPaymentSent(String bookingId) async {
    final ref = _db.collection('bookings').doc(bookingId);
    await ref.update({'customerConfirmedPayment': true})
        .timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }
}

// ════════════════════════════════════════════════════════════
// EARNINGS REPOSITORY
// ════════════════════════════════════════════════════════════

class EarningsRepository {
  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  // ✅ [FIX-1] ?? '' ແທນ !
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<Wallet> watchWallet() {
    return _db.collection('wallets').doc(_uid).snapshots().map(
          (doc) => doc.exists ? Wallet.fromFirestore(doc) : Wallet.empty(_uid),
    );
  }

  Stream<List<ProviderTransaction>> watchTransactions() {
    return _db
        .collection('transactions')
        .where('providerId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((s) => s.docs
        .map(ProviderTransaction.fromFirestore)
        .toList());
  }

  Future<void> requestWithdrawal(double amount) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final walletDoc = await _db.collection('wallets').doc(_uid).get()
        .timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    final balance   = (walletDoc.data()?['balance'] as num?)
        ?.toDouble() ?? 0;
    if (amount < 50000) throw Exception('ຂັ້ນຕ່ຳ ₭50,000');
    if (amount > balance) throw Exception('ຍອດບໍ່ພໍ');
    await _db.collection('withdrawalRequests').add({
      'providerId': _uid,
      'amount':     amount,
      'status':     'pending',
      'createdAt':  FieldValue.serverTimestamp(),
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  // 🔒 [AUDIT CRIT-5 follow-up] file upload ໃຊ້ເວລາດົນກວ່າ Firestore query
  // ໂດຍທຳມະຊາດ — timeout ດົນກວ່າ kNetworkOpTimeout (ຄືກັນກັບ ProfileRepository.
  // uploadProfilePhoto/uploadKyc ຂ້າງເທິງ).
  static const _kUploadTimeout = Duration(seconds: 30);

  // ✅ [Top-up slip] ຮູບ slip ໂອນເງິນ — admin ຕ້ອງເບິ່ງຮູບນີ້ກ່ອນອະນຸມັດ (ບໍ່ມີ
  // ຮູບ = ບໍ່ມີຫຼັກຖານການໂອນຈິງ). path ແຍກຕໍ່ provider, ຊື່ໄຟລ໌ unique ຕໍ່ຄຳຂໍ
  // (timestamp) ບໍ່ໃຫ້ຄຳຂໍໃໝ່ຂຽນທັບຮູບຂອງຄຳຂໍເກົ່າ. ເບິ່ງ storage.rules —
  // topupRequests/{uid}/** ຂຽນ/ອ່ານໄດ້ສະເພາະເຈົ້າຂອງ (admin ອ່ານຜ່ານ token
  // ໃນ download URL ທີ່ເກັບໄວ້ໃນ Firestore ໂດຍກົງ, ຄືກັນກັບ KYC).
  Future<String> uploadTopupSlip(File slip) async {
    final fileName = 'slip_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final task = await _storage
        .ref('topupRequests/$_uid/$fileName')
        .putFile(slip, SettableMetadata(contentType: 'image/jpeg'))
        .timeout(_kUploadTimeout, onTimeout: () => throw Exception(
            'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)'));
    return task.ref.getDownloadURL().timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  // 🔒 [Top-up] ຄືກັນກັບ requestWithdrawal() — client ບໍ່ສາມາດຂຽນ
  // wallets/{uid}.balance ຫຼື transactions/{id} ໂດຍກົງໄດ້ເລີຍ (firestore.rules
  // ບັງຄັບໃຫ້ຜ່ານ Admin SDK ເທົ່ານັ້ນ, ເບິ່ງ [AUDIT C3]/[FOLLOWUP-1]). ຄຳຂໍນີ້ພຽງແຕ່
  // ບັນທຶກຄວາມຕັ້ງໃຈຕື່ມເງິນ ('pending') — admin ຕ້ອງກວດການໂອນຈິງຜ່ານທະນາຄານ
  // ກ່ອນຈຶ່ງເພີ່ມຍອດ+ສ້າງ transaction ຈິງ (ຄືກັນກັບຂະບວນການອະນຸມັດຄຳຂໍຖອນເງິນ)
  // — ບໍ່ດັ່ງນັ້ນ provider ຄົນໃດກໍໄດ້ຈະສາມາດຕື່ມເງິນປອມເຂົ້າ wallet ຕົນເອງໄດ້
  // ໂດຍບໍ່ຕ້ອງໂອນເງິນຈິງເລີຍ. slipUrl ບັງຄັບ (upload ກ່ອນຢູ່ UI, ເບິ່ງ
  // earnings_tab.dart) — ບໍ່ມີຮູບ = admin ບໍ່ມີທາງກວດການໂອນໄດ້ເລີຍ.
  Future<void> requestTopup(double amount, {required String slipUrl}) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    if (amount < 10000) throw Exception('ຂັ້ນຕ່ຳ ₭10,000');
    await _db.collection('topupRequests').add({
      'providerId': _uid,
      'amount':     amount,
      'slipUrl':    slipUrl,
      'status':     'pending',
      'createdAt':  FieldValue.serverTimestamp(),
    }).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }

  Future<void> updateBankInfo({
    required String bankName,
    required String bankAccount,
    required String bankHolder,
  }) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    await _db.collection('wallets').doc(_uid).set({
      'bankName':    bankName,
      'bankAccount': bankAccount,
      'bankHolder':  bankHolder,
      'updatedAt':   FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
  }
}

// ════════════════════════════════════════════════════════════
// PROFILE REPOSITORY
// ════════════════════════════════════════════════════════════

class ProfileRepository {
  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth    = FirebaseAuth.instance;
  // ✅ [FIX-1] ?? '' ແທນ !
  String get _uid => _auth.currentUser?.uid ?? '';

  Stream<ProviderProfile> watchProfile() {
    return _db.collection('providers').doc(_uid).snapshots()
        .asyncMap((doc) async {
      if (!doc.exists) {
        final user = _auth.currentUser;
        await _db.collection('providers').doc(_uid).set({
          'displayName':    user?.displayName ?? '',
          'email':          user?.email       ?? '',
          'isOnline':       false,
          'kycStatus':      'none',
          'serviceTypes':   <String>[],
          'fcmTokens':      <String>[],
          'rating':         0.0,
          'totalJobs':      0,
          'completionRate': 0.0,
          'createdAt':      FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return ProviderProfile(
          uid:         _uid,
          displayName: user?.displayName ?? '',
          email:       user?.email       ?? '',
        );
      }
      return ProviderProfile.fromFirestore(doc);
    });
  }

  // 🔒 [AUDIT CRIT-5 follow-up] uploadProfilePhoto()/uploadKyc() ໄດ້ timeout
  // ຂັ້ນຕອນ upload ຮູບແລ້ວ, ແຕ່ call ນີ້ (ຂຽນ url ກັບຄືນ providers/{uid}) ຢູ່
  // ທ້າຍ method ທັງສອງບໍ່ມີ timeout — ຍັງຄ້າງໄດ້ຢູ່ຂັ້ນຕອນສຸດທ້າຍນີ້.
  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    await _db.collection('providers').doc(_uid).set(
      {...data, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    ).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    if (data.containsKey('displayName')) {
      await _auth.currentUser
          ?.updateDisplayName(data['displayName'] as String)
          .timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
              'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    }
  }

  // 🔒 [AUDIT CRIT-5] ອັບໂຫລດຮູບ (network-bound, ບໍ່ແມ່ນ Firestore) ບໍ່ເຄີຍມີ
  // timeout — ຖ້າອັບໂຫລດຄ້າງ (ອອບໄລນ໌/ອິນເຕີເນັດອ່ອນ) ໜ້າຈໍຈະ loading ຄ້າງ
  // ຕະຫຼອດໄປ. ໃຊ້ timeout ດົນກວ່າ query ທຳມະດາ (30s) ເພາະ file upload ໃຊ້ເວລາ
  // ດົນກວ່າໂດຍທຳມະຊາດ.
  static const _kUploadTimeout = Duration(seconds: 30);

  Future<String> uploadProfilePhoto(File photo) async {
    final ref  = _storage.ref('providers/$_uid/profile.jpg');
    final task = await ref.putFile(
        photo, SettableMetadata(contentType: 'image/jpeg'))
        .timeout(_kUploadTimeout, onTimeout: () => throw Exception(
            'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)'));
    final url  = await task.ref.getDownloadURL().timeout(kNetworkOpTimeout,
        onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    await updateProfile({'photoUrl': url});
    return url;
  }

  Future<void> uploadKyc({
    required File idPhoto,
    required File selfiePhoto,
  }) async {
    final idUrl = await (await _storage
        .ref('kyc/$_uid/id.jpg')
        .putFile(idPhoto)
        .timeout(_kUploadTimeout, onTimeout: () => throw Exception(
            'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)')))
        .ref
        .getDownloadURL()
        .timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    final selfieUrl = await (await _storage
        .ref('kyc/$_uid/selfie.jpg')
        .putFile(selfiePhoto)
        .timeout(_kUploadTimeout, onTimeout: () => throw Exception(
            'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)')))
        .ref
        .getDownloadURL()
        .timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
            'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    // 🔒 [AUDIT KYC-1] ຮູບບັດປະຈຳຕົວ/selfie ຫ້າມຢູ່ໃນ providers/{uid} — doc ນັ້ນ
    // ອ່ານໄດ້ໂດຍ user login ໃດກໍໄດ້ (firestore.rules). ເກັບໄວ້ໃນ kyc/{uid} ແທນ
    // (ອ່ານໄດ້ສະເພາະເຈົ້າຂອງ/admin), ແລະ kycStatus ຢູ່ໃນ providers/{uid} ຄືເກົ່າ
    // ເພາະຍັງຕ້ອງໃຊ້ໂດຍ isVerifiedProvider() (firestore.rules).
    await _db.collection('kyc').doc(_uid).set({
      'idDocUrl':  idUrl,
      'selfieUrl': selfieUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(kNetworkOpTimeout, onTimeout: () => throw Exception(
        'ໝົດເວລາການເຊື່ອມຕໍ່, ກະລຸນາລອງໃໝ່ (connection timed out)'));
    await updateProfile({
      'kycStatus': KycStatus.pending.name,
    });
  }

  Stream<WorkSchedule> watchSchedule() {
    return _db.collection('schedules').doc(_uid).snapshots().map(
          (doc) => doc.exists
          ? WorkSchedule.fromFirestore(doc)
          : WorkSchedule.defaultSchedule(),
    );
  }

  Future<void> saveSchedule(WorkSchedule schedule) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    await _db.collection('schedules').doc(_uid).set(
      {...schedule.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Stream<List<Review>> watchReviews() {
    return _db
        .collection('providers').doc(_uid)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((s) => s.docs.map(Review.fromFirestore).toList());
  }

  Future<void> replyToReview(String reviewId, String reply) async {
    await _db
        .collection('providers').doc(_uid)
        .collection('reviews').doc(reviewId)
        .update({'providerReply': reply});
  }
}