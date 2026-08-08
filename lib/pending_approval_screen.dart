// ============================================================
// pending_approval_screen.dart — LinTho App
// ສະແດງເມື່ອບັນຊີຊ່າງລົງທະບຽນແລ້ວ ແຕ່ providers/{uid}.kycStatus ຍັງບໍ່ 'verified'
// (ລໍຖ້າທີມງານກວດສອບເອກະສານ, ຫຼືຖືກປະຕິເສດ)
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'profile_tab.dart' show KycScreen;

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // 🔒 [AUDIT PROV-NEW-1 / 2026-08-06] ກ່ອນໜ້ານີ້ໜ້ານີ້ບໍ່ໄດ້ stream
    // kycStatus ຂອງຕົນເອງເລີຍ — ສະແດງຂໍ້ຄວາມ "ກຳລັງກວດສອບເອກະສານ, 24 ຊົ່ວໂມງ"
    // ຄືກັນທຸກກໍລະນີ, ບໍ່ວ່າຈິງໆແລ້ວ status ຈະເປັນ 'pending' ຫຼື 'rejected'.
    // ຊ່າງທີ່ຖືກປະຕິເສດຈຶ່ງບໍ່ມີທາງຮູ້ວ່າຕົນຖືກປະຕິເສດ ຫຼືເຫດຜົນຫຍັງ, ແລະ ບໍ່ມີ
    // ທາງອັບໂຫລດເອກະສານໃໝ່ໄດ້ເລີຍພາຍໃນແອັບ (KycScreen resubmit form ມີຢູ່ແລ້ວ
    // ໃນ profile_tab.dart ແຕ່ຢູ່ຫຼັງ ProviderDashboard — RoleRouter ບໍ່ໃຫ້ບັນຊີ
    // ທີ່ບໍ່ 'verified' ເຂົ້າໄປໄດ້ເລີຍ) — ບັນຊີຄ້າງຢູ່ໜ້ານີ້ຕະຫຼອດໄປ ນອກຈາກຕິດຕໍ່
    // support ນອກແອັບ. ຕອນນີ້ stream providers/{uid} ໂດຍກົງ ແລະ ແຍກ UI ຕາມ
    // kycStatus ຈິງ: 'rejected' → ສະແດງເຫດຜົນ (rejectReason, ຂຽນໂດຍ
    // lintho-admin useRejectProviderKyc) + ປຸ່ມສົ່ງເອກະສານໃໝ່ (ໄປ KycScreen
    // ໂດຍກົງ, ບໍ່ຕ້ອງຜ່ານ ProviderDashboard — KycScreen ຮັບ profile:null ໄດ້
    // ຢູ່ແລ້ວ, ໃຊ້ພຽງແຕ່ເພື່ອກວດວ່າ verified ແລ້ວບໍ ເຊິ່ງບໍ່ແມ່ນກໍລະນີນີ້); ອື່ນໆ
    // (pending/none) → ຄົງຂໍ້ຄວາມເດີມ.
    if (uid == null) return const _PendingApprovalBody();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('providers').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final kycStatus = data?['kycStatus'] as String?;
        final rejectReason = data?['rejectReason'] as String?;
        if (kycStatus == 'rejected') {
          return _PendingApprovalBody(
            rejected: true,
            rejectReason: rejectReason,
          );
        }
        return const _PendingApprovalBody();
      },
    );
  }
}

class _PendingApprovalBody extends StatelessWidget {
  final bool    rejected;
  final String? rejectReason;
  const _PendingApprovalBody({this.rejected = false, this.rejectReason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                rejected ? Icons.error_outline_rounded : Icons.hourglass_top_rounded,
                size: 64,
                color: rejected ? C.red : C.navy,
              ),
              const SizedBox(height: 24),
              Text(
                  rejected ? tr('kyc_rejected_title') : tr('pending_approval_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900,
                      color: rejected ? C.red : C.navy)),
              const SizedBox(height: 12),
              Text(
                  rejected
                      ? (rejectReason != null && rejectReason!.isNotEmpty
                          ? '${tr('kyc_rejected_msg')}\n\n${tr('kyc_rejected_reason_label')}: $rejectReason'
                          : tr('kyc_rejected_msg'))
                      : tr('pending_approval_msg'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: C.muted, height: 1.5)),
              const SizedBox(height: 32),
              if (rejected) ...[
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KycScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.navy, elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr('kyc_resubmit_btn'), style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity, height: 50,
                child: OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(tr('logout'), style: const TextStyle(
                      color: C.text, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
