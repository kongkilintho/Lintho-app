// ============================================================
// rewards_screen.dart — LinTho Customer App
// ສະແດງແຕ້ມຄົງເຫຼືອ, ປະຫວັດ ແລະ ໃຫ້ແລກແຕ້ມເປັນຄູປອງສ່ວນຫຼຸດ
// (ກວດເງື່ອນໄຂຈາກ `settings/rewards` ກ່ອນອອກຄູປອງ).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'rewards_provider.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/error_state_view.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _redeeming = false;

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(rewardPointsProvider);
    final settingsAsync = ref.watch(rewardSettingsProvider);
    final historyAsync = ref.watch(rewardHistoryProvider);

    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(tr('rewards_title'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _BalanceCard(points: pointsAsync.value ?? 0),
          const SizedBox(height: 20),
          Text(tr('redeem_points_title'), style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
          const SizedBox(height: 8),
          settingsAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('ໂຫລດເງື່ອນໄຂບໍ່ໄດ້: $e',
                style: const TextStyle(color: C.red, fontSize: 12)),
            data: (settings) => _RedeemCard(
              balance: pointsAsync.value ?? 0,
              settings: settings,
              redeeming: _redeeming,
              onRedeem: (points) => _redeem(points),
            ),
          ),
          const SizedBox(height: 24),
          Text(tr('points_history_title'), style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
          const SizedBox(height: 8),
          historyAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator())),
            // 🔒 [AUDIT M-9 / 2026-07-27] ກ່ອນໜ້ານີ້ສະແດງ error text ດິບ ໂດຍ
            // ບໍ່ມີປຸ່ມ retry ໃດເລີຍ — ໃຊ້ ErrorStateView ມາດຕະຖານດຽວກັນກັບ
            // ໜ້າຈໍອື່ນ (coupon_list_screen.dart ເປັນຕົ້ນ).
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ErrorStateView(
                compact: true,
                message: tr('points_history_load_failed'),
                onRetry: () => ref.invalidate(rewardHistoryProvider),
              ),
            ),
            data: (history) {
              if (history.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: EmptyStateView(
                    icon: Icons.history_rounded,
                    title: tr('no_points_history'),
                    accent: C.muted,
                  ),
                );
              }
              // 🔒 [AUDIT PERF-3 / 2026-08-02 — Medium, fresh re-audit] ກ່ອນໜ້ານີ້
              // Column+for ສ້າງທຸກແຖວທັນທີ ບໍ່ວ່າຈະເຫັນຢູ່ໜ້າຈໍຫຼືບໍ່ — ListView.builder
              // (shrinkWrap ເພາະຢູ່ໃນ SingleChildScrollView ຂ້າງນອກຢູ່ແລ້ວ, ບໍ່ໃຫ້
              // scroll ຊ້ອນກັນ) ສ້າງສະເພາະແຖວທີ່ເບິ່ງເຫັນ.
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: history.length,
                itemBuilder: (_, i) => _HistoryRow(txn: history[i]),
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _redeem(int points) async {
    setState(() => _redeeming = true);
    final result = await redeemPointsForCoupon(points);
    setState(() => _redeeming = false);
    if (!mounted) return;

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error!),
        backgroundColor: C.red,
      ));
      return;
    }

    final code = result.couponCode!;
    Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ແລກສຳເລັດ!', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ນຳໂຄ້ດນີ້ໄປໃຊ້ໃນການຈອງຄັ້ງຕໍ່ໄປ (ສຳເນົາແລ້ວ):'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: C.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(code, style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900,
                color: C.navy, letterSpacing: 1.5)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ປິດ')),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int points;
  const _BalanceCard({required this.points});

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
        const Row(children: [
          Icon(Icons.monetization_on_rounded, color: C.yellow, size: 22),
          SizedBox(width: 8),
          Text('ແຕ້ມຄົງເຫຼືອ', style: TextStyle(
              color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(_formatPoints(points), style: const TextStyle(
            color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        const Text('ສະສົມແຕ້ມຈາກທຸກການຈອງ ເພື່ອແລກສ່ວນຫຼຸດ',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    );
  }
}

class _RedeemCard extends StatelessWidget {
  final int balance;
  final RewardSettings settings;
  final bool redeeming;
  final void Function(int points) onRedeem;

  const _RedeemCard({
    required this.balance,
    required this.settings,
    required this.redeeming,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final canRedeem = balance >= settings.minRedeemPoints;
    final options = <int>{
      settings.minRedeemPoints,
      settings.minRedeemPoints * 2,
      balance,
    }.where((p) => p >= settings.minRedeemPoints && p <= balance).toList()..sort();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '1 ແຕ້ມ = ${settings.redeemRate.toStringAsFixed(0)} ກີບ • ແລກຂັ້ນຕ່ຳ ${settings.minRedeemPoints} ແຕ້ມ',
          style: const TextStyle(fontSize: 12, color: C.muted),
        ),
        const SizedBox(height: 12),
        if (!canRedeem)
          Text('ສະສົມໃຫ້ຄົບ ${settings.minRedeemPoints} ແຕ້ມ ເພື່ອແລກຄູປອງ',
              style: const TextStyle(fontSize: 13, color: C.orange, fontWeight: FontWeight.w600))
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in options)
              ElevatedButton(
                onPressed: redeeming ? null : () => onRedeem(p),
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.navy, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: redeeming
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('ແລກ $p ແຕ້ມ'),
              ),
          ]),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final RewardTransaction txn;
  const _HistoryRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final positive = txn.points >= 0;
    final label = switch (txn.type) {
      'earn'             => 'ໄດ້ຮັບແຕ້ມຈາກການຈອງ',
      'redeem'           => 'ແລກແຕ້ມເປັນຄູປອງ',
      'manual_add'       => 'ແອັດມິນເພີ່ມແຕ້ມໃຫ້',
      'manual_subtract'  => 'ແອັດມິນຫັກແຕ້ມ',
      'expire'           => 'ແຕ້ມໝົດອາຍຸ',
      _                  => txn.type,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (positive ? C.green : C.red).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(positive ? Icons.add_rounded : Icons.remove_rounded,
              color: positive ? C.green : C.red, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text)),
          if (txn.createdAt != null)
            Text(_formatDate(txn.createdAt!), style: const TextStyle(fontSize: 11, color: C.muted)),
        ])),
        Text('${positive ? '+' : ''}${txn.points}', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: positive ? C.green : C.red)),
      ]),
    );
  }
}

String _formatPoints(int points) {
  final s = points.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '$buf ແຕ້ມ';
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
