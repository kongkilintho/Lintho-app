// ============================================================
// register_otp.dart — LinTho App
// Register — ໜ້າທຳອິດ: ເລືອກປະເພດບັນຊີ
//   'ລູກຄ້າ' → CustomerRegisterFlow (Phone → OTP → ຂໍ້ມູນ → Selfie → Location)
//   'ຊ່າງ'   → TechnicianRegisterScreen (ຂໍ້ມູນພື້ນຖານ + ຂໍ້ມູນເພີ່ມເຕີມ)
// Rules:
//   ✅ InkWell + Material ແທນ GestureDetector
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'brand_mark_tile.dart';
import 'customer_register_flow.dart';
import 'technician_register_screen.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header ──
          Row(children: [
            const BrandMarkTile(size: 44, radius: 14),
            const SizedBox(width: 12),
            const Text('LinTho', style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w900, color: C.primary,
            )),
          ]),
          const SizedBox(height: 32),

          Text(tr('register_submit'), style: const TextStyle(
            fontSize: 28, fontWeight: FontWeight.w900, color: C.primary,
          )),
          const SizedBox(height: 6),
          Text(tr('welcome_register'),
              style: const TextStyle(color: C.muted, fontSize: 14)),
          const SizedBox(height: 32),

          _fieldLabel(tr('account_type')),
          const SizedBox(height: 12),

          _AccountTypeCard(
            emoji: '🙋', title: tr('customer'),
            subtitle: tr('order_service'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const CustomerRegisterFlow())),
          ),
          const SizedBox(height: 14),
          _AccountTypeCard(
            emoji: '🔧', title: tr('provider'),
            subtitle: tr('receive_job'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const TechnicianRegisterScreen())),
          ),

          const SizedBox(height: 32),

          // ── Login link ──
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${tr("have_account")} ',
                style: const TextStyle(color: C.muted)),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => Navigator.pop(context),
                child: Text(tr('login'), style: const TextStyle(
                  color: C.teal, fontWeight: FontWeight.w800,
                )),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text, style: const TextStyle(
    fontSize: 13, fontWeight: FontWeight.w700, color: C.text,
  ));
}

// ════════════════════════════════════════════════════════════
// ACCOUNT TYPE CARD (big, tappable, navigates immediately)
// ════════════════════════════════════════════════════════════

class _AccountTypeCard extends StatelessWidget {
  final String       emoji, title, subtitle;
  final VoidCallback onTap;
  const _AccountTypeCard({
    required this.emoji, required this.title, required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(18),
          border:       Border.all(color: C.border),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: C.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(
                  fontSize: 13, color: C.muted)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: C.muted),
        ]),
      ),
    ),
  );
}
