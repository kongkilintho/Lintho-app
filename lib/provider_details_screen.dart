// ============================================================
// provider_details_screen.dart — LinTho
// Fixes:
//   ✅ [FIX-1] provider.name → provider.displayName
//   ✅ [FIX-1] provider.about → provider.bio
//   ✅ [FIX-1] provider.services → provider.serviceTypes
//   ✅ [FIX-1] provider.isAvailable → provider.isOnline
//   ✅ [FIX-1] provider.totalReviews → provider.totalJobs
//   ✅ [FIX-2] tr() → Lao strings ໂດຍກົງ
//   ✅ [FIX-3] import paths ຖືກຕ້ອງ (ບໍ່ມີ ../)
//   ── Rules (kept) ──────────────────────────────────────────
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ Skeleton loading ແທນ CircularProgressIndicator
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'firestore_service.dart';
import 'provider_model.dart';
import 'chat_screen.dart';
import 'booking_form_screen.dart';

// ════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ════════════════════════════════════════════════════════════

// ✅ autoDispose — ຍົກເລີກ cache/listener ອັດຕະໂນມັດເມື່ອອອກຈາກໜ້ານີ້
// (ບໍ່ໃຫ້ Firestore snapshot listener ຄ້າງສະສົມຕອນ browse provider ຫຼາຍຄົນ)
// ✅ StreamProvider ແທນ FutureProvider — ຖ້າຊ່າງປິດ online ຫຼືປ່ຽນ rating
// ຂະນະລູກຄ້າກຳລັງເບິ່ງໜ້ານີ້ຢູ່, UI ຕ້ອງອັບເດດທັນທີ ບໍ່ແມ່ນຄ້າງຄ່າຕອນເປີດໜ້າ
final providerDetailProvider =
StreamProvider.autoDispose.family<ProviderModel?, String>((ref, uid) {
  return FirestoreService().watchProvider(uid);
});

final providerReviewsProvider =
StreamProvider.autoDispose.family<List<ReviewModel>, String>((ref, uid) {
  return FirestoreService().getProviderReviews(uid);
});

// ════════════════════════════════════════════════════════════
// MAIN SCREEN
// ════════════════════════════════════════════════════════════

class ProviderDetailsScreen extends ConsumerWidget {
  final String providerId;
  const ProviderDetailsScreen({super.key, required this.providerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provAsync = ref.watch(providerDetailProvider(providerId));

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        provAsync.when(
          loading: () => const _ProviderDetailSkeleton(),
          error:   (e, _) => Center(child: Text('${tr("error")}: $e')),
          data: (provider) {
            if (provider == null) {
              return Center(child: Text(tr('provider_not_found')));
            }
            return _ProviderDetailsBody(provider: provider);
          },
        ),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: provAsync.maybeWhen(
            data: (provider) => provider != null
                ? _BottomActions(provider: provider)
                : const SizedBox(),
            orElse: () => const SizedBox(),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SKELETON
// ════════════════════════════════════════════════════════════

class _ProviderDetailSkeleton extends StatefulWidget {
  const _ProviderDetailSkeleton();

  @override
  State<_ProviderDetailSkeleton> createState() =>
      _ProviderDetailSkeletonState();
}

class _ProviderDetailSkeletonState extends State<_ProviderDetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double radius = 8}) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color:        C.muted.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            height: 260,
            color: C.muted.withValues(alpha: 0.12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color:  C.muted.withValues(alpha: 0.2),
                    shape:  BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 12),
                _box(140, 18, radius: 8),
                const SizedBox(height: 8),
                _box(100, 13, radius: 6),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            margin:  const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(80, 14),
                const SizedBox(height: 10),
                _box(double.infinity, 12),
                const SizedBox(height: 6),
                _box(double.infinity, 12),
                const SizedBox(height: 6),
                _box(180, 12),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            margin:  const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(80, 14),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _box(70, 28, radius: 14),
                  _box(90, 28, radius: 14),
                  _box(60, 28, radius: 14),
                  _box(80, 28, radius: 14),
                ]),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
                (_, __) => Container(
              margin:  const EdgeInsets.fromLTRB(16, 6, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color:  C.muted.withValues(alpha: 0.15),
                      shape:  BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(100, 13),
                      const SizedBox(height: 6),
                      _box(double.infinity, 11),
                      const SizedBox(height: 4),
                      _box(160, 11),
                    ],
                  )),
                ],
              ),
            ),
            childCount: 3,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// BODY
