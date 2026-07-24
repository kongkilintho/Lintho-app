import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'coupon_repository.dart';
import 'pricing_repository.dart';

final _kipFormat = NumberFormat('#,##0', 'en_US');

// 🔒 [AUDIT QA-1 / HI-6] ກ່ອນໜ້ານີ້ clientRequestId ຖືກ generate ໃໝ່ທຸກຄັ້ງ
// ທີ່ confirmBooking() ຖືກເອີ້ນ (ຈາກ DateTime.now()) — ໝາຍຄວາມວ່າຖ້າ
// confirmBooking() ຖືກເອີ້ນຊ້ຳ (double-tap, retry ຫຼັງເນັດຂາດ) ຈະໄດ້ ID
// ໃໝ່ທຸກຄັ້ງ, ບໍ່ collapse ເປັນ doc ດຽວແບບທີ່ຕັ້ງໃຈ (ຕ່າງຈາກ main booking flow
// ທີ່ clientRequestId ເປັນ final field ຄົງທີ່ຕະຫຼອດອາຍຸຂອງ BookingOrder ດຽວ).
// ຕອນນີ້ generate ຄັ້ງດຽວຕອນເລີ່ມເລືອກບໍລິການ (selectService) ແລະ persist ໄວ້ໃນ
// draft state ຕະຫຼອດ session ນີ້ — ຖືກລ້າງ (ໄດ້ ID ໃໝ່) ສະເພາະຕອນ draft reset
// (ຫຼັງຈອງສຳເລັດ ຫຼືອອກຈາກ flow).
String _generateQuickClientRequestId() {
  final rnd = Random();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final suffix = List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
  return 'qcr_${ts}_$suffix';
}

/// ຟໍແມັດລາຄາແບບ "300,000 ກີບ" — ໃຊ້ຮ່ວມກັນທົ່ວ Quick Booking + Referral UI
String formatKip(num amount) => '${_kipFormat.format(amount)} ກີບ';

// ▸ ລາຄາ literal ເກົ່າເປັນ fallback — ໃຊ້ທັນທີຕອນເປີດໜ້າ (ບໍ່ໃຫ້ກະພິບ
// spinner) ແລະ ໃຊ້ຕໍ່ຖ້າ Firestore offline/fetch ບໍ່ໄດ້. `serviceId` ໃຊ້
// lookup `services/{serviceId}` ໃນ admin ເພື່ອອັບເດດ `price` ໃຫ້ກົງກັນ.
const defaultQuickPackages = [
  {
    'serviceId': 'ac_general_clean',
    'type': 'ລ້າງແອທົ່ວໄປ',
    'emoji': '❄️',
    'price': 300000.0,
    'desc': 'ລ້າງຄອຍເຢັນ+ຮ້ອນ · 45–60 ນາທີ',
    'category': 'ac_clean',
  },
  {
    'serviceId': 'house_general_clean',
    'type': 'ທຳຄວາມສະອາດທົ່ວໄປ',
    'emoji': '🧹',
    'price': 180000.0,
    'desc': '2 ຊົ່ວໂມງ',
    'category': 'house_clean',
  },
  {
    'serviceId': 'ac_deep_clean_quick',
    'type': 'ລ້າງແອ Deep Clean',
    'emoji': '✨',
    'price': 450000.0,
    'desc': 'ລ້າງລະອຽດ · 60–90 ນາທີ',
    'category': 'ac_clean',
  },
];

/// ດຶງ basePrice ຈິງຈາກ admin (Firestore `services/{serviceId}`) ມາທັບລາຄາ
/// literal ຖ້າ service ນັ້ນເປັນ FIXED ແລະ fetch ສຳເລັດ — ບໍ່ດັ່ງນັ້ນໃຊ້ literal
/// ເກົ່າຕໍ່ (offline-safe, ບໍ່ throw).
final quickBookingPackagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = PricingRepository.instance;
  final result = <Map<String, dynamic>>[];
  for (final pkg in defaultQuickPackages) {
    final pricing = await repo.fetchPricing(pkg['serviceId'] as String);
    if (pricing != null && pricing.isFixed && pricing.basePrice != null) {
      result.add({...pkg, 'price': pricing.basePrice!.toDouble()});
    } else {
      result.add(pkg);
    }
  }
  return result;
});

enum QuickBookingStep { service, schedule, checkout }

class QuickBookingDraft {
  final String?   serviceType;
  final String?   serviceEmoji;
  final String?   category;
  final double?   packagePrice;
  final DateTime? scheduledAt;
  final GeoPoint?  location;
  final String?   address;
  final bool      saveAsDefaultAddress;
  final String?   addressLabel;
  final QuickBookingStep step;
  final bool      isSubmitting;
  final String?   error;
  final String?   couponCode;
  final num?      couponDiscount;
  final bool      checkingCoupon;
  final String?   couponError;
  final String?   clientRequestId;

