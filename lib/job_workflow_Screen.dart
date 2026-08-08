// ============================================================
// job_workflow_screen.dart — LinTho Provider App
// Job Workflow: Accept → OTW → Arrived → InProgress → Done
// ============================================================

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'booking_provider.dart';
import 'booking_repository.dart';
import 'chat_screen.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/status_stepper.dart' as shared;
import 'widgets/pulsing_fade.dart';

// 🔒 [AUDIT PROV-NEW-4 / 2026-08-06] launchUrl('tel:...') ບໍ່ເຄີຍກວດ
// canLaunchUrl() ກ່ອນຢູ່ 2 ບ່ອນໃນໄຟລ໌ນີ້ (AppBar + _CustomerCard) — ຕ່າງຈາກ
// match_screen.dart's ຝັ່ງລູກຄ້າທີ່ກວດຢູ່ແລ້ວ. ຄວາມສ່ຽງຕ່ຳ (AndroidManifest.xml
// ມີ DIAL intent query ຢູ່ແລ້ວ) ແຕ່ຄວນສອດຄ່ອງກັນ.
Future<void> _callTel(String phone) async {
  final uri = Uri.parse('tel:$phone');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

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
      backgroundColor: C.background,
      appBar: _buildAppBar(context, b),
      body: isLoading
          ? const _WorkflowSkeleton()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _StatusStepper(status: b.status),
          const SizedBox(height: 16),
          _CustomerCard(booking: b),
          // ✅ [FIX ME-5] ຮູບໜ້າວຽກທີ່ລູກຄ້າອັບໂຫລດຕອນຈອງ — ໃຫ້ຊ່າງເຫັນກ່ອນໄປເຮັດວຽກ
          if (b.jobPhotoUrl != null && b.jobPhotoUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CustomerJobPhoto(url: b.jobPhotoUrl!),
          ],
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
              b.status != JobStatus.rejected) ...[
            _ActionButton(booking: b),
            // 🔒 [AUDIT PROV-NEW-5 / 2026-08-06] ສຳລັບວຽກທີ່ຍັງ 'pending'
            // (ຈອງໂດຍກົງໃສ່ຊ່າງຄົນນີ້, ຍັງບໍ່ທັນຮັບ) home_tab.dart's
            // _PendingActions (Reject/Accept) ຄືທາງເລືອກທີ່ຖືກຕ້ອງແລ້ວຢູ່ Home
            // tab — ປຸ່ມ "ຍົກເລີກ" ນີ້ຄືກັນຢູ່ໜ້ານີ້ຊ້ຳກັນ ບັນທຶກເປັນ terminal
            // state ຄົນລະຄ່າ (cancelled ບໍ່ແມ່ນ rejected) ສຳລັບການກະທຳດຽວກັນ.
            // ຄ່ອນຢູ່ໜ້ານີ້ສະເພາະຫຼັງຮັບງານແລ້ວ (accepted ຂຶ້ນໄປ).
            if (b.status != JobStatus.pending) ...[
              const SizedBox(height: 10),
              _CancelJobButton(booking: b),
            ],
          ],
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
        // 🔒 [AUDIT UI-14 / 2026-08-02 — Low, fresh re-audit] these two
        // IconButtons previously had no tooltip/Semantics label — unlike the
        // identical call/navigate actions duplicated lower on this same
        // screen (AppIconButton, ~line 442), which already enforce this.
        IconButton(
          icon: const Icon(Icons.phone_outlined,
              color: Colors.white, size: 22),
          tooltip: tr('call_semantic'),
          onPressed: () => _callTel(b.contactPhone),
        ),
        IconButton(
          icon: const Icon(Icons.navigation_outlined,
              color: Colors.white, size: 22),
          tooltip: tr('navigate_semantic'),
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

// ✅ [FIX — shared StatusStepper] ນີ້ເຄີຍເປັນ implementation ອິດສະຫຼະຈາກ
// tracking_screen.dart's _StatusSteps (ຝັ່ງລູກຄ້າ) ທັງໆທີ່ສະແດງຄວາມຄືບໜ້າ
// ວຽກດຽວກັນ — ຕອນນີ້ທັງສອງໜ້າຈໍໃຊ້ lib/widgets/status_stepper.dart ຮ່ວມກັນ.
class _StatusStepper extends StatelessWidget {
  final JobStatus status;
  const _StatusStepper({required this.status});

  static const _order = [
    JobStatus.accepted, JobStatus.onTheWay, JobStatus.arrived,
    JobStatus.inProgress, JobStatus.completed,
  ];

  static List<shared.StatusStep> get _steps => [
    shared.StatusStep(icon: Icons.check_rounded,            label: tr('accepted')),
    shared.StatusStep(icon: Icons.directions_car_rounded,    label: tr('step_traveling')),
    shared.StatusStep(icon: Icons.place_rounded,             label: tr('step_arrived_short')),
    shared.StatusStep(icon: Icons.build_rounded,             label: tr('step_working')),
    shared.StatusStep(icon: Icons.check_circle_rounded,      label: tr('completed')),
  ];

  int get _currentIdx {
    final i = _order.indexOf(status);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        shared.StatusStepper(
          steps: _steps,
          currentIndex: _currentIdx,
          axis: Axis.horizontal,
          activeColor: C.navy,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
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

class _CustomerCard extends ConsumerWidget {
  final Booking booking;
  const _CustomerCard({required this.booking});

  Future<void> _openChat(BuildContext context, WidgetRef ref, Booking b) async {
    final provider = FirebaseAuth.instance.currentUser;
    if (provider == null) return;
    final providerName =
        ref.read(profileStreamProvider).valueOrNull?.displayName ??
            provider.displayName ?? '';
    final chatId = await ChatService.createOrGetChat(
      bookingId:    b.id,
      customerId:   b.customerId,
      customerName: b.customerName,
      providerId:   provider.uid,
      providerName: providerName,
      serviceName:  b.serviceType,
    );
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
      chatId:         chatId,
      otherName:      b.customerName,
      bookingService: b.serviceType,
      receiverId:     b.customerId,
      receiverName:   b.customerName,
    )));
  }

  Future<void> _copyPhone(BuildContext context, String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('phone_copied_msg')), backgroundColor: C.success));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                Text(b.contactPhone, style: const TextStyle(
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
              // ✅ [FIX ME-5] ຮ່ອມ/ຈຸດສັງເກດ ແລະ ໝາຍເຫດເຖິງຊ່າງ — ລູກຄ້າໃສ່ມາ
              // ຕອນຈອງແຕ່ບໍ່ເຄີຍຖືກສະແດງໃຫ້ຊ່າງເຫັນມາກ່ອນ
              if (b.landmark.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.signpost_outlined,
                      size: 12, color: C.muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(b.landmark,
                      style: const TextStyle(
                          fontSize: 12, color: C.muted),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
              if (b.specialInstructions.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 12, color: C.orange),
                  const SizedBox(width: 4),
                  Expanded(child: Text(b.specialInstructions,
                      style: const TextStyle(
                          fontSize: 12, color: C.orange,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ],
          )),
          // ✅ [FIX H12] AppIconButton (lib/widgets/app_icon_button.dart) ຖືກ
          // ສ້າງມາແທນ _QuickBtn ນີ້ໂດຍສະເພາະ (ຄຳເຫັນຫົວໄຟລ໌ຂອງມັນອ້າງເຖິງໄຟລ໌
          // ນີ້ໂດຍກົງ) — ບັງຄັບ 44dp tap target ຂັ້ນຕ່ຳ ແລະ Semantics/tooltip,
          // ຕ່າງຈາກ _QuickBtn ເກົ່າ (38×38px, ບໍ່ມີ label ໃດເລີຍ).
          Column(children: [
            AppIconButton(icon: Icons.phone, color: C.green,
                label: tr('call_semantic'),
                onTap: () => _callTel(b.contactPhone)),
            const SizedBox(height: 8),
            AppIconButton(icon: Icons.navigation_rounded, color: C.blue,
                label: tr('navigate_semantic'),
                onTap: () => launchUrl(Uri.parse(
                    'https://www.google.com/maps/dir/?api=1'
                        '&destination=${b.location.latitude},'
                        '${b.location.longitude}'))),
          ]),
        ]),
        const SizedBox(height: 10),
        // ✅ [Phone-verified booking] ສົນທະນາ + ຄັດລອກເບີ — ໂທຫາລູກຄ້າ (Call)
        // ຢູ່ Column ຂ້າງເທິງແລ້ວ (ໃກ້ avatar, ໃຊ້ຫຼາຍທີ່ສຸດ)
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _openChat(context, ref, b),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: Text(tr('chat_customer_semantic'), style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _copyPhone(context, b.contactPhone),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(tr('copy_phone_semantic'), style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: C.bg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            // ✅ [FIX H11] Icon ຈາກ category ແທນ raw emoji ທີ່ເກັບໄວ້ໃນ doc
            Icon(b.serviceIcon, size: 22, color: C.navy),
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

// ✅ [FIX ME-5] ຮູບໜ້າວຽກ (ທາງເລືອກ) ທີ່ລູກຄ້າອັບໂຫລດຕອນຈອງ
class _CustomerJobPhoto extends StatelessWidget {
  final String url;
  const _CustomerJobPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // 🔒 [AUDIT H-5 / 2026-07-27] cacheWidth/Height — thumbnail 56x56
          child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover,
              cacheWidth: 112, cacheHeight: 112),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('customer_job_photo_label'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: C.text))),
      ]),
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
      // 🔒 [AUDIT H-5 / 2026-07-27] ກ່ອນໜ້ານີ້ບໍ່ມີ maxWidth/maxHeight — ຮູບ
      // ກ່ອນ/ຫຼັງວຽກຈາກກ້ອງຖືກອັບໂຫລດເຕັມຄວາມລະອຽດ ທັງໆທີ່ສະແດງເປັນ thumbnail
      // ນ້ອຍ (56x56) ໃນ job workflow — ຈຳກັດ 1600px ຄືກັນກັບ jobPhotoUrl ໃນ
      // booking_form_screen.dart (ພຽງພໍສຳລັບ before/after photo, ຫຼຸດຂະໜາດ
      // ອັບໂຫລດ/ຄວາມສ່ຽງ OOM ຕອນ decode ຢ່າງຫຼວງຫຼາຍ).
      final picked = await ImagePicker().pickImage(
          source: ImageSource.camera, imageQuality: 80,
          maxWidth: 1600, maxHeight: 1600);
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
                label: tr('photo_before'), icon: Icons.camera_alt_outlined,
                imageUrl: b.beforePhotoUrl,
                uploading: _uploadingBefore,
                onTap: b.status != JobStatus.completed
                    ? () => _pickPhoto(isBefore: true) : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: _PhotoSlot(
                label: tr('photo_after'), icon: Icons.auto_awesome_outlined,
                imageUrl: b.afterPhotoUrl,
                uploading: _uploadingAfter,
                // 🔒 [AUDIT PROV-NEW-2 / 2026-08-06] ກ່ອນໜ້ານີ້ຍັງ tap ໄດ້
                // ຫຼັງ completed — Cloudinary upload ຈະສຳເລັດ (ເສຍຄ່າ storage,
                // ຮູບບໍ່ຖືກເຊື່ອມກັບ booking) ແຕ່ Firestore write ຈະຖືກ
                // firestore.rules' isValidProviderChargesRequest() reject ຢ່າງ
                // ບໍ່ມີເງື່ອນໄຂເມື່ອ status=='completed' (permission-denied ທັນທີ,
                // ບໍ່ວ່າ field ໃດຖືກແກ້). ຕອນນີ້ລ໋ອກໄວ້ຄືກັນກັບ before-photo
                // (ອະນຸຍາດສະເພາະ inProgress).
                onTap: b.status == JobStatus.inProgress
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
  final IconData       icon;
  final String?       imageUrl;
  final bool          uploading;
  final VoidCallback? onTap;

  const _PhotoSlot({
    required this.label, required this.icon,
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
                Icon(icon, size: 28, color: C.muted),
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
    // 🔒 [AUDIT EDGE-2 / 2026-08-06] ປຸ່ມນີ້ບໍ່ເຄີຍຖືກປິດ/disable ໃນຂະນະທີ່
    // await requestAdditionalCharges() ຍັງບໍ່ resolve — sheet ຖືກ pop ຫຼັງ await
    // ເທົ່ານັ້ນ, ຕ່າງຈາກ pattern ທີ່ປອດໄພກວ່າໃນ home_tab.dart's reject sheet
    // (pop ກ່ອນ await). ຖ້າກົດຊ້ຳໄວໆ (ອິນເຕີເນັດຊ້າ) requestAdditionalCharges()
    // ຈະຖືກເອີ້ນ 2 ຄັ້ງ — additionalChargesRound ຖືກ increment ຊ້ຳ ແລະ
    // ລູກຄ້າໄດ້ຮັບ push notification ຊ້ຳກັນ 2 ຄັ້ງຕໍ່ 1 ຄຳຮ້ອງຂໍ. ຕອນນີ້ໃຊ້
    // StatefulBuilder ເພື່ອ track ສະຖານະ sending ໃນ local, ປິດປຸ່ມໄວ້ໃນຂະນະ
    // ກຳລັງສົ່ງ.
    bool sending = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(24))),
      // ✅ fix: dispose() ສະເໝີຫຼັງ sheet ປິດ (ບໍ່ວ່າ submit ຫຼື swipe ປິດ)
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
              onPressed: sending ? null : () async {
                final amt = double.tryParse(
                    amountCtrl.text.replaceAll(',', ''));
                if (amt == null || amt <= 0) return;
                setSheetState(() => sending = true);
                // 🔒 [AUDIT M-1 / 2026-07-27] ລຶບການເອີ້ນສົ່ງ additional-charges
                // notification ອອກຈາກໜ້ານີ້ — BookingRepository.requestAdditionalCharges()
                // (booking_repository.dart) ສົ່ງ notification ນີ້ຢູ່ແລ້ວພາຍໃນຕົວ
                // ມັນເອງ, ການເອີ້ນຊ້ຳຢູ່ນີ້ເຮັດໃຫ້ລູກຄ້າໄດ້ຮັບ push ຊ້ຳສອງເທື່ອຕໍ່ 1
                // ຄຳຮ້ອງຂໍ.
                final ok = await ref
                    .read(bookingNotifierProvider.notifier)
                    .requestAdditionalCharges(
                    booking.id, amt, noteCtrl.text.trim());

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
              child: sending
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('send_request'), style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ),
          ),
        ]),
        ),
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
    // 🔒 [AUDIT CRIT-1] status == inProgress ບໍ່ໄດ້ໝາຍຄວາມວ່າພ້ອມປິດງານໄດ້ເລີຍ —
    // updateStatus(completed) ຈະ throw ຖ້າ paymentStatus != 'paid' (booking_
    // repository.dart). ກ່ອນໜ້ານີ້ບໍ່ມີ UI ໃດເອີ້ນ confirmPaymentReceived() ເລີຍ
    // ເຮັດໃຫ້ "ສຳເລັດວຽກ" throw ຕະຫຼອດເວລາ. ຕອນນີ້ສະແດງ step "ຢືນຢັນຮັບເງິນ"
    // ກ່ອນ ແລ້ວຈຶ່ງໃຫ້ "ສຳເລັດວຽກ" ປາກົດ.
    final needsPaymentConfirm = b.status == JobStatus.inProgress &&
        !needsAfterPhoto &&
        b.paymentStatus != 'paid';

    final (label, icon, color, nextStatus, isPaymentStep) =
        _getAction(b.status, needsPaymentConfirm: needsPaymentConfirm);
    if (label == null) return const SizedBox.shrink();

    final blocked = isLoading || needsAfterPhoto;

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
          onPressed: blocked
              ? null
              : () => isPaymentStep
                  ? _onConfirmPayment(context, ref)
                  : _onPressed(context, ref, nextStatus!),
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

  (String?, IconData?, Color?, JobStatus?, bool) _getAction(JobStatus s,
      {required bool needsPaymentConfirm}) {
    if (s == JobStatus.inProgress && needsPaymentConfirm) {
      return (tr('action_confirm_payment'),
          Icons.payments_outlined, C.teal, null, true);
    }
    return switch (s) {
      JobStatus.accepted   => (tr('action_start_travel'),
      Icons.directions_car_outlined, C.blue,  JobStatus.onTheWay, false),
      JobStatus.onTheWay   => (tr('action_arrived'),
      Icons.place_outlined,          C.orange, JobStatus.arrived, false),
      JobStatus.arrived    => (tr('action_start_work'),
      Icons.build_outlined,          C.navy,   JobStatus.inProgress, false),
      JobStatus.inProgress => (tr('action_complete_job'),
      Icons.check_circle_outline,    C.green,  JobStatus.completed, false),
      _                    => (null, null, null, null, false),
    };
  }

  // ✅ [FIX CRIT-1] ຢືນຢັນຮັບເງິນ — ຕ້ອງເອີ້ນກ່ອນ "ສຳເລັດວຽກ" ຈຶ່ງຈະຜ່ານໄດ້
  Future<void> _onConfirmPayment(BuildContext context, WidgetRef ref) async {
    final b = booking;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('confirm_payment_title'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(tr('confirm_payment_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('back'),
                  style: const TextStyle(color: C.muted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: C.teal, elevation: 0),
            child: Text(tr('confirm_check_emoji'),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await ref
        .read(bookingNotifierProvider.notifier)
        .confirmPayment(b.id);

    // ✅ RULE: mounted check ຫຼັງ async
    if (!context.mounted) return;

    // 🔒 [AUDIT PROV-NEW-3 / 2026-08-06] BookingNotifier ຈັບ error message
    // ສະເພາະເຈາະຈົງໄວ້ຢູ່ແລ້ວ (ຕົວຢ່າງ: "ກະລຸນາຢືນຢັນການຮັບເງິນກ່ອນປິດງານ") ແຕ່
    // ບໍ່ເຄີຍຖືກອ່ານມາສະແດງ — ຜູ້ໃຊ້ເຫັນແຕ່ "ເກີດຂໍ້ຜິດພາດ, ລອງໃໝ່" ທົ່ວໄປ ໂດຍບໍ່ຮູ້
    // ສາເຫດແທ້.
    final errMsg = ok ? null : ref.read(bookingNotifierProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? tr('payment_confirmed_snackbar')
                          : (errMsg ?? tr('error_try_again'))),
        backgroundColor: ok ? C.teal : C.red));
  }

  Future<void> _onPressed(BuildContext context, WidgetRef ref,
      JobStatus nextStatus) async {
    final b = booking;

    if (nextStatus == JobStatus.completed) {
      // 🔒 [AUDIT PROV-4 / 2026-07-30] badge "ຈຳເປັນ" (required_badge) ຂ້າງເທິງ
      // ສະແດງເມື່ອຮູບກ່ອນ/ຫຼັງບໍ່ຄົບ ແຕ່ບໍ່ເຄີຍມີຫຍັງບັງຄັບແທ້ — provider ກົດ
      // "ສຳເລັດວຽກ" ໄດ້ໂດຍບໍ່ມີຮູບກ່ອນເລີຍ. ບັງຄັບຢູ່ນີ້ແທ້: ຕ້ອງມີ beforePhotoUrl
      // ກ່ອນຈຶ່ງອະນຸຍາດເປີດ dialog ຢືນຢັນສຳເລັດວຽກ.
      if (b.beforePhotoUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('before_photo_required_error')),
            backgroundColor: C.red));
        return;
      }
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
      // 🔒 [AUDIT PROV-NEW-3 / 2026-08-06] ເບິ່ງຄໍາເຫັນຢູ່ _onConfirmPayment
      // ຂ້າງເທິງ — ອ່ານເຫດຜົນສະເພາະເຈາະຈົງຈາກ state.error ແທນຂໍ້ຄວາມທົ່ວໄປ.
      final errMsg = ref.read(bookingNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errMsg ?? tr('error_try_again')),
          backgroundColor: C.red));
      return;
    }

    // ✅ RULE: mounted check ຫຼັງ async
    if (context.mounted && nextStatus == JobStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('job_complete_earnings_added')),
          backgroundColor: C.success,
          duration: const Duration(seconds: 3)));
      Navigator.pop(context);
    }
  }
}

