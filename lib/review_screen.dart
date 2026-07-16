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
  final String        serviceEmoji;

  const ReviewScreen({
    super.key,
    required this.bookingId,
    required this.provider,
    required this.serviceName,
    required this.serviceEmoji,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {

  int  _selectedStar = 0;
  int  _hoverStar    = 0;
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

      // 1) ບັນທຶກລົງ reviews subcollection
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
      });

      // ✅ RULE: mounted check ຫຼັງ async
      if (!mounted) return;

      // 2) ຄຳນວນ rating ສະເລ່ຍ (ຈາກ reviews subcollection)
      final reviewsSnap = await provRef.collection('reviews').get();

      if (!mounted) return;

      double total = 0;
      for (final doc in reviewsSnap.docs) {
        total += (doc.data()['rating'] as num?)?.toDouble() ?? 0;
      }
      final avg = reviewsSnap.docs.isNotEmpty
          ? total / reviewsSnap.docs.length
          : 0.0;

      // ✅ [FIX-4] totalJobs = ຈຳນວນງານທີ່ "ສຳເລັດ" ແທ້ (ບໍ່ແມ່ນຈຳນວນ review)
      final bookingsRef = db.collection('bookings');
      final completedCountSnap = await bookingsRef
          .where('providerId', isEqualTo: widget.provider.uid)
          .where('status', isEqualTo: 'completed')
          .count()
          .get();
      final cancelledCountSnap = await bookingsRef
          .where('providerId', isEqualTo: widget.provider.uid)
          .where('status', isEqualTo: 'cancelled')
          .count()
          .get();
      final rejectedCountSnap = await bookingsRef
          .where('providerId', isEqualTo: widget.provider.uid)
          .where('status', isEqualTo: 'rejected')
          .count()
          .get();

      if (!mounted) return;

      final completedCount = completedCountSnap.count ?? 0;
      final cancelledCount = cancelledCountSnap.count ?? 0;
      final rejectedCount  = rejectedCountSnap.count ?? 0;
      final totalAttempted = completedCount + cancelledCount + rejectedCount;
      final completionRate = totalAttempted > 0
          ? (completedCount / totalAttempted) * 100
          : 0.0;

      await provRef.update({
        'rating':         double.parse(avg.toStringAsFixed(1)),
        'totalJobs':      completedCount,
        'completionRate': double.parse(completionRate.toStringAsFixed(1)),
      });

      if (!mounted) return;

      // 3) ໝາຍ reviewed ໃນ bookings
      await db
          .collection('bookings')
          .doc(widget.bookingId)
          .update({'reviewed': true});

      if (!mounted) return;

      // 4) ແຈ້ງເຕືອນຊ່າງວ່າມີຣີວິວໃໝ່
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
      backgroundColor: C.bg,
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
                Center(child: Text(
                  '${widget.serviceEmoji} ${widget.serviceName}',
                  style: const TextStyle(
                      fontSize: 13, color: C.textSecondary),
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
                Center(child: _StarRow(
                  selected: _selectedStar,
                  hover:    _hoverStar,
                  onHover:  (i) => setState(() => _hoverStar = i),
                  onTap:    (i) => setState(() {
                    _selectedStar = i;
                    _hoverStar    = 0;
                  }),
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
                    fillColor: Colors.white,
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
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [C.green, C.green.withValues(alpha: 0.8)],
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
                color: C.green, size: 40,
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

// ════════════════════════════════════════════════════════════
//  STAR ROW
// ════════════════════════════════════════════════════════════

class _StarRow extends StatelessWidget {
  final int               selected;
  final int               hover;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onTap;

  const _StarRow({
    required this.selected,
    required this.hover,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = hover > 0 ? hover : selected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final idx = i + 1;
        final isActive = idx <= active;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:          () => onTap(idx),
            borderRadius:   BorderRadius.circular(8),
            splashColor:    Colors.transparent,
            highlightColor: Colors.transparent,
            child: MouseRegion(
              onEnter: (_) => onHover(idx),
              onExit:  (_) => onHover(0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 150),
                  scale: isActive ? 1.15 : 1.0,
                  child: Icon(
                    isActive ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isActive ? C.gold : C.border,
                    size:  40,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}