// ============================================================
// earnings_tab.dart — LinTho Provider App
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'widgets/error_state_view.dart';

class ProviderEarningsTab extends ConsumerWidget {
  const ProviderEarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final txAsync     = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        title: Text(tr('earnings_wallet'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          TextButton.icon(
            onPressed: () => _showWithdrawalSheet(context, ref),
            icon:  const Icon(Icons.upload_outlined, color: C.navy, size: 18),
            label: Text(tr('withdraw'), style: const TextStyle(
                color: C.navy, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: C.blue,
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(transactionsProvider);
        },
        child: walletAsync.when(
          // ✅ CircularProgressIndicator → Skeleton
          loading: () => const _EarningsSkeleton(),
          // ✅ [FIX] ຍອດເງິນໂຫລດບໍ່ຂຶ້ນ ຕ້ອງແຈ້ງໃຫ້ຊ່າງຮູ້ຊັດເຈນ + ໃຫ້ລອງໃໝ່ໄດ້ —
          // ຫ້າມສະແດງເປັນ "$0"/ວ່າງເປົ່າ ເພາະນັ້ນຄື data ຈິງ ບໍ່ແມ່ນ error state
          error: (_, __) => ErrorStateView(
              onRetry: () => ref.invalidate(walletProvider)),
          data: (wallet) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _WalletCards(wallet: wallet,
                  onWithdraw: () => _showWithdrawalSheet(context, ref)),
              const SizedBox(height: 20),
              _WeeklyChart(txAsync: txAsync),
              const SizedBox(height: 20),
              _BankCard(wallet: wallet,
                  onTap: () => _showBankSheet(context, ref, wallet)),
              const SizedBox(height: 20),
              Text(tr('recent_transactions'), style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
              const SizedBox(height: 12),
              txAsync.when(
                // ✅ CircularProgressIndicator → Skeleton
                loading: () => const _TxListSkeleton(),
                // ✅ [FIX] ກ່ອນໜ້ານີ້ error ຖືກປອມເປັນ "ยัງບໍ່ມີລາຍການ" ເພື່ອບໍ່ໃຫ້
                // ຊ່າງຕົກໃຈ — ແຕ່ນັ້ນເຮັດໃຫ້ error ຈິງເບິ່ງຄືກັບບໍ່ມີລາຍຮັບເລີຍ, ເປັນ
                // ບັນຫາຄວາມໜ້າເຊື່ອຖືໃນໜ້າການເງິນ. ຕອນນີ້ແຍກ error ອອກຈາກ empty
                // ຊັດເຈນ, ໃຫ້ text ສະຫງົບ (ບໍ່ໃຊ້ຄຳວ່າ "ລົ້ມເຫລວ") ພ້ອມປຸ່ມລອງໃໝ່.
                error: (_, __) => ErrorStateView(
                    compact: true,
                    onRetry: () => ref.invalidate(transactionsProvider)),
                data: (txs) => txs.isEmpty
                    ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(tr('no_transactions'),
                      style: const TextStyle(color: C.muted)),
                ))
                    : Column(
                    children: txs.map((t) => _TxRow(tx: t)).toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWithdrawalSheet(BuildContext context, WidgetRef ref) {
    final ctrl   = TextEditingController();
    final wallet = ref.read(walletProvider).valueOrNull;
    // ✅ [FIX C4] flag ກັນກົດຊ້ຳ — ຄວບຄຸມທັງການບລັອກ tap ຊ້ຳ ແລະ ສະແດງ
    // loading spinner ຢູ່ປຸ່ມ. ຄວາມຖືກຕ້ອງແທ້ (ບໍ່ໃຫ້ຍອດເງິນຕິດລົບ) ບັງຄັບ
    // ຢູ່ຝັ່ງ server ແລ້ວ (onWithdrawalRequested ໃນ functions/index.js ຫັກ
    // balance ແບບ atomic ພາຍໃນ transaction) — flag ນີ້ຄື UX ຊັ້ນທຳອິດເທົ່ານັ້ນ.
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Handle(),
          const SizedBox(height: 16),
          Text(tr('withdraw'), style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 4),
          Text('${tr("balance")}: ${wallet?.formattedBalance ?? '₭0'}',
              style: const TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w800, color: C.text),
            decoration: InputDecoration(
              prefixText: '₭  ',
              hintText: '50,000',
              hintStyle: const TextStyle(color: C.muted),
              filled: true, fillColor: C.bg,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.sky, width: 2)),
            ),
          ),
          const SizedBox(height: 8),
          Text(tr('withdraw_note'),
              style: const TextStyle(fontSize: 11, color: C.muted)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            // ✅ [FIX C4] ປິດປຸ່ມຂະນະກຳລັງສົ່ງ — ກັນກົດຊ້ຳສ້າງຄຳຂໍຖອນເງິນຊ້ອນກັນ
            onPressed: submitting ? null : () async {
              final amt = double.tryParse(ctrl.text.replaceAll(',', ''));
              // ✅ [FIX C4] ກ່ອນໜ້ານີ້ກວດແຕ່ amt == null — ຈຳນວນ 0 ຫຼືຕິດລົບ
              // ຜ່ານໄດ້ (ບໍ່ມີ amt <= 0 guard)
              if (amt == null || amt <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ'),
                    backgroundColor: C.red));
                return;
              }
              setS(() => submitting = true);
              try {
                await ref.read(earningsRepoProvider).requestWithdrawal(amt);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('withdraw_sent')),
                      backgroundColor: C.green));
                }
              } catch (e) {
                if (ctx.mounted) {
                  setS(() => submitting = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e'),
                          backgroundColor: C.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: submitting
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(tr('confirm_withdraw'), style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: 16)),
          )),
        ]),
        ),
      ),
    );
  }

  void _showBankSheet(BuildContext context, WidgetRef ref, Wallet wallet) {
    final nameCtrl    = TextEditingController(text: wallet.bankName    ?? '');
    final accountCtrl = TextEditingController(text: wallet.bankAccount ?? '');
    final holderCtrl  = TextEditingController(text: wallet.bankHolder  ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Handle(),
          const SizedBox(height: 16),
          Text(tr('bank_info'), style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 20),
          _BankField(nameCtrl,    tr('bank_name'),      Icons.account_balance_outlined),
          const SizedBox(height: 12),
          _BankField(accountCtrl, tr('account_no'),     Icons.credit_card_outlined),
          const SizedBox(height: 12),
          _BankField(holderCtrl,  tr('account_holder'), Icons.person_outline),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              await ref.read(earningsRepoProvider).updateBankInfo(
                bankName:    nameCtrl.text.trim(),
                bankAccount: accountCtrl.text.trim(),
                bankHolder:  holderCtrl.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('bank_saved')),
                    backgroundColor: C.green));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(tr('save'), style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 16)),
          )),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// EARNINGS SKELETON (ແທນ CircularProgressIndicator)
