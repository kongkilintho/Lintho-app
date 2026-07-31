// ============================================================
// Booking.dart — LinTho Provider App — All Models
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show IconData, Icons;

// 🔒 [AUDIT H11] serviceEmoji ຖືກເກັບເປັນ emoji character ຢູ່ໃນ Firestore doc
// ເອງ (ບໍ່ແມ່ນ derive ຈາກ category ຝັ່ງ client) — render ຄືເກົ່າທຸກຄັ້ງທີ່ booking
// ໃດຖືກສະແດງ (8+ ໜ້າຈໍ), ບໍ່ວ່າ widget-level "ປ່ຽນ emoji ເປັນ Material icon"
// ຈະຖືກແກ້ໄຂຫຼາຍປານໃດ. ຕອນນີ້ resolve icon ຈາກ category (canonical key) ຢູ່
// client ແທນ — serviceEmoji ຄົງໄວ້ໃນ model ເປັນ fallback ສະເພາະ doc ເກົ່າ/
// unknown category ເທົ່ານັ້ນ, ບໍ່ໄດ້ຖືກ render ໂດຍກົງອີກຕໍ່ໄປ.
IconData serviceIconForCategory(String category) => switch (category) {
      'ac_clean'    => Icons.ac_unit_rounded,
      'house_clean' => Icons.cleaning_services_rounded,
      _             => Icons.build_rounded,
    };

// ── ENUMS ────────────────────────────────────────────────────

enum JobStatus {
  pending, accepted, onTheWay, arrived, inProgress,
  completed, cancelled, rejected,
}

extension JobStatusX on JobStatus {
  String get label => switch (this) {
    JobStatus.pending    => 'ໃໝ່',
    JobStatus.accepted   => 'ຮັບແລ້ວ',
    JobStatus.onTheWay   => 'ກຳລັງໄປ',
    JobStatus.arrived    => 'ຮອດແລ້ວ',
    JobStatus.inProgress => 'ກຳລັງເຮັດ',
    JobStatus.completed  => 'ສຳເລັດ',
    JobStatus.cancelled  => 'ຍົກເລີກ',
    JobStatus.rejected   => 'ປະຕິເສດ',
  };
  bool get isActive => [
    JobStatus.accepted, JobStatus.onTheWay,
    JobStatus.arrived,  JobStatus.inProgress,
  ].contains(this);
  bool get isFinished => [
    JobStatus.completed, JobStatus.cancelled, JobStatus.rejected,
  ].contains(this);
}

enum TxType { earning, withdrawal, bonus, refund, topup, adjustment }

extension TxTypeX on TxType {
  String get label => switch (this) {
    TxType.earning    => 'ລາຍຮັບ',
    TxType.withdrawal => 'ຖອນເງິນ',
    TxType.bonus      => 'ໂບນັດ',
    TxType.refund     => 'ຄືນເງິນ',
    TxType.topup      => 'ຕື່ມເງິນ',
    TxType.adjustment => 'ຍອດປັບປຸງ',
  };
  // 🔒 [Admin wallet adjustment] adjustment ຄົງທີ່ false ຢູ່ນີ້ໂດຍຕັ້ງໃຈ — ນີ້
  // ຄືຄ່າທີ່ _WeeklyChart (booking_provider.dart) ໃຊ້ກອງ "ລາຍຮັບຈິງ" ເທົ່ານັ້ນ
  // ເຂົ້າກຣາຟ, ແລະ admin adjustment (ບໍ່ວ່າບວກ ຫຼື ຫັກ) ບໍ່ຄວນນັບເປັນຜົນງານ/
  // ລາຍຮັບຈິງ. ສຳລັບການສະແດງເຄື່ອງໝາຍ +/- ແລະ ສີໃນລາຍການ (ProviderTransaction.
  // isCredit ຂ້າງລຸ່ມ) ໃຊ້ເຄື່ອງໝາຍຂອງ amount ທີ່ເກັບໄວ້ຈິງແທນ — admin ອາດ
  // ບວກ(ຄືນ)ຫຼືຫັກເງິນໄດ້ທັງສອງທິດທາງດ້ວຍ type ດຽວກັນນີ້.
  bool get isCredit =>
      this == TxType.earning || this == TxType.bonus || this == TxType.topup;
}

