// ============================================================
// tracking_screen.dart — LinTho
// Features:
//   ✅ Real-time status tracking (Firestore stream)
//   ✅ Status steps: pending→on_way→arrived→working→done
//   ✅ flutter_map — ຊ່າງ location + ລູກຄ້າ location
//   ✅ Provider real-time location (lat/lng stream)
//   ✅ Call provider button
//   ✅ Skeleton loading
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ InkWell + Material ທຸກ tap
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'provider_model.dart';
import 'review_screen.dart';
import 'booking_repository.dart';
import 'chat_screen.dart';
import 'widgets/status_stepper.dart' as shared;
import 'widgets/app_icon_button.dart';

// ════════════════════════════════════════════════════════════
// STATUS MODEL
// ════════════════════════════════════════════════════════════

enum BookingStatus {
  pending,    // ລໍຖ້າຊ່າງ
  onWay,      // ຊ່າງກຳລັງໄປ
  arrived,    // ຊ່າງຮອດແລ້ວ
  working,    // ກຳລັງເຮັດວຽກ
  done,       // ສຳເລັດ
  cancelled,  // ຍົກເລີກ
}

extension BookingStatusX on BookingStatus {
  static BookingStatus fromString(String s) => switch (s) {
    'accepted'   => BookingStatus.pending,
    'onTheWay'   => BookingStatus.onWay,
    'arrived'    => BookingStatus.arrived,
    'inProgress' => BookingStatus.working,
    'completed'  => BookingStatus.done,
    'cancelled'  => BookingStatus.cancelled,
    'rejected'   => BookingStatus.cancelled,
    _            => BookingStatus.pending,
  };

  String get label => switch (this) {
    BookingStatus.pending   => tr('tracking_status_pending'),
    BookingStatus.onWay     => tr('tracking_status_on_way'),
    BookingStatus.arrived   => tr('tracking_status_arrived'),
    BookingStatus.working   => tr('tracking_status_working'),
    BookingStatus.done      => tr('tracking_status_done'),
    BookingStatus.cancelled => tr('tracking_status_cancelled'),
  };

  String get emoji => switch (this) {
    BookingStatus.pending   => '⏳',
    BookingStatus.onWay     => '🚗',
    BookingStatus.arrived   => '📍',
    BookingStatus.working   => '🔧',
    BookingStatus.done      => '✅',
    BookingStatus.cancelled => '❌',
  };

  // 🔒 [AUDIT M-10 / 2026-07-27] Material icon ແທນ emoji ຂ້າງເທິງ ສຳລັບ
  // map-marker badge ແລະ status badge (ຄືກັນກັບການ migrate ອື່ນໆທົ່ວແອັບ) —
  // `emoji` ຄົງໄວ້ເປັນ fallback ໃນກໍລະນີໃນອະນາຄົດຕ້ອງການ, ບໍ່ໄດ້ຖືກ render ໂດຍກົງ
  // ອີກຕໍ່ໄປ.
  IconData get icon => switch (this) {
    BookingStatus.pending   => Icons.hourglass_empty_rounded,
    BookingStatus.onWay     => Icons.directions_car_rounded,
    BookingStatus.arrived   => Icons.location_on_rounded,
    BookingStatus.working   => Icons.build_rounded,
    BookingStatus.done      => Icons.check_circle_rounded,
    BookingStatus.cancelled => Icons.cancel_rounded,
  };

  int get stepIndex => switch (this) {
    BookingStatus.pending   => 0,
    BookingStatus.onWay     => 1,
    BookingStatus.arrived   => 2,
    BookingStatus.working   => 3,
    BookingStatus.done      => 4,
    BookingStatus.cancelled => -1,
  };
}

// ════════════════════════════════════════════════════════════
// TRACKING SCREEN
// ════════════════════════════════════════════════════════════

