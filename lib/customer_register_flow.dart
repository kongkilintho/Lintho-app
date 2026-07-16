// ============================================================
// customer_register_flow.dart — LinTho App
// ລົງທະບຽນ 'ລູກຄ້າ' — Multi-step:
//   Step 0: ເບີໂທລະສັບ
//   Step 1: ຢືນຢັນ OTP (Firebase Phone Auth)
//   Step 2: ຂໍ້ມູນສ່ວນຕົວ (ຊື່ + ລະຫັດຜ່ານ)
//   Step 3: ເຊວຟີຢືນຢັນຕົວຕົນ (ກ້ອງໜ້າ)
//   Step 4: ເປີດຕຳແໜ່ງ GPS
//   → ບັນທຶກ Firestore + ເຂົ້າສູ່ໜ້າຫຼັກ (RoleRouter)
// Rules:
//   ✅ withValues(alpha:) ແທນ withOpacity
//   ✅ InkWell + Material ແທນ GestureDetector
//   ✅ Skeleton loading ແທນ CircularProgressIndicator
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'brand_mark_tile.dart';
import 'cloudinary_service.dart';
import 'lao_phone.dart';

class CustomerRegisterFlow extends StatefulWidget {
  const CustomerRegisterFlow({super.key});

  @override
  State<CustomerRegisterFlow> createState() => _CustomerRegisterFlowState();
}

class _CustomerRegisterFlowState extends State<CustomerRegisterFlow> {
  final _phoneCtrl   = TextEditingController();
  final _otpCtrl      = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  int     _step = 0;
  bool    _loading = false;
  bool    _obscure = true;
  bool    _obscureConfirm = true;
  String? _error;

  String? _verificationId;
  File?   _selfieFile;
  double? _lat, _lng;

  // ✅ DEBUG-ONLY: true ຫຼັງກົດ 'Bypass OTP' — ຂ້າມ Firebase Auth call ທຸກອັນ
  // ໃນ step ຕໍ່ໄປ (ບໍ່ link credential, ບໍ່ສ້າງ user ແທ້) ເພື່ອທົດສອບ UI flow
  // ຕອນ Firebase Console ຍັງບລັອກການສະໝັກ (admin-restricted-operation)
  bool _debugBypass = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _normalizedPhone => laoPhoneDigitsOnly(_phoneCtrl.text);
  String get _e164Phone => toE164LaoPhone(_normalizedPhone);