enum KycStatus { none, pending, verified, rejected }

// ── BOOKING ──────────────────────────────────────────────────

class Booking {
  final String    id;
  final String    customerId;
  final String    customerName;
  final String    customerPhone;
  // ✅ [Phone-verified booking] ເບີໂທທີ່ໃຊ້ຕິດຕໍ່ຈິງສຳລັບ booking ນີ້ — ມາຈາກ
  // ເບີໂທທີ່ຢືນຢັນແລ້ວຂອງບັນຊີ (FirebaseAuth.currentUser.phoneNumber) ຕອນຈອງ.
  // fromFirestore() fallback ໄປ customerPhone ໃຫ້ booking ເກົ່າ (ກ່ອນ field ນີ້
  // ຖືກເພີ່ມ) ຍັງໃຊ້ໄດ້ປົກກະຕິ — ຝັ່ງຊ່າງ (job_workflow_Screen.dart) ຄວນອ່ານ
  // field ນີ້ແທນ customerPhone ໂດຍກົງ.
  final String    contactPhone;
  final String?   customerPhotoUrl;
  final String    providerId;
  final String    serviceType;
  // 🔒 [AUDIT QA-1 / HI-5] 'serviceType' ແມ່ນ display text (Quick Booking ຂຽນ
  // label ພາສາລາວ, main flow ຂຽນ category key) — ບໍ່ຄວນໃຊ້ຄ່ານີ້ຈັບຄູ່ວຽກກັບ
  // provider.serviceTypes (canonical key ສະເໝີ, ເບິ່ງ profile_tab.dart:674-675).
  // ເພີ່ມ 'category' ແຍກຕ່າງຫາກໃຫ້ matching logic ໃຊ້ແທນ.
  final String    category;
  final String    serviceEmoji;
  final String    address;
  // ✅ [FIX ME-5] booking_form_screen.dart ຂຽນ landmark/specialInstructions/
  // jobPhotoUrl ຕອນສ້າງ booking ແຕ່ບໍ່ເຄີຍຖືກອ່ານກັບຄືນ ຫຼື ສະແດງໃຫ້ຊ່າງເຫັນ —
  // ເພີ່ມເຂົ້າ model ໃຫ້ provider job-detail screen ສະແດງໄດ້
  final String    landmark;
  final String    specialInstructions;
  final String?   jobPhotoUrl;
  final GeoPoint  location;
  final DateTime  scheduledAt;
  final JobStatus status;
  final double    price;
  final double?   additionalCharges;
  final String?   additionalChargesNote;
  final bool      additionalChargesApproved;
  final String?   beforePhotoUrl;
  final String?   afterPhotoUrl;
  final String?   cancelReason;
  final DateTime  createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final DateTime  expiresAt;
  final String    paymentMethod;
  final String    paymentStatus;
  final String?   clientRequestId;
  final String?   cancelledBy;
  final double?   cancelFeeAmount;
  // ✅ [FIX H7] providers ທີ່ reject ວຽກນີ້ໄປແລ້ວ (ຕອນຍັງເປັນ open job board,
  // providerId ຍັງວ່າງເປົ່າ) — ໃຊ້ຍົກເວັ້ນອອກຈາກ unassignedOpenJobsProvider
  // ຂອງ provider ຄົນນັ້ນ ບໍ່ໃຫ້ວຽກທີ່ຕົນເອງເຄີຍປະຕິເສດແລ້ວປາກົດຄືນອີກ
  final List<String> rejectedBy;
  // 🔒 [FOLLOWUP-H] Top-3 provider ທີ່ match_screen.dart ສົ່ງຄຳຂໍໃຫ້ (ຂຽນຢູ່
  // 'sentTo' ຕອນ _sendRequestToTop3()) — ກ່ອນໜ້ານີ້ model ນີ້ບໍ່ເຄີຍອ່ານ field
  // ນີ້ກັບຄືນມາເລີຍ, ຈຶ່ງບໍ່ມີບ່ອນໃດໃຊ້ຈຳກັດການເບິ່ງເຫັນ open job ໃຫ້ຈຳກັດແຕ່ 3 ຄົນ
  // ທີ່ຖືກເລືອກແທ້ (ເບິ່ງ isJobVisibleToProvider() ໃນ booking_provider.dart).
  final List<String> sentTo;
  // 🔒 [FOLLOWUP-K] ລູກຄ້າຢືນຢັນວ່າໄດ້ໂອນເງິນຜ່ານ BCEL ແລ້ວ (ຕັ້ງໂດຍ
  // customer_confirm_payment ໃນ tracking_screen.dart) — ໃຊ້ເປັນ counter-
  // signature ກ່ອນ confirmPaymentReceived() (booking_repository.dart) ຈະ
  // ຍອມໃຫ້ຊ່າງປິດງານ ສຳລັບ paymentMethod != 'cash'. ຊ່າງບໍ່ສາມາດຢືນຢັນເອງຝ່າຍ
  // ດຽວອີກຕໍ່ໄປສຳລັບການໂອນເງິນ (cash ຍັງເປັນ self-attested, ຍອມຮັບເປັນຂໍ້ຈຳກັດ
  // ທີ່ຮູ້ຢູ່ແລ້ວເນື່ອງຈາກບໍ່ມີ payment gateway ແທ້).
  final bool customerConfirmedPayment;
  // 🔒 [AUDIT H-1 / 2026-07-27] ຊ່າງ (displayName/phone/rating/totalJobs/
  // photoUrl ຈາກ providers/{uid}) ຖືກ denormalize ໃສ່ booking doc ໂດຍ
  // acceptBooking() (booking_repository.dart) ຕອນຮັບງານ — ກ່ອນໜ້ານີ້ບໍ່ເຄີຍຖືກ
  // ຂຽນເລີຍ, ເຮັດໃຫ້ Match/Tracking/Detail/Review screen (ອ່ານ field ເຫຼົ່ານີ້
  // ໂດຍກົງຈາກ booking doc) ສະແດງຊື່/ຮູບ/ຄະແນນ/ເບີວ່າງເປົ່າ ແລະ ປຸ່ມ "ໂທຫາຊ່າງ"
  // ບໍ່ເຮັດວຽກ (phone ຫວ່າງ). ນຳໃຊ້ field ຊື່ດຽວກັນກັບທີ່ 4 ໜ້າຈໍນັ້ນອ່ານຢູ່ແລ້ວ.
  final String? providerName;
  final String? providerPhone;
  final double? providerRating;
  final int?    providerJobs;
  final String? providerPhoto;