class TrackingScreen extends StatefulWidget {
  final String        bookingId;
  final ProviderModel provider;
  final String        serviceName;
  final String        serviceEmoji;
  // 🔒 [FOLLOWUP-J3] serviceEmoji ຍັງຄົງໄວ້ (ບໍ່ໄດ້ໃຊ້ສະແດງອີກຕໍ່ໄປ) ເພື່ອບໍ່ໃຫ້
  // ຕ້ອງແກ້ constructor call ທຸກບ່ອນ — serviceIcon (Material icon, derive ຈາກ
  // category) ຄືອັນທີ່ໃຊ້ສະແດງແທນ emoji ດິບໃນ _ProviderInfoRow ຂ້າງລຸ່ມ.
  final IconData       serviceIcon;
  final String         address;
  final double?        customerLat;
  final double?        customerLng;

  const TrackingScreen({
    super.key,
    required this.bookingId,
    required this.provider,
    required this.serviceName,
    required this.serviceEmoji,
    required this.serviceIcon,
    required this.address,
    this.customerLat,
    this.customerLng,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {

  // ── state ─────────────────────────────────────────────────
  BookingStatus _status      = BookingStatus.pending;
  bool          _isLoading   = true;
  double?       _provLat;
  double?       _provLng;
  double?       _custLat;
  double?       _custLng;
  int           _elapsedSecs = 0;
  bool          _mapReady    = false;
  double?       _additionalCharges;
  String?       _additionalChargesNote;
  bool          _additionalChargesApproved = false;
  bool          _respondingToCharges       = false;
  // 🔒 [FOLLOWUP-K] ຕ້ອງຮູ້ paymentMethod/customerConfirmedPayment ຢູ່ນີ້
  // ເພື່ອສະແດງປຸ່ມ "ຢືນຢັນວ່າໄດ້ໂອນເງິນແລ້ວ" (ສະເພາະ BCEL, ຍັງບໍ່ທັນຢືນຢັນ)
  String        _paymentMethod             = 'cash';
  bool          _customerConfirmedPayment  = false;
  bool          _confirmingPayment         = false;

  // ── controllers ───────────────────────────────────────────
  late final MapController          _mapCtrl;
  late final AnimationController    _pulseCtrl;
  late final AnimationController    _statusCtrl;
  late final Animation<double>      _pulseAnim;
  late final Animation<double>      _statusAnim;
  StreamSubscription<DocumentSnapshot>? _bookingSub;
  StreamSubscription<DocumentSnapshot>? _providerSub;
  Timer? _elapsedTimer;

  final _db = FirebaseFirestore.instance;

  // ════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _mapCtrl   = MapController();
    _custLat   = widget.customerLat;
    _custLng   = widget.customerLng;
    _provLat   = widget.provider.lat;
    _provLng   = widget.provider.lng;
    _setupAnimations();
    _init();
  }

  @override
  void dispose() {
    _bookingSub?.cancel();
    _providerSub?.cancel();
    _elapsedTimer?.cancel();
    _pulseCtrl.dispose();
    _statusCtrl.dispose();
    // ✅ MapController ບໍ່ມີ .dispose() — ບໍ່ call
    super.dispose();
  }

  // ── animations ────────────────────────────────────────────

  void _setupAnimations() {
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _statusCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _statusAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _statusCtrl, curve: Curves.easeOut));
  }

  // ════════════════════════════════════════════════════════
  // INIT
  // ════════════════════════════════════════════════════════

  Future<void> _init() async {
    await _loadInitialData();
    if (!mounted) return;
    _watchBooking();
    _watchProviderLocation();
    _startElapsedTimer();
  }