  // ✅ firestore.rules ຫ້າມປ່ຽນ field 'role' ຕອນ update — ຖ້າເບີໂທນີ້ເຄີຍ
  // ລົງທະບຽນເປັນ 'provider' ມາກ່ອນ (Firebase Auth phone sign-in ຄືນ uid
  // ດຽວກັນສະເໝີສຳລັບເບີດຽວກັນ), users/{uid} doc ຈະມີຢູ່ແລ້ວ ແລະ ການ set
  // role:'customer' ຈະຖືກຕີເປັນ "update" ບໍ່ແມ່ນ "create" → permission-denied
  // ຢູ່ security rules. ກວດຄັດປະຕິເສດແຕ່ຫົວທີ (ຫຼັງ OTP ຢືນຢັນສຳເລັດ) ເພື່ອບໍ່ໃຫ້
  // user ເສຍເວລາຖ່າຍເຊວຟີ+ເປີດ GPS ຫຼາຍ step ແລ້ວມາລົ້ມເຫຼວຕອນຈົບ.
  Future<bool> _blockIfRoleConflict(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final existingRole = doc.data()?['role'] as String?;
      if (doc.exists && existingRole != null && existingRole != 'customer') {
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
          // ✅ ພິມ error ແທ້ຈິງອອກ console ໃຫ້ເຫັນຊັດ (ເຊັ່ນ Play Integrity/SHA-256
          // ບໍ່ໄດ້ setup ໃນໂໝດ dev) — ຊ່ວຍ debug ວ່າ error ມາຈາກໃສ
          debugPrint('[CustomerRegisterFlow] verifyPhoneNumber FAILED: '
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
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      // ✅ ພິມ error ແທ້ຈິງອອກ console — ບໍ່ໃຫ້ error ຫາຍໄປເສີຍໆ
      debugPrint('[CustomerRegisterFlow] verifyPhoneNumber EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = '${tr("error")}: $e'; });
    }
  }

  // ✅ DEBUG-ONLY: ຂ້າມການເອີ້ນໃຊ້ Firebase Auth 100% (ບໍ່ verifyPhoneNumber,
  // ບໍ່ signInAnonymously, ບໍ່ signInWithCredential — ບໍ່ແຕະ Firebase Auth
  // ເລີຍ) ເພື່ອທົດສອບ UI flow ຕອນ Firebase Console ບລັອກການສະໝັກ
  // (admin-restricted-operation). ໃຊ້ Navigator/setState ລ້າໆ ໄປ Step 2 ໂດຍ
  // ເອົາ mock phone number ທີ່ກອກໄວ້ໄປນຳ. ⚠️ kDebugMode ກວດສະເພາະ build dev.
  void _debugBypassOtp() {
    final mockPhone = _normalizedPhone.isEmpty ? '02091312566' : _normalizedPhone;
    debugPrint('[CustomerRegisterFlow] DEBUG BYPASS — skipping Firebase Auth '
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
      debugPrint('[CustomerRegisterFlow] verifyOtp FAILED: ${e.code} — ${e.message}');
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('otp_invalid'); });
    } catch (e) {
      debugPrint('[CustomerRegisterFlow] verifyOtp EXCEPTION: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = '${tr("error")}: $e'; });
    }
  }

  // ── Step 2: ຂໍ້ມູນສ່ວນຕົວ ──────────────────────────────

  Future<void> _submitPersonalInfo() async {
    final name    = _nameCtrl.text.trim();
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (name.isEmpty)    { setState(() => _error = tr('fill_all')); return; }
    if (pass.length < 6) { setState(() => _error = tr('pass_min')); return; }
    if (pass != confirm) { setState(() => _error = tr('password_mismatch')); return; }

    setState(() { _loading = true; _error = null; });

    // ✅ DEBUG BYPASS — ບໍ່ແຕະ Firebase Auth ເລີຍ, ໄປ step ຕໍ່ໄປທັນທີ
    if (_debugBypass) {
      debugPrint('[CustomerRegisterFlow] DEBUG BYPASS — skip linkWithCredential, '
          'name=$name');
      setState(() { _loading = false; _step = 3; });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('no-auth-user');

      // ✅ ຕັ້ງລະຫັດຜ່ານໂດຍ link email/password credential ກັບບັນຊີ phone-auth ນີ້
      // (ໃຊ້ email ສັງເຄາະຈາກເບີໂທ ດຽວກັນກັບ Login/TechnicianRegister flow)
      final syntheticEmail = '$_normalizedPhone@lintho.app';
      await user.linkWithCredential(
        EmailAuthProvider.credential(email: syntheticEmail, password: pass),
      );
      await user.updateDisplayName(name);

      if (!mounted) return;
      setState(() { _loading = false; _step = 3; });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = '${tr("error")} (${e.code})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '${tr("error")}: $e'; });
    }
  }

  // ── Step 3: Selfie ───────────────────────────────────────

  Future<void> _takeSelfie() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 75,
    );
    if (picked == null || !mounted) return;
    setState(() => _selfieFile = File(picked.path));
  }

  void _continueAfterSelfie() {
    if (_selfieFile == null) {
      setState(() => _error = tr('must_take_selfie'));
      return;
    }
    setState(() { _error = null; _step = 4; });
  }

  // ── Step 4: Location ─────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(tr('must_enable_location'));
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception(tr('must_enable_location'));
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  // ── Finalize: ບັນທຶກ Firestore + ເຂົ້າສູ່ໜ້າຫຼັກ ──────

  Future<void> _finish() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = tr('must_enable_location'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    // ✅ DEBUG BYPASS — ບໍ່ຂຽນ Firestore ແທ້ (ບໍ່ມີ auth.uid ໃຫ້ໃຊ້) ພຽງແຕ່
    // ສະແດງວ່າ flow ໄປຮອດຈົບ — print mock data ອອກ console ໃຫ້ກວດໄດ້
    if (_debugBypass) {
      debugPrint('[CustomerRegisterFlow] DEBUG BYPASS — flow completed (no real '
          'write). phone=$_normalizedPhone name=${_nameCtrl.text.trim()} '
          'lat=$_lat lng=$_lng selfie=${_selfieFile?.path}');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🧪 Debug bypass — flow ຈົບແລ້ວ (ບໍ່ໄດ້ບັນທຶກຂໍ້ມູນແທ້)'),
        backgroundColor: Colors.orange,
      ));
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid  = user?.uid;
      if (uid == null) throw Exception('no-auth-user');

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid':         uid,
        'displayName': _nameCtrl.text.trim(),
        'phone':       _normalizedPhone,
        'role':        'customer',
        'photoUrl':    '',
        'status':      'active',
        'lat':         _lat,
        'lng':         _lng,
        'createdAt':   FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (_selfieFile != null) {
        await CloudinaryService.instance.uploadCustomerPhoto(_selfieFile!);
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // ✅ ໄປໜ້າຫຼັກ — RoleRouter ຈະອ່ານ role/status ແລະ ພາໄປ MainShell
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
      if (!mounted) return;
      setState(() { _loading = false; _error = '${tr("error")}: $e'; });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  String get _stepTitle => switch (_step) {
    0 => tr('phone_step_title'),
    1 => tr('otp_step_title'),
    2 => tr('personal_info_step_title'),
    3 => tr('selfie_step_title'),
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
          onPressed: () {
            if (_step > 0 && _step != 1) {
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
          const SizedBox(height: 24),

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
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _loading ? null : _sendOtp,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(tr('resend_otp'), style: const TextStyle(
                        color: C.teal, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ],

          // ✅ DEBUG-ONLY — ປຸ່ມຂ້າມ OTP ສຳລັບທົດສອບ flow ຕອນ Play
          // Integrity/SHA-256 ຍັງບໍ່ໄດ້ setup. ບໍ່ສະແດງໃນ release build.
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
                child: const Text('🧪 Bypass OTP (Debug Only)', style: TextStyle(
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
    3 => _continueAfterSelfie,
    _ => _finish,
  };

  String _primaryLabel() => switch (_step) {
    0 => tr('get_otp'),
    1 => tr('verify_otp'),
    2 => tr('next'),
    3 => tr('next'),
    _ => tr('enter_app'),
  };

  List<Widget> _buildStepBody() => switch (_step) {
    0 => _buildPhoneStep(),
    1 => _buildOtpStep(),
    2 => _buildPersonalInfoStep(),
    3 => _buildSelfieStep(),
    _ => _buildLocationStep(),
  };

  List<Widget> _buildPhoneStep() => [
    _fieldLabel(tr('phone')),
    const SizedBox(height: 8),
    _TextField(
      controller: _phoneCtrl,
      hint:       tr('phone_hint'),
      icon:       Icons.phone_outlined,
      inputType:  TextInputType.phone,
    ),
  ];

  List<Widget> _buildOtpStep() => [
    Text('${tr("otp_sent_to")} $_e164Phone',
        style: const TextStyle(color: C.muted, fontSize: 13)),
    const SizedBox(height: 16),
    _TextField(
      controller: _otpCtrl,
      hint:       '••••••',
      icon:       Icons.lock_clock_outlined,
      inputType:  TextInputType.number,
    ),
  ];

  List<Widget> _buildPersonalInfoStep() => [
    _fieldLabel(tr('name')),
    const SizedBox(height: 8),
    _TextField(
      controller: _nameCtrl,
      hint:       'ສົມໃຈ ໄຊສົງຄາມ',
      icon:       Icons.person_outline,
      inputType:  TextInputType.name,
    ),
    const SizedBox(height: 16),

    _fieldLabel(tr('password')),
    const SizedBox(height: 8),
    _TextField(
      controller: _passCtrl,
      hint:       '••••••••',
      icon:       Icons.lock_outline,
      obscure:    _obscure,
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: C.muted),
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
      suffixIcon: IconButton(
        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: C.muted),
        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
      ),
    ),
  ];

  List<Widget> _buildSelfieStep() => [
    Text(tr('selfie_hint'), style: const TextStyle(color: C.muted, fontSize: 13)),
    const SizedBox(height: 16),
    Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: _takeSelfie,
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              color:  Colors.white,
              shape:  BoxShape.circle,
              border: Border.all(color: C.border, width: 2),
            ),
            child: _selfieFile == null
                ? const Icon(Icons.camera_alt_outlined, size: 48, color: C.muted)
                : ClipOval(child: Image.file(_selfieFile!, fit: BoxFit.cover)),
          ),
        ),
      ),
    ),
    const SizedBox(height: 16),
    Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _takeSelfie,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _selfieFile == null ? tr('take_selfie') : tr('retake_selfie'),
              style: const TextStyle(color: C.sky, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    ),
  ];

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
        icon: const Icon(Icons.my_location, color: C.navy),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        label: Text(tr('use_current_location'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w700)),
      ),
    ),
  ];

  Widget _fieldLabel(String text) => Text(text, style: const TextStyle(
    fontSize: 13, fontWeight: FontWeight.w700, color: C.text,
  ));
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

  const _TextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.inputType,
    this.obscure   = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller:      controller,
    keyboardType:    inputType,
    obscureText:     obscure,
    style: const TextStyle(fontSize: 15, color: C.text),
    decoration: InputDecoration(
      hintText:    hint,
      hintStyle:   const TextStyle(color: C.muted),
      prefixIcon:  Icon(icon, color: C.teal, size: 20),
      suffixIcon:  suffixIcon,
      filled:      true,
      fillColor:   Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.teal, width: 2)),
    ),
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
