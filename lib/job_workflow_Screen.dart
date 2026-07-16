// ============================================================
// job_workflow_screen.dart — LinTho Provider App
// Job Workflow: Accept → OTW → Arrived → InProgress → Done
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'booking_repository.dart';
import 'fcm_service.dart';

// ── SINGLE BOOKING STREAM ────────────────────────────────────

final singleBookingProvider =
StreamProvider.family<Booking, String>((ref, id) {
  return ref.watch(bookingRepoProvider).watchBooking(id);
});

// ════════════════════════════════════════════════════════════
// JOB WORKFLOW SCREEN
// ════════════════════════════════════════════════════════════

class JobWorkflowScreen extends ConsumerWidget {
  final Booking initialBooking;
  const JobWorkflowScreen({super.key, required this.initialBooking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync =
    ref.watch(singleBookingProvider(initialBooking.id));

    return bookingAsync.when(
      // ✅ RULE: Skeleton loading ແທນ CircularProgressIndicator
      loading: () => _buildScaffold(context, initialBooking, ref,
          isLoading: true),
      error:   (_, __) => _buildScaffold(context, initialBooking, ref),
      data:    (b)     => _buildScaffold(context, b, ref),
    );
  }

  Scaffold _buildScaffold(
      BuildContext context, Booking b, WidgetRef ref,
      {bool isLoading = false}) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: _buildAppBar(context, b),
      body: isLoading
          ? const _WorkflowSkeleton()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _StatusStepper(status: b.status),
          const SizedBox(height: 16),
          _CustomerCard(booking: b),
          const SizedBox(height: 12),
          if (b.status == JobStatus.arrived ||
              b.status == JobStatus.inProgress ||
              b.status == JobStatus.completed)
            _PhotoSection(booking: b),
          if (b.status == JobStatus.inProgress) ...[
            const SizedBox(height: 12),
            _AdditionalChargesSection(booking: b),
          ],
          if (b.status == JobStatus.completed) ...[
            const SizedBox(height: 12),
            _PriceSummary(booking: b),
          ],
          const SizedBox(height: 20),
          if (b.status != JobStatus.completed &&
              b.status != JobStatus.cancelled &&
              b.status != JobStatus.rejected)
            _ActionButton(booking: b),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Booking b) {
    return AppBar(
      backgroundColor: C.navy,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(b.serviceType,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800)),
          Text(b.formattedSchedule,
              style: TextStyle(
                // ✅ RULE: withValues(alpha:) ແທນ withOpacity
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone_outlined,
              color: Colors.white, size: 22),
          onPressed: () =>
              launchUrl(Uri.parse('tel:${b.customerPhone}')),
        ),
        IconButton(
          icon: const Icon(Icons.navigation_outlined,
              color: Colors.white, size: 22),
          onPressed: () => launchUrl(Uri.parse(
              'https://www.google.com/maps/dir/?api=1'
                  '&destination=${b.location.latitude},'
                  '${b.location.longitude}')),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// SKELETON — ໃຊ້ຕອນ loading
// ════════════════════════════════════════════════════════════

class _WorkflowSkeleton extends StatefulWidget {
  const _WorkflowSkeleton();

  @override
  State<_WorkflowSkeleton> createState() => _WorkflowSkeletonState();
}

class _WorkflowSkeletonState extends State<_WorkflowSkeleton>
    with SingleTickerProviderStateMixin {
  // ✅ RULE: dispose() ທຸກ controller
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
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

  Widget _box(double w, double h, {double radius = 10}) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      // ✅ RULE: withValues(alpha:) ແທນ withOpacity
      color: C.muted.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Stepper skeleton
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) => Column(children: [
                _box(32, 32, radius: 16),
                const SizedBox(height: 6),
                _box(28, 8),
              ])),
            ),
          ),
          const SizedBox(height: 16),
          // Customer card skeleton
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              _box(44, 44, radius: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(120, 14),
                  const SizedBox(height: 8),
                  _box(80, 11),
                  const SizedBox(height: 6),
                  _box(160, 11),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 12),
          // Action button skeleton
          _box(double.infinity, 54, radius: 16),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// STATUS STEPPER
