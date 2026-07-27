// ============================================================
// phone_verification.dart — LinTho
// ▸ ເບີໂທ "ຢືນຢັນແລ້ວ" ຂອງບັນຊີ = FirebaseAuth.currentUser.phoneNumber —
//   ນີ້ຄືແຫຼ່ງຄວາມຈິງດຽວ (single source of truth). Firebase Auth ຕັ້ງຄ່ານີ້ໃຫ້
//   ອັດຕະໂນມັດສະເພາະຫຼັງຈາກຢືນຢັນ OTP ສຳເລັດ (signInWithCredential ຕອນ
//   ລົງທະບຽນ — customer_register_flow.dart — ຫຼື linkWithCredential/
//   updatePhoneNumber ຢູ່ PhoneVerificationScreen ນີ້) — client ບໍ່ສາມາດປອມ
//   ຄ່ານີ້ໄດ້ໂດຍກົງ, ຕ່າງຈາກ field 'phone' ໃນ Firestore users/{uid} ທີ່ເປັນ
//   ຂໍ້ມູນ contact ທົ່ວໄປ (ຜູ້ໃຊ້ແກ້ໄຂເອງໄດ້, ບໍ່ຜ່ານການຢືນຢັນ).
//
// ▸ ໃຊ້ໂດຍ: booking_form_screen.dart / quick_booking_screen.dart (gate ການ
//   ຈອງ + ສະແດງເບີແບບ read-only) ແລະ main.dart's ProfileScreen (ຈຸດເລີ່ມຕົ້ນ
//   ຢືນຢັນ/ປ່ຽນເບີ).
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'app_colors.dart';
import 'app_locale.dart';
import 'lao_phone.dart';
import 'widgets/app_text_field.dart';

// ✅ [DEV ONLY] placeholder phone ໃຊ້ແທນ verified phone ຕອນ debug build ເພື່ອ
// ໃຫ້ທົດສອບ booking flow ໄດ້ໂດຍບໍ່ຕ້ອງຜ່ານ OTP ຈິງ. `kDebugMode` ເປັນ false
// ໂດຍອັດຕະໂນມັດໃນ release/profile build (flutter build/run --release) — ດັ່ງນັ້ນ
// bypass ນີ້ຈະບໍ່ຫຼຸດຄວາມປອດໄພຂອງ production build ໃດໆ
const String _kDebugBypassPhone = '+8562000000000';

/// ✅ ເບີໂທຢືນຢັນແລ້ວຂອງບັນຊີປັດຈຸບັນ (E.164) — null ຖ້າຍັງບໍ່ໄດ້ຢືນຢັນ
/// (ຍົກເວັ້ນ debug build ຈະຄືນຄ່າ placeholder ໃຫ້ທົດສອບ flow ໄດ້ — ເບິ່ງ
/// `_kDebugBypassPhone` ຂ້າງເທິງ)
String? verifiedPhoneNumber() {
  final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
  if (phone != null && phone.isNotEmpty) return phone;
  if (kDebugMode) return _kDebugBypassPhone;
  return null;
}

// ════════════════════════════════════════════════════════════
// GATE — ຫຸ້ມ Booking Form / Quick Booking, ບໍ່ໃຫ້ຈອງໄດ້ຖ້າຍັງບໍ່ຢືນຢັນເບີໂທ
// ════════════════════════════════════════════════════════════

