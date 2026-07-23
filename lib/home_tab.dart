// ============================================================
// home_tab.dart — LinTho Provider App
// Fixes:
//   ✅ [FIX-1] GestureDetector → InkWell + Material (_OnlineToggle)
//   ✅ [FIX-2] CircularProgressIndicator → Skeleton (_PendingActions)
// ── Rules (kept) ────────────────────────────────────────────
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ Skeleton loading
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
//   ✅ isLoading per bookingId
//   ✅ CountdownBar dynamic total
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'online_provider.dart';
import 'job_workflow_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/error_state_view.dart';
import 'widgets/skeleton_box.dart';

// ════════════════════════════════════════════════════════════
// HOME TAB
// ════════════════════════════════════════════════════════════

class ProviderHomeTab extends ConsumerWidget {
  const ProviderHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline      = ref.watch(onlineStatusProvider);
    final bookingsAsync = ref.watch(activeBookingsProvider);
    final walletAsync   = ref.watch(walletProvider);
    final profileAsync  = ref.watch(profileStreamProvider);
    final openJobs       = ref.watch(unassignedOpenJobsProvider);

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(children: [
          _Header(
            isOnline:    isOnline,
            walletAsync: walletAsync,
            profile:     profileAsync,
          ),
          Expanded(
            child: !isOnline
                ? const _OfflineView()
                : bookingsAsync.when(
              loading: () => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 3,
                itemBuilder: (_, __) => const SkeletonListTile(),
              ),
              error:   (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(activeBookingsProvider),
              ),
              data: (bookings) => _JobListView(bookings: bookings, openJobs: openJobs),
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// HEADER
// ════════════════════════════════════════════════════════════

class _Header extends ConsumerWidget {
  final bool                        isOnline;
  final AsyncValue<Wallet>          walletAsync;
  final AsyncValue<ProviderProfile> profile;

  const _Header({
    required this.isOnline,
    required this.walletAsync,
    required this.profile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user   = FirebaseAuth.instance.currentUser;
    final p      = profile.valueOrNull;
    final wallet = walletAsync.valueOrNull;
    final name   = p?.displayName.isNotEmpty == true
        ? p!.displayName
        : (user?.displayName ?? tr('provider'));

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [C.navy, C.blue],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius:          24,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            foregroundImage: p?.photoUrl != null
                ? NetworkImage(p!.photoUrl!) : null,
            onForegroundImageError: p?.photoUrl != null
                ? (_, __) {} : null,
            child: Text(
              p?.avatarLetter ?? '🔧',
              style: const TextStyle(
                fontSize:   20,
                color:      Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tr("welcome")}, $name 👋',
                  style: TextStyle(
                    color:    Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
                Text(tr('provider_dashboard'), style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   17,
                  fontWeight: FontWeight.w800,
                )),
              ],
            ),
          ),
          _OnlineToggle(isOnline: isOnline),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _StatCard(
            value: wallet?.formattedBalance ?? '₭0',
            label: tr('earnings'),
            icon:  Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(width: 10),
          _StatCard(
            value: '${p?.ratingLabel ?? '0.0'}★',
            label: tr('reviews'),
            icon:  Icons.star_outline,
          ),
          const SizedBox(width: 10),
          _StatCard(
            value: p?.completionRateLabel ?? '0%',
            label: tr('completed'),
            icon:  Icons.check_circle_outline,
          ),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ONLINE TOGGLE
// ✅ [FIX-1] GestureDetector → InkWell + Material
// ════════════════════════════════════════════════════════════

class _OnlineToggle extends ConsumerStatefulWidget {
  final bool isOnline;
  const _OnlineToggle({required this.isOnline});

  @override
  ConsumerState<_OnlineToggle> createState() => _OnlineToggleState();
}

class _OnlineToggleState extends ConsumerState<_OnlineToggle> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result =
        await ref.read(onlineStatusProvider.notifier).toggle();
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      OnlineToggleResult.success => null,
      OnlineToggleResult.locationServiceDisabled =>
          tr('enable_gps_for_jobs'),
      OnlineToggleResult.permissionDenied =>
          tr('allow_location_for_jobs'),
      OnlineToggleResult.writeFailed =>
          tr('status_change_failed'),
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: C.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.isOnline;
    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : _handleTap,
        child: AnimatedContainer(
          duration:  const Duration(milliseconds: 300),
          padding:   const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isOnline ? C.green : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isOnline
                ? null
                : Border.all(color: C.red, width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_busy)
              SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                      isOnline ? Colors.white : C.red),
                ),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isOnline ? Icons.check_circle : Icons.wifi_off,
                  color: isOnline ? Colors.white : C.red,
                  size:  14,
                  key:   ValueKey(isOnline),
                ),
              ),
            const SizedBox(width: 5),
            Text(
              isOnline ? tr('online') : tr('offline'),
              style: TextStyle(
                color:      isOnline ? Colors.white : C.red,
                fontSize:   12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// STAT CARD
// ════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String   value;
  final String   label;
  final IconData icon;
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800,
          )),
          Text(label, style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7), fontSize: 10,
          )),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// JOB LIST
// ════════════════════════════════════════════════════════════

class _JobListView extends ConsumerWidget {
  final List<Booking> bookings;
  final List<Booking> openJobs;
  const _JobListView({required this.bookings, this.openJobs = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = bookings
        .where((b) => b.status == JobStatus.pending && !b.isExpired)
        .toList();
    final active = bookings
        .where((b) => b.status != JobStatus.pending)
        .toList();

    if (bookings.isEmpty && openJobs.isEmpty) {
      return EmptyStateView(
        icon: Icons.inbox_outlined,
        title: tr('no_jobs'),
        subtitle: tr('wait_customer'),
        accent: C.sky,
      );
    }

    return RefreshIndicator(
      color:     C.blue,
      onRefresh: () async => ref.invalidate(activeBookingsProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty) ...[
            _SectionHeader(
              title:      '${tr("new_jobs")} 🔔',
              badge:      '${pending.length} ${tr("pending")}',
              badgeColor: C.red,
            ),
            const SizedBox(height: 8),
            ...pending.map((b) => JobCard(booking: b)),
            const SizedBox(height: 16),
          ],
          // ✅ [FIX-3] booking ທີ່ system ຍັງບໍ່ໄດ້ມອບໝາຍ providerId ໃຫ້ໃຜ —
          // ໃຫ້ provider ຄົນນີ້ຮັບເອງໄດ້ ຄືກັນກັບວຽກທີ່ຖືກສົ່ງມາຫາໂດຍກົງ
          if (openJobs.isNotEmpty) ...[
            _SectionHeader(
              title:      '${tr("open_jobs")} 📋',
              badge:      '${openJobs.length}',
              badgeColor: C.blue,
            ),
            const SizedBox(height: 8),
            ...openJobs.map((b) => JobCard(booking: b)),
            const SizedBox(height: 16),
          ],
          if (active.isNotEmpty) ...[
            _SectionHeader(title: '${tr("inprogress")} ⚡'),
            const SizedBox(height: 8),
            ...active.map((b) => JobCard(booking: b)),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String  title;
  final String? badge;
  final Color?  badgeColor;
  const _SectionHeader({required this.title, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, color: C.text,
      )),
      const Spacer(),
      if (badge != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color:        (badgeColor ?? C.blue).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(badge!, style: TextStyle(
            fontSize: 11, color: badgeColor ?? C.blue,
            fontWeight: FontWeight.w700,
          )),
        ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
// OFFLINE VIEW
// ════════════════════════════════════════════════════════════

class _OfflineView extends ConsumerStatefulWidget {
  const _OfflineView();

  @override
  ConsumerState<_OfflineView> createState() => _OfflineViewState();
}

class _OfflineViewState extends ConsumerState<_OfflineView> {
  bool _busy = false;

  Future<void> _goOnline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(onlineStatusProvider.notifier).toggle();
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      OnlineToggleResult.success => null,
      OnlineToggleResult.locationServiceDisabled =>
          tr('enable_gps_for_jobs'),
      OnlineToggleResult.permissionDenied =>
          tr('allow_location_for_jobs'),
      OnlineToggleResult.writeFailed =>
          tr('status_change_failed'),
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: C.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color:        C.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.wifi_off_rounded, color: C.red, size: 36),
          ),
          const SizedBox(height: 18),
          Text(tr('currently_offline'), style: const TextStyle(
            fontSize: 16, color: C.text, fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 6),
          Text(
            tr('go_online_to_receive'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: C.muted),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _busy ? null : _goOnline,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.power_settings_new_rounded),
            label: Text(tr('go_online')),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.green,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          )),
        ],
      ),
    ));
  }
}