// ════════════════════════════════════════════════════════════

class _StatusStepper extends StatelessWidget {
  final JobStatus status;
  const _StatusStepper({required this.status});

  static List<(JobStatus, String, String)> get _steps => [
    (JobStatus.accepted,   '✓',  tr('accepted')),
    (JobStatus.onTheWay,   '🚗', tr('step_traveling')),
    (JobStatus.arrived,    '📍', tr('step_arrived_short')),
    (JobStatus.inProgress, '🔧', tr('step_working')),
    (JobStatus.completed,  '✅', tr('completed')),
  ];

  int get _currentIdx {
    for (int i = 0; i < _steps.length; i++) {
      if (_steps[i].$1 == status) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cur = _currentIdx;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Row(children: List.generate(_steps.length, (i) {
          final done  = i <= cur;
          final isCur = i == cur;
          final (_, emoji, label) = _steps[i];
          return Expanded(child: Column(children: [
            Row(children: [
              if (i > 0)
                Expanded(child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 3,
                  decoration: BoxDecoration(
                    color: done ? C.navy : C.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width:  isCur ? 40 : 32,
                height: isCur ? 40 : 32,
                decoration: BoxDecoration(
                  color: done ? C.navy : C.border,
                  shape: BoxShape.circle,
                  boxShadow: isCur ? [BoxShadow(
                    // ✅ RULE: withValues(alpha:) ແທນ withOpacity
                      color: C.navy.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3))] : [],
                ),
                child: Center(child: Text(done ? emoji : '',
                    style: TextStyle(fontSize: isCur ? 18 : 14))),
              ),
              if (i < _steps.length - 1)
                Expanded(child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 3,
                  decoration: BoxDecoration(
                    color: i < cur ? C.navy : C.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            ]),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
                fontSize: 9,
                fontWeight: isCur ? FontWeight.w800 : FontWeight.w500,
                color: done ? C.navy : C.muted)),
          ]));
        })),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            color: C.navy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _stepLabel(status),
            style: const TextStyle(
                fontSize: 13, color: C.navy,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  String _stepLabel(JobStatus s) => switch (s) {
    JobStatus.accepted   => tr('workflow_status_accepted'),
    JobStatus.onTheWay   => tr('workflow_status_on_the_way'),
    JobStatus.arrived    => tr('workflow_status_arrived'),
    JobStatus.inProgress => tr('workflow_status_in_progress'),
    JobStatus.completed  => tr('workflow_status_completed'),
    _                    => '',
  };
}

// ════════════════════════════════════════════════════════════
// CUSTOMER CARD
// ════════════════════════════════════════════════════════════

class _CustomerCard extends StatelessWidget {
  final Booking booking;
  const _CustomerCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            backgroundColor: C.navy.withValues(alpha: 0.1),
            backgroundImage: b.customerPhotoUrl != null
                ? NetworkImage(b.customerPhotoUrl!) : null,
            child: b.customerPhotoUrl == null
                ? Text(b.customerName[0].toUpperCase(),
                style: const TextStyle(
                    color: C.navy, fontWeight: FontWeight.w800,
                    fontSize: 16))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.customerName, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: C.text)),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.phone_outlined,
                    size: 12, color: C.muted),
                const SizedBox(width: 4),
                Text(b.customerPhone, style: const TextStyle(
                    fontSize: 12, color: C.muted)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 12, color: C.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(b.address,
                    style: const TextStyle(
                        fontSize: 12, color: C.muted),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ],
          )),
          Column(children: [
            _QuickBtn(icon: Icons.phone, color: C.green,
                onTap: () => launchUrl(
                    Uri.parse('tel:${b.customerPhone}'))),
            const SizedBox(height: 8),
            _QuickBtn(icon: Icons.navigation_rounded, color: C.blue,
                onTap: () => launchUrl(Uri.parse(
                    'https://www.google.com/maps/dir/?api=1'
                        '&destination=${b.location.latitude},'
                        '${b.location.longitude}'))),
          ]),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: C.bg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Text(b.serviceEmoji,
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(b.serviceType,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: C.text))),
            Text(b.formattedPrice, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800,
                color: C.navy)),
          ]),
        ),
      ]),
    );
  }
}

