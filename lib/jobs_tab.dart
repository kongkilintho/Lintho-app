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
import 'theme/app_theme.dart' show AppRadius;
import 'widgets/empty_state_view.dart';
import 'widgets/error_state_view.dart';
import 'widgets/skeleton_box.dart';

class ProviderJobsTab extends ConsumerWidget {
  const ProviderJobsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🔒 [AUDIT PROV-5 / 2026-08-02] (label, value) pairs — value is the
    // stable JobStatus? compared against jobFilterProvider's state; label is
    // still localized for display via tr().
    final filters = <(String, JobStatus?)>[
      (tr('all'), null),
      (tr('completed'), JobStatus.completed),
      (tr('cancelled'), JobStatus.cancelled),
      (tr('rejected'), JobStatus.rejected),
    ];

    final filter       = ref.watch(jobFilterProvider);
    final historyAsync = ref.watch(filteredHistoryProvider);

    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
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
                final (label, value) = f;
                final sel = filter == value;
                return _FilterChip(
                  label:    label,
                  selected: sel,
                  onTap:    () =>
                  ref.read(jobFilterProvider.notifier).state = value,
                );
              }).toList(),
            ),
          ),
        ),

        // ── Job List ─────────────────────────────────────────
        Expanded(
          child: historyAsync.when(
            loading: () => ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              itemBuilder: (_, __) => const SkeletonListTile(),
            ),
            error:   (_, __) => ErrorStateView(
              onRetry: () => ref.invalidate(jobHistoryProvider),
            ),
            data: (jobs) => RefreshIndicator(
              // ✅ [Brand color audit 2026-07-27] C.blue → C.primary (ສີຂຽວແບຣນ)
              color:     C.primary,
              onRefresh: () async => ref.invalidate(jobHistoryProvider),
              child: jobs.isEmpty
                  ? ListView(children: [EmptyStateView(
                      icon: Icons.receipt_long_outlined,
                      title: tr('no_job_history'),
                      // ✅ [Brand color audit 2026-07-27] empty state ຄວນເປັນ
                      // ສີກາງ (ບໍ່ແມ່ນສີແບຣນ) — ບໍ່ແມ່ນ CTA, ບໍ່ຄວນດຶງດູດສາຍຕາ
                      accent: C.muted,
                    )])
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
          // ✅ [Brand color audit 2026-07-27] filter chip ທີ່ເລືອກໃຊ້ສີຂຽວແບຣນ
          // (ແທນ C.blue) — ໃຫ້ຕົງກັບ tab/chip ອື່ນໆທົ່ວແອັບ
          color:        selected ? C.primary : C.bg,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(
            color: selected ? C.primary : C.border, width: 1.5,
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset:     const Offset(0, 3),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                  color: C.bg, borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                // ✅ [FIX H11] Icon ຈາກ category ແທນ raw emoji ທີ່ເກັບໄວ້ໃນ doc
                child: Center(child: Icon(booking.serviceIcon,
                    size: 26, color: C.navy)),
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

// ✅ [FIX — shared components] _EmptyView/_SkeletonList/_SkeletonCard/
// _Shimmer/_ErrorView ຖືກລຶບອອກ — ໃຊ້ EmptyStateView/SkeletonListTile/
// ErrorStateView ຈາກ lib/widgets/ ແທນ (ດຽວກັນກັບ home_tab.dart).