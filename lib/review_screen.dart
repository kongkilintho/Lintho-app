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
import 'app_colors.dart';
import 'provider_model.dart';
import 'fcm_service.dart';

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
      // ✅ [FIX-2] Lao string ໂດຍກົງ ແທນ tr('select_star')
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:         Text('ກະລຸນາເລືອກດາວກ່ອນ'),
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
      await provRef.collection('reviews').add({
        'customerId':       user?.uid     ?? '',
        'customerName':     user?.displayName ?? 'ລູກຄ້າ',
        'customerPhotoUrl': user?.photoURL    ?? '',
        'providerId':       widget.provider.uid,
        'rating':           _selectedStar.toDouble(),
        'comment':          _commentCtrl.text.trim(),
        'bookingId':        widget.bookingId,
        'serviceName':      widget.serviceName,
        'createdAt':        now,
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
      // ✅ [FIX-2] Lao string ໂດຍກົງ ແທນ tr('error')
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text('ເກີດຂໍ້ຜິດພາດ: $e'),
        backgroundColor: C.red,
      ));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            // ✅ [FIX-2] Lao string ໂດຍກົງ ແທນ tr('review_thanks')
            const Text(
              'ຂອບໃຈສຳລັບການໃຫ້ຄະແນນ!\nຄຳຄິດເຫັນຂອງທ່ານສຳຄັນຫຼາຍ',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: C.textPrimary,
              ),
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
            // ✅ [FIX-2] ແທນ tr('ok')
            child: const Text('ຕົກລົງ',
                style: TextStyle(
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
                    Text(widget.serviceName,
                      style: const TextStyle(
                          fontSize: 13, color: C.textSecondary),
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
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: C.gold.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded,
                          color: C.gold, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        widget.provider.ratingLabel,
                        style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: C.gold,
                        ),
                      ),
                      Text(
                        '  ·  ${widget.provider.totalJobs} ງານ',
                        style: const TextStyle(
                            fontSize: 11, color: C.muted),
                      ),
                    ]),
                  )),

                const SizedBox(height: 28),

                // ── Stars ───────────────────────────────
                const Text('ໃຫ້ຄະແນນຊ່າງ', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: C.textPrimary,
                )),
                const SizedBox(height: 12),
                // ✅ [FIX — flutter_rating_bar was in pubspec.yaml, unused]
                // ອາທິດເກົ່າຫັນຄະແນນເອງດ້ວຍ InkWell 5 ໜ່ວຍ ບໍ່ມີ Semantics ໃດເລີຍ —
                // screen reader ຈະໄດ້ຍິນ 5 icon ບໍ່ມີປ້າຍຊື່. ຕອນນີ້ໃຊ້ RatingBar
                // (ຈາກ package) ຫຸ້ມດ້ວຍ Semantics ບອກຄະແນນປັດຈຸບັນ.
                Center(child: Semantics(
                  label: 'ໃຫ້ຄະແນນຊ່າງ',
                  value: '$_selectedStar ຈາກ 5 ດາວ',
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
                    child: Text(
                      _starLabel(_selectedStar),
                      key: ValueKey(_selectedStar),
                      style: const TextStyle(
                        fontSize: 14, color: C.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),

                const SizedBox(height: 28),

                // ── Comment ─────────────────────────────
                const Text('ຄຳຄິດເຫັນ (ບໍ່ບັງຄັບ)',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: C.textPrimary,
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLength:  200,
                  maxLines:   4,
                  onChanged:  (_) => setState(() {}),
                  decoration: InputDecoration(
                    // ✅ [FIX-2] ແທນ tr('review_hint')
                    hintText:  'ຊ່າງດີແນວໃດ? ວຽກເປັນແນວໃດ?...',
                    hintStyle: const TextStyle(
                        color: C.muted, fontSize: 13),
                    filled:    true,
                    fillColor: C.white,
                    counterText:
                    '${_commentCtrl.text.length}/200',
                    counterStyle: const TextStyle(
                        color: C.muted, fontSize: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:   const BorderSide(color: C.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:   const BorderSide(color: C.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:   const BorderSide(
                          color: C.primary, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Submit ──────────────────────────────
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
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const _BtnLoadingSkeleton()
                    // ✅ [FIX-2] ແທນ tr('submit_review')
                        : const Text('ສົ່ງຄຳຄິດເຫັນ', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Book Again ──────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.popUntil(
                        context, (r) => r.isFirst),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.primary,
                      side:    const BorderSide(color: C.primary),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    // ✅ [FIX-2] ແທນ tr('book_again')
                    child: const Text('📱 ຈອງອີກຄັ້ງ', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),

                const SizedBox(height: 12),

                // ── View History ────────────────────────
                Center(child: TextButton(
                  onPressed: () => Navigator.popUntil(
                      context, (r) => r.isFirst),
                  // ✅ [FIX-2] ແທນ tr('view_history')
                  child: const Text('ເບິ່ງປະຫວັດການຈອງ',
                      style: TextStyle(
                        fontSize: 14, color: C.muted,
                        fontWeight: FontWeight.w600,
                      )),
                )),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ✅ [FIX-2] ແທນ tr('star_X') ທຸກດາວ
  String _starLabel(int star) => switch (star) {
    1 => '😞 ບໍ່ດີ',
    2 => '😐 ພໍໄດ້',
    3 => '🙂 ດີ',
    4 => '😊 ດີຫຼາຍ',
    5 => '🤩 ດີເລີດ!',
    _ => '',
  };
}

// ════════════════════════════════════════════════════════════
//  BUTTON LOADING SKELETON
// ════════════════════════════════════════════════════════════

class _BtnLoadingSkeleton extends StatefulWidget {
  const _BtnLoadingSkeleton();

  @override
  State<_BtnLoadingSkeleton> createState() => _BtnLoadingSkeletonState();
}

class _BtnLoadingSkeletonState extends State<_BtnLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.4, end: 1.0).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
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
          const Text('ງານສຳເລັດແລ້ວ! 🎉', style: TextStyle(
            color: Colors.white, fontSize: 22,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 4),
          const Text('ຂອບໃຈທີ່ໃຊ້ບໍລິການ LinTho',
              style: TextStyle(
                color: Colors.white70, fontSize: 13,
              )),
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