// ════════════════════════════════════════════════════════════
// CANCEL JOB — [AUDIT PROV-2 / 2026-07-30]
// ຊ່າງທີ່ຮັບງານໄປແລ້ວແຕ່ເຮັດຕໍ່ບໍ່ໄດ້ (ລົດເສຍ, ສຸກເສີນ) ຕ້ອງມີທາງຍົກເລີກ —
// mirrors home_tab.dart's _showRejectSheet() (preset-reason bottom sheet)
// ================================================================

class _CancelJobButton extends ConsumerWidget {
  final Booking booking;
  const _CancelJobButton({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(bookingNotifierProvider).isLoading;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : () => _showCancelSheet(context, ref),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: C.red.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(tr('action_cancel_job'), style: const TextStyle(
          color: C.red, fontSize: 14, fontWeight: FontWeight.w700,
        )),
      ),
    );
  }

  void _showCancelSheet(BuildContext context, WidgetRef ref) {
    final reasons = [
      tr('cancel_job_vehicle'), tr('cancel_job_emergency'),
      tr('cancel_job_customer_unreachable'), tr('cancel_job_other'),
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
            Text(tr('cancel_job_reason_title'), style: const TextStyle(
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
                final navigator   = Navigator.of(context);
                Navigator.pop(ctx);
                final ok = await ref
                    .read(bookingNotifierProvider.notifier)
                    .cancelJob(booking.id, reason);
                if (ok) {
                  navigator.pop();
                } else {
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
              child: Text(tr('confirm_cancel_job'), style: const TextStyle(
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

// 🔒 [AUDIT UI-5 / 2026-08-02 — Medium, fresh re-audit] previously its own
// AnimationController+Tween+dispose() (identical 600ms/0.4-1.0 pattern
// duplicated in review_screen.dart and main.dart) — now built on the shared
// PulsingFade primitive.
class _BtnLoadingSkeleton extends StatelessWidget {
  const _BtnLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return PulsingFade(
      duration: const Duration(milliseconds: 600),
      begin: 0.4, end: 1.0,
      child: Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}