// ============================================================
// provider_model.dart — LinTho
// Fixes:
//   ✅ field names ກົງກັບ Firestore ທຸກຈຸດ
//      displayName  (ບໍ່ແມ່ນ name)
//      isOnline     (ບໍ່ແມ່ນ isAvailable)
//      serviceTypes (ບໍ່ແມ່ນ services)
//      totalJobs    (ບໍ່ແມ່ນ totalReviews)
//   ✅ ເພີ່ມ lat / lng    — ສຳລັບ distance-based matching
//   ✅ ເພີ່ມ fcmTokens   — ສຳລັບ push notification
//   ✅ ເພີ່ມ completionRate, kycStatus, photoUrl, bio
//   ✅ (as num).toDouble() — ປ້ອງກັນ Firestore int→double crash
//   ✅ copyWith() — ອັບເດດສ່ວນໜຶ່ງໂດຍບໍ່ rebuild ທັງໝົດ
//   ✅ distanceTo() — ຄຳນວນໄລຍະທາງສຳລັບ Auto-Match sort
// ============================================================

import 'dart:math' show sqrt, sin, cos, atan2, pi;
import 'package:cloud_firestore/cloud_firestore.dart';

class ProviderModel {
  final String       uid;
  final String       displayName;   // Firestore: displayName
  final String       photoUrl;
  final String       bio;           // Firestore: bio (ບໍ່ແມ່ນ about)
  final String       phone;
  final String       email;
  final String       gender;
  final String       kycStatus;     // "none" | "pending" | "verified"
  final double       rating;
  final int          totalJobs;     // Firestore: totalJobs (ບໍ່ແມ່ນ totalReviews)
  final int          experienceYears;
  final double       completionRate;
  final List<String> serviceTypes;  // Firestore: serviceTypes (ບໍ່ແມ່ນ services)
  final List<String> fcmTokens;     // ສຳລັບ push notification
  final bool         isOnline;      // Firestore: isOnline (ບໍ່ແມ່ນ isAvailable)
  final double?      lat;           // ສຳລັບ distance-based matching
  final double?      lng;
  final String?      geohash;       // ສຳລັບ bounding-box query (ກ່ອນ limit)
  final DateTime?    lastSeen;
  final DateTime?    createdAt;
  final DateTime?    updatedAt;

  const ProviderModel({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.bio,
    required this.phone,
    required this.email,
    required this.gender,
    required this.kycStatus,
    required this.rating,
    required this.totalJobs,
    required this.experienceYears,
    required this.completionRate,
    required this.serviceTypes,
    required this.fcmTokens,
    required this.isOnline,
    this.lat,
    this.lng,
    this.geohash,
    this.lastSeen,
    this.createdAt,
    this.updatedAt,
  });

  // ── fromMap (Firestore → Model) ──────────────────────────
  factory ProviderModel.fromMap(String uid, Map<String, dynamic> d) {
    return ProviderModel(
      uid:             uid,

      // ✅ ໃຊ້ຊື່ກົງກັບ Firestore
      displayName:     d['displayName']    as String? ?? '',
      photoUrl:        d['photoUrl']       as String? ?? '',
      bio:             d['bio']            as String? ?? '',
      phone:           d['phone']          as String? ?? '',
      email:           d['email']          as String? ?? '',
      gender:          d['gender']         as String? ?? '',
      kycStatus:       d['kycStatus']      as String? ?? 'none',
      isOnline:        d['isOnline']       as bool?   ?? false,

      // ✅ (as num).toDouble() — ປ້ອງກັນ int crash
      rating:          (d['rating']         as num?)?.toDouble() ?? 0.0,
      completionRate:  (d['completionRate']  as num?)?.toDouble() ?? 0.0,
      lat:             (d['lat']             as num?)?.toDouble(),
      lng:             (d['lng']             as num?)?.toDouble(),
      geohash:         d['geohash']        as String?,

      // ✅ ໃຊ້ຊື່ກົງກັບ Firestore
      totalJobs:       d['totalJobs']      as int? ?? 0,
      experienceYears: d['experienceYears'] as int? ?? 0,

      // ✅ List fields
      serviceTypes:    List<String>.from(d['serviceTypes'] ?? []),
      fcmTokens:       List<String>.from(d['fcmTokens']   ?? []),

      // ✅ Timestamps
      lastSeen:  _toDateTime(d['lastSeen']),
      createdAt: _toDateTime(d['createdAt']),
      updatedAt: _toDateTime(d['updatedAt']),
    );
  }