  Future<void> _loadInitialData() async {
    try {
      final doc = await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final d      = doc.data()!;
        final status = d['status'] as String? ?? 'pending';
        _custLat ??= (d['lat'] as num?)?.toDouble();
        _custLng ??= (d['lng'] as num?)?.toDouble();
        setState(() {
          _status    = BookingStatusX.fromString(status);
          _isLoading = false;
          _paymentMethod            = d['paymentMethod'] as String? ?? 'cash';
          _customerConfirmedPayment = d['customerConfirmedPayment'] as bool? ?? false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('loadInitialData: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // STREAMS
  // ════════════════════════════════════════════════════════

  void _watchBooking() {
    _bookingSub = _db
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final d         = doc.data()!;
      final newStatus = BookingStatusX.fromString(
          d['status'] as String? ?? 'pending');

      setState(() {
        _additionalCharges         = (d['additionalCharges'] as num?)?.toDouble();
        _additionalChargesNote     = d['additionalChargesNote'] as String?;
        _additionalChargesApproved = d['additionalChargesApproved'] as bool? ?? false;
        _paymentMethod             = d['paymentMethod'] as String? ?? 'cash';
        _customerConfirmedPayment  = d['customerConfirmedPayment'] as bool? ?? false;
      });

      if (newStatus != _status) {
        setState(() => _status = newStatus);
        _statusCtrl.forward(from: 0);

        // ວຽກສຳເລັດ → ໄປ review
        if (newStatus == BookingStatus.done && mounted) {
          _elapsedTimer?.cancel();
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            _goReview();
          });
        }
      }
    }, onError: (e) => debugPrint('watchBooking: $e'));
  }

  void _watchProviderLocation() {
    if (widget.provider.uid.isEmpty) return;
    _providerSub = _db
        .collection('providers')
        .doc(widget.provider.uid)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final d   = doc.data()!;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() {
          _provLat = lat;
          _provLng = lng;
        });
        // ✅ pan map ໄປຫາ provider (ຖ້າ map ພ້ອມ)
        if (_mapReady) {
          _mapCtrl.move(LatLng(lat, lng), _mapCtrl.camera.zoom);
        }
      }
    }, onError: (e) => debugPrint('watchProviderLoc: $e'));
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSecs++);
    });
  }

  // ════════════════════════════════════════════════════════
  // ACTIONS
  // ════════════════════════════════════════════════════════

  Future<void> _callProvider() async {
    final phone = widget.provider.phone;
    if (phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('tel:$digits');
    // NOTE: AndroidManifest.xml ຕ້ອງມີ:
    // <queries><intent><action android:name="android.intent.action.DIAL"/>
    // <data android:scheme="tel"/></intent></queries>
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // 🔒 [FOLLOWUP-K] ລູກຄ້າກົດຢືນຢັນວ່າໄດ້ໂອນເງິນຜ່ານ BCEL ແລ້ວ — counter-
  // signature ກ່ອນຊ່າງຈະຢືນຢັນຮັບເງິນ/ປິດງານໄດ້ (confirmPaymentReceived()).
  Future<void> _confirmPaymentSent() async {
    if (_confirmingPayment) return;
    setState(() => _confirmingPayment = true);
    try {
      await CustomerBookingRepository().confirmPaymentSent(widget.bookingId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${tr("error")}: $e'), backgroundColor: C.red));
      }
    } finally {
      if (mounted) setState(() => _confirmingPayment = false);
    }
  }

  Future<void> _openChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final chatId = await ChatService.createOrGetChat(
      bookingId:    widget.bookingId,
      customerId:   user.uid,
      customerName: user.displayName ?? '',
      providerId:   widget.provider.uid,
      providerName: widget.provider.displayName,
      serviceName:  widget.serviceName,
    );
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
      chatId:         chatId,
      otherName:      widget.provider.displayName,
      bookingService: widget.serviceName,
      receiverId:     widget.provider.uid,
      receiverName:   widget.provider.displayName,
    )));
  }

  Future<void> _respondToCharges(bool approve) async {
    if (_respondingToCharges) return;
    setState(() => _respondingToCharges = true);
    try {
      await CustomerBookingRepository()
          .respondToAdditionalCharges(widget.bookingId, approve);
    } catch (e) {
      debugPrint('respondToCharges: $e');
    } finally {
      if (mounted) setState(() => _respondingToCharges = false);
    }
  }

  // 🔒 [AUDIT H8 follow-up] ໜ້ານີ້ (onWay/arrived) ບໍ່ມີທາງຍົກເລີກໄດ້ເລີຍ
  // ທັງໆທີ່ CustomerBookingRepository.cancelBooking() ຄິດໄລ່ຄ່າທຳນຽມ
  // onWay/arrived ໄວ້ແລ້ວ (booking_repository.dart) — ໜ້າ match_screen.dart
  // ມີແຕ່ປຸ່ມຍົກເລີກກ່ອນຮອດ onWay ເທົ່ານັ້ນ. ຕອນນີ້ເພີ່ມປຸ່ມນີ້ສະເພາະ
  // pending(accepted)/onWay/arrived — ບໍ່ສະແດງຕອນ working ເພາະ cancelBooking()
  // ຍັງບໍ່ມີ fee policy ສະເພາະສຳລັບວຽກທີ່ເລີ່ມແລ້ວ (product decision ຄ້າງ).
  bool get _canCancel =>
      _status == BookingStatus.pending ||
      _status == BookingStatus.onWay ||
      _status == BookingStatus.arrived;

  Future<void> _confirmAndCancel() async {
    final reasonCtrl = TextEditingController();
    final showFeeWarning = _status == BookingStatus.onWay ||
        _status == BookingStatus.arrived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('cancel_booking_question')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('cancel_confirm_short')),
          if (showFeeWarning) ...[
            const SizedBox(height: 8),
            Text(tr('cancel_fee_warning'), style: const TextStyle(
              color: C.red, fontSize: 12, fontWeight: FontWeight.w600,
            )),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLength:  200,
            maxLines:   2,
            decoration: InputDecoration(
              hintText: tr('cancel_reason_hint'),
              filled:   true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('no')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;

    try {
      await CustomerBookingRepository().cancelBooking(
          widget.bookingId, reason.isEmpty ? 'ລູກຄ້າຍົກເລີກ' : reason);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('cancelBooking: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr("error")}: $e'), backgroundColor: C.red));
    }
  }

  void _goReview() {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ReviewScreen(
        bookingId:    widget.bookingId,
        provider:     widget.provider,
        serviceName:  widget.serviceName,
        serviceIcon:  widget.serviceIcon,
      ),
    ));
  }

  // ── center map ────────────────────────────────────────────

  void _centerMap() {
    if (!_mapReady) return;
    final lat = _provLat ?? _custLat ?? 17.9757;
    final lng = _provLng ?? _custLng ?? 102.6331;
    _mapCtrl.move(LatLng(lat, lng), 14);
  }

  // ── elapsed label ─────────────────────────────────────────

  String get _elapsedLabel {
    final m = _elapsedSecs ~/ 60;
    final s = _elapsedSecs % 60;
    return m > 0
        ? '${m}ນ ${s.toString().padLeft(2, '0')}ວ'
        : '${_elapsedSecs}ວິ';
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _TrackingSkeleton();

    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [

        // ── MAP (full screen background) ──────────────────
        _buildMap(),

        // ── TOP BAR ───────────────────────────────────────
        SafeArea(child: _buildTopBar()),

        // ── ADDITIONAL CHARGES BANNER ─────────────────────
        if (_additionalCharges != null && !_additionalChargesApproved)
          Positioned(
            left: 16, right: 16,
            bottom: _bottomSheetHeight + 80,
            child: _buildAdditionalChargesBanner(),
          ),

        // ── BOTTOM SHEET ──────────────────────────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _buildBottomSheet(),
        ),

        // ── FAB: center map ───────────────────────────────
        Positioned(
          right: 16,
          bottom: _bottomSheetHeight + 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:        _centerMap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset:     const Offset(0, 3),
                  )],
                ),
                child: const Icon(Icons.my_location,
                    color: C.primary, size: 22),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  double get _bottomSheetHeight => _status == BookingStatus.done ? 280 : 340;

  Widget _buildAdditionalChargesBanner() {
    final amount = _additionalCharges ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: const Color(0xFFF97316), width: 1.5),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.1),
          blurRadius: 12,
          offset:     const Offset(0, 4),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('additional_charges_requested'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: C.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('₭${amount.toStringAsFixed(0)}'
              '${_additionalChargesNote != null && _additionalChargesNote!.isNotEmpty ? ' · ${_additionalChargesNote!}' : ''}',
              style: const TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _respondingToCharges ? null : () => _respondToCharges(false),
                  child: Text(tr('reject')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _respondingToCharges ? null : () => _respondToCharges(true),
                  style: ElevatedButton.styleFrom(backgroundColor: C.primary),
                  child: Text(tr('approve'), style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // MAP
  // ════════════════════════════════════════════════════════

  Widget _buildMap() {
    final center = LatLng(
      _provLat ?? _custLat ?? 17.9757,
      _provLng ?? _custLng ?? 102.6331,
    );

    final markers = <Marker>[];

    // ── Provider marker ──────────────────────────────────
    if (_provLat != null && _provLng != null) {
      markers.add(Marker(
        key:    const ValueKey('provider'),
        point:  LatLng(_provLat!, _provLng!),
        width:  60,
        height: 80,
        child: ScaleTransition(
          scale: _pulseAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        C.primary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(
                    color:      C.primary.withValues(alpha: 0.4),
                    blurRadius: 6,
                  )],
                ),
                child: Text(
                  widget.provider.displayName.isNotEmpty
                      ? widget.provider.displayName
                      : tr('provider'),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color:  C.primary,
                  shape:  BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(
                    color:      C.primary.withValues(alpha: 0.5),
                    blurRadius: 10,
                  )],
                ),
                child: Center(child: Icon(
                  _status.icon,
                  size: 18, color: Colors.white,
                )),
              ),
            ],
          ),
        ),
      ));
    }

    // ── Customer marker ───────────────────────────────────
    if (_custLat != null && _custLng != null) {
      markers.add(Marker(
        key:    const ValueKey('customer'),
        point:  LatLng(_custLat!, _custLng!),
        width:  60,
        height: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        C.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('you_marker'),
                style: const TextStyle(
                  color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color:  C.green,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(
                  color:      C.green.withValues(alpha: 0.5),
                  blurRadius: 10,
                )],
              ),
              child: const Center(
                child: Icon(Icons.home_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: center,
        initialZoom:   14,
        onMapReady:    () => setState(() => _mapReady = true),
      ),
      children: [
        TileLayer(
          urlTemplate:         'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.lintho.app',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // TOP BAR
  // ════════════════════════════════════════════════════════

  Widget _buildTopBar() => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      // back button
      // 🔒 [AUDIT H12] 40×40 ຕ່ຳກວ່າ 44dp tap target ຂັ້ນຕ່ຳ ແລະ ບໍ່ມີ
      // Semantics — ຕອນນີ້ໃຊ້ AppIconButton ຮ່ວມກັນ (ບັງຄັບ 44dp + tooltip)
      AppIconButton(
        icon:  Icons.arrow_back_ios,
        color: C.primary,
        label: tr('back_semantic'),
        onTap: () => Navigator.pop(context),
      ),
      const SizedBox(width: 12),

      // status badge
      Expanded(
        child: FadeTransition(
          opacity: _statusAnim,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color:      Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset:     const Offset(0, 3),
              )],
            ),
            child: Row(children: [
              Icon(_status.icon, size: 18, color: C.primary),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status.label, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: C.textPrimary,
                  )),
                  Text(
                    _status == BookingStatus.working
                        ? '${tr('elapsed_time_label')}: $_elapsedLabel'
                        : widget.serviceName,
                    style: const TextStyle(
                        fontSize: 11, color: C.muted),
                  ),
                ],
              )),
              // live dot
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color:  _status == BookingStatus.done
                      ? C.green : C.primary,
                  shape:  BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _status == BookingStatus.done ? 'Done' : 'Live',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: _status == BookingStatus.done
                      ? C.green : C.primary,
                ),
              ),
            ]),
          ),
        ),
      ),

      const SizedBox(width: 12),

      // chat button — ສະເພາະຕອນ booking ຍັງ active (ບໍ່ done/cancelled)
      if (_status != BookingStatus.done &&
          _status != BookingStatus.cancelled) ...[
        AppIconButton(
          icon:  Icons.chat_bubble_outline_rounded,
          color: C.primary,
          label: tr('chat_semantic'),
          onTap: _openChat,
        ),
        const SizedBox(width: 12),
      ],

      // call button
      AppIconButton(
        icon:  Icons.phone_rounded,
        color: C.green,
        label: tr('call_provider_btn'),
        onTap: _callProvider,
      ),
    ]),
  );

  // ════════════════════════════════════════════════════════
  // BOTTOM SHEET
  // ════════════════════════════════════════════════════════

  Widget _buildBottomSheet() => Container(
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24)),
      boxShadow: [BoxShadow(
        color:      Colors.black.withValues(alpha: 0.1),
        blurRadius: 20,
        offset:     const Offset(0, -4),
      )],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // drag handle
        const SizedBox(height: 10),
        Center(child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color:        C.border,
            borderRadius: BorderRadius.circular(2),
          ),
        )),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Provider Info ─────────────────────────
              _ProviderInfoRow(
                provider:     widget.provider,
                serviceIcon:  widget.serviceIcon,
                serviceName:  widget.serviceName,
                onCall:       _callProvider,
              ),
              const SizedBox(height: 16),

              // ── Status Steps ──────────────────────────
              _StatusSteps(currentStatus: _status),
              const SizedBox(height: 16),

              // ── Confirm BCEL payment sent (FOLLOWUP-K) ─
              if (_paymentMethod != 'cash' &&
                  !_customerConfirmedPayment &&
                  (_status == BookingStatus.onWay ||
                      _status == BookingStatus.arrived ||
                      _status == BookingStatus.working)) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: C.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.gold.withValues(alpha: 0.3)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('ໂອນເງິນຜ່ານ BCEL ແລ້ວບໍ?', style: TextStyle(
                        fontWeight: FontWeight.w800, color: C.textPrimary, fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text('ກົດຢືນຢັນເມື່ອທ່ານໂອນເງິນຄ່າບໍລິການໃຫ້ຊ່າງແລ້ວ',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: ElevatedButton(
                      onPressed: _confirmingPayment ? null : _confirmPaymentSent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.gold, elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _confirmingPayment
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('ຢືນຢັນວ່າໄດ້ໂອນເງິນແລ້ວ', style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // ── Address ───────────────────────────────
              if (widget.address.isNotEmpty) ...[
                _AddressRow(address: widget.address),
                const SizedBox(height: 16),
              ],

              // ── Done button ───────────────────────────
              if (_status == BookingStatus.done) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                    ),
                    child: const Text(
                      '⭐ ໃຫ້ຄະແນນຊ່າງ',
                      style: TextStyle(
                        color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_canCancel) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _confirmAndCancel,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: C.red.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(tr('cancel_booking_btn'), style: const TextStyle(
                      color: C.red, fontSize: 14, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
// STATUS STEPS WIDGET
// ════════════════════════════════════════════════════════════

// ✅ [FIX — shared StatusStepper] ນີ້ເຄີຍເປັນ implementation ອິດສະຫຼະຈາກ
// job_workflow_Screen.dart's _StatusStepper (ຝັ່ງຊ່າງ) ທັງໆທີ່ສະແດງ
// ຄວາມຄືບໜ້າວຽກດຽວກັນ — ຕອນນີ້ທັງສອງໜ້າຈໍໃຊ້
// lib/widgets/status_stepper.dart ຮ່ວມກັນ.
class _StatusSteps extends StatelessWidget {
  final BookingStatus currentStatus;
  const _StatusSteps({required this.currentStatus});

  static List<shared.StatusStep> get _steps => [
    shared.StatusStep(icon: Icons.hourglass_top_rounded,   label: tr('tracking_status_pending')),
    shared.StatusStep(icon: Icons.directions_car_rounded,  label: tr('tracking_status_on_way')),
    shared.StatusStep(icon: Icons.place_rounded,           label: tr('tracking_status_arrived')),
    shared.StatusStep(icon: Icons.build_rounded,           label: tr('tracking_status_working')),
    shared.StatusStep(icon: Icons.check_circle_rounded,    label: tr('tracking_status_done')),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        C.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: shared.StatusStepper(
        steps: _steps,
        currentIndex: currentStatus.stepIndex,
        axis: Axis.vertical,
        activeColor: C.green,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PROVIDER INFO ROW
// ════════════════════════════════════════════════════════════

class _ProviderInfoRow extends StatelessWidget {
  final ProviderModel provider;
  final IconData       serviceIcon;
  final String        serviceName;
  final VoidCallback  onCall;

  const _ProviderInfoRow({
    required this.provider,
    required this.serviceIcon,
    required this.serviceName,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    // avatar
    Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color:        C.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.gold.withValues(alpha: 0.3)),
      ),
      child: Center(child: Text(
        provider.avatarLetter,
        style: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.w900,
          color: C.gold,
        ),
      )),
    ),
    const SizedBox(width: 12),

    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(provider.displayName, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800,
          color: C.textPrimary,
        )),
        const SizedBox(height: 3),
        Row(children: [
          const Icon(Icons.star_rounded, color: C.gold, size: 14),
          const SizedBox(width: 3),
          Text(provider.ratingLabel, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: C.gold,
          )),
          // 🔒 [FOLLOWUP-J3] ໃຊ້ Material icon (serviceIcon) ແທນ emoji ດິບ —
          // ຄືກັນກັບ home_tab.dart/jobs_tab.dart/job_workflow_Screen.dart/
          // match_screen.dart ທີ່ຖືກແກ້ໄປແລ້ວກ່ອນໜ້ານີ້.
          const Text('  ·  ', style: TextStyle(fontSize: 11, color: C.muted)),
          Icon(serviceIcon, size: 12, color: C.muted),
          const SizedBox(width: 3),
          Text(serviceName,
              style: const TextStyle(
                  fontSize: 11, color: C.muted)),
        ]),
      ],
    )),

    // call button
    Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onCall,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color:        C.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: C.green.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.phone_rounded,
              color: C.green, size: 20),
        ),
      ),
    ),
  ]);
}