// ✅ RULE: InkWell + Material ແທນ GestureDetector
class _QuickBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            // ✅ RULE: withValues(alpha:) ແທນ withOpacity
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// BEFORE / AFTER PHOTOS
// ════════════════════════════════════════════════════════════

class _PhotoSection extends ConsumerStatefulWidget {
  final Booking booking;
  const _PhotoSection({required this.booking});

  @override
  ConsumerState<_PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends ConsumerState<_PhotoSection> {
  bool _uploadingBefore = false;
  bool _uploadingAfter  = false;

  Future<void> _pickPhoto({required bool isBefore}) async {
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.camera, imageQuality: 80);
      // ✅ RULE: mounted check ຫຼັງ async
      if (picked == null || !mounted) return;

      setState(() => isBefore
          ? _uploadingBefore = true
          : _uploadingAfter  = true);

      await ref.read(bookingRepoProvider).uploadJobPhoto(
          widget.booking.id, File(picked.path),
          isBefore: isBefore);
    } catch (e) {
      // ✅ RULE: mounted check ຫຼັງ async
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr("upload_failed")}: $e'),
          backgroundColor: C.red));
    } finally {
      // ✅ RULE: mounted check ຫຼັງ async
      if (mounted) {
        setState(() => isBefore
            ? _uploadingBefore = false
            : _uploadingAfter  = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.photo_camera_outlined,
                  color: C.navy, size: 18),
              const SizedBox(width: 8),
              Text(tr('before_after_photos'), style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: C.text)),
              const Spacer(),
              if (b.beforePhotoUrl == null || b.afterPhotoUrl == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    // ✅ RULE: withValues(alpha:) ແທນ withOpacity
                      color: C.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('required_badge'), style: const TextStyle(
                      fontSize: 10, color: C.orange,
                      fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _PhotoSlot(
                label: tr('photo_before'), emoji: '📷',
                imageUrl: b.beforePhotoUrl,
                uploading: _uploadingBefore,
                onTap: b.status != JobStatus.completed
                    ? () => _pickPhoto(isBefore: true) : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: _PhotoSlot(
                label: tr('photo_after'), emoji: '✨',
                imageUrl: b.afterPhotoUrl,
                uploading: _uploadingAfter,
                onTap: (b.status == JobStatus.inProgress ||
                    b.status == JobStatus.completed)
                    ? () => _pickPhoto(isBefore: false) : null,
              )),
            ]),
            if (b.beforePhotoUrl == null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.info_outline, size: 13, color: C.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    tr('before_after_hint'),
                    style: const TextStyle(fontSize: 11, color: C.muted))),
              ]),
            ],
          ]),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String        label;
  final String        emoji;
  final String?       imageUrl;
  final bool          uploading;
  final VoidCallback? onTap;

  const _PhotoSlot({
    required this.label, required this.emoji,
    this.imageUrl, required this.uploading, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ RULE: InkWell + Material ແທນ GestureDetector
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: imageUrl != null ? C.navy : C.border,
              width: imageUrl != null ? 2 : 1.5,
            ),
            image: imageUrl != null
                ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover)
                : null,
          ),
          // ✅ RULE: Skeleton loading ແທນ CircularProgressIndicator
          child: uploading
              ? const _PhotoUploadingSkeleton()
              : imageUrl == null
              ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji,
                    style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: C.muted)),
                const SizedBox(height: 2),
                Text(tr('tap_to_photo'), style: const TextStyle(
                    fontSize: 10, color: C.muted)),
              ])
              : Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: C.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check,
                  color: Colors.white, size: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ RULE: Skeleton ສຳລັບຕອນ upload ຮູບ
class _PhotoUploadingSkeleton extends StatefulWidget {
  const _PhotoUploadingSkeleton();

  @override
  State<_PhotoUploadingSkeleton> createState() =>
      _PhotoUploadingSkeletonState();
}