// ════════════════════════════════════════════════════════════

class _EarningsSkeleton extends StatefulWidget {
  const _EarningsSkeleton();

  @override
  State<_EarningsSkeleton> createState() => _EarningsSkeletonState();
}

class _EarningsSkeletonState extends State<_EarningsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double r = 8, Color? color}) =>
      AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Opacity(
          opacity: _anim.value,
          child: Container(
            width: w, height: h,
            decoration: BoxDecoration(
              color: color ?? C.border,
              borderRadius: BorderRadius.circular(r),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Wallet cards skeleton
        Row(children: [
          Expanded(child: Container(height: 120,
              decoration: BoxDecoration(
                  color: C.navy.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18)))),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 120,
              decoration: BoxDecoration(
                  color: C.green.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18)))),
        ]),
        const SizedBox(height: 20),
        // Chart skeleton
        Container(
          height: 170, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _box(double.infinity,
                    [40, 70, 55, 90, 65, 100, 80][i].toDouble(), r: 6,
                    color: C.border),
              ),
            )),
          ),
        ),
        const SizedBox(height: 20),
        // Bank card skeleton
        Container(
          height: 72, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            _box(44, 44, r: 12),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
                  _box(100, 12),
                  const SizedBox(height: 6),
                  _box(70, 10),
                ]),
          ]),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// TX LIST SKELETON
// ════════════════════════════════════════════════════════════

class _TxListSkeleton extends StatefulWidget {
  const _TxListSkeleton();

  @override
  State<_TxListSkeleton> createState() => _TxListSkeletonState();
}

class _TxListSkeletonState extends State<_TxListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (_) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Opacity(
          opacity: _anim.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                      color: C.border, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 140, height: 12,
                    decoration: BoxDecoration(color: C.border,
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 6),
                Container(width: 80, height: 10,
                    decoration: BoxDecoration(color: C.border,
                        borderRadius: BorderRadius.circular(6))),
              ]),
              const Spacer(),
              Container(width: 60, height: 12,
                  decoration: BoxDecoration(color: C.border,
                      borderRadius: BorderRadius.circular(6))),
            ]),
          ),
        ),
      )),
    );
  }
}

// ── WALLET CARDS ─────────────────────────────────────────────

class _WalletCards extends StatelessWidget {
  final Wallet        wallet;
  final VoidCallback? onWithdraw;
  const _WalletCards({required this.wallet, this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Card(
        amount:      _spaced(wallet.formattedBalance),
        label:       tr('balance'),
        icon:        Icons.account_balance_wallet_outlined,
        color:       C.navy,
        onTap:       onWithdraw,
        actionLabel: '${tr("withdraw")} →',
      ),
      const SizedBox(width: 12),
      _Card(
        amount: _spaced(wallet.formattedTotal),
        label:  tr('total_earnings'),
        icon:   Icons.trending_up_outlined,
        color:  C.green,
      ),
    ]);
  }

  // '₭1,234' → '1,234 ₭' — ໄລຍະຫ່າງລະຫວ່າງຕົວເລກ ແລະ ສັນຍາລັກເງິນ
  static String _spaced(String formatted) =>
      formatted.startsWith('₭') ? '${formatted.substring(1)} ₭' : formatted;
}

