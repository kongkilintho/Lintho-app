// ============================================================
// earnings_tab.dart — LinTho Provider App
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'payment_config_provider.dart';
import 'widgets/error_state_view.dart';

// ✅ [UI Polish] ຍອດຕ່ຳກວ່ານີ້ຈະສະແດງ banner ເຕືອນໃຫ້ຕື່ມເງິນ
const double kLowBalanceThreshold = 20000;

class ProviderEarningsTab extends ConsumerWidget {
  const ProviderEarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final txAsync     = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: C.background,
      // ✅ [UI Polish] ປຸ່ມ "ຖອນ" ຢູ່ header ຖືກເອົາອອກ — ຊ້ຳກັບປຸ່ມ "ຖອນ →"
      // ຢູ່ໃນ Card ຍອດຄົງເຫຼືອຂ້າງລຸ່ມແລ້ວ (ສອງທາງໄປບ່ອນດຽວກັນ, ບໍ່ຈຳເປັນ)
      appBar: AppBar(
        elevation: 0, centerTitle: true,
        title: Text(tr('earnings_wallet'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: RefreshIndicator(
        // ✅ [Brand color audit 2026-07-27] C.blue → C.primary
        color: C.primary,
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
                  onWithdraw: () => _showWithdrawalSheet(context, ref),
                  onTopUp: () => _showTopUpSheet(context, ref)),
              // ✅ [UI Polish] Low balance alert — ເຕືອນຊ່າງໃຫ້ຕື່ມເງິນ ຖ້າຍອດ
              // ຄົງເຫຼືອຕ່ຳກວ່າ kLowBalanceThreshold, ແຕະໄດ້ເພື່ອຕື່ມທັນທີ
              if (wallet.balance < kLowBalanceThreshold) ...[
                const SizedBox(height: 12),
                _LowBalanceBanner(onTopUp: () => _showTopUpSheet(context, ref)),
              ],
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
                      backgroundColor: C.success));
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
    ).whenComplete(ctrl.dispose); // 🔒 [AUDIT L-6 / 2026-07-27] dispose the
    //                                controller once the sheet is fully closed
  }

  // ✅ [Top-up] ຄຳຂໍຕື່ມເງິນ — ສະແດງຂໍ້ມູນໂອນທະນາຄານ + QR (ເປັນ QR ຂໍ້ຄວາມ
  // ຂໍ້ມູນບັນຊີ, ບໍ່ແມ່ນ payment QR ມາດຕະຖານ BCEL — ໃຊ້ສະແກນ/ແຕະຄັດລອກເລກບັນຊີ
  // ໄວໆເທົ່ານັ້ນ) ພ້ອມ reference code ໃຫ້ໃສ່ຕອນໂອນ ເພື່ອໃຫ້ admin ກົງກັບຄຳຂໍນີ້
  // ໄດ້ງ່າຍຕອນກວດ. ກົດ "ຢືນຢັນວ່າໂອນເງິນແລ້ວ" ພຽງແຕ່ສ້າງຄຳຂໍ status:'pending' —
  // ບໍ່ໄດ້ເພີ່ມຍອດ wallet ທັນທີ (ຕ້ອງລໍ admin ກວດການໂອນຈິງກ່ອນ, ຄືກັນກັບ
  // ຂະບວນການຖອນເງິນຂ້າງເທິງ).
  Future<File?> _pickSlipImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
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
    if (source == null) return null;
    final picked = await ImagePicker().pickImage(
      source: source, imageQuality: 75, maxWidth: 1600, maxHeight: 1600,
    );
    return picked == null ? null : File(picked.path);
  }

  void _showTopUpSheet(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    final uid  = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref6 = uid.length >= 6
        ? uid.substring(uid.length - 6).toUpperCase()
        : uid.toUpperCase();
    // ✅ [Dynamic payment config] admin ຕັ້ງຄ່າຜ່ານ lintho-admin (Settings >
    // Payment) — ຖ້າຍັງບໍ່ທັນຕັ້ງ (qrImageUrl null), fallback ໄປໃຊ້ QR ສ້າງເອງ
    // ຈາກຂໍ້ຄວາມຄືເກົ່າ ແທນທີ່ຈະສະແດງຮູບຫວ່າງ.
    final cfg = ref.read(paymentConfigProvider).valueOrNull ?? PaymentConfig.fallback;
    bool submitting = false;
    File? slipFile;

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
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _Handle(),
              const SizedBox(height: 16),
              Text(tr('top_up_title'), style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: C.text)),
              const SizedBox(height: 20),
              Text(tr('top_up_amount_label'), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w800, color: C.text),
                decoration: InputDecoration(
                  prefixText: '₭  ',
                  hintText: '100,000',
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
              Text(tr('top_up_note'),
                  style: const TextStyle(fontSize: 11, color: C.muted)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: C.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.border),
                ),
                child: Column(children: [
                  Text(tr('top_up_bank_details'), style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: C.text)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: cfg.qrImageUrl != null
                        ? Image.network(
                            cfg.qrImageUrl!,
                            width: 140, height: 140, fit: BoxFit.contain,
                            cacheWidth: 280, cacheHeight: 280, // 🔒 [AUDIT PERF-5 / 2026-08-02]
                            errorBuilder: (_, __, ___) => QrImageView(
                              data: '${cfg.bankName}|${cfg.accountNumber}|REF:$ref6',
                              version: QrVersions.auto,
                              size: 140,
                              backgroundColor: Colors.white,
                            ),
                          )
                        : QrImageView(
                            data: '${cfg.bankName}|${cfg.accountNumber}|REF:$ref6',
                            version: QrVersions.auto,
                            size: 140,
                            backgroundColor: Colors.white,
                          ),
                  ),
                  const SizedBox(height: 12),
                  _TopUpDetailRow(label: tr('bank_name'), value: cfg.bankName),
                  _TopUpDetailRow(label: tr('account_holder'), value: cfg.accountName),
                  _TopUpDetailRow(label: tr('account_no'), value: cfg.accountNumber),
                  const SizedBox(height: 8),
                  _TopUpDetailRow(
                    label: tr('top_up_reference'),
                    value: ref6,
                    highlight: true,
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              Text(tr('top_up_slip_label'), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: submitting ? null : () async {
                  final file = await _pickSlipImage(ctx);
                  if (file != null) setS(() => slipFile = file);
                },
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: C.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: slipFile == null ? C.border : C.primary,
                        width: slipFile == null ? 1 : 1.6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: slipFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload_file_outlined,
                                color: C.muted, size: 28),
                            const SizedBox(height: 8),
                            Text(tr('top_up_slip_hint'), style: const TextStyle(
                                fontSize: 12, color: C.muted)),
                          ],
                        )
                      : Stack(fit: StackFit.expand, children: [
                          Image.file(slipFile!, fit: BoxFit.cover),
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              color: Colors.black.withValues(alpha: 0.55),
                              child: Text(tr('top_up_slip_change'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ),
                          ),
                        ]),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: submitting ? null : () async {
                  final amt = double.tryParse(ctrl.text.replaceAll(',', ''));
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ'),
                        backgroundColor: C.red));
                    return;
                  }
                  if (slipFile == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(tr('top_up_slip_required')),
                        backgroundColor: C.red));
                    return;
                  }
                  setS(() => submitting = true);
                  try {
                    final slipUrl = await ref.read(earningsRepoProvider)
                        .uploadTopupSlip(slipFile!);
                    await ref.read(earningsRepoProvider)
                        .requestTopup(amt, slipUrl: slipUrl);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('top_up_sent')),
                          backgroundColor: C.success));
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
                    backgroundColor: C.primary, elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: submitting
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white)),
                        const SizedBox(width: 10),
                        Text(tr('top_up_slip_uploading'), style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                      ])
                    : Text(tr('confirm_top_up'), style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800,
                        fontSize: 16)),
              )),
            ]),
          ),
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  // 🔒 [AUDIT M-5 / 2026-07-27] ກ່ອນໜ້ານີ້ບໍ່ມີ `submitting` guard ຄືກັນກັບ
  // _showWithdrawalSheet() ຂ້າງເທິງ — double-tap ໄວໆ ຈະຍິງ updateBankInfo()
  // 2 ຄັ້ງພ້ອມກັນ, ຄັ້ງທຳອິດທີ່ resolve ຈະ Navigator.pop() ປິດ sheet, ຄັ້ງທີສອງ
  // ທີ່ resolve ຫຼັງຈາກນັ້ນຈະ Navigator.pop() ອີກຄັ້ງ — ປັອບ route ອື່ນທີ່ບໍ່ໄດ້
  // ຕັ້ງໃຈ (ອອກຈາກ Earnings tab). ຕອນນີ້ໃຊ້ pattern ດຽວກັນກັບ withdrawal sheet.
  // ✅ [AUDIT L-6] ຄວບຄູ່ກັນ — TextEditingController ທັງ 3 ຕົວບໍ່ເຄີຍ dispose()
  // ມາກ່ອນ; ຕອນນີ້ dispose ຫຼັງ sheet ປິດ (ບໍ່ວ່າຈະ save ສຳເລັດ, error, ຫຼື
  // ຜູ້ໃຊ້ປັດປິດເອງ).
  void _showBankSheet(BuildContext context, WidgetRef ref, Wallet wallet) {
    final nameCtrl    = TextEditingController(text: wallet.bankName    ?? '');
    final accountCtrl = TextEditingController(text: wallet.bankAccount ?? '');
    final holderCtrl  = TextEditingController(text: wallet.bankHolder  ?? '');
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
            onPressed: submitting ? null : () async {
              setS(() => submitting = true);
              try {
                await ref.read(earningsRepoProvider).updateBankInfo(
                  bankName:    nameCtrl.text.trim(),
                  bankAccount: accountCtrl.text.trim(),
                  bankHolder:  holderCtrl.text.trim(),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('bank_saved')),
                      backgroundColor: C.success));
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
                : Text(tr('save'), style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: 16)),
          )),
        ]),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      accountCtrl.dispose();
      holderCtrl.dispose();
    });
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
  final VoidCallback? onTopUp;
  const _WalletCards({required this.wallet, this.onWithdraw, this.onTopUp});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Card(
        amount: _spaced(wallet.formattedBalance),
        label:  tr('balance'),
        icon:   Icons.account_balance_wallet_outlined,
        color:  C.navy,
        actions: [
          // ✅ [UI Polish] "ຕື່ມເງິນ" ໃຊ້ soft accent (gold) ໃຫ້ເດັ່ນກວ່າ "ຖອນ"
          // (ຍັງເປັນ pill ໂປ່ງໃສແບບເກົ່າ) — ຕື່ມເງິນຄືການກະທຳທີ່ຢາກໃຫ້ຊ່າງເຫັນ
          // ກ່ອນ, ໂດຍສະເພາະຕອນຍອດເງິນຕ່ຳ
          _CardAction('+ ${tr("top_up")}', onTopUp, accent: C.gold),
          _CardAction('${tr("withdraw")} →', onWithdraw),
        ],
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

class _CardAction {
  final String        label;
  final VoidCallback? onTap;
  final Color?         accent;
  const _CardAction(this.label, this.onTap, {this.accent});
}

class _Card extends StatelessWidget {
  final String            amount;
  final String            label;
  final IconData           icon;
  final Color              color;
  final List<_CardAction>  actions;

  const _Card({
    required this.amount, required this.label,
    required this.icon,   required this.color,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    // ✅ [UI Polish] Card ທີ່ມີ action pill (ຍອດຄົງເຫຼືອ) ໄດ້ padding ລຸ່ມ
    // ຫຼາຍກວ່າເລັກນ້ອຍ — ບໍ່ໃຫ້ pill ຮູ້ສຶກຕິດຂອບລຸ່ມເກີນໄປ
    return Expanded(child: Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, actions.isNotEmpty ? 18 : 16),
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
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: actions.map((a) =>
                  // ✅ GestureDetector → Material + InkWell (ແຍກແຕ່ລະ pill ໃຫ້
                  // ກົດໄດ້ເອກະລາດຈາກກັນ — card ນີ້ອາດມີ 2 ຄຳສັ່ງ, ບໍ່ໃຫ້ pill
                  // ດຽວກັນທັງໝົດ trigger callback ດຽວ)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: a.onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          // ✅ [UI Polish] soft accent (ຖ້າມີ) ໃຫ້ pill ນັ້ນເດັ່ນ
                          // ຂຶ້ນມາ — ບໍ່ດັ່ງນັ້ນໃຊ້ pill ໂປ່ງໃສແບບເກົ່າ
                          color: a.accent ?? Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(a.label, style: TextStyle(
                            color: a.accent != null ? C.navy : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                      ),
                    ),
                  )).toList()),
            ],
          ]),
    ));
  }
}

