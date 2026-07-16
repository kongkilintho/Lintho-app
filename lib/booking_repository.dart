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
import 'coupon_repository.dart';

// ════════════════════════════════════════════════════════════
// BOOKING REPOSITORY
// ════════════════════════════════════════════════════════════

class BookingRepository {
  final _db = FirebaseFirestore.instance;
  // ✅ [FIX-2] ລຶບ _storage ທີ່ບໍ່ໄດ້ໃຊ້ໃນ class ນີ້ອອກ
  // ✅ [FIX-1] ໃຊ້ ?? '' ແທນ ! — ປ້ອງກັນ crash ຕອນ logout
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<List<Booking>> watchActiveBookings() {
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
        .snapshots()
        .map((s) => s.docs.map(Booking.fromFirestore).toList());
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
        .map((s) => s.docs.map(Booking.fromFirestore).toList());
  }

  // ✅ [FIX-3] ວຽກທີ່ຍັງບໍ່ຖືກມອບໝາຍ providerId (ບາງ flow ສ້າງ booking ໂດຍບໍ່
  // ໃສ່ providerId — ເບິ່ງ booking_form_screen.dart) ຈະບໍ່ເຄີຍປາກົດຢູ່ໃນ
  // watchActiveBookings() ຂອງ provider ຄົນໃດເລີຍ ເພາະ query ນັ້ນ filter
  // ດ້ວຍ providerId == _uid. ນຳໃຊ້ rule ທີ່ມີຢູ່ແລ້ວ (firestore.rules:
  // isProvider() && resource.data.status == 'pending') ໃຫ້ provider ເຫັນ
  // ວຽກ pending ທັງໝົດ ໂດຍບໍ່ຈຳກັດ providerId — caller filter ຕໍ່ວ່າອັນໃດ
  // ຍັງບໍ່ຖືກຮັບ (providerId ວ່າງ) ແລະ ກົງກັບ serviceTypes ຂອງຕົນເອງ
  Stream<List<Booking>> watchOpenJobs() {
    return _db
        .collection('bookings')
        .where('status', isEqualTo: JobStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(Booking.fromFirestore).toList());
  }

  Stream<Booking> watchBooking(String bookingId) {
    return _db
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .map(Booking.fromFirestore);
  }

  // ── ຮັບງານ ────────────────────────────────────────────────