class _PhotoUploadingSkeletonState extends State<_PhotoUploadingSkeleton>
    with SingleTickerProviderStateMixin {
  // ✅ RULE: dispose() ທຸກ controller
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.8).animate(_anim);
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
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            // ✅ RULE: withValues(alpha:) ແທນ withOpacity
            color: C.navy.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 60, height: 10,
          decoration: BoxDecoration(
            color: C.muted.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ADDITIONAL CHARGES
// ════════════════════════════════════════════════════════════

class _AdditionalChargesSection extends ConsumerWidget {
  final Booking booking;
  const _AdditionalChargesSection({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;

    if (b.additionalCharges != null) {
      final approved = b.additionalChargesApproved;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: approved ? C.green : C.orange, width: 1.5),
        ),
        child: Row(children: [
          Icon(
            approved
                ? Icons.check_circle
                : Icons.pending_outlined,
            color: approved ? C.green : C.orange, size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approved
                    ? tr('charges_approved')
                    : tr('charges_pending'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: approved ? C.green : C.orange),
              ),
              const SizedBox(height: 2),
              Text(
                '₭${b.additionalCharges!.toStringAsFixed(0)}'
                    '  ·  ${b.additionalChargesNote ?? ''}',
                style: const TextStyle(fontSize: 12, color: C.muted),
              ),
            ],
          )),
        ]),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => _showChargesSheet(context, ref),
      icon: const Icon(Icons.add_circle_outline, size: 18),
      label: Text(tr('add_charges')),
      style: OutlinedButton.styleFrom(
        foregroundColor: C.orange,
        side: const BorderSide(color: C.orange),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
      ),
    );
  }

  void _showChargesSheet(BuildContext context, WidgetRef ref) {
    // ✅ RULE: dispose() — ຈັດການໃນ closure ກ່ອນ pop
    final amountCtrl = TextEditingController();
    final noteCtrl   = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(24))),
      // ✅ fix: dispose() ສະເໝີຫຼັງ sheet ປິດ (ບໍ່ວ່າ submit ຫຼື swipe ປິດ)
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          Text(tr('additional_charges_title'), style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900,
              color: C.text)),
          const SizedBox(height: 4),
          Text(tr('customer_will_get_confirm_notif'),
              style: const TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 20),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w800, color: C.text),
            decoration: InputDecoration(
              labelText: tr('amount_kip_label'),
              prefixIcon: const Icon(Icons.attach_money,
                  color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                  const BorderSide(color: C.sky, width: 2)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            style: const TextStyle(fontSize: 14, color: C.text),
            decoration: InputDecoration(
              labelText: tr('charge_reason_hint'),
              prefixIcon: const Icon(Icons.edit_outlined,
                  color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                  const BorderSide(color: C.sky, width: 2)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(
                    amountCtrl.text.replaceAll(',', ''));
                if (amt == null || amt <= 0) return;
                final ok = await ref
                    .read(bookingNotifierProvider.notifier)
                    .requestAdditionalCharges(
                    booking.id, amt, noteCtrl.text.trim());

                if (ok) {
                  await NotificationSender.additionalCharges(
                    customerId: booking.customerId,
                    bookingId:  booking.id,
                    amount:     amt,
                    note:       noteCtrl.text.trim(),
                  );
                }

                // ✅ RULE: mounted check ຫຼັງ async
                if (!context.mounted) return;

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? tr('charge_request_sent')
                        : '❌ ${tr("error")}'),
                    backgroundColor: ok ? C.green : C.red));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: C.orange, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(tr('send_request'), style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: 16)),
            ),
          ),
        ]),
      ),
      // ✅ fix: dispose() ສະເໝີຫຼັງ sheet ປິດ (submit, swipe, ຫຼື back ກໍ່ໄດ້)
    ).whenComplete(() {
      amountCtrl.dispose();
      noteCtrl.dispose();
    });
  }
}

// ════════════════════════════════════════════════════════════
// PRICE SUMMARY
// ════════════════════════════════════════════════════════════

