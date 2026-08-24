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
import 'theme/app_theme.dart' show AppTypography, AppRadius;
import 'widgets/app_button.dart';
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
        // ✅ [Phase 2 / Batch C] matches AppTypography.appBarTitle exactly.
        title: Text(tr('rewards_title'), style: AppTypography.appBarTitle),
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
            // ✅ [Phase 2 / Batch C] was a raw error string with no retry —
            // the sibling history section right below already used
            // ErrorStateView (🔒 AUDIT M-9 / 2026-07-27) but this one was
            // missed in that pass. Retry genuinely re-fetches via
            // ref.invalidate, same pattern as the history section.
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ErrorStateView(
                compact: true,
                onRetry: () => ref.invalidate(rewardSettingsProvider),
              ),
            ),
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
      // ✅ [Phase 2 / Batch C] dropped the explicit radius(16) override —
      // already the theme's dialogTheme default, applied automatically.
      builder: (_) => AlertDialog(
        title: Text(tr('reward_redeemed_title'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('reward_redeemed_body')),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: C.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(code, style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900,
                color: C.navy, letterSpacing: 1.5)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('close'))),
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
      // ✅ [Phase 2 / Batch C] navy is correct here — this is the hero/
      // header card background (brand-surface usage), not a CTA button, so
      // it's outside the primary-CTA-must-be-green rule.
      decoration: BoxDecoration(
        color: C.navy,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.monetization_on_rounded, color: C.yellow, size: 22),
          const SizedBox(width: 8),
          Text(tr('points_balance_label'), style: const TextStyle(
              color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.display exactly.
        Text(_formatPoints(points), style: AppTypography.display.copyWith(
            color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(tr('points_balance_sub'),
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
        // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.caption.
        Text(
          '${tr("redeem_rate_prefix")} ${settings.redeemRate.toStringAsFixed(0)} ${tr("kip_currency")} • '
          '${tr("redeem_min_label")} ${settings.minRedeemPoints} ${tr("points_unit")}',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 12),
        if (!canRedeem)
          // ✅ fontSize+weight match AppTypography.label exactly.
          Text(
              '${tr("redeem_min_required_prefix")} ${settings.minRedeemPoints} ${tr("points_unit")} '
              '${tr("redeem_min_required_suffix")}',
              style: AppTypography.label.copyWith(color: C.orange))
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in options)
              // ✅ [Phase 2 / Batch C] was C.navy — redeeming points is this
              // screen's primary action, so it renders LinTho green like
              // every other primary CTA (money-adjacent screen, see the
              // migration plan's flagged CTA-color/trust concern).
              AppButton.primary(
                fullWidth: false,
                loading: redeeming,
                label: '${tr("redeem_button_prefix")} $p ${tr("points_unit")}',
                onPressed: redeeming ? null : () => onRedeem(p),
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
    // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
    final label = switch (txn.type) {
      'earn'             => tr('reward_tx_earn'),
      'redeem'           => tr('reward_tx_redeem'),
      'manual_add'       => tr('reward_tx_manual_add'),
      'manual_subtract'  => tr('reward_tx_manual_subtract'),
      'expire'           => tr('reward_tx_expire'),
      _                  => txn.type,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(positive ? Icons.add_rounded : Icons.remove_rounded,
              color: positive ? C.green : C.red, size: 18),
        ),
        const SizedBox(width: 12),
        // ✅ fontSize+weight match AppTypography.label exactly (color
        // already the same as label's default ink).
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTypography.label.copyWith(color: C.text)),
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
  return '$buf ${tr("points_unit")}';
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