  const QuickBookingDraft({
    this.serviceType,
    this.serviceEmoji,
    this.category,
    this.packagePrice,
    this.scheduledAt,
    this.location,
    this.address,
    this.saveAsDefaultAddress = false,
    this.addressLabel,
    this.step = QuickBookingStep.service,
    this.isSubmitting = false,
    this.error,
    this.couponCode,
    this.couponDiscount,
    this.checkingCoupon = false,
    this.couponError,
    this.clientRequestId,
  });

  bool get canGoToSchedule => serviceType != null && packagePrice != null;
  bool get canGoToCheckout =>
      canGoToSchedule && scheduledAt != null && location != null && address != null;

  /// ລາຄາສຸດທິຫຼັງຫັກສ່ວນຫຼຸດ coupon (ຖ້າມີ) — ໃຊ້ສະແດງ ແລະ ສົ່ງເຂົ້າ booking.
  double get finalPrice =>
      ((packagePrice ?? 0) - (couponDiscount ?? 0)).clamp(0, double.infinity);

  QuickBookingDraft copyWith({
    String? serviceType,
    String? serviceEmoji,
    String? category,
    double? packagePrice,
    DateTime? scheduledAt,
    GeoPoint? location,
    String? address,
    bool? saveAsDefaultAddress,
    String? addressLabel,
    QuickBookingStep? step,
    bool? isSubmitting,
    String? error,
    String? couponCode,
    num? couponDiscount,
    bool? checkingCoupon,
    String? couponError,
    bool clearCoupon = false,
    String? clientRequestId,
  }) => QuickBookingDraft(
    serviceType: serviceType ?? this.serviceType,
    serviceEmoji: serviceEmoji ?? this.serviceEmoji,
    category: category ?? this.category,
    packagePrice: packagePrice ?? this.packagePrice,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    location: location ?? this.location,
    address: address ?? this.address,
    saveAsDefaultAddress: saveAsDefaultAddress ?? this.saveAsDefaultAddress,
    addressLabel: addressLabel ?? this.addressLabel,
    step: step ?? this.step,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error,
    couponCode: clearCoupon ? null : (couponCode ?? this.couponCode),
    couponDiscount: clearCoupon ? null : (couponDiscount ?? this.couponDiscount),
    checkingCoupon: checkingCoupon ?? this.checkingCoupon,
    couponError: clearCoupon ? null : couponError,
    clientRequestId: clientRequestId ?? this.clientRequestId,
  );
}

class QuickBookingNotifier extends Notifier<QuickBookingDraft> {
  @override
  QuickBookingDraft build() => const QuickBookingDraft();

  void selectService({
    required String type,
    required String emoji,
    required double price,
    required String category,
  }) {
    state = state.copyWith(
      serviceType: type, serviceEmoji: emoji, packagePrice: price,
      category: category, step: QuickBookingStep.schedule,
      // ✅ [FIX HI-6] generate ຄັ້ງດຽວຕໍ່ draft session — ຄົງຄ່າເກົ່າໄວ້ ຖ້າ
      // selectService() ຖືກເອີ້ນຊ້ຳ (ຜູ້ໃຊ້ຍ້ອນກັບໄປປ່ຽນບໍລິການ) ໃນ session ດຽວກັນ
      clientRequestId: state.clientRequestId ?? _generateQuickClientRequestId(),
    );
  }

  void setSchedule({
    required DateTime scheduledAt,
    required GeoPoint location,
    required String address,
    bool saveAsDefault = false,
    String? label,
  }) {
    state = state.copyWith(
      scheduledAt: scheduledAt, location: location, address: address,
      saveAsDefaultAddress: saveAsDefault, addressLabel: label,
      step: QuickBookingStep.checkout,
    );
  }

  void backTo(QuickBookingStep step) => state = state.copyWith(step: step);

  Future<void> applyCoupon(String code) async {
    if (code.trim().isEmpty) return;
    state = state.copyWith(checkingCoupon: true, couponError: null);
    final result = await CouponRepository.instance.validate(code, state.packagePrice ?? 0);
    if (result == null) {
      state = state.copyWith(
        checkingCoupon: false, clearCoupon: true,
        couponError: 'ລະຫັດບໍ່ຖືກຕ້ອງ ຫຼື ໝົດອາຍຸແລ້ວ',
      );
      return;
    }
    state = state.copyWith(
      checkingCoupon: false,
      couponCode: result.code,
      couponDiscount: result.discountAmount,
    );
  }

