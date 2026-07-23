// ============================================================
// cloudinary_service.dart — LinTho App
// Upload ຮູບໄປ Cloudinary (ແທນ Firebase Storage)
// Cloud: duznxeuny
// 🔒 [Security fix] ອັບໂຫລດແບບ "signed" ຜ່ານ Cloud Function
// getCloudinarySignature — ບໍ່ໃຊ້ unsigned upload preset ອີກຕໍ່ໄປ. ເມື່ອກ່ອນ
// preset name + cloud name hardcode ຢູ່ client (ດຶງອອກຈາກ APK ໄດ້) ເຮັດໃຫ້
// ໃຜກໍອັບໂຫລດເຂົ້າ account ນີ້ໄດ້ໂດຍກົງ ໂດຍບໍ່ຕ້ອງຜ່ານ auth — ຕອນນີ້ Cloud
// Function ອອກ signature ໃຫ້ສະເພາະ user ທີ່ login ແລ້ວ ແລະ ຈຳກັດ folder ໃຫ້
// ຢູ່ພາຍໃຕ້ uid/booking ຂອງຕົນເອງເທົ່ານັ້ນ (ເບິ່ງ functions/index.js).
// ============================================================

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CloudinaryService {
  CloudinaryService._();
  static final instance = CloudinaryService._();

  static const _cloudName  = 'duznxeuny';
  static const _uploadUrl =
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  // ── Upload ຮູບ (signed) ─────────────────────────────────

  // 🔒 [AUDIT CRIT-5] ບໍ່ເຄີຍມີ timeout ໃນທັງ callable ແລະ http request ນີ້ —
  // ຖ້າອອບໄລນ໌/ອິນເຕີເນັດອ່ອນ, ອັບໂຫລດຮູບ (ໜ້າວຽກ, KYC, profile) ຄ້າງໂຫລດ
  // ຕະຫຼອດໄປໂດຍບໍ່ມີ error. ຕອນນີ້ timeout ທັງສອງຂັ້ນຕອນແຍກກັນ.
  static const _kSignatureTimeout = Duration(seconds: 15);
  static const _kUploadTimeout    = Duration(seconds: 30);

  Future<String?> uploadImage(File file, {required String folder}) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('getCloudinarySignature');
      final result = await callable.call<Map<String, dynamic>>({'folder': folder})
          .timeout(_kSignatureTimeout, onTimeout: () => throw Exception(
              'ໝົດເວລາການເຊື່ອມຕໍ່ (connection timed out)'));
      final sig = result.data;

      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..fields['api_key']   = sig['apiKey'] as String
        ..fields['timestamp'] = '${sig['timestamp']}'
        ..fields['signature'] = sig['signature'] as String
        ..fields['folder']    = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send().timeout(_kUploadTimeout,
          onTimeout: () => throw Exception(
              'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)'));
      final body     = await response.stream.bytesToString()
          .timeout(_kUploadTimeout, onTimeout: () => throw Exception(
              'ອັບໂຫລດຮູບໝົດເວລາ, ກະລຸນາລອງໃໝ່ (upload timed out)'));
      final json     = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return json['secure_url'] as String?;
      } else {
        throw Exception(json['error']?['message'] ?? 'Upload failed');
      }
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Cloudinary signature error: ${e.message}');
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
      // 🔒 [AUDIT CRIT-5 follow-up] upload ຕົວຮູບເອງ timeout ແລ້ວ, ແຕ່ການຂຽນ
      // url ກັບຄືນ Firestore ນີ້ບໍ່ເຄີຍມີ — ຄ້າງໄດ້ຢູ່ຂັ້ນຕອນສຸດທ້າຍ
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'photoUrl': url})
          .timeout(_kSignatureTimeout, onTimeout: () => throw Exception(
              'ໝົດເວລາການເຊື່ອມຕໍ່ (connection timed out)'));
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
          .update({'photoUrl': url})
          .timeout(_kSignatureTimeout, onTimeout: () => throw Exception(
              'ໝົດເວລາການເຊື່ອມຕໍ່ (connection timed out)'));
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
          .update({isBefore ? 'beforePhotoUrl' : 'afterPhotoUrl': url})
          .timeout(_kSignatureTimeout, onTimeout: () => throw Exception(
              'ໝົດເວລາການເຊື່ອມຕໍ່ (connection timed out)'));
    }
    return url;
  }
}