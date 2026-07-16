// ============================================================
// cloudinary_service.dart — LinTho App
// Upload ຮູບໄປ Cloudinary (ແທນ Firebase Storage)
// Cloud: duznxeuny | Preset: Lintho uploads
// ============================================================

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CloudinaryService {
  CloudinaryService._();
  static final instance = CloudinaryService._();

  static const _cloudName  = 'duznxeuny';
  static const _uploadPreset = 'Lintho uploads';
  static const _uploadUrl =
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  // ── Upload ຮູບ ──────────────────────────────────────────

  Future<String?> uploadImage(File file, {String folder = 'profiles'}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder']        = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final body     = await response.stream.bytesToString();
      final json     = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return json['secure_url'] as String?;
      } else {
        throw Exception(json['error']?['message'] ?? 'Upload failed');
      }
    } catch (e) {
      throw Exception('Cloudinary upload error: $e');
    }
  }

  // ── Customer: upload ຮູບໂປຣໄຟລ໌ ────────────────────────

  Future<String?> uploadCustomerPhoto(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final url = await uploadImage(file, folder: 'profiles/customers/$uid');
    if (url != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'photoUrl': url});
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
    }
    return url;
  }

  // ── Provider: upload ຮູບໂປຣໄຟລ໌ ────────────────────────

  Future<String?> uploadProviderPhoto(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final url = await uploadImage(file, folder: 'profiles/providers/$uid');
    if (url != null) {
      await FirebaseFirestore.instance
          .collection('providers')
          .doc(uid)
          .update({'photoUrl': url});
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
    }
    return url;
  }

  // ── Provider: upload ຮູບ KYC ────────────────────────────

  Future<String?> uploadKycPhoto(File file, {required bool isId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final folder = 'kyc/$uid/${isId ? 'id' : 'selfie'}';
    return uploadImage(file, folder: folder);
  }

  // ── Job: upload ຮູບກ່ອນ/ຫຼັງ ────────────────────────────

  Future<String?> uploadJobPhoto(
      String bookingId, File file, {required bool isBefore}) async {
    final folder = 'jobs/$bookingId/${isBefore ? 'before' : 'after'}';
    final url    = await uploadImage(file, folder: folder);
    if (url != null) {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({isBefore ? 'beforePhotoUrl' : 'afterPhotoUrl': url});
    }
    return url;
  }
}