import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'quick_booking_provider.dart' show formatKip;
import 'referral_provider.dart';
import 'theme/app_theme.dart' show AppTypography, AppRadius;
import 'widgets/app_button.dart';
import 'widgets/empty_state_view.dart';
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
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        // ✅ [Phase 2 / Batch C] matches AppTypography.appBarTitle exactly.
        title: Text(tr('referral_title'), style: AppTypography.appBarTitle),
      ),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 🔒 [AUDIT M-9 / 2026-07-27] ກ່ອນໜ້ານີ້ສະແດງ error text ດິບ ໂດຍບໍ່ມີ
        // ປຸ່ມ retry ໃດເລີຍ — ໃຊ້ ErrorStateView ມາດຕະຖານດຽວກັນກັບໜ້າຈໍອື່ນ.
        error: (e, _) => ErrorStateView(
          onRetry: () => ref.invalidate(referralInfoProvider),
        ),
        data: (info) {
          // ✅ [Phase 2 / Batch C] was tr('fill_all') ("please fill in all
          // fields") — a form-validation string that made no sense here.
          // referralInfoProvider only emits null when there's no signed-in
          // user, so the correct message is the login-required one.
          if (info == null) {
            return EmptyStateView(
              icon:  Icons.person_off_outlined,
              title: tr('referral_login_required'),
            );
          }
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
                    hintText: tr('referral_code_hint'),
                    filled: true, fillColor: C.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: const BorderSide(color: C.border)),
                  ),
                )),
                const SizedBox(width: 10),
                // ✅ [Phase 2 / Batch C] was C.navy — redeeming a friend's
                // code is the one concrete money-saving action a user takes
                // on this screen, so it renders LinTho green like this
                // batch's other primary money-adjacent CTAs (see
                // rewards_screen.dart's Redeem button, same fix).
                AppButton.primary(
                  fullWidth: false,
                  loading: _redeeming,
                  label: tr('referral_redeem_button'),
                  onPressed: _redeeming ? null : _redeem,
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
    if (!mounted) return;
    setState(() => _redeeming = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? tr('referral_redeem_success')),
      backgroundColor: error != null ? C.red : C.success,
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
      // ✅ [Phase 2 / Batch C] navy is correct here — hero/header card
      // background (brand-surface usage), not a CTA button.
      decoration: BoxDecoration(
        color: C.navy,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
            tooltip: tr('referral_copy_code_semantic'),
            icon: const Icon(Icons.copy, color: Colors.white70, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                  // 🔒 [AUDIT UI-10 / 2026-08-02]
                  SnackBar(content: Text(tr('copied_to_clipboard'))));
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
            borderRadius: BorderRadius.circular(AppRadius.card),
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
        // ✅ [Phase 2 / Batch C] not converted to AppButton — this is a
        // deliberate white-fill/navy-text style specific to sitting on the
        // navy hero card, which AppButton's variants don't express (its
        // "secondary" variant is a solid navy fill, wrong here). Radius
        // token converged; text/share-message restored to tr().
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Share.share(
                '${tr("referral_share_use_code")} $code ${tr("referral_share_get_discount")} '
                '${formatKip(20000)} ${tr("referral_share_at_lintho")} https://lintho.app/r/$code'),
            icon: const Icon(Icons.share, size: 18),
            label: Text(tr('referral_share_button')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: C.navy,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
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
          borderRadius: BorderRadius.circular(AppRadius.card),
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
