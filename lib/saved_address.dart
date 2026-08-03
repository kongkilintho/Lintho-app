// ============================================================
// saved_address.dart — Shared "SavedAddress" model + provider
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SavedAddress {
  final String id;
  final String label;
  final String address;
  // ✅ [FIX ME-16] location ຖືກຂຽນຢູ່ແລ້ວຕອນບັນທຶກ (quick_booking_provider.dart
  // saveAsDefaultAddress) ແຕ່ model ນີ້ບໍ່ເຄີຍອ່ານກັບຄືນມາກ່ອນ — ເຮັດໃຫ້
  // _useSavedAddress() ໃນ quick_booking_screen.dart ຕ້ອງໃຊ້ພິກັດຄົງທີ່
  // (ວຽງຈັນ) ແທນ ທຸກຄັ້ງ. ເພີ່ມເຂົ້າມາໃຫ້ໃຊ້ພິກັດແທ້ໄດ້.
  final GeoPoint? location;
  // ✅ [Customer UX pass 2026-08-03] ໃໝ່ — ໃຫ້ລູກຄ້າຕັ້ງທີ່ຢູ່ໜຶ່ງອັນເປັນ
  // ຄ່າເລີ່ມຕົ້ນ. Additive field, ບໍ່ກະທົບ document ເກົ່າທີ່ບໍ່ມີ field ນີ້
  // (default false).
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    this.location,
    this.isDefault = false,
  });

  factory SavedAddress.fromMap(Map<String, dynamic> d, String id) =>
      SavedAddress(
        id:        id,
        label:     d['label']   as String? ?? '',
        address:   d['address'] as String? ?? '',
        location:  d['location'] as GeoPoint?,
        isDefault: d['isDefault'] as bool? ?? false,
      );
}

final savedAddressesProvider = StreamProvider<List<SavedAddress>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('addresses')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
      .map((d) => SavedAddress.fromMap(d.data(), d.id))
      .toList());
});