// ✅ [FIX — shared components] _EmptyView/_SkeletonList/_SkeletonCard/
// _Shimmer/_ErrorView ຖືກລຶບອອກ — ໃຊ້ EmptyStateView/SkeletonListTile/
// ErrorStateView ຈາກ lib/widgets/ ແທນ (ດຽວກັນກັບ jobs_tab.dart).

// ════════════════════════════════════════════════════════════
// STATUS BADGE
// ════════════════════════════════════════════════════════════

class StatusBadge extends StatelessWidget {
  final JobStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // ✅ [FIX — Phase 2 status map] ເຄີຍກຳນົດສີສະຖານະຂອງຕົນເອງແຍກຈາກ
    // booking_display_helpers.dart — ຕອນນີ້ດຶງຈາກ AppStatus ບ່ອນດຽວ.
    final color = AppStatus.colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status.label, style: TextStyle(
        fontSize: 10, color: color, fontWeight: FontWeight.w700,
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════
// COUNTDOWN BAR
// ════════════════════════════════════════════════════════════

class CountdownBar extends StatefulWidget {
  final DateTime expiresAt;
  const CountdownBar({super.key, required this.expiresAt});

  @override
  State<CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<CountdownBar> {
  late Timer    _timer;
  late double   _totalSecs;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    final diff = widget.expiresAt.difference(DateTime.now());
    _totalSecs = diff.inSeconds.toDouble().clamp(1, double.infinity);
    _remaining = _calc();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = _calc());
    });
  }

  Duration _calc() {
    final d = widget.expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final secs     = _remaining.inSeconds;
    final progress = (secs / _totalSecs).clamp(0.0, 1.0);
    final color    = secs <= 10 ? C.red : C.green;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.timer_outlined, size: 13, color: color),
        const SizedBox(width: 4),
        Text('${tr("expires_in")} $secs${tr("sec")}',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value:           progress,
          backgroundColor: color.withValues(alpha: 0.15),
          valueColor:      AlwaysStoppedAnimation(color),
          minHeight:       5,
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════
// JOB CARD
// ════════════════════════════════════════════════════════════

class JobCard extends ConsumerWidget {
  final Booking booking;
  const JobCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (booking.isExpired) return const SizedBox.shrink();
    final isPending = booking.status == JobStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isPending
            ? Border.all(
            color: C.sky.withValues(alpha: 0.5), width: 1.5)
            : null,
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) =>
                  JobWorkflowScreen(initialBooking: booking))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color:        C.bg,
                    borderRadius: BorderRadius.circular(14),
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
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: C.text,
                    )),
                    const SizedBox(height: 3),
                    _InfoRow(Icons.person_outline, booking.customerName),
                    _InfoRow(Icons.location_on_outlined, booking.address,
                        overflow: true),
                    _InfoRow(Icons.access_time_outlined,
                        booking.formattedSchedule),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(status: booking.status),
                    const SizedBox(height: 6),
                    Text(booking.formattedPrice, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: C.navy,
                    )),
                  ],
                ),
              ]),
              if (isPending) ...[
                const SizedBox(height: 10),
                CountdownBar(expiresAt: booking.expiresAt),
                const SizedBox(height: 10),
                _PendingActions(booking: booking),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final bool     overflow;
  const _InfoRow(this.icon, this.text, {this.overflow = false});

  @override
  Widget build(BuildContext context) {
    final tw = Text(text,
      style:    const TextStyle(fontSize: 11, color: C.muted),
      overflow: overflow ? TextOverflow.ellipsis : null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(icon, size: 11, color: C.muted),
        const SizedBox(width: 3),
        overflow ? Expanded(child: tw) : Flexible(child: tw),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PENDING ACTIONS
// ✅ [FIX-2] CircularProgressIndicator → _ButtonSkeleton
// ════════════════════════════════════════════════════════════

class _PendingActions extends ConsumerWidget {
  final Booking booking;
  const _PendingActions({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingIds = ref.watch(
      bookingNotifierProvider.select((s) => s.loadingIds),
    );
    final isLoading = loadingIds.contains(booking.id);

    return Row(children: [
      Expanded(child: OutlinedButton(
        onPressed: isLoading ? null : () => _showRejectSheet(context, ref),
        style: OutlinedButton.styleFrom(
          side:    const BorderSide(color: C.red),
          shape:   RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(tr('reject'), style: const TextStyle(
          color: C.red, fontSize: 12, fontWeight: FontWeight.w700,
        )),
      )),
      const SizedBox(width: 10),
      Expanded(child: ElevatedButton(
        onPressed: isLoading ? null : () async {
          final ok = await ref
              .read(bookingNotifierProvider.notifier)
              .accept(booking.id);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr('error')),
              backgroundColor: C.red,
            ));
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: C.green,
          elevation:       0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        // ✅ [FIX-2] ໃຊ້ _ButtonSkeleton ແທນ CircularProgressIndicator
        child: isLoading
            ? const _ButtonSkeleton()
            : Text('${tr("accept_job")} ✓', style: const TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w700)),
      )),
    ]);
  }

  void _showRejectSheet(BuildContext context, WidgetRef ref) {
    final reasons = [
      tr('reject_far'),      tr('reject_schedule'),
      tr('reject_tools'),    tr('reject_health'),
      tr('reject_other'),
    ];
    String? selected;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: C.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text(tr('reject_reason'), style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text,
            )),
            const SizedBox(height: 12),
            ...reasons.map((r) => RadioListTile<String>(
              title: Text(r, style: const TextStyle(
                  fontSize: 14, color: C.text)),
              value: r, groupValue: selected, activeColor: C.navy,
              onChanged: (v) => setS(() => selected = v),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: selected == null ? null : () async {
                final reason      = selected!;
                final scaffoldMsg = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final ok = await ref
                    .read(bookingNotifierProvider.notifier)
                    .reject(booking.id, reason);
                if (!ok) {
                  scaffoldMsg.showSnackBar(SnackBar(
                    content:         Text(tr('error')),
                    backgroundColor: C.red,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: C.red, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(tr('confirm_reject'), style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 15,
              )),
            )),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// BUTTON SKELETON — ໃຊ້ຕອນ isLoading ໃນ button
// ✅ [FIX-2] ແທນ CircularProgressIndicator
// ════════════════════════════════════════════════════════════

class _ButtonSkeleton extends StatefulWidget {
  const _ButtonSkeleton();

  @override
  State<_ButtonSkeleton> createState() => _ButtonSkeletonState();
}

class _ButtonSkeletonState extends State<_ButtonSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize:      MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color:  Colors.white.withValues(alpha: _anim.value),
            shape:  BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 50, height: 10,
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: _anim.value * 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    ),
  );
}