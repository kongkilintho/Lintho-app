// ============================================================
// technician_register_screen.dart — LinTho App
// ລົງທະບຽນ 'ຊ່າງ' — Multi-step:
//   Step 0: ເບີໂທລະສັບ
//   Step 1: ຢືນຢັນ OTP (Firebase Phone Auth)
//   Step 2: ຂໍ້ມູນສ່ວນຕົວ (ຊື່ + ລະຫັດຜ່ານ)
//   Step 3: ທັກສະ/ປະເພດງານ + ປະສົບການ (ປີ)
//   Step 4: KYC — ຮູບບັດປະຊາຊົນ + ເຊວຟີຄູ່ກັບບັດ
//   Step 5: ເປີດຕຳແໜ່ງ GPS
//   → ບັນທຶກ Firestore (status = 'pending') → PendingApprovalScreen
// Rules:
//   ✅ withValues(alpha:) ແທນ withOpacity
//   ✅ InkWell + Material ແທນ GestureDetector
//   ✅ Skeleton loading ແທນ CircularProgressIndicator
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'brand_mark_tile.dart';
import 'cloudinary_service.dart';
import 'lao_phone.dart';
import 'main.dart' show LoginPage;
import 'widgets/app_text_field.dart';

const _serviceCategories = <(String id, String labelKey)>[
  ('aircon',       'service_aircon'),
  ('maid',         'service_maid'),
  ('electrician',  'service_electrician'),
  ('plumber',      'service_plumber'),
];

class TechnicianRegisterScreen extends StatefulWidget {
  const TechnicianRegisterScreen({super.key});

  @override
  State<TechnicianRegisterScreen> createState() => _TechnicianRegisterScreenState();
}

class _TechnicianRegisterScreenState extends State<TechnicianRegisterScreen> {
  final _phoneCtrl      = TextEditingController();
  final _otpCtrl        = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _passCtrl       = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  final _experienceCtrl = TextEditingController();

  int     _step = 0;
  bool    _loading = false;
  bool    _obscure = true;
  bool    _obscureConfirm = true;
  String? _error;
  // ✅ [FIX HI-AUTH-1]
  bool    _showLoginLink = false;

  String? _verificationId;
  String? _serviceCategory;
  File?   _idDocFile;
  File?   _idSelfieFile;
  double? _lat, _lng;
  bool    _locationDeniedForever = false;

  // ✅ [FIX ME-AUTH-2] cooldown ຕອນ "ສົ່ງ OTP ຄືນ"
  Timer?  _resendTimer;
  int     _resendCooldown = 0;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  // ✅ DEBUG-ONLY: true ຫຼັງກົດ 'Bypass OTP' — ຂ້າມ Firebase Auth call ທຸກອັນ
  // ໃນ step ຕໍ່ໄປ ເພື່ອທົດສອບ UI flow ຕອນ Firebase Console ບລັອກການສະໝັກ
  // (admin-restricted-operation)
  bool _debugBypass = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _experienceCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _normalizedPhone => laoPhoneDigitsOnly(_phoneCtrl.text);
  String get _e164Phone => toE164LaoPhone(_normalizedPhone);

