// ============================================================
// jobs_tab.dart — LinTho Provider App
// Jobs Tab: Filter + History
//
// Fixes:
//   ✅ import StatusBadge ຈາກ home_tab (ບໍ່ຕ້ອງ widgets/ folder)
//   ✅ withOpacity → withValues(alpha:)
//   ✅ Skeleton loading
//   ✅ GestureDetector → InkWell
//   ✅ Error view + retry button
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'home_tab.dart' show StatusBadge; // ✅ ຈາກ home_tab ຕາມເດີມ
import 'job_workflow_Screen.dart';

class ProviderJobsTab extends ConsumerWidget {
  const ProviderJobsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = [
      tr('all'), tr('completed'), tr('cancelled'), tr('rejected'),
    ];

    final filter       = ref.watch(jobFilterProvider);
    final historyAsync = ref.watch(filteredHistoryProvider);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation:       0,
        centerTitle:     true,
        title: Text(tr('all_jobs'), style: const TextStyle(
          color: C.text, fontWeight: FontWeight.w800, fontSize: 18,
        )),
      ),
      body: Column(children: [
        // ── Filter Chips ─────────────────────────────────────
        Container(
          color:   Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final sel = filter == f;
                return _FilterChip(
                  label:    f,
                  selected: sel,
                  onTap:    () =>
                  ref.read(jobFilterProvider.notifier).state = f,
                );
              }).toList(),
            ),
          ),
        ),

        // ── Job List ─────────────────────────────────────────
        Expanded(
          child: historyAsync.when(
            loading: () => const _SkeletonList(),
            error:   (_, __) => _ErrorView(
              onRetry: () => ref.invalidate(jobHistoryProvider),
            ),
            data: (jobs) => RefreshIndicator(
              color:     C.blue,
              onRefresh: () async => ref.invalidate(jobHistoryProvider),
              child: jobs.isEmpty
                  ? ListView(children: const [_EmptyView()])
                  : ListView.builder(
                padding:     const EdgeInsets.all(16),
                itemCount:   jobs.length,
                itemBuilder: (_, i) => _JobHistoryCard(booking: jobs[i]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── FILTER CHIP ──────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration:     const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color:        selected ? C.blue : C.bg,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(
            color: selected ? C.blue : C.border, width: 1.5,
          ),
        ),
        child: Material(
          color:        Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(label, style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.w700,
                color:      selected ? Colors.white : C.muted,
              )),
            ),
          ),
        ),
      ),
    );
  }
}

// ── JOB HISTORY CARD ─────────────────────────────────────────

class _JobHistoryCard extends StatelessWidget {
  final Booking booking;
  const _JobHistoryCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset:     const Offset(0, 3),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          // ✅ [FIX] ບັດນີ້ເຄີຍກົດແລ້ວບໍ່ມີຫຍັງເກີດຂຶ້ນ (dead tap target) —
          // JobWorkflowScreen ຮອງຮັບ status completed/cancelled/rejected
          // ແບບ read-only ຢູ່ແລ້ວ, ຈຶ່ງໃຊ້ເປັນໜ້າລາຍລະອຽດປະຫວັດວຽກນຳກັນ.
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => JobWorkflowScreen(initialBooking: booking))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: C.bg, borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(booking.serviceEmoji,
                    style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.serviceType, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: C.text,
                  )),
                  const SizedBox(height: 3),
                  _InfoRow(Icons.person_outline, booking.customerName),
                  _InfoRow(Icons.calendar_today_outlined,
                      _fmtDate(booking.completedAt ?? booking.createdAt)),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                StatusBadge(status: booking.status),
                const SizedBox(height: 4),
                Text(booking.formattedPrice, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: C.navy,
                )),
                // ✅ fix: Booking ບໍ່ມີ field rating ຈິງ — ລຶບ stars ປອມອອກ
                // (rating ແທ້ຢູ່ໃນ providers/{uid}/reviews, ບໍ່ແມ່ນໃນ booking)
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(icon, size: 11, color: C.muted),
        const SizedBox(width: 3),
        Flexible(child: Text(text,
            style: const TextStyle(fontSize: 11, color: C.muted),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ── EMPTY VIEW ───────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color:        C.sky.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Center(child: Text('📋', style: TextStyle(fontSize: 36))),
        ),
        const SizedBox(height: 14),
        Text(tr('no_job_history'), style: const TextStyle(
          fontSize: 15, color: C.muted, fontWeight: FontWeight.w600,
        )),
      ],
    ));
  }
}

// ── SKELETON LOADING ─────────────────────────────────────────

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: 5,
    itemBuilder: (_, __) => const _SkeletonCard(),
  );
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3),
          )],
        ),
        child: Row(children: [
          _Shimmer(width: 50, height: 50, radius: 14, opacity: _anim.value),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Shimmer(width: 130, height: 13, radius: 4, opacity: _anim.value),
              const SizedBox(height: 7),
              _Shimmer(width: 90,  height: 10, radius: 4, opacity: _anim.value),
              const SizedBox(height: 5),
              _Shimmer(width: 110, height: 10, radius: 4, opacity: _anim.value),
            ],
          )),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _Shimmer(width: 60, height: 20, radius: 8, opacity: _anim.value),
            const SizedBox(height: 8),
            _Shimmer(width: 70, height: 13, radius: 4, opacity: _anim.value),
          ]),
        ]),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double width, height, radius, opacity;
  const _Shimmer({
    required this.width, required this.height,
    required this.radius, required this.opacity,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
      color:        C.border.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

// ── ERROR VIEW ───────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off_outlined, size: 56, color: C.muted),
        const SizedBox(height: 12),
        Text(tr('load_failed'), style: const TextStyle(
          fontSize: 15, color: C.muted, fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon:  const Icon(Icons.refresh),
          label: Text(tr('retry')),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.navy,
            side: const BorderSide(color: C.navy),
          ),
        ),
      ],
    ));
  }
}