class _PriceSummary extends StatelessWidget {
  final Booking booking;
  const _PriceSummary({required this.booking});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final hasExtra = b.additionalCharges != null &&
        b.additionalCharges! > 0 &&
        b.additionalChargesApproved;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [C.navy, C.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('price_summary_title'), style: const TextStyle(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _PriceRow(tr('base_price_label'), b.formattedPrice),
            if (hasExtra)
              _PriceRow(
                  '${tr("extra_charge_label")} (${b.additionalChargesNote ?? ''})',
                  '₭${b.additionalCharges!.toStringAsFixed(0)}'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white30),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('grand_total_label'), style: const TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800)),
                  Text(
                    '₭${b.totalPrice.toStringAsFixed(0).replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                            (m) => '${m[1]},')}',
                    style: const TextStyle(
                        color: C.yellow, fontSize: 20,
                        fontWeight: FontWeight.w900),
                  ),
                ]),
          ]),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  const _PriceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(
              // ✅ RULE: withValues(alpha:) ແທນ withOpacity
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13)),
            Text(value, style: const TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w700)),
          ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PRIMARY ACTION BUTTON
// ════════════════════════════════════════════════════════════

class _ActionButton extends ConsumerWidget {
  final Booking booking;
  const _ActionButton({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b         = booking;
    final isLoading = ref.watch(bookingNotifierProvider).isLoading;

    final needsAfterPhoto = b.status == JobStatus.inProgress &&
        b.afterPhotoUrl == null;

    final (label, icon, color, nextStatus) = _getAction(b.status);
    if (label == null) return const SizedBox.shrink();

    return Column(children: [
      if (needsAfterPhoto)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            // ✅ RULE: withValues(alpha:) ແທນ withOpacity
              color: C.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: C.orange.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.warning_amber_outlined,
                color: C.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
                tr('please_take_after_photo'),
                style: const TextStyle(
                    color: C.orange, fontSize: 13,
                    fontWeight: FontWeight.w600))),
          ]),
        ),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (isLoading || needsAfterPhoto)
              ? null
              : () => _onPressed(context, ref, nextStatus!),
          // ✅ RULE: Skeleton loading ແທນ CircularProgressIndicator
          icon: isLoading
              ? const _BtnLoadingSkeleton()
              : Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: needsAfterPhoto ? C.muted : color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    ]);
  }

  (String?, IconData?, Color?, JobStatus?) _getAction(JobStatus s) =>
      switch (s) {
        JobStatus.accepted   => (tr('action_start_travel'),
        Icons.directions_car_outlined, C.blue,  JobStatus.onTheWay),
        JobStatus.onTheWay   => (tr('action_arrived'),
        Icons.place_outlined,          C.orange, JobStatus.arrived),
        JobStatus.arrived    => (tr('action_start_work'),
        Icons.build_outlined,          C.navy,   JobStatus.inProgress),
        JobStatus.inProgress => (tr('action_complete_job'),
        Icons.check_circle_outline,    C.green,  JobStatus.completed),
        _                    => (null, null, null, null),
      };

  Future<void> _onPressed(BuildContext context, WidgetRef ref,
      JobStatus nextStatus) async {
    final b = booking;

    if (nextStatus == JobStatus.completed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tr('confirm_complete_title'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(tr('confirm_complete_body')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('back'),
                    style: const TextStyle(color: C.muted))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: C.green, elevation: 0),
              child: Text(tr('confirm_check_emoji'),
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final ok = await ref
        .read(bookingNotifierProvider.notifier)
        .updateStatus(b.id, nextStatus);

    // ✅ RULE: mounted check ຫຼັງ async
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('error_try_again')),
          backgroundColor: C.red));
      return;
    }

    // ✅ RULE: mounted check ຫຼັງ async
    if (context.mounted && nextStatus == JobStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('job_complete_earnings_added')),
          backgroundColor: C.green,
          duration: const Duration(seconds: 3)));
      Navigator.pop(context);
    }
  }
}

/// ✅ RULE: Skeleton loading ສຳລັບ button loading state
class _BtnLoadingSkeleton extends StatefulWidget {
  const _BtnLoadingSkeleton();

  @override
  State<_BtnLoadingSkeleton> createState() => _BtnLoadingSkeletonState();
}

class _BtnLoadingSkeletonState extends State<_BtnLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  // ✅ RULE: dispose() ທຸກ controller
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
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
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          // ✅ RULE: withValues(alpha:) ແທນ withOpacity
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}