  const Booking({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.contactPhone = '',
    this.customerPhotoUrl,
    required this.providerId,
    required this.serviceType,
    this.category = '',
    required this.serviceEmoji,
    required this.address,
    this.landmark = '',
    this.specialInstructions = '',
    this.jobPhotoUrl,
    required this.location,
    required this.scheduledAt,
    required this.status,
    required this.price,
    this.additionalCharges,
    this.additionalChargesNote,
    this.additionalChargesApproved = false,
    this.beforePhotoUrl,
    this.afterPhotoUrl,
    this.cancelReason,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    required this.expiresAt,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'pending',
    this.clientRequestId,
    this.cancelledBy,
    this.cancelFeeAmount,
    this.rejectedBy = const [],
    this.sentTo = const [],
    this.customerConfirmedPayment = false,
    this.providerName,
    this.providerPhone,
    this.providerRating,
    this.providerJobs,
    this.providerPhoto,
  });

  // 🔒 [AUDIT H10] ກ່ອນໜ້ານີ້ scheduledAt/createdAt/expiresAt (`as Timestamp`
  // non-nullable) ແລະ status (`JobStatus.values.byName()`) throw ໄດ້ຖ້າ doc
  // ໃດໜຶ່ງມີ field ຂາດ/ຜິດຮູບແບບ (legacy doc, write ຄ້າງກາງທາງ, ຫຼືແກ້ຈາກ
  // console ໂດຍກົງ). ເນື່ອງຈາກ Booking.fromFirestore ຖືກເອີ້ນຢູ່ໃນ
  // Stream.map(watchActiveBookings()/watchJobHistory()/watchOpenJobs()) —
  // exception ຈາກ doc ດຽວຈະກາຍເປັນ stream error ຂອງ "ທັງ list" ບໍ່ແມ່ນສະເພາະ
  // doc ນັ້ນ, ເຮັດໃຫ້ວຽກທັງໝົດຂອງ provider ຫາຍໄປຫລັງ error screen ຍ້ອນ doc
  // ດຽວ. ຕອນນີ້ທຸກ field ເຫຼົ່ານີ້ default ປອດໄພແທນ throw.
  // 🔒 [AUDIT H-4 / 2026-07-27] `as String?` throws (does NOT coerce) if the
  // underlying Firestore value is a non-null, non-String type (e.g. a number
  // or map written by a modified client, a manual console edit, or a partial/
  // corrupt write). Every String field below used to cast this way — one
  // malformed document would throw inside Stream.map(Booking.fromFirestore)
  // and take down the *entire* list (watchOpenJobs/watchActiveBookings/
  // watchJobHistory), silently emptying every provider's job board. _str()/
  // _strN() check the runtime type first and fall back instead of throwing.
  static String _str(dynamic v, [String fallback = '']) =>
      v is String ? v : fallback;
  static String? _strN(dynamic v) => v is String ? v : null;

