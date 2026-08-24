// ============================================================
// review_screen.dart — LinTho
// Fixes:
//   ✅ [FIX-1] Constructor: ຮັບ ProviderModel ແທນ providerId/Name
//              — ກົງກັບ match_screen + tracking_screen
//   ✅ [FIX-2] tr() ທຸກຈຸດ → hardcoded Lao strings
//              — ປອດໄພກວ່າ: ບໍ່ຂຶ້ນກັບ app_locale.dart
//   ✅ [FIX-3] totalReviews → totalJobs (ກົງກັບ Firestore)
//   ── Rules (kept) ───────────────────────────────────────────
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async ທຸກຈຸດ
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ InkWell + Material ທຸກ tap
//   ✅ Skeleton loading ແທນ CircularProgressIndicator
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'app_navigation_state.dart';
import 'provider_details_screen.dart';
import 'provider_model.dart';
import 'fcm_service.dart';
import 'theme/app_theme.dart' show AppTypography, AppRadius;
import 'widgets/app_button.dart';
import 'widgets/pulsing_fade.dart';

// ════════════════════════════════════════════════════════════
//  REVIEW SCREEN
// ════════════════════════════════════════════════════════════

class ReviewScreen extends StatefulWidget {
  // ✅ [FIX-1] ຮັບ ProviderModel ແທນ providerId + providerName
  final String        bookingId;
  final ProviderModel provider;
  final String        serviceName;
  // 🔒 [FOLLOWUP-J3] serviceEmoji (raw emoji character) ຖືກແທນທີ່ດ້ວຍ
  // serviceIcon (Material icon, derive ຈາກ category) — ຄືກັນກັບ pattern ອື່ນໆ
  // ທີ່ຖືກແກ້ໄປແລ້ວ (home_tab.dart/jobs_tab.dart/job_workflow_Screen.dart/
  // match_screen.dart). ໜ້ານີ້ແມ່ນໜຶ່ງໃນສອງຈຸດສຸດທ້າຍທີ່ຍັງເຫຼືອ.
  final IconData       serviceIcon;