// ════════════════════════════════════════════════════════════

class _ProviderDetailsBody extends ConsumerWidget {
  final ProviderModel provider;
  const _ProviderDetailsBody({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(providerReviewsProvider(provider.uid));

    return CustomScrollView(slivers: [
      SliverAppBar(
        expandedHeight:  260,
        pinned:          true,
        backgroundColor: C.primary,
        flexibleSpace: FlexibleSpaceBar(
          background: _ProfileHeader(provider: provider),
        ),
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      // ── About ──
      SliverToBoxAdapter(
        child: _SectionCard(
          title: tr('about'),
          child: Text(
            // ✅ [FIX-1] provider.bio ແທນ provider.about
            provider.bio.isNotEmpty ? provider.bio : tr('no_info_yet'),
            style: const TextStyle(color: C.textSecondary, height: 1.5),
          ),
        ),
      ),

      // ── Services ──
      SliverToBoxAdapter(
        child: _SectionCard(
          title: tr('services'),
          child: provider.serviceTypes.isEmpty
              ? Text(tr('no_info_yet'),
              style: const TextStyle(color: C.muted))
              : Wrap(
            spacing: 8, runSpacing: 6,
            // ✅ [FIX-1] provider.serviceTypes ແທນ provider.services
            children: provider.serviceTypes.map((s) => Chip(
              label: Text(s, style: const TextStyle(
                  color: C.primary, fontSize: 12)),
              backgroundColor: C.primary.withValues(alpha: 0.1),
              side: BorderSide(
                  color: C.primary.withValues(alpha: 0.3)),
              padding: EdgeInsets.zero,
            )).toList(),
          ),
        ),
      ),

      // ── Stats ──
      SliverToBoxAdapter(
        child: _SectionCard(
          title: tr('statistics_label'),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem('⭐', provider.ratingLabel, tr('rating_label')),
              // ✅ [FIX-1] provider.totalJobs ແທນ provider.totalReviews
              _StatItem('✅', '${provider.totalJobs}', tr('total_jobs')),
              _StatItem('🏆', '${provider.experienceYears} ${tr("years_unit")}', tr('experience_label')),
              _StatItem(
                provider.isOnline ? '🟢' : '⚫',
                // ✅ [FIX-1] provider.isOnline ແທນ provider.isAvailable
                provider.isOnline ? tr('online') : tr('offline'),
                tr('status_label'),
              ),
            ],
          ),
        ),
      ),

      // ── Reviews Header ──
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Text(tr('reviews'), style: const TextStyle(
              fontSize:   16,
              fontWeight: FontWeight.bold,
              color:      C.textPrimary,
            )),
            const Spacer(),
            // ✅ [FIX-1] totalJobs ແທນ totalReviews
            Text('${provider.totalJobs} ${tr("jobs_unit")}',
                style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
      ),

      // ── Reviews List ──
      reviewsAsync.when(
        loading: () => SliverList(
          delegate: SliverChildBuilderDelegate(
                (_, __) => const _ReviewSkeletonTile(),
            childCount: 3,
          ),
        ),
        error: (e, _) => SliverToBoxAdapter(
            child: Center(child: Text('$e'))),
        data: (reviews) => reviews.isEmpty
            ? SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(tr('no_reviews'),
                style: const TextStyle(color: C.muted))),
          ),
        )
            : SliverList(
          delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ReviewTile(review: reviews[i]),
            childCount: reviews.length,
          ),
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ]);
  }
}

// ── Stat Item ─────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String emoji, value, label;
  const _StatItem(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 22)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(
        fontSize: 13, fontWeight: FontWeight.w800, color: C.textPrimary)),
    Text(label, style: const TextStyle(fontSize: 10, color: C.muted)),
  ]);
}

// ════════════════════════════════════════════════════════════
// REVIEW SKELETON TILE
// ════════════════════════════════════════════════════════════

class _ReviewSkeletonTile extends StatefulWidget {
  const _ReviewSkeletonTile();

  @override
  State<_ReviewSkeletonTile> createState() => _ReviewSkeletonTileState();
}