  factory Booking.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Booking(
      id:                        doc.id,
      customerId:                _str(d['customerId']),
      customerName:              _str(d['customerName']),
      customerPhone:             _str(d['customerPhone']),
      // ✅ fallback ໄປ customerPhone ໃຫ້ booking ເກົ່າ (ກ່ອນ field ນີ້ຖືກເພີ່ມ)
      contactPhone:              _str(d['contactPhone'], _str(d['customerPhone'])),
      customerPhotoUrl:          _strN(d['customerPhotoUrl']),
      // ✅ Path A booking (booking_form_screen.dart) ບໍ່ຂຽນ providerId/
      // serviceType/serviceEmoji ຕອນສ້າງ booking (ມັນຖືກ backfill ພາຍຫຼັງ
      // ຕອນ matched) — cast ແບບ non-nullable ຈະ crash ໃສ່ booking ທີ່ຍັງບໍ່
      // ມີ provider ຈັບຄູ່. ໃຫ້ default ປອດໄພແທນ.
      providerId:                _str(d['providerId']),
      serviceType:               _str(d['serviceType'], _str(d['category'])),
      category:                  _str(d['category']),
      serviceEmoji:              _str(d['serviceEmoji'], '🔧'),
      address:                   _str(d['address']),
      landmark:                  _str(d['landmark']),
      specialInstructions:       _str(d['specialInstructions']),
      jobPhotoUrl:               _strN(d['jobPhotoUrl']),
      location:                  d['location']                  as GeoPoint? ?? const GeoPoint(0, 0),
      scheduledAt:              (d['scheduledAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      status:                    _parseStatus(d['status'] as String?),
      // ✅ ໃຊ້ as num? ບໍ່ແມ່ນ as num — booking ເກົ່າຈາກ booking_form_screen.dart
      // (ກ່ອນແກ້ໄຂ) ບໍ່ມີ field 'price' ມາກ່ອນ, cast ແບບບໍ່ null-safe ຈະ crash
      // ຕອນ rehydrate booking ເກົ່ານັ້ນ.
      price:                    (d['price'] as num?)?.toDouble() ?? 0,
      additionalCharges:        (d['additionalCharges'] as num?)?.toDouble(),
      additionalChargesNote:     _strN(d['additionalChargesNote']),
      additionalChargesApproved: d['additionalChargesApproved'] as bool? ?? false,
      beforePhotoUrl:            _strN(d['beforePhotoUrl']),
      afterPhotoUrl:             _strN(d['afterPhotoUrl']),
      cancelReason:              _strN(d['cancelReason']),
      createdAt:                (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt:               (d['acceptedAt'] as Timestamp?)?.toDate(),
      completedAt:              (d['completedAt'] as Timestamp?)?.toDate(),
      expiresAt:                (d['expiresAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      paymentMethod:             _str(d['paymentMethod'], 'cash'),
      paymentStatus:             _str(d['paymentStatus'], 'pending'),
      clientRequestId:           _strN(d['clientRequestId']),
      cancelledBy:               _strN(d['cancelledBy']),
      cancelFeeAmount:          (d['cancelFeeAmount'] as num?)?.toDouble(),
      rejectedBy:                List<String>.from(d['rejectedBy'] ?? const []),
      sentTo:                    List<String>.from(d['sentTo'] ?? const []),
      customerConfirmedPayment:  d['customerConfirmedPayment'] as bool? ?? false,
      providerName:              _strN(d['providerName']),
      providerPhone:             _strN(d['providerPhone']),
      providerRating:           (d['providerRating'] as num?)?.toDouble(),
      providerJobs:              d['providerJobs'] as int?,
      providerPhoto:             _strN(d['providerPhoto']),
    );
  }

  // ✅ [FIX H10] JobStatus.values.byName() throw ໃສ່ status ໃດກໍໄດ້ທີ່ບໍ່ຕົງ
  // enum name ເປ๊ະ (legacy value, typo ຈາກ manual edit) — ໃຫ້ fallback ໄປ
  // 'pending' ແທນ throw
  static JobStatus _parseStatus(String? raw) {
    if (raw == null) return JobStatus.pending;
    for (final s in JobStatus.values) {
      if (s.name == raw) return s;
    }
    return JobStatus.pending;
  }

  Map<String, dynamic> toMap() => {
    'customerId': customerId, 'customerName': customerName,
    'customerPhone': customerPhone, 'contactPhone': contactPhone,
    'customerPhotoUrl': customerPhotoUrl,
    'providerId': providerId, 'serviceType': serviceType,
    'category': category,
    'serviceEmoji': serviceEmoji, 'address': address,
    'landmark': landmark, 'specialInstructions': specialInstructions,
    'jobPhotoUrl': jobPhotoUrl,
    'location': location, 'scheduledAt': Timestamp.fromDate(scheduledAt),
    'status': status.name, 'price': price,
    'additionalCharges': additionalCharges,
    'additionalChargesNote': additionalChargesNote,
    'additionalChargesApproved': additionalChargesApproved,
    'beforePhotoUrl': beforePhotoUrl, 'afterPhotoUrl': afterPhotoUrl,
    'cancelReason': cancelReason, 'createdAt': Timestamp.fromDate(createdAt),
    'acceptedAt':  acceptedAt  != null ? Timestamp.fromDate(acceptedAt!)  : null,
    'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    'expiresAt': Timestamp.fromDate(expiresAt),
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'clientRequestId': clientRequestId,
    'cancelledBy': cancelledBy,
    'cancelFeeAmount': cancelFeeAmount,
    'rejectedBy': rejectedBy,
    'sentTo': sentTo,
    'customerConfirmedPayment': customerConfirmedPayment,
    'providerName': providerName,
    'providerPhone': providerPhone,
    'providerRating': providerRating,
    'providerJobs': providerJobs,
    'providerPhoto': providerPhoto,
  };

  Booking copyWith({
    JobStatus? status, double? additionalCharges,
    String? additionalChargesNote, bool? additionalChargesApproved,
    String? beforePhotoUrl, String? afterPhotoUrl,
    String? cancelReason, DateTime? acceptedAt, DateTime? completedAt,
    String? paymentStatus, String? cancelledBy, double? cancelFeeAmount,
  }) => Booking(
    id: id, customerId: customerId, customerName: customerName,
    customerPhone: customerPhone, contactPhone: contactPhone,
    customerPhotoUrl: customerPhotoUrl,
    providerId: providerId, serviceType: serviceType,
    category: category,
    serviceEmoji: serviceEmoji, address: address,
    landmark: landmark, specialInstructions: specialInstructions,
    jobPhotoUrl: jobPhotoUrl,
    location: location,
    scheduledAt: scheduledAt,
    status:                    status               ?? this.status,
    price: price,
    additionalCharges:         additionalCharges    ?? this.additionalCharges,
    additionalChargesNote:     additionalChargesNote ?? this.additionalChargesNote,
    additionalChargesApproved: additionalChargesApproved ?? this.additionalChargesApproved,
    beforePhotoUrl:            beforePhotoUrl       ?? this.beforePhotoUrl,
    afterPhotoUrl:             afterPhotoUrl        ?? this.afterPhotoUrl,
    cancelReason:              cancelReason         ?? this.cancelReason,
    createdAt: createdAt,
    acceptedAt:  acceptedAt  ?? this.acceptedAt,
    completedAt: completedAt ?? this.completedAt,
    expiresAt: expiresAt,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    clientRequestId: clientRequestId,
    cancelledBy: cancelledBy ?? this.cancelledBy,
    cancelFeeAmount: cancelFeeAmount ?? this.cancelFeeAmount,
    rejectedBy: rejectedBy,
    sentTo: sentTo,
    customerConfirmedPayment: customerConfirmedPayment,
    providerName: providerName,
    providerPhone: providerPhone,
    providerRating: providerRating,
    providerJobs: providerJobs,
    providerPhoto: providerPhoto,
  );

  bool   get isExpired       => status == JobStatus.pending && expiresAt.isBefore(DateTime.now());
  double get totalPrice      => price + (additionalCharges ?? 0);
  String get formattedPrice  => _fmt(price);
  // ✅ [FIX H11] ໃຊ້ແທນ serviceEmoji ໃນ UI ທຸກຈຸດ — ເບິ່ງ serviceIconForCategory()
  IconData get serviceIcon   => serviceIconForCategory(category);

  static String _fmt(double v) =>
      '₭${v.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  String get formattedSchedule {
    final dt = scheduledAt;
    return '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')} · '
        '${dt.day.toString().padLeft(2,'0')}/'
        '${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }
}

// ── PROVIDER TRANSACTION ─────────────────────────────────────

class ProviderTransaction {
  final String   id;
  final String   providerId;
  final TxType   type;
  final double   amount;
  final String?  bookingId;
  final String   description;
  final DateTime createdAt;

  const ProviderTransaction({
    required this.id, required this.providerId, required this.type,
    required this.amount, this.bookingId,
    required this.description, required this.createdAt,
  });

  factory ProviderTransaction.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProviderTransaction(
      id:          doc.id,
      providerId:  d['providerId']  as String,
      type:        TxType.values.byName(d['type'] as String),
      amount:     (d['amount']      as num).toDouble(),
      bookingId:   d['bookingId']   as String?,
      description: d['description'] as String,
      createdAt:  (d['createdAt']   as Timestamp).toDate(),
    );
  }

  // ✅ [Admin wallet adjustment] ທຸກ type ອື່ນ amount ເປັນບວກສະເໝີ ແລະ sign/ສີ
  // ມາຈາກ type.isCredit (fixed ຕໍ່ type) — ແຕ່ adjustment ອາດເປັນໄດ້ທັງບວກ
  // (admin ຄືນເງິນ/bonus ພິເສດ) ຫຼືລົບ (admin ຫັກ) ດ້ວຍ type ດຽວກັນ, ຈຶ່ງໃຊ້
  // ເຄື່ອງໝາຍຂອງ amount ທີ່ເກັບໄວ້ຈິງແທນສຳລັບ type ນີ້ໂດຍສະເພາະ.
  bool get isCredit => type == TxType.adjustment ? amount >= 0 : type.isCredit;
  double get absAmount => amount.abs();

  String get formattedAmount {
    final sign = isCredit ? '+' : '-';
    return '$sign${Booking._fmt(absAmount)}';
  }

  String get formattedDate {
    final dt = createdAt;
    return '${dt.day.toString().padLeft(2,'0')}/'
        '${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }
}

// ── WALLET ───────────────────────────────────────────────────

class Wallet {
  final String  providerId;
  final double  balance;
  final double  totalEarnings;
  final double  totalWithdrawn;
  final String? bankName;
  final String? bankAccount;
  final String? bankHolder;

  const Wallet({
    required this.providerId, required this.balance,
    required this.totalEarnings, required this.totalWithdrawn,
    this.bankName, this.bankAccount, this.bankHolder,
  });

  factory Wallet.empty(String uid) => Wallet(
      providerId: uid, balance: 0, totalEarnings: 0, totalWithdrawn: 0);

  factory Wallet.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Wallet(
      providerId:     doc.id,
      balance:       (d['balance']        as num? ?? 0).toDouble(),
      totalEarnings: (d['totalEarnings']  as num? ?? 0).toDouble(),
      totalWithdrawn:(d['totalWithdrawn'] as num? ?? 0).toDouble(),
      bankName:       d['bankName']    as String?,
      bankAccount:    d['bankAccount'] as String?,
      bankHolder:     d['bankHolder']  as String?,
    );
  }

  bool   get hasBankLinked    => bankName != null && bankAccount != null && bankHolder != null;
  String get formattedBalance => Booking._fmt(balance);
  String get formattedTotal   => Booking._fmt(totalEarnings);
}

// ── PROVIDER PROFILE ─────────────────────────────────────────

class ProviderProfile {
  final String       uid;
  final String       displayName;
  final String       email;
  final String?      phone;
  final String?      age;
  final String?      gender;
  final String?      address;
  final String?      bio;
  final String?      photoUrl;
  final List<String> serviceTypes;
  final bool         isOnline;
  final double       rating;
  final int          totalJobs;
  final double       completionRate;
  final KycStatus    kycStatus;
  final List<String> fcmTokens;
  final DateTime?    createdAt;

