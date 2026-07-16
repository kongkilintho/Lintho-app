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

  const SavedAddress({
    required this.id,
    required this.label,
    required this.address,
  });

  factory SavedAddress.fromMap(Map<String, dynamic> d, String id) =>
      SavedAddress(
        id:      id,
        label:   d['label']   as String? ?? '',
        address: d['address'] as String? ?? '',
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
