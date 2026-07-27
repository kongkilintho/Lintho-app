import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'quick_booking_provider.dart' show formatKip;
import 'referral_provider.dart';
import 'widgets/error_state_view.dart';

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _codeCtrl = TextEditingController();
  bool _redeeming = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(referralInfoProvider);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(tr('referral_title'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 🔒 [AUDIT M-9 / 2026-07-27] ກ່ອນໜ້ານີ້ສະແດງ error text ດິບ ໂດຍບໍ່ມີ
        // ປຸ່ມ retry ໃດເລີຍ — ໃຊ້ ErrorStateView ມາດຕະຖານດຽວກັນກັບໜ້າຈໍອື່ນ.
        error: (e, _) => ErrorStateView(
          onRetry: () => ref.invalidate(referralInfoProvider),
        ),
        data: (info) {
          if (info == null) return Center(child: Text(tr('fill_all')));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _CodeCard(code: info.code),
              const SizedBox(height: 16),
              Row(children: [
                _Stat('${info.referredCount}', tr('referral_succeeded_count')),
                _Stat(formatKip(info.totalEarnedFromReferrals), tr('referral_total_earned')),
              ]),
              const SizedBox(height: 24),
              Text(tr('enter_friend_code'), style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'e.g. LINTHO123',
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: C.border)),
                  ),
                )),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _redeeming ? null : _redeem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.navy, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _redeeming
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('ໃຊ້ໂຄ້ດ'),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _redeem() async {
    setState(() => _redeeming = true);
    final error = await redeemReferralCode(_codeCtrl.text);
    setState(() => _redeeming = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'ໃຊ້ໂຄ້ດສຳເລັດ! ສ່ວນຫຼຸດຈະໄດ້ຮັບໃນການຈອງຄັ້ງຕໍ່ໄປ'),
      backgroundColor: error != null ? C.red : C.green,
    ));
    if (error == null) _codeCtrl.clear();
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('your_referral_code'), style: const TextStyle(
            color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(code, style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900,
              letterSpacing: 1.5))),
          // ✅ [FIX — accessibility] IconButton ນີ້ບໍ່ມີ tooltip/Semantics ມາກ່ອນ
          IconButton(
            tooltip: 'ສຳເນົາໂຄ້ດ',
            icon: const Icon(Icons.copy, color: Colors.white70, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ສຳເນົາແລ້ວ')));
            },
          ),
        ]),
        const SizedBox(height: 16),
        // ✅ [FIX — qr_flutter was in pubspec.yaml, unused] ໃຫ້ໝູ່ scan ໂຄ້ດ
        // ໄດ້ໄວກວ່າພິມເອງ — ເຂົ້າລະຫັດ referral link ດຽວກັນກັບປຸ່ມແຊ.
        Center(child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: 'https://lintho.app/r/$code',
            version: QrVersions.auto,
            size: 132,
            gapless: true,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: C.navy),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: C.navy),
          ),
        )),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Share.share(
                'ໃຊ້ໂຄ້ດ $code ຮັບສ່ວນຫຼຸດ ${formatKip(20000)} ທີ່ LinTho! https://lintho.app/r/$code'),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('ແຊໂຄ້ດໃຫ້ໝູ່'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: C.navy,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Text(value, style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.navy)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: C.muted)),
        ]),
      ),
    );
  }
}