  // ✅ firestore.rules ຫ້າມປ່ຽນ field 'role' ຕອນ update — ຖ້າເບີໂທນີ້ເຄີຍ
  // ລົງທະບຽນເປັນ 'customer' ມາກ່ອນ (Firebase Auth phone sign-in ຄືນ uid
  // ດຽວກັນສະເໝີສຳລັບເບີດຽວກັນ), users/{uid} doc ຈະມີຢູ່ແລ້ວ ແລະ ການ set
  // role:'provider' ຈະຖືກຕີເປັນ "update" ບໍ່ແມ່ນ "create" → permission-denied
  // ຢູ່ security rules. ກວດຄັດປະຕິເສດແຕ່ຫົວທີ (ຫຼັງ OTP ຢືນຢັນສຳເລັດ) ເພື່ອບໍ່ໃຫ້
  // user ເສຍເວລາອັບໂຫຼດ KYC ຫຼາຍ step ແລ້ວມາລົ້ມເຫຼວຕອນຈົບ.
  Future<bool> _blockIfRoleConflict(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final existingRole = doc.data()?['role'] as String?;
      if (doc.exists && existingRole != null && existingRole != 'provider') {
        if (!mounted) return true;
        setState(() { _loading = false; _error = tr('role_conflict_error'); });
        return true;
      }
    } catch (_) {
      // ✅ ອ່ານບໍ່ໄດ້ (offline ຫຼືອື່ນໆ) — ປ່ອຍຜ່ານໄປ, ຈະຖືກ security rules
      // block ອີກຄັ້ງຢູ່ _finish() ຢູ່ແລ້ວ (defense in depth)
    }
    return false;
  }

  // ── Step 0: Phone ────────────────────────────────────────

  Future<void> _sendOtp() async {
    if (!isValidLaoPhone(_phoneCtrl.text)) {
      setState(() => _error = tr('invalid_phone'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _e164Phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (!mounted) return;
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null && await _blockIfRoleConflict(uid)) return;
          if (!mounted) return;
          setState(() { _loading = false; _step = 2; });
        },
        verificationFailed: (FirebaseAuthException e) {
          // ✅ ພິມ error ແທ້ຈິງອອກ console (ເຊັ່ນ Play Integrity/SHA-256
          // ບໍ່ໄດ້ setup ໃນໂໝດ dev) — ຊ່ວຍ debug ວ່າ error ມາຈາກໃສ
          debugPrint('[TechnicianRegister] verifyPhoneNumber FAILED: '
              '${e.code} — ${e.message}');
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error   = '${tr("error")} (${e.code})';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _verificationId = verificationId;
            _step = 1;
          });
          _startResendCooldown(); // ✅ [FIX ME-AUTH-2]
        },
        // 🔒 [FOLLOWUP-J4] ກ່ອນໜ້ານີ້ບໍ່ໄດ້ clear _loading ຢູ່ນີ້ເລີຍ — ຖ້າ
        // Firebase ຍິງ timeout ນີ້ກ່ອນ codeSent (ເນັດຊ້າ), ປຸ່ມສົ່ງ OTP ຄ້າງ
        // disabled/spinning ຈົນກວ່າ codeSent ຈະມາເຖິງ (ຫຼືບໍ່ມາເລີຍ).
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (!mounted) return;
          setState(() => _loading = false);
        },
      );
    } catch (e) {
      debugPrint('[TechnicianRegister] verifyPhoneNumber EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

  // ✅ DEBUG-ONLY: ຂ້າມການເອີ້ນໃຊ້ Firebase Auth 100% (ບໍ່ verifyPhoneNumber,
  // ບໍ່ signInAnonymously, ບໍ່ signInWithCredential) ເພື່ອທົດສອບ UI flow ຕອນ
  // Firebase Console ບລັອກການສະໝັກ (admin-restricted-operation). ໃຊ້
  // setState ລ້າໆ ໄປ Step 2 ໂດຍເອົາ mock phone number ທີ່ກອກໄວ້ໄປນຳ.
  // ⚠️ kDebugMode ກວດສະເພາະ build dev.
  void _debugBypassOtp() {
    final mockPhone = _normalizedPhone.isEmpty ? '02091312566' : _normalizedPhone;
    debugPrint('[TechnicianRegister] DEBUG BYPASS — skipping Firebase Auth '
        'entirely, mock phone = $mockPhone');
    setState(() {
      _error = null;
      _verificationId = null;
      _debugBypass = true;
      if (_phoneCtrl.text.trim().isEmpty) _phoneCtrl.text = mockPhone;
      _step = 2;
    });
  }

  // ── Step 1: OTP ──────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = tr('must_enter_otp'));
      return;
    }
    if (_verificationId == null) {
      setState(() => _error = tr('otp_invalid'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode:        code,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && await _blockIfRoleConflict(uid)) return;
      if (!mounted) return;
      setState(() { _loading = false; _step = 2; });
    } on FirebaseAuthException catch (e) {
      debugPrint('[TechnicianRegister] verifyOtp FAILED: ${e.code} — ${e.message}');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('otp_invalid'); });
    } catch (e) {
      debugPrint('[TechnicianRegister] verifyOtp EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

  // ── Step 2: ຂໍ້ມູນສ່ວນຕົວ ──────────────────────────────

  Future<void> _submitPersonalInfo() async {
    final name    = _nameCtrl.text.trim();
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (name.isEmpty)                     { setState(() => _error = tr('fill_all')); return; }
    if (pass.trim().isEmpty || pass.length < 6) { setState(() => _error = tr('pass_min')); return; }
    if (pass != confirm)                  { setState(() => _error = tr('password_mismatch')); return; }

    setState(() { _loading = true; _error = null; });

    // ✅ DEBUG BYPASS — ບໍ່ແຕະ Firebase Auth ເລີຍ, ໄປ step ຕໍ່ໄປທັນທີ
    if (_debugBypass) {
      debugPrint('[TechnicianRegister] DEBUG BYPASS — skip linkWithCredential, '
          'name=$name');
      setState(() { _loading = false; _step = 3; });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('no-auth-user');

      // ✅ ຕັ້ງລະຫັດຜ່ານໂດຍ link email/password credential ກັບບັນຊີ phone-auth ນີ້
      final syntheticEmail = '$_normalizedPhone@lintho.app';
      await user.linkWithCredential(
        EmailAuthProvider.credential(email: syntheticEmail, password: pass),
      );
      await user.updateDisplayName(name);

      if (!mounted) return;
      setState(() { _loading = false; _step = 3; });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // 🔒 [AUDIT QA-2 / HI-AUTH-1] ເບີໂທນີ້ມີບັນຊີ role ດຽວກັນ (provider) ຢູ່
      // ແລ້ວ — ແຈ້ງຊັດເຈນ ແລະ ໃຫ້ປຸ່ມພາໄປ Login ແທນ raw error code
      final isDuplicate = e.code == 'provider-already-linked' ||
          e.code == 'email-already-in-use' ||
          e.code == 'credential-already-in-use';
      setState(() {
        _loading = false;
        _error   = isDuplicate
            ? tr('account_already_exists_error')
            : '${tr("error")} (${e.code})';
        _showLoginLink = isDuplicate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); _showLoginLink = false; });
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => route.isFirst,
    );
  }

  // ── Step 3: ທັກສະ + ປະສົບການ ───────────────────────────

  void _submitSkillStep() {
    if (_serviceCategory == null) {
      setState(() => _error = tr('must_select_service'));
      return;
    }
    // ✅ [FIX Medium-7] ຫ້າມຮັບຄ່າຕິດລົບ ຫຼື ຫຼາຍເກີນໄປ — ຈຳກັດ 0-60 ປີ
    final exp = int.tryParse(_experienceCtrl.text.trim());
    if (exp == null || exp < 0 || exp > 60) {
      setState(() => _error = tr('must_fill_experience_years'));
      return;
    }
    setState(() { _error = null; _step = 4; });
  }

  // ── Step 4: KYC ──────────────────────────────────────────

  // ✅ [FIX Low-8] ID document ເຄີຍມີແຕ່ gallery — ບໍ່ມີທາງຖ່າຍຮູບໃໝ່ໂດຍກົງ
  // ຖ້າຜູ້ໃຊ້ບໍ່ມີຮູບບັດແຕ່ກ່ອນ. ຕອນນີ້ໃຫ້ເລືອກກ້ອງ ຫຼື ຄັງຮູບໄດ້.
  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: C.teal),
            title: Text(tr('take_photo')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: C.teal),
            title: Text(tr('choose_from_gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickIdDocument() async {
    final source = await _chooseImageSource();
    if (source == null || !mounted) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 75, maxWidth: 1600, maxHeight: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() => _idDocFile = File(picked.path));
    } catch (e) {
      debugPrint('[TechnicianRegister] _pickIdDocument EXCEPTION: $e');
      if (!mounted) return;
      setState(() => _error = tr('camera_permission_error'));
    }
  }

  Future<void> _takeIdSelfie() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 75,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null || !mounted) return;
      setState(() => _idSelfieFile = File(picked.path));
    } catch (e) {
      debugPrint('[TechnicianRegister] _takeIdSelfie EXCEPTION: $e');
      if (!mounted) return;
      setState(() => _error = tr('camera_permission_error'));
    }
  }

  void _submitKycStep() {
    if (_idDocFile == null) {
      setState(() => _error = tr('must_upload_id'));
      return;
    }
    if (_idSelfieFile == null) {
      setState(() => _error = tr('must_take_id_selfie'));
      return;
    }
    setState(() { _error = null; _step = 5; });
  }

  // ── Step 5: Location ─────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() { _loading = true; _error = null; _locationDeniedForever = false; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(() { _loading = false; _error = tr('must_enable_location'); });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = tr('location_denied_forever');
          _locationDeniedForever = true;
        });
        return;
      }
      if (perm == LocationPermission.denied) {
        if (!mounted) return;
        setState(() { _loading = false; _error = tr('must_enable_location'); });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      debugPrint('[TechnicianRegister] _useCurrentLocation EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('location_error'); });
    }
  }

  // ── Finalize: ບັນທຶກ Firestore (status: pending) ────────

  Future<void> _finish() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = tr('must_enable_location'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    // ✅ DEBUG BYPASS — ບໍ່ຂຽນ Firestore/ອັບໂຫຼດ KYC ແທ້ (ບໍ່ມີ auth.uid ໃຫ້ໃຊ້)
    // ພຽງແຕ່ສະແດງວ່າ flow ໄປຮອດຈົບ — print mock data ອອກ console
    if (_debugBypass) {
      debugPrint('[TechnicianRegister] DEBUG BYPASS — flow completed (no real '
          'write). phone=$_normalizedPhone name=${_nameCtrl.text.trim()} '
          'service=$_serviceCategory exp=${_experienceCtrl.text.trim()} '
          'lat=$_lat lng=$_lng idDoc=${_idDocFile?.path} '
          'idSelfie=${_idSelfieFile?.path}');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Debug bypass — flow ຈົບແລ້ວ (ບໍ່ໄດ້ບັນທຶກຂໍ້ມູນແທ້)'),
        backgroundColor: Colors.orange,
      ));
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid  = user?.uid;
      if (uid == null) throw Exception('no-auth-user');

      final name = _nameCtrl.text.trim();

      // ✅ ອັບໂຫຼດເອກະສານ KYC
      final idDocUrl    = await CloudinaryService.instance
          .uploadKycPhoto(_idDocFile!, isId: true);
      final idSelfieUrl = await CloudinaryService.instance
          .uploadKycPhoto(_idSelfieFile!, isId: false);
      if (!mounted) return;

      // ✅ ຂຽນ users + providers ດ້ວຍ WriteBatch ດຽວ — atomic (ສຳເລັດພ້ອມກັນ
      // ຫຼືບໍ່ສຳເລັດເລີຍ). ກ່ອນໜ້ານີ້ໃຊ້ .set() ແຍກກັນ 2 ຄັ້ງ: ຖ້າ write ທີ 2
      // (providers) ລົ້ມເຫຼວຫຼັງ write ທຳອິດ (users) ສຳເລັດແລ້ວ — ບັນຊີຈະກາຍເປັນ
      // "ghost": users ບອກວ່າ role=provider/status=pending ເຮັດໃຫ້ RoleRouter
      // ພາໄປ PendingApprovalScreen ຕະຫຼອດໄປ (ມີແຕ່ປຸ່ມ Logout, ບໍ່ມີທາງກັບຄືນ
      // ໄປລົງທະບຽນຕໍ່) ໃນຂະນະທີ່ providers doc ບໍ່ມີເລີຍ ເຮັດໃຫ້ admin ຫາບໍ່ພົບ
      // ບັນຊີນີ້ເພື່ອອະນຸມັດ.
      final batch = FirebaseFirestore.instance.batch();

      batch.set(FirebaseFirestore.instance.collection('users').doc(uid), {
        'uid':         uid,
        'displayName': name,
        'phone':       _normalizedPhone,
        'role':        'provider',
        'photoUrl':    '',
        'status':      'pending',
        'lat':         _lat,
        'lng':         _lng,
        'createdAt':   FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 🔒 [AUDIT KYC-1] ຮູບບັດປະຈຳຕົວ/selfie ຫ້າມຢູ່ໃນ providers/{uid} — doc
      // ນັ້ນອ່ານໄດ້ໂດຍ user login ໃດກໍໄດ້ (firestore.rules). ເກັບໄວ້ໃນ kyc/{uid}
      // ແທນ (ອ່ານໄດ້ສະເພາະເຈົ້າຂອງ/admin).
      batch.set(FirebaseFirestore.instance.collection('kyc').doc(uid), {
        'idDocUrl':  idDocUrl ?? '',
        'selfieUrl': idSelfieUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final expYears = int.tryParse(_experienceCtrl.text.trim()) ?? 0;
      batch.set(FirebaseFirestore.instance.collection('providers').doc(uid), {
        'displayName':     name,
        'phone':           _normalizedPhone,
        'isOnline':        false,
        'status':          'pending',
        'kycStatus':       'pending',
        'serviceTypes':    [_serviceCategory],
        'experienceYears': expYears,
        'fcmTokens':       <String>[],
        'lat':             _lat,
        'lng':             _lng,
        'rating':          0.0,
        'totalJobs':       0,
        'completionRate':  0.0,
        'createdAt':       FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;
      setState(() => _loading = false);

      // ✅ RoleRouter ຈະອ່ານ status == 'pending' ແລະ ພາໄປ PendingApprovalScreen
      // ໂດຍອັດຕະໂນມັດ — ບໍ່ມີທາງກັບຄືນໄປ Home ໄດ້ ຈົນກວ່າ Admin ຈະ Approve
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      // ✅ permission-denied ຢູ່ນີ້ ໝາຍວ່າ users/{uid} ມີ role ອື່ນຢູ່ກ່ອນແລ້ວ
      // (ຫຼຸດຜ່ານ _blockIfRoleConflict ຕອນ OTP — ເຊັ່ນ race condition) —
      // firestore.rules ຫ້າມແກ້ໄຂ field 'role' ຕອນ update
      setState(() {
        _loading = false;
        _error   = e.code == 'permission-denied'
            ? tr('role_conflict_error')
            : '${tr("error")} (${e.code})';
      });
    } catch (e) {
      debugPrint('[TechnicianRegister] _finish EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  String get _stepTitle => switch (_step) {
    0 => tr('phone_step_title'),
    1 => tr('otp_step_title'),
    2 => tr('personal_info_step_title'),
    3 => tr('skill_step_title'),
    4 => tr('kyc_step_title'),
    _ => tr('location_step_title'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.text, size: 20),
          tooltip: tr('back_semantic'), // ✅ [FIX ME-AUTH-5]
          // ✅ [FIX Medium-1] ຫ້າມກົດຍ້ອນຄືນລະຫວ່າງມີ request ຄ້າງຢູ່
          onPressed: _loading ? null : () {
            // 🔒 [AUDIT QA-2 / ME-AUTH-1] ຈາກ step 2, ເງື່ອນໄຂເກົ່າ decrement ໄປ
            // step 1 (ໜ້າ OTP) ພໍດີ, ຂັດກັບ comment ຂ້າງລຸ່ມ — ຕອນນີ້ຍ້ອນກັບໄປ
            // step 0 ໂດຍກົງແທນ
            if (_step == 2) {
              _resendTimer?.cancel();
              setState(() {
                _step = 0; _error = null; _showLoginLink = false;
                _verificationId = null; _resendCooldown = 0;
                _otpCtrl.clear();
                // ✅ [FIX Medium-6] ລຶບຂໍ້ມູນ KYC/ທັກສະ/GPS ທີ່ເຄີຍໃສ່ໄວ້ ເພື່ອບໍ່ໃຫ້
                // ຂໍ້ມູນຂອງເບີໂທເກົ່າຫຼຸດຕິດໄປກັບເບີໂທໃໝ່ທີ່ຈະລົງທະບຽນ
                _serviceCategory = null; _experienceCtrl.clear();
                _idDocFile = null; _idSelfieFile = null;
                _lat = null; _lng = null; _locationDeniedForever = false;
              });
            } else if (_step > 0 && _step != 1) {
              // ✅ ບໍ່ໃຫ້ກັບຄືນຫາ OTP step ຫຼັງຢືນຢັນສຳເລັດແລ້ວ
              setState(() { _step -= 1; _error = null; });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Row(children: [
            const BrandMarkTile(size: 44, radius: 14),
            const SizedBox(width: 12),
            const Text('LinTho', style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w900, color: C.primary,
            )),
          ]),
          const SizedBox(height: 20),

          // ✅ [FIX ME-AUTH-3] progress indicator — flow ນີ້ມີ 6 step (0-5)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step + 1) / 6,
              minHeight: 6,
              backgroundColor: C.border,
              valueColor: const AlwaysStoppedAnimation(C.primary),
            ),
          ),
          const SizedBox(height: 16),

          Text(_stepTitle, style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w900, color: C.primary,
          )),
          const SizedBox(height: 24),

          ..._buildStepBody(),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        C.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.red.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: C.red, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(
                  color: C.red, fontSize: 13,
                ))),
              ]),
            ),
            // ✅ [FIX HI-AUTH-1]
            if (_showLoginLink) ...[
              const SizedBox(height: 8),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _goToLogin,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(tr('go_to_login'), style: const TextStyle(
                          color: C.teal, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: _loading ? null : _primaryAction(),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                  ? const _ButtonSkeleton()
                  : Text(_primaryLabel(), style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),

          if (_step == 1) ...[
            const SizedBox(height: 12),
            // ✅ [FIX ME-AUTH-2] disable + ນັບຖອຍຫຼັງ ຕອນ cooldown ຍັງບໍ່ໝົດ
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: (_loading || _resendCooldown > 0) ? null : _sendOtp,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                        _resendCooldown > 0
                            ? '${tr("resend_otp")} (${_resendCooldown}s)'
                            : tr('resend_otp'),
                        style: TextStyle(
                            color: _resendCooldown > 0 ? C.muted : C.teal,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],

          // ✅ DEBUG-ONLY — ປຸ່ມຂ້າມ OTP ສຳລັບທົດສອບ flow. ບໍ່ສະແດງໃນ release build.
          if (kDebugMode && (_step == 0 || _step == 1)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 48,
              child: OutlinedButton(
                onPressed: _loading ? null : _debugBypassOtp,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Bypass OTP (Debug Only)', style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  VoidCallback _primaryAction() => switch (_step) {
    0 => _sendOtp,
    1 => _verifyOtp,
    2 => _submitPersonalInfo,
    3 => _submitSkillStep,
    4 => _submitKycStep,
    _ => _finish,
  };

  String _primaryLabel() => switch (_step) {
    0 => tr('get_otp'),
    1 => tr('verify_otp'),
    2 => tr('next'),
    3 => tr('next'),
    4 => tr('next'),
    _ => tr('submit_for_review'),
  };

  List<Widget> _buildStepBody() => switch (_step) {
    0 => _buildPhoneStep(),
    1 => _buildOtpStep(),
    2 => _buildPersonalInfoStep(),
    3 => _buildSkillStep(),
    4 => _buildKycStep(),
    _ => _buildLocationStep(),
  };

  // ── Step 0 ──

  List<Widget> _buildPhoneStep() => [
    _fieldLabel(tr('phone')),
    const SizedBox(height: 8),
    _TextField(
      controller: _phoneCtrl,
      hint:       tr('phone_hint'),
      icon:       Icons.phone_outlined,
      inputType:  TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    ),
  ];

  // ── Step 1 ──

  List<Widget> _buildOtpStep() => [
    Text('${tr("otp_sent_to")} $_e164Phone',
        style: const TextStyle(color: C.muted, fontSize: 13)),
    const SizedBox(height: 16),
    _TextField(
      controller: _otpCtrl,
      hint:       '••••••',
      icon:       Icons.lock_clock_outlined,
      inputType:  TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength:  6,
      textAlign:  TextAlign.center,
    ),
  ];

  // ── Step 2 ──

  List<Widget> _buildPersonalInfoStep() => [
    _fieldLabel(tr('name')),
    const SizedBox(height: 8),
    _TextField(
      controller: _nameCtrl,
      hint:       tr('name_hint'),
      icon:       Icons.person_outline,
      inputType:  TextInputType.name,
      textCapitalization: TextCapitalization.words,
      maxLength:  60,
      autofillHints: const [AutofillHints.name],
    ),
    const SizedBox(height: 16),

    _fieldLabel(tr('password')),
    const SizedBox(height: 8),
    _TextField(
      controller: _passCtrl,
      hint:       '••••••••',
      icon:       Icons.lock_outline,
      obscure:    _obscure,
      autofillHints: const [AutofillHints.newPassword],
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: C.muted),
        tooltip: _obscure ? tr('show_password_semantic') : tr('hide_password_semantic'),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
    const SizedBox(height: 16),

    _fieldLabel(tr('confirm_password')),
    const SizedBox(height: 8),
    _TextField(
      controller: _confirmCtrl,
      hint:       '••••••••',
      icon:       Icons.lock_outline,
      obscure:    _obscureConfirm,
      autofillHints: const [AutofillHints.newPassword],
      suffixIcon: IconButton(
        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: C.muted),
        tooltip: _obscureConfirm ? tr('show_password_semantic') : tr('hide_password_semantic'),
        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
      ),
    ),
  ];

  // ── Step 3: ທັກສະ/ປະເພດງານ ເປັນ Grid + ປະສົບການ ──────

  List<Widget> _buildSkillStep() => [
    _fieldLabel(tr('service_category')),
    const SizedBox(height: 10),
    GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: _serviceCategories.map((c) {
        final selected = _serviceCategory == c.$1;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _serviceCategory = c.$1),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? C.primary.withValues(alpha: 0.07) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? C.primary : C.border, width: selected ? 2 : 1),
              ),
              child: Text(tr(c.$2), style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: selected ? C.primary : C.text)),
            ),
          ),
        );
      }).toList(),
    ),
    const SizedBox(height: 20),

    _fieldLabel(tr('experience')),
    const SizedBox(height: 8),
    _TextField(
      controller: _experienceCtrl,
      hint:       tr('experience_years_hint'),
      icon:       Icons.work_outline,
      inputType:  TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength:  2,
    ),
  ];

  // ── Step 4: KYC ──

  List<Widget> _buildKycStep() => [
    _fieldLabel(tr('id_document')),
    const SizedBox(height: 4),
    Text(tr('id_document_hint'), style: const TextStyle(color: C.muted, fontSize: 12)),
    const SizedBox(height: 8),
    _UploadTile(
      file: _idDocFile,
      placeholderLabel: tr('upload_id_document'),
      changeLabel: tr('change_id_document'),
      onTap: _pickIdDocument,
    ),
    const SizedBox(height: 20),

    _fieldLabel(tr('id_selfie')),
    const SizedBox(height: 4),
    Text(tr('id_selfie_hint'), style: const TextStyle(color: C.muted, fontSize: 12)),
    const SizedBox(height: 8),
    _UploadTile(
      file: _idSelfieFile,
      placeholderLabel: tr('take_id_selfie'),
      changeLabel: tr('retake_selfie'),
      icon: Icons.camera_alt_outlined,
      onTap: _takeIdSelfie,
    ),
  ];

  // ── Step 5: Location ──

  List<Widget> _buildLocationStep() => [
    Text(tr('location_hint'), style: const TextStyle(color: C.muted, fontSize: 13)),
    const SizedBox(height: 20),
    Center(child: Icon(Icons.location_on_outlined,
        size: 64, color: _lat != null ? C.green : C.muted)),
    const SizedBox(height: 12),
    if (_lat != null)
      Center(child: Text(tr('location_acquired'), style: const TextStyle(
          color: C.green, fontWeight: FontWeight.w700))),
    const SizedBox(height: 16),
    SizedBox(
      width: double.infinity, height: 50,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _useCurrentLocation,
        icon: const Icon(Icons.my_location, color: C.teal),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        label: Text(tr('use_current_location'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w700)),
      ),
    ),
    // ✅ [FIX Medium-5] deniedForever — ບໍ່ມີ dialog ຂໍສິດອີກ, ພາໄປ Settings ໂດຍກົງ
    if (_locationDeniedForever) ...[
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity, height: 46,
        child: OutlinedButton(
          onPressed: () => Geolocator.openAppSettings(),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: C.teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(tr('open_settings'), style: const TextStyle(
              color: C.teal, fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  ];

  Widget _fieldLabel(String text) => Text(text, style: const TextStyle(
    fontSize: 13, fontWeight: FontWeight.w700, color: C.text,
  ));
}

// ════════════════════════════════════════════════════════════
// UPLOAD TILE — ໃຊ້ຮ່ວມກັນລະຫວ່າງ ID document ແລະ ID selfie
// ════════════════════════════════════════════════════════════

class _UploadTile extends StatelessWidget {
  final File?         file;
  final String        placeholderLabel;
  final String        changeLabel;
  final IconData      icon;
  final VoidCallback  onTap;

  const _UploadTile({
    required this.file,
    required this.placeholderLabel,
    required this.changeLabel,
    required this.onTap,
    this.icon = Icons.upload_file_outlined,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: C.border),
        ),
        child: file == null
            ? Row(children: [
                Icon(icon, color: C.muted),
                const SizedBox(width: 10),
                Text(placeholderLabel, style: const TextStyle(color: C.muted, fontSize: 14)),
              ])
            // ✅ [FIX ME-AUTH-4] ຂະຫຍາຍ thumbnail ຈາກ 48x48 -> 96x96 ໃຫ້ກວດຄວາມ
            // ຄົມຊັດຂອງເອກະສານກ່ອນສົ່ງໄດ້ຈິງ (ຂອງເກົ່ານ້ອຍເກີນໄປ ບໍ່ພໍໃຫ້ກວດ)
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(file!, width: 96, height: 96, fit: BoxFit.cover,
                      cacheWidth: 192, cacheHeight: 192),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: C.green, size: 18),
                    const SizedBox(height: 4),
                    Text(changeLabel,
                        style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                )),
              ]),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════