// ════════════════════════════════════════════════════════════
// ADDRESS ROW
// ════════════════════════════════════════════════════════════

class _AddressRow extends StatelessWidget {
  final String address;
  const _AddressRow({required this.address});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        C.primary.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: C.primary.withValues(alpha: 0.15)),
    ),
    child: Row(children: [
      const Icon(Icons.location_on_outlined,
          color: C.primary, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(
        address,
        style: const TextStyle(
            fontSize: 12, color: C.textSecondary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      )),
    ]),
  );
}

// ════════════════════════════════════════════════════════════
// SKELETON
// ════════════════════════════════════════════════════════════

class _TrackingSkeleton extends StatefulWidget {
  const _TrackingSkeleton();

  @override
  State<_TrackingSkeleton> createState() => _TrackingSkeletonState();
}

class _TrackingSkeletonState extends State<_TrackingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double r = 8}) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color:        C.muted.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(r),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: FadeTransition(
      opacity: _fade,
      child: Stack(children: [
        // map placeholder
        Container(color: C.muted.withValues(alpha: 0.08)),

        // top bar skeleton
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            _box(44, 44, r: 12),
            const SizedBox(width: 12),
            Expanded(child: _box(double.infinity, 56, r: 14)),
            const SizedBox(width: 12),
            _box(44, 44, r: 12),
          ]),
        )),

        // bottom sheet skeleton
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color:        C.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(height: 16),
                Row(children: [
                  _box(52, 52, r: 16),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(140, 15),
                      const SizedBox(height: 6),
                      _box(100, 12),
                    ],
                  )),
                  _box(44, 44, r: 12),
                ]),
                const SizedBox(height: 16),
                _box(double.infinity, 180, r: 16),
                const SizedBox(height: 16),
                _box(double.infinity, 44, r: 14),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ]),
    ),
  );
}