  const ReviewScreen({
    super.key,
    required this.bookingId,
    required this.provider,
    required this.serviceName,
    required this.serviceIcon,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {

  int  _selectedStar = 0;
  bool _isLoading    = false;

  // ✅ RULE: dispose() ທຸກ controller
  final _commentCtrl = TextEditingController();
  late final AnimationController _confettiCtrl;
  late final Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _scaleAnim = CurvedAnimation(
      parent: _confettiCtrl,
      curve:  Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  //  SUBMIT
  // ════════════════════════════════════════════════════════

  Future<void> _submit() async {
    if (_selectedStar == 0) {
      // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(tr('select_star')),
        backgroundColor: C.red,
        behavior:        SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final db   = FirebaseFirestore.instance;
      final now  = FieldValue.serverTimestamp();

      // ✅ [FIX-1] ໃຊ້ widget.provider.uid ແທນ widget.providerId
      final provRef = db
          .collection('providers')
          .doc(widget.provider.uid);

      // 🔒 [AUDIT H6/H9/H13] ກ່ອນໜ້ານີ້ຫຼັງຂຽນ review ນີ້ຈະອ່ານ reviews
      // subcollection ທັງໝົດ + count() booking 3 ຄັ້ງ + ຂຽນ providers/{id}
      // ໂດຍກົງ + ຕັ້ງ reviewed:true ເອງ — 4 round-trip ເພີ່ມ, ບໍ່ atomic
      // (partial failure ລະຫວ່າງທາງເຮັດໃຫ້ reviewed ຄ້າງ false, review ຄືນໄດ້
      // ຊ້ຳ), ແລະ firestore.rules ອະນຸຍາດ client ຂຽນ rating/totalJobs/
      // completionRate ໂດຍກົງ (ບໍ່ຕ້ອງມີ review ຈິງ — ຊ່ອງໂຫວ່ໃຫ້ປອມຄະແນນ).
      // ຕອນນີ້ client ຂຽນສະເພາະ review doc ດຽວ — Cloud Function
      // `onReviewCreated` (functions/index.js) ຄິດໄລ່ rating ສະເລ່ຍ ແລະ
      // ຕັ້ງ bookings/{id}.reviewed = true ໃຫ້ອັດຕະໂນມັດ, ໃນ transaction ດຽວ,
      // ຫຼັງຈາກກວດ server-side ວ່າ booking ນີ້ເປັນຂອງລູກຄ້າ+ຊ່າງຄູ່ນີ້ແທ້,
      // completed ແລ້ວ, ແລະ ຍັງບໍ່ເຄີຍ review.
      //
      // 🔒 [AUDIT CUST-3 / 2026-07-30] .add() ສ້າງ doc ID ແບບສຸ່ມ — ຖ້າ submit
      // ຖືກເອີ້ນ 2 ຄັ້ງໃກ້ກັນ (double-tap ກ່ອນ _isLoading disable ປຸ່ມ, ຫຼື retry
      // ຫຼັງ timeout ທີ່ຈິງແລ້ວສຳເລັດ) ຈະໄດ້ 2 review doc ຄົນລະ ID, ທັງສອງຜ່ານ
      // rules ໄດ້ (booking.reviewed ຍັງ false ຢູ່ຕອນທັງສອງ read/write ພ້ອມກັນ),
      // ແລະ onReviewCreated ທັງສອງ invocation ອາດອ່ານ ratingSum/reviewCount
      // ກ່ອນອັນທຳອິດຈະ commit — ນັບຄະແນນຊ້ຳ. ໃຊ້ bookingId ເປັນ doc ID ແທນ
      // (deterministic, ບໍ່ແມ່ນສຸ່ມ) ພາຍໃນ transaction ທີ່ກວດວ່າ doc ນີ້ຍັງບໍ່ມີ
      // ກ່ອນ — Firestore transaction ຮັບປະກັນວ່າຖ້າ 2 ຄັ້ງແຂ່ງກັນ, ຄັ້ງທີສອງຈະ
      // ອ່ານເຫັນ doc ທີ່ຄັ້ງທຳອິດຂຽນໄປແລ້ວຕອນ retry ແລະ throw ແທນທີ່ຈະຂຽນຊ້ຳ.
      final reviewRef = provRef.collection('reviews').doc(widget.bookingId);
      await db.runTransaction((tx) async {
        final existing = await tx.get(reviewRef);
        if (existing.exists) {
          throw Exception(tr('review_duplicate_error'));
        }
        tx.set(reviewRef, {
          'customerId':       user?.uid     ?? '',
          'customerName':     user?.displayName ?? tr('review_default_customer_name'),
          'customerPhotoUrl': user?.photoURL    ?? '',
          'providerId':       widget.provider.uid,
          'rating':           _selectedStar.toDouble(),
          'comment':          _commentCtrl.text.trim(),
          'bookingId':        widget.bookingId,
          'serviceName':      widget.serviceName,
          'createdAt':        now,
        });
      }).timeout(const Duration(seconds: 15));

      // ✅ RULE: mounted check ຫຼັງ async
      if (!mounted) return;

      // ແຈ້ງເຕືອນຊ່າງວ່າມີຣີວິວໃໝ່
      await NotificationSender.reviewReceived(
        providerId: widget.provider.uid,
        bookingId:  widget.bookingId,
        rating:     _selectedStar,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSuccessDialog();

    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text('${tr("error")}: $e'),
        backgroundColor: C.red,
      ));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context:            context,
      barrierDismissible: false,
      // ✅ [Phase 2 / Batch C] dropped the explicit radius(20) override — the
      // app's dialogTheme already applies AppRadius.card automatically when
      // no shape is given, so this was silent drift, not an intentional size.
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎉 decorative/celebratory copy, not a functional status icon —
            // kept as-is (same exemption as the header's confetti below).
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
            Text(
              tr('review_thanks'),
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // back to home
            },
            child: Text(tr('ok'),
                style: const TextStyle(
                  color: C.primary, fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      body: SingleChildScrollView(
        child: Column(children: [

          // ── Header ──────────────────────────────────────
          _GreenHeader(scaleAnim: _scaleAnim),

          // ── Content ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Provider name + service
                // ✅ [FIX-1] ໃຊ້ widget.provider.displayName
                Center(child: Text(
                  widget.provider.displayName,
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: C.textPrimary,
                  ),
                )),
                const SizedBox(height: 4),
                Center(child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.serviceIcon, size: 14, color: C.textSecondary),
                    const SizedBox(width: 5),
                    // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.label.
                    Text(widget.serviceName,
                      style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w400, color: C.textSecondary),
                    ),
                  ],
                )),
                const SizedBox(height: 8),

                // rating badge (current)
                if (widget.provider.rating > 0)
                  Center(child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color:        C.gold.withValues(alpha: 0.1),
                      // ✅ [Phase 2 / Batch C] 20 is equidistant between chip
                      // and sheet; rounds up to sheet, matching this batch's
                      // established tie-break rule — no visible change since
                      // this is already a fully-rounded pill at this height.
                      borderRadius: BorderRadius.circular(AppRadius.sheet),
                      border: Border.all(
                          color: C.gold.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded,
                          color: C.gold, size: 14),
                      const SizedBox(width: 4),
                      // 🔒 [AUDIT UI-8 / 2026-08-02 — Medium, fresh re-audit]
                      // C.gold ຄິດໄລ່ contrast ~1.7:1 ຕໍ່ພື້ນຫຼັງຂາວ, ຕ່ຳກວ່າ
                      // WCAG AA ຫຼາຍ (4.5:1) — ໃຊ້ C.gold ສະເພາະ icon fill
                      // (ຂ້າງເທິງ) ຄືເກົ່າ, ຂໍ້ຄວາມໃຊ້ C.text ແທນ.
                      // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.caption.
                      Text(
                        widget.provider.ratingLabel,
                        style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700, color: C.text),
                      ),
                      Text(
                        '  ·  ${widget.provider.totalJobs} ${tr("jobs_unit")}',
                        style: const TextStyle(
                            fontSize: 11, color: C.muted),
                      ),
                    ]),
                  )),

                const SizedBox(height: 28),

                // ── Stars ───────────────────────────────
                // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.body.
                Text(tr('rate_provider'), style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700, color: C.textPrimary,
                )),
                const SizedBox(height: 12),
                // ✅ [FIX — flutter_rating_bar was in pubspec.yaml, unused]
                // ອາທິດເກົ່າຫັນຄະແນນເອງດ້ວຍ InkWell 5 ໜ່ວຍ ບໍ່ມີ Semantics ໃດເລີຍ —
                // screen reader ຈະໄດ້ຍິນ 5 icon ບໍ່ມີປ້າຍຊື່. ຕອນນີ້ໃຊ້ RatingBar
                // (ຈາກ package) ຫຸ້ມດ້ວຍ Semantics ບອກຄະແນນປັດຈຸບັນ.
                Center(child: Semantics(
                  label: tr('rate_provider'),
                  value: '$_selectedStar ${tr("review_out_of_5_stars")}',
                  child: RatingBar.builder(
                    initialRating: 0,
                    minRating: 0,
                    itemCount: 5,
                    itemSize: 40,
                    glow: false,
                    unratedColor: C.border,
                    itemPadding: const EdgeInsets.symmetric(horizontal: 6),
                    itemBuilder: (context, _) =>
                        const Icon(Icons.star_rounded, color: C.gold),
                    onRatingUpdate: (rating) =>
                        setState(() => _selectedStar = rating.toInt()),
                  ),
                )),
                const SizedBox(height: 8),
                if (_selectedStar > 0)
                  Center(child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey(_selectedStar),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ [Phase 2 / Batch C] emoji face → Material icon,
                        // same migration already applied elsewhere in the app.
                        Icon(_starIcon(_selectedStar), size: 16, color: C.green),
                        const SizedBox(width: 4),
                        Text(
                          _starLabel(_selectedStar),
                          style: const TextStyle(
                            fontSize: 14, color: C.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )),

                const SizedBox(height: 28),

                // ── Comment ─────────────────────────────
                // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.body.
                Text(tr('review_comment_label'),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700, color: C.textPrimary,
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLength:  200,
                  maxLines:   4,
                  onChanged:  (_) => setState(() {}),
                  decoration: InputDecoration(
                    // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
                    hintText:  tr('review_hint'),
                    // ✅ fontSize matches AppTypography.label.
                    hintStyle: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w400, color: C.muted),
                    filled:    true,
                    fillColor: C.white,
                    counterText:
                    '${_commentCtrl.text.length}/200',
                    counterStyle: const TextStyle(
                        color: C.muted, fontSize: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide:   const BorderSide(color: C.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide:   const BorderSide(color: C.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide:   const BorderSide(
                          color: C.primary, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Submit ──────────────────────────────
                // ✅ [Phase 2 / Batch C] not converted to AppButton — its
                // _BtnLoadingSkeleton (shared PulsingFade primitive) is a
                // better loading pattern than AppButton's plain spinner,
                // same documented judgment call already made for
                // booking_form_screen.dart's primary CTA in Batch B. Radius
                // converged to the token; color/loading-child preserved.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:        C.primary,
                      foregroundColor:        Colors.white,
                      disabledBackgroundColor:
                      C.primary.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card)),
                    ),
                    child: _isLoading
                        ? const _BtnLoadingSkeleton()
                        // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
                        : Text(tr('submit_review'), style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Book Again ──────────────────────────
                // 🔒 [PHASE0 P0-1] ເຄີຍ Navigator.popUntil(isFirst) ອย่างດຽວ —
                // ຄືກັນເປ໊ະກັບ View History ຂ້າງລຸ່ມ, ພາຜູ້ໃຊ້ໄປ Home ໂດຍບໍ່ໄດ້
                // ຈອງຫຍັງເລີຍ. ຕອນນີ້ pop ກັບຄືນ MainShell ແລ້ວເປີດ
                // ProviderDetailsScreen ຂອງ provider ຄົນເກົ່າ — ໜ້ານັ້ນອ່ານ
                // isOnline ສົດຈາກ Firestore ຜ່ານ providerDetailProvider (ບໍ່ແມ່ນ
                // ຄ່າເກົ່າຕອນ booking ຄັ້ງກ່ອນ) ແລະ ດຽວນີ້ block ການຈອງຖ້າ
                // provider offline (ເບິ່ງ PHASE0 P1 fix ໃນ provider_details_screen.dart).
                // ✅ [Phase 2 / Batch C] AppButton.outline — this is a
                // secondary action (Submit above is primary), so it now
                // renders the standard navy outline instead of a green
                // outline, matching the CTA-hierarchy rule ("only the
                // primary action is green"). Navigation behavior (Phase 0
                // P0-1 fix: pop to MainShell tab 0, then push
                // ProviderDetailsScreen for this same provider) is
                // unchanged — verified below, not regressed to a bare Home
                // pop. Emoji prefix dropped in favor of a proper icon.
                Consumer(builder: (context, ref, _) => AppButton.outline(
                  label: tr('book_again'),
                  icon:  Icons.replay_rounded,
                  onPressed: () {
                    ref.read(mainShellTabIndexProvider.notifier).state = 0;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProviderDetailsScreen(
                          providerId: widget.provider.uid),
                    ));
                  },
                )),

                const SizedBox(height: 12),

                // ── View History ────────────────────────
                // 🔒 [PHASE0 P0-1] ຕອນນີ້ໄປ BookingScreen ແທ້ (MainShell tab 1)
                // ຜ່ານ goToBookingTab() — ບໍ່ແມ່ນ Home ອີກຕໍ່ໄປ.
                // ✅ [Phase 2 / Batch C] AppButton.ghost — tertiary action,
                // navigation unchanged. Kept centered (AppButton.ghost isn't
                // full-width by default, unlike the outline/primary variants
                // above) to match the original layout.
                Center(child: Consumer(builder: (context, ref, _) => AppButton.ghost(
                  label: tr('view_history'),
                  onPressed: () => goToBookingTab(context, ref),
                ))),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ✅ [Phase 2 / Batch C] restored tr() — see LINTHO_PHASE2_BATCH_C_AUDIT.md
  String _starLabel(int star) => switch (star) {
    1 => tr('star_1'),
    2 => tr('star_2'),
    3 => tr('star_3'),
    4 => tr('star_4'),
    5 => tr('star_5'),
    _ => '',
  };

  // ✅ [Phase 2 / Batch C] emoji faces → Material icons (paired with
  // _starLabel above), same migration already applied elsewhere in the app.
  IconData _starIcon(int star) => switch (star) {
    1 => Icons.sentiment_very_dissatisfied_rounded,
    2 => Icons.sentiment_dissatisfied_rounded,
    3 => Icons.sentiment_neutral_rounded,
    4 => Icons.sentiment_satisfied_rounded,
    5 => Icons.sentiment_very_satisfied_rounded,
    _ => Icons.star_rounded,
  };
}

// ════════════════════════════════════════════════════════════
//  BUTTON LOADING SKELETON
// ════════════════════════════════════════════════════════════

// 🔒 [AUDIT UI-5 / 2026-08-02 — Medium, fresh re-audit] previously its own
// AnimationController+Tween+dispose() (identical 600ms/0.4-1.0 pattern
// duplicated in job_workflow_Screen.dart and main.dart) — now built on the
// shared PulsingFade primitive.
class _BtnLoadingSkeleton extends StatelessWidget {
  const _BtnLoadingSkeleton();

  @override
  Widget build(BuildContext context) => PulsingFade(
    duration: const Duration(milliseconds: 600),
    begin: 0.4, end: 1.0,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize:      MainAxisSize.min,
      children: [
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 100, height: 14,
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
//  GREEN HEADER
// ════════════════════════════════════════════════════════════

class _GreenHeader extends StatelessWidget {
  final Animation<double> scaleAnim;
  const _GreenHeader({required this.scaleAnim});

  @override
  Widget build(BuildContext context) => Container(
    width:   double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 60, 24, 36),
    // ✅ [Brand color audit 2026-07-27 v2] ໜ້າ "ສົ່ງລີວິວສຳເລັດ" = Success
    // (#22C55E), ແຍກຈາກ Primary
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [C.success, C.success.withValues(alpha: 0.8)],
        begin:  Alignment.topLeft,
        end:    Alignment.bottomRight,
      ),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        ..._confettiItems(),
        Column(children: [
          ScaleTransition(
            scale: scaleAnim,
            child: Container(
              width: 72, height: 72,
              decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: C.success, size: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ✅ [Phase 2 / Batch C] restored tr(); fontSize matches
          // AppTypography.title exactly.
          Text(tr('review_job_completed_title'),
              style: AppTypography.title.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          // ✅ fontSize matches AppTypography.label.
          Text(tr('review_thanks_using_lintho'),
              style: AppTypography.label.copyWith(
                  color: Colors.white70, fontWeight: FontWeight.w400)),
        ]),
      ],
    ),
  );

  List<Widget> _confettiItems() => [
    {'emoji': '🎊', 'top': 20.0, 'left':  20.0, 'size': 18.0},
    {'emoji': '✨', 'top': 40.0, 'right': 30.0, 'size': 16.0},
    {'emoji': '🎉', 'top': 10.0, 'right': 60.0, 'size': 20.0},
    {'emoji': '⭐', 'bottom': 20.0, 'left': 40.0, 'size': 14.0},
    {'emoji': '🎊', 'bottom': 30.0, 'right': 20.0, 'size': 16.0},
  ].map((item) => Positioned(
    top:    item['top']    as double?,
    left:   item['left']   as double?,
    right:  item['right']  as double?,
    bottom: item['bottom'] as double?,
    child:  Text(item['emoji'] as String,
        style: TextStyle(fontSize: item['size'] as double)),
  )).toList();
}

// ✅ [FIX — shared package] _StarRow removed — replaced by RatingBar
// (flutter_rating_bar) at the call site above.