// TEXT FIELD WIDGET
// ════════════════════════════════════════════════════════════

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;
  final IconData              icon;
  final TextInputType?        inputType;
  final bool                  obscure;
  final Widget?               suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final int?                  maxLength;
  final TextAlign              textAlign;
  final TextCapitalization     textCapitalization;
  final List<String>?          autofillHints;

  const _TextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.inputType,
    this.obscure   = false,
    this.suffixIcon,
    this.inputFormatters,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
  });

  // ✅ [Consolidated] ຫຸ້ມ AppTextField (lib/widgets/app_text_field.dart) ດ້ວຍ
  // style ຄົງທີ່ຂອງ flow ນີ້ — logic ຫຼັກ (border builder/decoration) ຢູ່ໃນ
  // widget ຮ່ວມນັ້ນດຽວແລ້ວ (ບໍ່ຊ້ຳກັບ customer_register_flow.dart's
  // _TextField ອີກຕໍ່ໄປ), ໜ້າຕາຄົງເກົ່າ 100%.
  @override
  Widget build(BuildContext context) => AppTextField(
    controller:      controller,
    hintText:        hint,
    prefixIcon:      icon,
    keyboardType:    inputType,
    obscureText:     obscure,
    suffixIcon:      suffixIcon,
    inputFormatters: inputFormatters,
    maxLength:       maxLength,
    textAlign:       textAlign,
    textCapitalization: textCapitalization,
    autofillHints:   autofillHints,
    style:      const TextStyle(fontSize: 15, color: C.text),
    hintStyle:  const TextStyle(color: C.muted),
    iconColor:  C.teal,
    iconSize:   20,
    fillColor:  Colors.white,
    borderRadius: 14,
    borderColor: C.border,
    focusedBorderColor: C.teal,
    focusedBorderWidth: 2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hideCounter: maxLength != null,
  );
}

// ════════════════════════════════════════════════════════════
// BUTTON SKELETON
// ════════════════════════════════════════════════════════════

class _ButtonSkeleton extends StatefulWidget {
  const _ButtonSkeleton();

  @override
  State<_ButtonSkeleton> createState() => _ButtonSkeletonState();
}

class _ButtonSkeletonState extends State<_ButtonSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize:      MainAxisSize.min,
      children: [
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            color:  Colors.white.withValues(alpha: _anim.value),
            shape:  BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 80, height: 14,
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: _anim.value * 0.7),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    ),
  );
}
