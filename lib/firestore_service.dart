// ============================================================
// firestore_service.dart — LinTho
// Fixes:
//   ✅ [FIX-1] ລຶບ ProviderModel ເກົ່າອອກ — ໃຊ້ provider_model.dart ແທນ
//   ✅ [FIX-2] ລຶບ BookingStatus ເກົ່າອອກ — ໃຊ້ອັນໃນ main.dart ແທນ
//   ✅ [FIX-3] import provider_model.dart
//   ✅ ຄົງ ReviewModel, FirestoreService ໄວ້ທັງໝົດ
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

  // ── USERS ─────────────────────────────────────────────────

  static Future<void> saveUser({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String role,
  }) async {
    await _db.collection('users').doc(uid).set({
      'uid':       uid,
      'name':      name,
      'email':     email,
      'phone':     phone,
      'role':      role,
      'createdAt': FieldValue.serverTimestamp(),
      'status':    'active',
    });
  }

  static Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  static Stream<QuerySnapshot> getAllUsers() =>
      _db.collection('users').snapshots();

  // ── BOOKINGS ──────────────────────────────────────────────

  static Future<String> createBooking({
    required String serviceName,
    required String serviceEmoji,
    required String price,
    required String date,
    required String time,
    required String address,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final ref  = await _db.collection('bookings').add({
      'customerId':    user?.uid,
      'customerName':  user?.displayName,
      'customerEmail': user?.email,
      'serviceName':   serviceName,
      'serviceEmoji':  serviceEmoji,
      'price':         price,
      'date':          date,
      'time':          time,
      'address':       address,
      'status':        'pending',
      'providerId':    null,
      'providerName':  null,
      'reviewed':      false,
      'createdAt':     FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<QuerySnapshot> getMyBookings() {
    final user = FirebaseAuth.instance.currentUser;
    return _db
        .collection('bookings')
        .where('customerId', isEqualTo: user?.uid)
        .snapshots();
  }

  static Stream<QuerySnapshot> getProviderJobs() {
    return _db
        .collection('bookings')
        .where('status', whereIn: ['pending', 'accepted', 'inprogress'])
        .snapshots();
  }

  static Stream<QuerySnapshot> getAllBookings() =>
      _db.collection('bookings').snapshots();

  static Future<void> updateBookingStatus(
      String bookingId, String status) async {
    await _db
        .collection('bookings')
        .doc(bookingId)
        .update({'status': status});
  }

  static Future<void> acceptBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    await _db.collection('bookings').doc(bookingId).update({
      'status':       'accepted',
      'providerId':   user?.uid,
      'providerName': user?.displayName,
    });
  }

  // ── SERVICES ──────────────────────────────────────────────

  static Stream<QuerySnapshot> getServices() {
    return _db
        .collection('services')
        .where('active', isEqualTo: true)
        .snapshots();
  }

  // ── STATS ─────────────────────────────────────────────────

  static Future<Map<String, int>> getStats() async {
    final users = await _db.collection('users').count().get();
    final bookings = await _db.collection('bookings').count().get();
    final providers = await _db
        .collection('users')
        .where('role', isEqualTo: 'provider')
        .count()
        .get();
    final pending = await _db
        .collection('bookings')
        .where('status', isEqualTo: 'pending')
        .count()
        .get();
    return {
      'users':     users.count     ?? 0,
      'bookings':  bookings.count  ?? 0,
      'providers': providers.count ?? 0,
      'pending':   pending.count   ?? 0,
    };
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