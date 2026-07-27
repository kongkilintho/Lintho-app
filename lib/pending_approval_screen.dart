// ============================================================
// pending_approval_screen.dart — LinTho App
// ສະແດງເມື່ອບັນຊີຊ່າງລົງທະບຽນແລ້ວ ແຕ່ status ຍັງ 'pending'
// (ລໍຖ້າທີມງານກວດສອບເອກະສານ kycStatus/status)
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_colors.dart';
import 'app_locale.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

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
              const Icon(Icons.hourglass_top_rounded, size: 64, color: C.navy),
              const SizedBox(height: 24),
              Text(tr('pending_approval_title'), textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: C.navy)),
              const SizedBox(height: 12),
              Text(tr('pending_approval_msg'), textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: C.muted, height: 1.5)),
              const SizedBox(height: 32),
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