  // ── fromDoc (DocumentSnapshot shortcut) ─────────────────
  factory ProviderModel.fromDoc(DocumentSnapshot doc) =>
      ProviderModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);

  // ── toMap (Model → Firestore) ────────────────────────────
  Map<String, dynamic> toMap() => {
    'displayName':     displayName,
    'photoUrl':        photoUrl,
    'bio':             bio,
    'phone':           phone,
    'email':           email,
    'gender':          gender,
    'kycStatus':       kycStatus,
    'rating':          rating,
    'totalJobs':       totalJobs,
    'experienceYears': experienceYears,
    'completionRate':  completionRate,
    'serviceTypes':    serviceTypes,
    'fcmTokens':       fcmTokens,
    'isOnline':        isOnline,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (geohash != null) 'geohash': geohash,
    'updatedAt':       FieldValue.serverTimestamp(),
  };

  // ── copyWith ─────────────────────────────────────────────
  ProviderModel copyWith({
    String?       displayName,
    String?       photoUrl,
    String?       bio,
    String?       phone,
    String?       email,
    String?       gender,
    String?       kycStatus,
    double?       rating,
    int?          totalJobs,
    int?          experienceYears,
    double?       completionRate,
    List<String>? serviceTypes,
    List<String>? fcmTokens,
    bool?         isOnline,
    double?       lat,
    double?       lng,
    String?       geohash,
    DateTime?     lastSeen,
    DateTime?     updatedAt,
  }) => ProviderModel(
    uid:             uid,
    displayName:     displayName     ?? this.displayName,
    photoUrl:        photoUrl        ?? this.photoUrl,
    bio:             bio             ?? this.bio,
    phone:           phone           ?? this.phone,
    email:           email           ?? this.email,
    gender:          gender          ?? this.gender,
    kycStatus:       kycStatus       ?? this.kycStatus,
    rating:          rating          ?? this.rating,
    totalJobs:       totalJobs       ?? this.totalJobs,
    experienceYears: experienceYears ?? this.experienceYears,
    completionRate:  completionRate  ?? this.completionRate,
    serviceTypes:    serviceTypes    ?? this.serviceTypes,
    fcmTokens:       fcmTokens       ?? this.fcmTokens,
    isOnline:        isOnline        ?? this.isOnline,
    lat:             lat             ?? this.lat,
    lng:             lng             ?? this.lng,
    geohash:         geohash         ?? this.geohash,
    lastSeen:        lastSeen        ?? this.lastSeen,
    createdAt:       createdAt,
    updatedAt:       updatedAt       ?? this.updatedAt,
  );

  // ── distanceTo() — Haversine formula (km) ───────────────
  // ໃຊ້ sort Top 3 ຕາມໄລຍະທາງ
  double? distanceTo(double? customerLat, double? customerLng) {
    if (lat == null || lng == null ||
        customerLat == null || customerLng == null) return null;

    const r    = 6371.0; // Earth radius km
    final dLat = _rad(customerLat - lat!);
    final dLng = _rad(customerLng - lng!);
    final a    = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat!)) * cos(_rad(customerLat)) *
            sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _rad(double deg) => deg * pi / 180;

  // ── helpers ──────────────────────────────────────────────

  // ✅ ກວດວ່າ provider ຮັບ service category ນີ້ໄດ້ບໍ
  bool supportsCategory(String category) =>
      serviceTypes.contains(category);

  // ✅ ກວດ verified
  bool get isVerified => kycStatus == 'verified';

  // ✅ display rating string
  String get ratingLabel =>
      rating > 0 ? rating.toStringAsFixed(1) : 'ໃໝ່';

  // ✅ avatar letter
  String get avatarLetter =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  // ── timestamp helper ─────────────────────────────────────
  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  @override
  String toString() =>
      'ProviderModel(uid: $uid, name: $displayName, '
          'online: $isOnline, rating: $rating)';
}