class PhoneRequiredGate extends StatelessWidget {
  final VoidCallback onGoToProfile;
  const PhoneRequiredGate({super.key, required this.onGoToProfile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: C.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_disabled_outlined,
                  color: C.orange, size: 34),
            ),
            const SizedBox(height: 20),
            Text(tr('phone_verification_required_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: C.text)),
            const SizedBox(height: 8),
            Text(tr('phone_verification_required_sub'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: C.muted)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: onGoToProfile,
                icon: const Icon(Icons.person_outline),
                label: Text(tr('go_to_profile_btn'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.primary, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// READ-ONLY PHONE DISPLAY — ໃຊ້ຢູ່ Booking Form / Quick Booking Step ຕິດຕໍ່
// ════════════════════════════════════════════════════════════

class VerifiedPhoneDisplay extends StatelessWidget {
  final String phone;
  final VoidCallback onEditTap;
  const VerifiedPhoneDisplay({
    super.key, required this.phone, required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.phone_iphone_rounded,
              color: C.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(phone, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
              const SizedBox(width: 6),
              const Icon(Icons.verified, size: 14, color: C.green),
            ]),
            const SizedBox(height: 2),
            Text(tr('phone_from_account_note'),
                style: const TextStyle(fontSize: 11.5, color: C.muted)),
          ],
        )),
        TextButton(
          onPressed: onEditTap,
          style: TextButton.styleFrom(foregroundColor: C.primary),
          child: Text(tr('edit'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PHONE VERIFICATION SCREEN — Phone → OTP → link/update ໃສ່ບັນຊີປັດຈຸບັນ
// ════════════════════════════════════════════════════════════

class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  int     _step = 0; // 0 = ເບີໂທ, 1 = OTP
  bool    _loading = false;
  String? _error;
  String? _verificationId;

  Timer? _resendTimer;
  int    _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    final existing = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (existing != null && existing.isNotEmpty) {
      _phoneCtrl.text = laoPhoneDigitsOnly(existing);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _normalizedPhone => laoPhoneDigitsOnly(_phoneCtrl.text);
  String get _e164Phone => toE164LaoPhone(_normalizedPhone);

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
          await _linkCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
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
          _startResendCooldown();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (!mounted) return;
          setState(() => _loading = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

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
      await _linkCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = e.code == 'invalid-verification-code'
            ? tr('otp_invalid')
            : _friendlyLinkError(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

  String _friendlyLinkError(String code) =>
      (code == 'credential-already-in-use' || code == 'provider-already-linked')
          ? tr('phone_already_used_error')
          : '${tr("error")} ($code)';

  // ✅ ຖ້າບັນຊີມີເບີໂທ verified ຢູ່ແລ້ວ (ຕ້ອງການປ່ຽນເບີ) ໃຊ້ updatePhoneNumber()
  // — linkWithCredential() throw 'provider-already-linked' ຖ້າມີ phone
  // provider ຢູ່ແລ້ວ
  Future<void> _linkCredential(PhoneAuthCredential credential) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('no-auth-user');

      if ((user.phoneNumber ?? '').isNotEmpty) {
        await user.updatePhoneNumber(credential);
      } else {
        await user.linkWithCredential(credential);
      }
      await user.reload();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'phone':           _normalizedPhone,
        'phoneVerifiedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('phone_verified_success')),
        backgroundColor: C.success,
      ));
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _friendlyLinkError(e.code); });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = tr('error'); });
    }
  }

  VoidCallback _primaryAction() => _step == 0 ? _sendOtp : _verifyOtp;
  String _primaryLabel() => _step == 0 ? tr('get_otp') : tr('verify_otp');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        title: Text(tr('verify_phone_title'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.text, size: 20),
          onPressed: _loading ? null : () {
            if (_step == 1) {
              _resendTimer?.cancel();
              setState(() {
                _step = 0; _error = null; _verificationId = null;
                _resendCooldown = 0; _otpCtrl.clear();
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_step == 0) ...[
            Text(tr('phone'), style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 8),
            AppTextField(
              controller: _phoneCtrl,
              hintText:   tr('phone_hint'),
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style:      const TextStyle(fontSize: 15, color: C.text),
              hintStyle:  const TextStyle(color: C.muted),
              iconColor:  C.primary,
              fillColor:  Colors.white,
              borderRadius: 14,
              borderColor: C.border,
              focusedBorderColor: C.primary,
              focusedBorderWidth: 2,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
          ] else ...[
            Text('${tr("otp_sent_to")} $_e164Phone',
                style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _otpCtrl,
              hintText:   '••••••',
              prefixIcon: Icons.lock_clock_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              hideCounter: true,
              textAlign: TextAlign.center,
              style:      const TextStyle(fontSize: 15, color: C.text),
              hintStyle:  const TextStyle(color: C.muted),
              iconColor:  C.primary,
              fillColor:  Colors.white,
              borderRadius: 14,
              borderColor: C.border,
              focusedBorderColor: C.primary,
              focusedBorderWidth: 2,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
          ],

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
                    color: C.red, fontSize: 13))),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(_primaryLabel(), style: const TextStyle(
                      color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ),

          if (_step == 1) ...[
            const SizedBox(height: 12),
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
        ]),
      ),
    );
  }
}