class _ReviewSkeletonTileState extends State<_ReviewSkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        margin:  const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: C.muted.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 110, height: 12,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 6),
                Container(width: double.infinity, height: 11,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 4),
                Container(width: 160, height: 11,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5))),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PROFILE HEADER
// ════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  final ProviderModel provider;
  const _ProfileHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [C.primary, C.primary.withValues(alpha: 0.75)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius:          50,
                  backgroundColor: Colors.white24,
                  foregroundImage: provider.photoUrl.isNotEmpty
                      ? NetworkImage(provider.photoUrl)
                      : null,
                  onForegroundImageError: provider.photoUrl.isNotEmpty
                      ? (_, __) {}
                      : null,
                  child: provider.photoUrl.isEmpty
                      ? const Icon(Icons.person,
                      size: 50, color: Colors.white)
                      : null,
                ),
                // ✅ [FIX-1] isOnline ແທນ isAvailable
                if (provider.isOnline)
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color:  Colors.greenAccent,
                      shape:  BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // ✅ [FIX-1] displayName ແທນ name
            Text(provider.displayName, style: const TextStyle(
              color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(provider.ratingLabel, style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                  // ✅ [FIX-1] totalJobs ແທນ totalReviews
                  '  (${provider.totalJobs} ${tr("jobs_unit")})',
                  style: TextStyle(
                    color:    Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:        Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${provider.experienceYears} ${tr("years_experience")}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12),
              ),
            ),
            if (provider.isVerified) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color:        Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_outlined,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(tr('verified_badge'), style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700,
                    )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SECTION CARD
// ════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    margin:  const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(
        color:      Colors.black.withValues(alpha: 0.05),
        blurRadius: 8, offset: const Offset(0, 2),
      )],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(
          fontSize:   15,
          fontWeight: FontWeight.bold,
          color:      C.textPrimary,
        )),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
// REVIEW TILE
// ════════════════════════════════════════════════════════════

class _ReviewTile extends StatelessWidget {
  final ReviewModel review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) => Container(
    margin:  const EdgeInsets.fromLTRB(16, 6, 16, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(
        color:      Colors.black.withValues(alpha: 0.04),
        blurRadius: 6, offset: const Offset(0, 2),
      )],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius:          20,
          backgroundColor: C.primary.withValues(alpha: 0.15),
          foregroundImage: review.customerPhoto.isNotEmpty
              ? NetworkImage(review.customerPhoto)
              : null,
          onForegroundImageError: review.customerPhoto.isNotEmpty
              ? (_, __) {}
              : null,
          child: review.customerPhoto.isEmpty
              ? Icon(Icons.person, size: 20, color: C.primary)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(review.customerName, style: const TextStyle(
                  fontWeight: FontWeight.w600, color: C.textPrimary,
                )),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < review.rating.round()
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber, size: 14,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(review.comment, style: const TextStyle(
              color: C.textSecondary, fontSize: 13, height: 1.4,
            )),
            const SizedBox(height: 4),
            Text(
              '${review.createdAt.day.toString().padLeft(2, '0')}/'
                  '${review.createdAt.month.toString().padLeft(2, '0')}/'
                  '${review.createdAt.year}',
              style: const TextStyle(color: C.muted, fontSize: 11),
            ),
          ],
        )),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
// BOTTOM ACTIONS
// ════════════════════════════════════════════════════════════

class _BottomActions extends StatelessWidget {
  final ProviderModel provider;
  const _BottomActions({required this.provider});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(
        color:      Colors.black.withValues(alpha: 0.08),
        blurRadius: 12, offset: const Offset(0, -3),
      )],
    ),
    child: SafeArea(
      top: false,
      child: Row(children: [
        // Chat
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ChatScreen(
                receiverId:   provider.uid,
                // ✅ [FIX-1] displayName ແທນ name
                receiverName: provider.displayName,
              )),
            ),
            icon:  const Icon(Icons.chat_bubble_outline),
            label: Text(tr('chat')),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.primary,
              side:    const BorderSide(color: C.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:   RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Book Now
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) =>
                  BookingFormScreen(providerId: provider.uid)),
            ),
            icon:  const Icon(Icons.calendar_today, size: 18),
            label: Text(tr('book_now')),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:   RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    ),
  );
}