class _Card extends StatelessWidget {
  final String        amount;
  final String        label;
  final IconData      icon;
  final Color         color;
  final VoidCallback? onTap;
  final String?       actionLabel;

  const _Card({
    required this.amount, required this.label,
    required this.icon,   required this.color,
    this.onTap, this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ GestureDetector → Material + InkWell
    return Expanded(child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
              // ✅ withOpacity → withValues
              color: color.withValues(alpha: 0.25),
              blurRadius: 12, offset: const Offset(0, 6),
            )],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ withOpacity → withValues
                Icon(icon,
                    color: Colors.white.withValues(alpha: 0.85), size: 20),
                const SizedBox(height: 8),
                Text(amount, style: const TextStyle(
                    color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(
                  // ✅ withOpacity → withValues
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11)),
                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      // ✅ withOpacity → withValues
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(actionLabel!, style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
        ),
      ),
    ));
  }
}

// ── WEEKLY CHART ─────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  final AsyncValue<List<ProviderTransaction>> txAsync;
  const _WeeklyChart({required this.txAsync});

  @override
  Widget build(BuildContext context) {
    final days = [
      tr('mon'), tr('tue'), tr('wed'),
      tr('thu'), tr('fri'), tr('sat'), tr('sun'),
    ];
    final amounts = txAsync.whenOrNull(data: (txs) {
      final now = DateTime.now();
      return List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        return txs
            .where((t) =>
        t.type.isCredit &&
            t.createdAt.day   == day.day &&
            t.createdAt.month == day.month &&
            t.createdAt.year  == day.year)
            .fold(0.0, (sum, t) => sum + t.amount);
      });
    }) ?? List.filled(7, 0.0);

    final maxVal  = amounts.fold(0.0, (a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1.0 : maxVal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          // ✅ withOpacity → withValues
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10, offset: const Offset(0, 4),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('weekly_earnings'), style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: C.text)),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final h       = (amounts[i] / safeMax * 100).clamp(4.0, 100.0);
                  final isToday = i == 6;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (amounts[i] > 0)
                          Text(_short(amounts[i]),
                              style: const TextStyle(
                                  fontSize: 8, color: C.muted)),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          height: h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isToday
                                  ? [C.navy, C.sky]
                              // ✅ withOpacity → withValues
                                  : [
                                C.blue.withValues(alpha: 0.5),
                                C.sky.withValues(alpha: 0.4),
                              ],
                              begin: Alignment.bottomCenter,
                              end:   Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(days[i], style: const TextStyle(
                            fontSize: 10, color: C.muted)),
                      ],
                    ),
                  ));
                }),
              ),
            ),
          ]),
    );
  }

  String _short(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ── BANK CARD ────────────────────────────────────────────────

class _BankCard extends StatelessWidget {
  final Wallet       wallet;
  final VoidCallback onTap;
  const _BankCard({required this.wallet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          // ✅ withOpacity → withValues
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            // ✅ withOpacity → withValues
              color: C.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.account_balance_outlined,
              color: C.navy, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: wallet.hasBankLinked
            ? Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(wallet.bankName!, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: C.text)),
              Text(wallet.bankAccount!,
                  style: const TextStyle(fontSize: 12, color: C.muted)),
              Text(wallet.bankHolder!,
                  style: const TextStyle(fontSize: 11, color: C.muted)),
            ])
            : Text(tr('no_bank_linked'),
            style: const TextStyle(fontSize: 13, color: C.muted))),
        // ✅ GestureDetector → Material + InkWell
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                // ✅ withOpacity → withValues
                color: C.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  wallet.hasBankLinked ? tr('edit') : tr('link'),
                  style: const TextStyle(
                      color: C.navy, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── TRANSACTION ROW ──────────────────────────────────────────

class _TxRow extends StatelessWidget {
  final ProviderTransaction tx;
  const _TxRow({required this.tx});

  static const _emojis = {
    TxType.earning:    '💰',
    TxType.withdrawal: '🏦',
    TxType.bonus:      '🎁',
    TxType.refund:     '↩️',
  };

  @override
  Widget build(BuildContext context) {
    final color = tx.type.isCredit ? C.green : C.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          // ✅ withOpacity → withValues
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: Row(children: [
        Text(_emojis[tx.type]!, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tx.description, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: C.text)),
            Text(tx.formattedDate,
                style: const TextStyle(fontSize: 11, color: C.muted)),
          ],
        )),
        Text(tx.formattedAmount, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

// ── HELPERS ──────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
        width: 40, height: 4,
        decoration: BoxDecoration(
            color: C.border,
            borderRadius: BorderRadius.circular(2))));
  }
}

class _BankField extends StatelessWidget {
  final TextEditingController ctrl;
  final String   label;
  final IconData icon;
  const _BankField(this.ctrl, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, color: C.text),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: C.muted, size: 18),
          filled: true, fillColor: C.bg,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: C.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: C.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: C.sky, width: 2)),
        ),
      ),
    ]);
  }
}