  const ProviderProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.phone, this.age, this.gender, this.address, this.bio, this.photoUrl,
    this.serviceTypes   = const [],
    this.isOnline       = false,
    this.rating         = 0,
    this.totalJobs      = 0,
    this.completionRate = 0,
    this.kycStatus      = KycStatus.none,
    this.fcmTokens      = const [],
    this.createdAt,
  });

  factory ProviderProfile.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProviderProfile(
      uid:            doc.id,
      displayName:    d['displayName']    as String? ?? '',
      email:          d['email']          as String? ?? '',
      phone:          d['phone']          as String?,
      age:            d['age']            as String?,
      gender:         d['gender']         as String?,
      address:        d['address']        as String?,
      bio:            d['bio']            as String?,
      photoUrl:       d['photoUrl']       as String?,
      serviceTypes:   List<String>.from(d['serviceTypes'] ?? []),
      isOnline:       d['isOnline']       as bool?   ?? false,
      rating:        (d['rating']         as num?)?.toDouble() ?? 0,
      totalJobs:      d['totalJobs']      as int?    ?? 0,
      completionRate:(d['completionRate'] as num?)?.toDouble() ?? 0,
      kycStatus: KycStatus.values.byName(d['kycStatus'] as String? ?? 'none'),
      fcmTokens:      List<String>.from(d['fcmTokens'] ?? []),
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName, 'email': email, 'phone': phone,
    'age': age, 'gender': gender, 'address': address, 'bio': bio,
    'photoUrl': photoUrl, 'serviceTypes': serviceTypes,
    'isOnline': isOnline, 'kycStatus': kycStatus.name,
    'fcmTokens': fcmTokens,
  };

  ProviderProfile copyWith({
    String? displayName, String? phone, String? age, String? gender,
    String? address, String? bio, String? photoUrl,
    List<String>? serviceTypes, bool? isOnline, KycStatus? kycStatus,
  }) => ProviderProfile(
    uid: uid, email: email,
    displayName:  displayName  ?? this.displayName,
    phone:        phone        ?? this.phone,
    age:          age          ?? this.age,
    gender:       gender       ?? this.gender,
    address:      address      ?? this.address,
    bio:          bio          ?? this.bio,
    photoUrl:     photoUrl     ?? this.photoUrl,
    serviceTypes: serviceTypes ?? this.serviceTypes,
    isOnline:     isOnline     ?? this.isOnline,
    rating: rating, totalJobs: totalJobs, completionRate: completionRate,
    kycStatus:    kycStatus    ?? this.kycStatus,
    fcmTokens: fcmTokens, createdAt: createdAt,
  );

  String get avatarLetter        => displayName.isNotEmpty ? displayName[0].toUpperCase() : '🔧';
  String get ratingLabel         => rating.toStringAsFixed(1);
  String get completionRateLabel => '${completionRate.toStringAsFixed(0)}%';
}