  void clearCoupon() => state = state.copyWith(clearCoupon: true);

  Future<String?> confirmBooking({
    required String customerId,
    required String customerName,
    required String customerPhone,
  }) async {
    if (!state.canGoToCheckout) return null;
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final repo = ref.read(customerBookingRepoProvider);
      // ✅ [FIX HI-6] ໃຊ້ ID ທີ່ generate ໄວ້ຄັ້ງດຽວຕອນ selectService() —
      // ຮັບປະກັນວ່າກົດຊ້ຳ/retry ພາຍໃນ session ດຽວກັນຈະໃຊ້ clientRequestId
      // ດຽວກັນ (idempotent), ບໍ່ສ້າງ booking ຊ້ຳ. Fallback ນີ້ບໍ່ຄວນເກີດຂຶ້ນຈິງ
      // ເພາະ canGoToCheckout ຮັບປະກັນວ່າ selectService() ຖືກເອີ້ນມາກ່ອນແລ້ວ.
      final clientRequestId = state.clientRequestId ?? _generateQuickClientRequestId();

      final db = FirebaseFirestore.instance;

      // ✅ [AUDIT C5] referral lookup ຖືກຍ້າຍໄປລວມສູນຢູ່
      // CustomerBookingRepository.createBooking() ແລ້ວ (booking_repository.dart)
      // ບໍ່ຕ້ອງ query users/{customerId} ຊ້ຳຢູ່ນີ້ອີກ — createBooking() ຈະໃສ່
      // field 'referralCode' ໃຫ້ອັດຕະໂນມັດຖ້າ users doc ມີ referredBy
      final id = await repo.createBooking({
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'serviceType': state.serviceType,
        'serviceEmoji': state.serviceEmoji,
        'category': state.category,
        'address': state.address,
        'location': state.location,
        'scheduledAt': Timestamp.fromDate(state.scheduledAt!),
        'status': JobStatus.pending.name,
        'price': state.finalPrice,
        if (state.couponCode != null) 'couponCode': state.couponCode,
        if (state.couponDiscount != null) 'discountAmount': state.couponDiscount,
        // ✅ [FIX LO-4] ໃຊ້ serverTimestamp() ຄືກັນກັບໜ້າຈອງຫຼັກ — client time
        // ອາດຄາດເຄື່ອນຖ້າໂມງເຄື່ອງບໍ່ກົງ, ເຮັດໃຫ້ລຳດັບ createdAt ຜິດເມື່ອ sort
        // ຮ່ວມກັບ booking ຈາກທັງສອງ flow
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10))),
        'paymentMethod': 'cash',
        'paymentStatus': 'pending',
        'clientRequestId': clientRequestId,
      }, couponCode: state.couponCode);

      // 🔒 [FOLLOWUP-F] ກ່ອນໜ້ານີ້ການບັນທຶກທີ່ຢູ່ (saveAsDefaultAddress, ບໍ່
      // ກ່ຽວຂ້ອງກັບ booking ໂດຍກົງ) ຢູ່ໃນ try/catch ດຽວກັນກັບ createBooking() —
      // ຖ້າການບັນທຶກທີ່ຢູ່ລົ້ມເຫລວ (ເຊັ່ນ offline ຊົ່ວຄາວ) catch block ຂ້າງລຸ່ມ
      // ຈະລາຍງານວ່າ "ຈອງລົ້ມເຫລວ" ທັງໆທີ່ booking ຖືກສ້າງແລ້ວແທ້ (live ຢູ່ໃນ
      // Firestore, ບໍ່ມີໃຜເບິ່ງແຍງ). ຕອນນີ້ແຍກ try/catch ຂອງຕົນເອງ — ລົ້ມເຫລວ
      // ໄດ້ພຽງແຕ່ debugPrint, ບໍ່ກະທົບ booking ທີ່ສ້າງສຳເລັດແລ້ວ.
      if (state.saveAsDefaultAddress) {
        try {
          await db.collection('users').doc(customerId).collection('addresses').add({
            'label': state.addressLabel ?? 'ບ້ານ',
            'address': state.address,
            'location': state.location,
            'createdAt': Timestamp.fromDate(DateTime.now()),
          });
        } catch (e) {
          debugPrint('QuickBookingNotifier: saveAsDefaultAddress failed (booking already succeeded): $e');
        }
      }

      state = const QuickBookingDraft();
      return id;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return null;
    }
  }
}

final quickBookingProvider =
    NotifierProvider<QuickBookingNotifier, QuickBookingDraft>(QuickBookingNotifier.new);
