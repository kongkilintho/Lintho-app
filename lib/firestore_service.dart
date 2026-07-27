// ============================================================
// firestore_service.dart — LinTho
// Fixes:
//   ✅ [FIX-1] ລຶບ ProviderModel ເກົ່າອອກ — ໃຊ້ provider_model.dart ແທນ
//   ✅ [FIX-2] ລຶບ BookingStatus ເກົ່າອອກ — ໃຊ້ອັນໃນ main.dart ແທນ
//   ✅ [FIX-3] import provider_model.dart
//   🔒 [AUDIT H-1 / L-1] ລຶບ dead legacy methods ອອກ (saveUser/getUser/
//      getAllUsers/createBooking/getProviderJobs/getAllBookings/
//      acceptBooking/getServices/getStats) — ບໍ່ມີ caller, ແລະ ໜຶ່ງໃນນັ້ນ
//      (acceptBooking) ເປັນສາເຫດທີ່ເຮັດໃຫ້ H-1 bug ຖືກຫຼົງເບິ່ງຂ້າມ.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ✅ [FIX-3] import ProviderModel ຈາກ provider_model.dart
import 'provider_model.dart';

// ════════════════════════════════════════════════════════════
// REVIEW MODEL
// ════════════════════════════════════════════════════════════

class ReviewModel {
  final String   reviewId;
  final String   customerId;
  final String   customerName;
  final String   customerPhoto;
  final double   rating;
  final String   comment;
  final DateTime createdAt;

  ReviewModel({
    required this.reviewId,
    required this.customerId,
    required this.customerName,
    required this.customerPhoto,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ReviewModel.fromMap(String id, Map<String, dynamic> map) {
    return ReviewModel(
      reviewId:      id,
      customerId:    map['customerId']    as String? ?? '',
      customerName:  map['customerName']  as String? ?? '',
      customerPhoto: map['customerPhoto'] as String? ?? '',
      rating:        (map['rating'] as num?)?.toDouble() ?? 0.0,
      comment:       map['comment']       as String? ?? '',
      createdAt:     (map['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }
}

// ════════════════════════════════════════════════════════════
// FIRESTORE SERVICE
// ════════════════════════════════════════════════════════════

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ── BOOKINGS ──────────────────────────────────────────────
  //
  // 🔒 [AUDIT H-1 / L-1 / 2026-07-27] ໜ້ານີ້ເຄີຍມີ saveUser()/getUser()/
  // getAllUsers()/createBooking()/getProviderJobs()/getAllBookings()/
  // acceptBooking()/getServices()/getStats() — ທັງໝົດເປັນ implementation ເກົ່າ
  // ຈາກກ່ອນແອັບຖືກປັບໂຄງສ້າງໄປໃຊ້ BookingRepository/CustomerBookingRepository
  // (booking_repository.dart) ແລະ ບໍ່ມີ caller ໃດເອີ້ນເລີຍ (ຢືນຢັນແລ້ວດ້ວຍ grep
  // ທົ່ວ lib/). ອັນຕະລາຍທີ່ພົບ: acceptBooking() ຂ້າງລຸ່ມນີ້ (ລຶບອອກແລ້ວ) ຂຽນ
  // providerName ຖືກຕ້ອງ — ໃນຂະນະທີ່ BookingRepository.acceptBooking() ຈິງ
  // (ໜ້າຈໍທຸກໜ້າເອີ້ນ) ບໍ່ເຄີຍຂຽນເລີຍ (H-1 bug, ແກ້ໄຂແລ້ວ). ໂຄ້ດເກົ່ານີ້ເຮັດໃຫ້
  // reviewer ຄົ້ນຫາ "acceptBooking ຂຽນ providerName ບໍ" ພົບ copy ນີ້ກ່ອນ ແລ້ວ
  // ເຂົ້າໃຈຜິດວ່າ bug ບໍ່ມີ. ລຶບອອກທັງໝົດເພື່ອບໍ່ໃຫ້ເກີດຄວາມສັບສົນຊ້ຳອີກ.
  //
  // 🔒 [AUDIT H13] ບໍ່ເຄີຍມີ .limit()/.orderBy() ຢູ່ນີ້ — listener ນີ້ຖືກ mount
  // ຕັ້ງແຕ່ເປີດແອັບ (BookingScreen ເປັນໜຶ່ງໃນ 3 tab ຂອງ IndexedStack ໃນ
  // MainShell, main.dart) ແລະ ຄ້າງໄວ້ຕະຫຼອດ session — ລູກຄ້າເກົ່າທີ່ຈອງມາຫຼາຍປີ
  // ຈະດາວໂຫລດທຸກ booking ທີ່ເຄີຍມີມາທັງໝົດທຸກຄັ້ງທີ່ເປີດແອັບ. ຕອນນີ້ຈຳກັດ 50
  // ອັນລ້າສຸດ (ພຽງພໍສຳລັບ history/payment list) ຄືກັນກັບ query ອື່ນໆໃນແອັບ.
  static Stream<QuerySnapshot> getMyBookings() {
    final user = FirebaseAuth.instance.currentUser;
    return _db
        .collection('bookings')
        .where('customerId', isEqualTo: user?.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // ── PROVIDERS ─────────────────────────────────────────────

  // ✅ [FIX-1] ໃຊ້ ProviderModel ຈາກ provider_model.dart
  Future<ProviderModel?> getProvider(String providerId) async {
    final doc = await _db.collection('providers').doc(providerId).get();
    if (!doc.exists) return null;
    return ProviderModel.fromDoc(doc);
  }

  // ✅ Live version of getProvider — isOnline/rating/kycStatus ອັບເດດທັນທີ
  // ຂະນະລູກຄ້າກຳລັງເບິ່ງໜ້າໂປຣໄຟລ໌ຊ່າງ (ບໍ່ຄ້າງຄ່າເກົ່າໄວ້ຈົນກວ່າຈະເປີດໜ້າໃໝ່)
  Stream<ProviderModel?> watchProvider(String providerId) {
    return _db
        .collection('providers')
        .doc(providerId)
        .snapshots()
        .map((doc) => doc.exists ? ProviderModel.fromDoc(doc) : null);
  }

  Stream<List<ReviewModel>> getProviderReviews(String providerId) {
    return _db
        .collection('providers')
        .doc(providerId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => ReviewModel.fromMap(d.id, d.data()))
        .toList());
  }
}

// ════════════════════════════════════════════════════════════
// ✅ [FIX-1] ProviderModel ຖືກລຶບອອກຈາກທີ່ນີ້ແລ້ວ
//    → ໃຊ້ class ຈາກ provider_model.dart ແທນ
// ✅ [FIX-2] BookingStatus ຖືກລຶບອອກຈາກທີ່ນີ້ແລ້ວ
//    → ໃຊ້ class ຈາກ main.dart ແທນ
// ════════════════════════════════════════════════════════════