// ── REVIEW ───────────────────────────────────────────────────

class Review {
  final String   id;
  final String   bookingId;
  final String   customerId;
  final String   customerName;
  final String?  customerPhotoUrl;
  final String   providerId;
  final double   rating;
  final String   comment;
  final String?  providerReply;
  final DateTime createdAt;

  const Review({
    required this.id, required this.bookingId,
    required this.customerId, required this.customerName,
    this.customerPhotoUrl, required this.providerId,
    required this.rating, required this.comment,
    this.providerReply, required this.createdAt,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Review(
      id:               doc.id,
      bookingId:        d['bookingId']       as String? ?? '',
      customerId:       d['customerId']       as String? ?? '',
      customerName:     d['customerName']     as String? ?? '',
      customerPhotoUrl: d['customerPhotoUrl'] as String?,
      providerId:       d['providerId']       as String? ?? '',
      rating:          (d['rating']           as num?)?.toDouble() ?? 0,
      comment:          d['comment']          as String? ?? '',
      providerReply:    d['providerReply']    as String?,
      createdAt:       (d['createdAt']        as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String get formattedDate {
    final dt = createdAt;
    return '${dt.day.toString().padLeft(2,'0')}/'
        '${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }
}

// ── CHAT MESSAGE ─────────────────────────────────────────────

class ChatMessage {
  final String   id;
  final String   senderId;
  final String?  text;
  final String?  imageUrl;
  final bool     isRead;
  final DateTime createdAt;

  const ChatMessage({
    required this.id, required this.senderId,
    this.text, this.imageUrl, this.isRead = false,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(String id, Map<dynamic, dynamic> d) =>
      ChatMessage(
        id: id, senderId: d['senderId'] as String,
        text: d['text'] as String?, imageUrl: d['imageUrl'] as String?,
        isRead: d['isRead'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(d['createdAt'] as int),
      );

  Map<String, dynamic> toMap() => {
    'senderId': senderId, 'text': text, 'imageUrl': imageUrl,
    'isRead': isRead, 'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

// ── WORK SCHEDULE ────────────────────────────────────────────

class WorkSchedule {
  final Map<String, bool> availableDays;
  final List<String>      blockedDates;
  final String            workStartTime;
  final String            workEndTime;

  const WorkSchedule({
    required this.availableDays,
    this.blockedDates  = const [],
    this.workStartTime = '08:00',
    this.workEndTime   = '20:00',
  });

  factory WorkSchedule.defaultSchedule() => WorkSchedule(
    availableDays: {
      'ຈັນ': true, 'ອັງຄານ': true, 'ພຸດ': true,
      'ພະຫັດ': true, 'ສຸກ': true, 'ເສົາ': true, 'ອາທິດ': false,
    },
  );

  factory WorkSchedule.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WorkSchedule(
      availableDays: Map<String, bool>.from(d['availableDays'] ?? {}),
      blockedDates:  List<String>.from(d['blockedDates']       ?? []),
      workStartTime: d['workStartTime'] as String? ?? '08:00',
      workEndTime:   d['workEndTime']   as String? ?? '20:00',
    );
  }

  Map<String, dynamic> toMap() => {
    'availableDays': availableDays, 'blockedDates': blockedDates,
    'workStartTime': workStartTime, 'workEndTime': workEndTime,
  };
}