  Future<void> acceptBooking(String bookingId) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final ref = _db.collection('bookings').doc(bookingId);
    late Booking b;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      b = Booking.fromFirestore(snap);
      if (b.status != JobStatus.pending) {
        throw Exception('ງານນີ້ມີຄົນຮັບໄປແລ້ວ');
      }
      tx.update(ref, {
        'status':     JobStatus.accepted.name,
        'acceptedAt': FieldValue.serverTimestamp(),
        'providerId': _uid,
      });
    });

    // ✅ Cloud Function `onBookingStatusChange` already notifies the customer
    // on every status write — no client-side notification here (was double-firing).
  }

  // ── ປະຕິເສດ ───────────────────────────────────────────────

  // ✅ Transaction: ກວດ status ປັດຈຸບັນກ່ອນຂຽນ — ປ້ອງກັນ overwrite booking
  // ທີ່ status ປ່ຽນໄປແລ້ວ (ເຊັ່ນ ລູກຄ້າຍົກເລີກ ຫຼື provider ອື່ນ accept ໄປແລ້ວ
  // ໃນຊ່ວງເວລາດຽວກັນ)
  Future<void> rejectBooking(String bookingId, String reason) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final b = Booking.fromFirestore(snap);
      if (b.status == JobStatus.completed || b.status == JobStatus.cancelled) {
        throw Exception('ບໍ່ສາມາດປະຕິເສດໄດ້: ສະຖານະປ່ຽນໄປແລ້ວ');
      }
      tx.update(ref, {
        'status':       JobStatus.rejected.name,
        'cancelReason': reason,
      });
    });

    // ✅ Cloud Function `onBookingStatusChange` already notifies the customer
    // on every status write — no client-side notification here (was double-firing).
  }

  // ── ອັບເດດ status ─────────────────────────────────────────

  // ✅ ບໍ່ມີ payment gateway webhook ແທ້ — ນີ້ແມ່ນຊ່າງຢືນຢັນວ່າໄດ້ຮັບເງິນແລ້ວ
  // (cash ໃນມື ຫຼື ເຫັນ BCEL ໂອນເຂົ້າແທ້) ກ່ອນປິດງານ.
  Future<void> confirmPaymentReceived(String bookingId) async {
    if (_uid.isEmpty) return;
    await _db.collection('bookings').doc(bookingId).update({
      'paymentStatus': 'paid',
    });
  }

  Future<void> updateStatus(String bookingId, JobStatus status) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    final doc = await _db.collection('bookings').doc(bookingId).get();
    final b   = Booking.fromFirestore(doc);

    if (status == JobStatus.completed && b.paymentStatus != 'paid') {
      throw Exception('ກະລຸນາຢືນຢັນການຮັບເງິນກ່ອນປິດງານ');
    }

    final data = <String, dynamic>{'status': status.name};
    if (status == JobStatus.completed) {
      data['completedAt'] = FieldValue.serverTimestamp();
    }
    await _db.collection('bookings').doc(bookingId).update(data);

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
    final doc = await _db.collection('bookings').doc(bookingId).get();
    final b   = Booking.fromFirestore(doc);

    await _db.collection('bookings').doc(bookingId).update({
      'additionalCharges':         amount,
      'additionalChargesNote':     note,
      'additionalChargesApproved': false,
    });

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
  // ✅ [Coupon] ຖ້າມີ `couponCode`, ການສ້າງ booking + ການ increment
  // `coupons/{code}.usedCount` ຈະຢູ່ໃນ WriteBatch ດຽວກັນ (atomic) — ບໍ່ໃຫ້
  // coupon ຖືກນັບໃຊ້ໂດຍບໍ່ມີ booking ຄູ່ກັນ (ຫຼື booking ຖືກສ້າງແຕ່ coupon
  // ບໍ່ຖືກນັບ).
  Future<String> createBooking(Map<String, dynamic> data, {String? couponCode}) async {
    final clientRequestId = data['clientRequestId'] as String?;
    final ref = (clientRequestId == null || clientRequestId.isEmpty)
        ? _db.collection('bookings').doc()
        : _db.collection('bookings').doc(clientRequestId);

    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      final existing = await ref.get();
      if (existing.exists) return ref.id;
    }

    // ✅ [AUDIT C5] ລວມ referral lookup ໄວ້ບ່ອນດຽວແທນທີ່ຈະໃຫ້ແຕ່ລະໜ້າຈໍຈອງ
    // (quick_booking_provider.dart, booking_form_screen.dart) ຂຽນແຍກກັນເອງ —
    // ກ່ອນໜ້ານີ້ມີແຕ່ Quick Booking flow ທີ່ໃສ່ field 'referralCode' ໃຫ້,
    // booking_form_screen.dart (ໜ້າຈອງຫຼັກ ໃຊ້ຫຼາຍທີ່ສຸດ) ບໍ່ໄດ້ໃສ່ເລີຍ —
    // ເຮັດໃຫ້ໂປຣແກຣມແນະນຳໝູ່ (onNewBooking ໃນ functions/index.js ອ່ານ field
    // ນີ້) ບໍ່ໄດ້ຜົນສຳລັບການຈອງສ່ວນຫຼາຍແບບງຽບໆ. ຕອນນີ້ createBooking() ດຶງ
    // users/{customerId}.referredBy ໃຫ້ອັດຕະໂນມັດ ຖ້າຜູ້ຮຽກຍັງບໍ່ໄດ້ໃສ່ມາເອງ.
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

    final batch = _db.batch();
    batch.set(ref, data);
    if (couponCode != null && couponCode.isNotEmpty) {
      CouponRepository.instance.incrementUsage(batch, couponCode);
    }
    await batch.commit();
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
    });
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
}

// ════════════════════════════════════════════════════════════
// EARNINGS REPOSITORY
// ════════════════════════════════════════════════════════════

class EarningsRepository {
  final _db = FirebaseFirestore.instance;
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
    final walletDoc = await _db.collection('wallets').doc(_uid).get();
    final balance   = (walletDoc.data()?['balance'] as num?)
        ?.toDouble() ?? 0;
    if (amount < 50000) throw Exception('ຂັ້ນຕ່ຳ ₭50,000');
    if (amount > balance) throw Exception('ຍອດບໍ່ພໍ');
    await _db.collection('withdrawalRequests').add({
      'providerId': _uid,
      'amount':     amount,
      'status':     'pending',
      'createdAt':  FieldValue.serverTimestamp(),
    });
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
    }, SetOptions(merge: true));
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

  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (_uid.isEmpty) return; // ✅ [FIX-1] guard
    await _db.collection('providers').doc(_uid).set(
      {...data, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    if (data.containsKey('displayName')) {
      await _auth.currentUser
          ?.updateDisplayName(data['displayName'] as String);
    }
  }

  Future<String> uploadProfilePhoto(File photo) async {
    final ref  = _storage.ref('providers/$_uid/profile.jpg');
    final task = await ref.putFile(
        photo, SettableMetadata(contentType: 'image/jpeg'));
    final url  = await task.ref.getDownloadURL();
    await updateProfile({'photoUrl': url});
    return url;
  }

  Future<void> uploadKyc({
    required File idPhoto,
    required File selfiePhoto,
  }) async {
    final idUrl = await (await _storage
        .ref('kyc/$_uid/id.jpg')
        .putFile(idPhoto))
        .ref
        .getDownloadURL();
    final selfieUrl = await (await _storage
        .ref('kyc/$_uid/selfie.jpg')
        .putFile(selfiePhoto))
        .ref
        .getDownloadURL();
    await updateProfile({
      'kycIdUrl':     idUrl,
      'kycSelfieUrl': selfieUrl,
      'kycStatus':    KycStatus.pending.name,
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