// ── LOW BALANCE ALERT ────────────────────────────────────────

class _LowBalanceBanner extends StatelessWidget {
  final VoidCallback onTopUp;
  const _LowBalanceBanner({required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTopUp,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: C.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.orange.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: C.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('low_balance_alert'), style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: C.orange))),
            const Icon(Icons.chevron_right_rounded, color: C.orange, size: 18),
          ]),
        ),
      ),
    );
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

  // ✅ [FIX — Phase 3 icon system] emoji ຖືກປ່ຽນເປັນ icon-in-tinted-circle,
  // ຮູບແບບດຽວກັນກັບ _BankCard ຂ້າງເທິງນີ້ ໃນໜ້າດຽວກັນ
  static const _icons = {
    TxType.earning:    Icons.attach_money_rounded,
    TxType.withdrawal: Icons.account_balance_outlined,
    TxType.bonus:      Icons.card_giftcard_rounded,
    TxType.refund:     Icons.replay_rounded,
    TxType.topup:      Icons.add_card_rounded,
    TxType.adjustment: Icons.tune_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // ✅ tx.isCredit (instance-level, ເບິ່ງ Booking.dart) ບໍ່ແມ່ນ tx.type.isCredit
    // (fixed ຕໍ່ type) — admin adjustment ອາດເປັນໄດ້ທັງບວກ/ລົບດ້ວຍ type ດຽວກັນ
    final color = tx.isCredit ? C.green : C.red;
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
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_icons[tx.type]!, color: color, size: 18),
        ),
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

class _TopUpDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   highlight;
  const _TopUpDetailRow({
    required this.label, required this.value, this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
          Flexible(child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ ຄັດລອກແລ້ວ'), duration: Duration(seconds: 1)),
                );
              },
              child: Text(value, textAlign: TextAlign.right, style: TextStyle(
                  fontSize: 13,
                  fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                  color: highlight ? C.primary : C.text)),
            ),
          )),
        ],
      ),
    );
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