// ============================================================
// match_screen.dart — LinTho (Rewrite)
// Features:
//   ✅ Auto-Match Top 3 providers (rating + distance)
//   ✅ ສົ່ງ request ໃຫ້ 3 ຄົນພ້ອມກັນ — ໃຜຮັບກ່ອນໄດ້ກ່ອນ
//   ✅ Real-time Firestore stream
//   ✅ Countdown 30s auto-confirm
//   ✅ No provider fallback + retry
// Fixes:
//   ✅ _SearchingDots — ໃຊ້ addStatusListener ຖືກຕ້ອງ
//   ✅ _autoConfirm race condition
//   ✅ canLaunchUrl tel: scheme note
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ InkWell + Material ທຸກ tap
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check ຫຼັງທຸກ async
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'geohash_util.dart';
import 'provider_model.dart';
import 'tracking_screen.dart';

// ════════════════════════════════════════════════════════════
// MATCH STATE
// ════════════════════════════════════════════════════════════

enum _MatchState {
  loading,      // ໂຫຼດ booking meta
  searching,    // ກຳລັງຊອກ Top 3
  waiting,      // ສົ່ງ request ໄປແລ້ວ — ລໍຖ້າ provider ຮັບ
  matched,      // provider ຮັບແລ້ວ — countdown 30s
  confirmed,    // user ຢືນຢັນ / auto-confirm
  noProvider,   // timeout ຫຼື ບໍ່ພົບ
}

// ════════════════════════════════════════════════════════════
// SCREEN
// ════════════════════════════════════════════════════════════

class MatchScreen extends StatefulWidget {
  final String  bookingId;
  final String? initialServiceName;
  final String? initialServiceEmoji;
  final String? initialAddress;
  final double? customerLat;
  final double? customerLng;

  const MatchScreen({
    super.key,
    required this.bookingId,
    this.initialServiceName,
    this.initialServiceEmoji,
    this.initialAddress,
    this.customerLat,
    this.customerLng,
  });

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen>
    with TickerProviderStateMixin {

  // ✅ ໄລຍະເວລາສູງສຸດທີ່ລະບົບຈະຄົ້ນຫາ/ລໍຖ້າຊ່າງຮັບ ກ່ອນສະແດງ "ບໍ່ພົບຊ່າງ"
  static const int _searchTimeoutSecs = 45;
  // ✅ ໄລຍະຫ່າງລະຫວ່າງແຕ່ລະຄັ້ງທີ່ retry ຊອກຫາໃໝ່ ເວລາຍັງບໍ່ພົບຊ່າງ online
  static const Duration _retryInterval = Duration(seconds: 4);

  // ── state ─────────────────────────────────────────────────
  _MatchState    _state       = _MatchState.loading;
  int            _countdown   = 30;
  int            _searchSecs  = 0;
  bool           _hasWidened  = false; // ✅ widen radius ຄັ້ງດຽວ ຫຼັງ retry ຄັ້ງທີ 1
  ProviderModel? _matchedProv;
  String         _serviceName  = '';
  String         _serviceEmoji = '🔧';
  String         _address      = '';
  double?        _custLat;
  double?        _custLng;
  List<ProviderModel> _top3   = [];

  // ✅ ວິນາທີທີ່ຍັງເຫຼືອກ່ອນໝົດເວລາຄົ້ນຫາ — ສະແດງເປັນ countdown ໃນ UI
  int get _searchSecsLeft =>
      (_searchTimeoutSecs - _searchSecs).clamp(0, _searchTimeoutSecs);

  // ── timers / subs ─────────────────────────────────────────
  Timer?                               _countdownTimer;
  Timer?                               _searchTimer;
  Timer?                               _retryTimer;
  StreamSubscription<DocumentSnapshot>? _bookingSub;

  // ── animations ────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _matchCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _matchAnim;

  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _custLat = widget.customerLat;
    _custLng = widget.customerLng;
    _init();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchTimer?.cancel();
    _retryTimer?.cancel();
    _bookingSub?.cancel();
    _pulseCtrl.dispose();
    _matchCtrl.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // ANIMATIONS
  // ════════════════════════════════════════════════════════

  void _setupAnimations() {
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _matchCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    );

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _matchAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _matchCtrl, curve: Curves.elasticOut));
  }

  // ════════════════════════════════════════════════════════
  // INIT
  // ════════════════════════════════════════════════════════

  Future<void> _init() async {
    await _loadBookingMeta();
    if (!mounted) return;
    _watchBooking();
    _startSearchTimer();
    await _findAndSendTop3();
  }

  // ── load booking meta ────────────────────────────────────

  Future<void> _loadBookingMeta() async {
    String name  = widget.initialServiceName  ?? tr('service_generic');
    String emoji = widget.initialServiceEmoji ?? '🔧';
    String addr  = widget.initialAddress      ?? '';

    try {
      final doc = await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (doc.exists) {
        final d = doc.data()!;
        name  = d['serviceName']  as String? ??
            d['serviceType']  as String? ?? name;
        emoji = d['serviceEmoji'] as String? ?? emoji;
        addr  = d['address']      as String? ?? addr;
        _custLat ??= (d['lat'] as num?)?.toDouble();
        _custLng ??= (d['lng'] as num?)?.toDouble();
      }
    } catch (e) {
      debugPrint('loadBookingMeta: $e');
    }

    if (!mounted) return;
    setState(() {
      _serviceName  = name;
      _serviceEmoji = emoji;
      _address      = addr;
      _state        = _MatchState.searching;
    });
  }

  // ════════════════════════════════════════════════════════
  // AUTO-MATCH: FIND TOP 3
  // ════════════════════════════════════════════════════════

  Future<void> _findAndSendTop3({bool widen = false}) async {
    try {
      // 1. ດຶງ category ຈາກ booking
      String category = 'ac_clean';
      try {
        final bDoc = await _db
            .collection('bookings')
            .doc(widget.bookingId)
            .get();
        if (bDoc.exists) {
          category = bDoc.data()?['category'] as String? ?? category;
        }
      } catch (_) {}

      // 2. Query providers ທີ່ online + ຮັບ service ນີ້
      // ✅ ຖ້າຮູ້ຈັກ lat/lng ລູກຄ້າ → ໃຊ້ geohash bounding-box query ກ່ອນ
      // (9 ຊ່ອງຂ້າງຄຽງ) ເພື່ອບໍ່ໃຫ້ provider ໄກໆຖືກເລືອກກ່ອນ provider ໃກ້
      // ເຫດຜົນ: Firestore .limit(20) ຕັດກ່ອນຮູ້ໄລຍະທາງ — ຖ້າມີ provider
      // online ຫຼາຍກວ່າ 20 ຄົນທົ່ວປະເທດ, ການ sort ໂດຍ distance ພາຍຫຼັງ
      // ບໍ່ຊ່ວຍຫາກ provider ໃກ້ສຸດບໍ່ໄດ້ຢູ່ໃນ 20 ໂຕທີ່ Firestore ສຸ່ມສົ່ງມາ
      // ✅ widen=true (auto-retry ຄັ້ງດຽວ ກ່ອນສະແດງ noProvider): precision 5
      // ແທນ 6 → cell ໃຫຍ່ກວ່າ → ຄອບຄຸມ provider ໄກກວ່າເດີມ
      QuerySnapshot<Map<String, dynamic>> snap;
      if (_custLat != null && _custLng != null) {
        final precision = widen ? 5 : 6;
        final myHash   = GeohashUtil.encode(_custLat!, _custLng!, precision);
        final neighbors = GeohashUtil.neighborsOf(myHash);
        // ⚠️ ຕ້ອງການ composite index ໃນ Firestore Console:
        // providers: isOnline (Asc), serviceTypes (Array), geohash (Asc)
        snap = await _db
            .collection('providers')
            .where('isOnline', isEqualTo: true)
            .where('serviceTypes', arrayContains: category)
            .where('geohash', whereIn: neighbors)
            .limit(20)
            .get();
      } else {
        snap = await _db
            .collection('providers')
            .where('isOnline', isEqualTo: true)
            .where('serviceTypes', arrayContains: category)
            .limit(20)
            .get();
      }

      // ✅ Fallback — provider ເກົ່າທີ່ຍັງບໍ່ມີ geohash field (ຍັງບໍ່ໄດ້
      // online ຫຼັງ migration) ຫຼື ບໍ່ມີ provider ໃນຊ່ອງໃກ້ຄຽງ
      // → ກັບໄປໃຊ້ query ເກົ່າເພື່ອບໍ່ໃຫ້ matching ລົ້ມເຫຼວທັງໝົດ
      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('providers')
            .where('isOnline', isEqualTo: true)
            .where('serviceTypes', arrayContains: category)
            .limit(20)
            .get();
      }

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        _scheduleRetry();
        return;
      }

      // 3. Map → ProviderModel
      final providers = snap.docs
          .map((d) => ProviderModel.fromDoc(d))
          .toList();

      // 4. Sort: distance ກ່ອນ (ຖ້າມີ lat/lng), ຈາກນັ້ນ rating
      providers.sort((a, b) {
        final dA = a.distanceTo(_custLat, _custLng);
        final dB = b.distanceTo(_custLat, _custLng);

        // ທັງຄູ່ມີ distance → sort ໂດຍ distance
        if (dA != null && dB != null) {
          final distCmp = dA.compareTo(dB);
          if (distCmp != 0) return distCmp;
        }
        // ບໍ່ມີ distance → sort ໂດຍ rating (ສູງສຸດກ່ອນ)
        return b.rating.compareTo(a.rating);
      });

      // 5. Top 3
      _top3 = providers.take(3).toList();

      // 6. ຂຽນ sentTo + ສົ່ງ notification ໃຫ້ Top 3
      await _sendRequestToTop3(_top3);

      if (!mounted) return;
      setState(() => _state = _MatchState.waiting);

    } catch (e) {
      debugPrint('findTop3: $e');
      if (mounted) _scheduleRetry();
    }
  }

  // ✅ ບໍ່ພົບຊ່າງ online ໃນຄັ້ງນີ້ — ບໍ່ຕັດຈົບທັນທີ! ສືບຕໍ່ retry ທຸກ
  // _retryInterval ຈົນກວ່າຈະຮອດ _searchTimeoutSecs (45 ວິ) ຈຶ່ງສະແດງ
  // "ບໍ່ພົບຊ່າງ" ແທ້ໆ. widen radius ຫຼັງ retry ຄັ້ງທີ 1 ເພື່ອຄອບຄຸມໄລຍະໄກຂຶ້ນ.
  void _scheduleRetry() {
    if (!mounted || _state != _MatchState.searching) return;

    if (_searchSecs >= _searchTimeoutSecs) {
      setState(() => _state = _MatchState.noProvider);
      return;
    }

    _hasWidened = true;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryInterval, () {
      if (!mounted || _state != _MatchState.searching) return;
      _findAndSendTop3(widen: _hasWidened);
    });
  }

  // ── ສົ່ງ request ──────────────────────────────────────────

  Future<void> _sendRequestToTop3(List<ProviderModel> top3) async {
    if (top3.isEmpty) return;
    final ids = top3.map((p) => p.uid).toList();
    try {
      await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
        'sentTo':    ids,
        'status':    'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // TODO: ສົ່ງ FCM push ຜ່ານ Cloud Function
      // ຕອນນີ້ provider app ຈະ stream bookings
      // ທີ່ sentTo contains uid ຂອງຕົນເອງ
    } catch (e) {
      debugPrint('sendRequestToTop3: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  // FIRESTORE STREAM
  // ════════════════════════════════════════════════════════

  void _watchBooking() {
    if (widget.bookingId.isEmpty) return;
    _bookingSub = _db
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final data   = doc.data()!;
      final status = data['status'] as String? ?? '';

      switch (status) {
        case 'accepted':
          if (_state == _MatchState.waiting ||
              _state == _MatchState.searching) {
            _onMatched(data);
          }
        case 'cancelled':
        case 'rejected':
          _searchTimer?.cancel();
          if (mounted) setState(() => _state = _MatchState.noProvider);
      }
    }, onError: (e) => debugPrint('watchBooking: $e'));
  }

  // ── match! ────────────────────────────────────────────────

  void _onMatched(Map<String, dynamic> data) {
    _searchTimer?.cancel();
    final provider = ProviderModel.fromMap(
      data['providerId'] as String? ?? '',
      {
        'displayName':    data['providerName'],
        'phone':          data['providerPhone'],
        'rating':         data['providerRating'],
        'totalJobs':      data['providerJobs'],
        'photoUrl':       data['providerPhoto'] ?? '',
        'isOnline':       true,
        'serviceTypes':   [],
        'fcmTokens':      [],
        'bio':            '',
        'email':          '',
        'gender':         '',
        'kycStatus':      'none',
        'completionRate': 0,
        'experienceYears':0,
        'estimatedMinutes': data['estimatedMinutes'] ?? 20,
      },
    );

    if (!mounted) return;
    setState(() {
      _matchedProv = provider;
      _state       = _MatchState.matched;
      _countdown   = 30;
    });
    _matchCtrl.forward(from: 0);
    _startCountdown();
  }

  // ════════════════════════════════════════════════════════
  // TIMERS
  // ════════════════════════════════════════════════════════

  void _startSearchTimer() {
    _searchTimer?.cancel();
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _searchSecs++);
      // ✅ ໝົດເວລາຄົ້ນຫາ/ລໍຖ້າຮັບ (45 ວິ) — ສະແດງ "ບໍ່ພົບຊ່າງ"
      if (_searchSecs >= _searchTimeoutSecs &&
          (_state == _MatchState.waiting ||
              _state == _MatchState.searching)) {
        _searchTimer?.cancel();
        _retryTimer?.cancel();
        setState(() => _state = _MatchState.noProvider);
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_countdown <= 1) {
        _countdownTimer?.cancel();
        _autoConfirm();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  // ════════════════════════════════════════════════════════
  // ACTIONS
  // ════════════════════════════════════════════════════════

  // ✅ FIX: capture mounted state ກ່ອນ await
  Future<void> _autoConfirm() async {
    await _markMatchConfirmed();
    if (!mounted) return;              // ✅ mounted check ຫຼັງ await
    _pulseCtrl.stop();
    setState(() => _state = _MatchState.confirmed);
  }

  void _confirmNow() {
    _countdownTimer?.cancel();
    _markMatchConfirmed();
    if (!mounted) return;
    _pulseCtrl.stop();
    setState(() => _state = _MatchState.confirmed);
  }

  Future<void> _cancelBooking() async {
    _countdownTimer?.cancel();
    _searchTimer?.cancel();
    _retryTimer?.cancel();
    await _updateStatus('cancelled');
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _retry() {
    _retryTimer?.cancel();
    setState(() {
      _state      = _MatchState.searching;
      _searchSecs = 0;
      _top3       = [];
      _hasWidened = false;
    });
    _startSearchTimer();
    _findAndSendTop3().then((_) {
      if (!mounted) return;
      _watchBooking();
    });
  }

  void _goTracking() {
    if (_matchedProv == null) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => TrackingScreen(
        bookingId:    widget.bookingId,
        provider:     _matchedProv!,
        serviceName:  _serviceName,
        serviceEmoji: _serviceEmoji,
        address:      _address,
      ),
    ));
  }

  // ── Firestore write ───────────────────────────────────────

  Future<void> _updateStatus(String status) async {
    if (widget.bookingId.isEmpty) return;
    try {
      await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
        'status':    status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('updateStatus: $e');
    }
  }

  // ✅ [FIX] "ຢືນຢັນການຈັບຄູ່" ແມ່ນ acknowledgement ຝັ່ງ UI ຂອງ MatchScreen
  // ເອງ ບໍ່ແມ່ນການປ່ຽນສະຖານະວຽກຈິງ (booking ຍັງເປັນ 'accepted' ຢູ່) — ຫ້າມ
  // ຂຽນ status:'confirmed' ເພາະບໍ່ແມ່ນສະມາຊິກຂອງ JobStatus enum
  // (lib/Booking.dart) — Booking.fromFirestore() ຈະ throw ຖ້າ stream ອື່ນ
  // (ເຊັ່ນ ໜ້າ "My Bookings" ຂອງລູກຄ້າ ຫຼື watchActiveBookings ຂອງຊ່າງ) ອ່ານ
  // booking ນີ້ໃນຊ່ວງທີ່ status ຖືກຂຽນເປັນຄ່ານີ້. ໃຊ້ field ແຍກຕ່າງຫາກແທນ.
  Future<void> _markMatchConfirmed() async {
    if (widget.bookingId.isEmpty) return;
    try {
      await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .update({
        'matchConfirmed': true,
        'updatedAt':       FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('markMatchConfirmed: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) async {
        if (_state == _MatchState.confirmed) {
          Navigator.pop(context);
        } else {
          final ok = await _showCancelDialog();
          if (ok && mounted) _cancelBooking();
        }
      },
      child: Scaffold(
        backgroundColor: C.navy,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: switch (_state) {
              _MatchState.loading   => _buildSkeleton(),
              _MatchState.searching => _buildSearching(),
              _MatchState.waiting   => _buildWaiting(),
              _MatchState.matched   => _buildMatched(),
              _MatchState.confirmed => _buildConfirmed(),
              _MatchState.noProvider=> _buildNoProvider(),
            },
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // SKELETON
  // ════════════════════════════════════════════════════════

  Widget _buildSkeleton() => Padding(
    key: const ValueKey('skeleton'),
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 20),
      _Shimmer(width: double.infinity, height: 40, radius: 12),
      const SizedBox(height: 60),
      const Center(child: _Shimmer(width: 170, height: 170, radius: 85)),
      const SizedBox(height: 40),
      const _Shimmer(width: 200, height: 28, radius: 8),
      const SizedBox(height: 12),
      const _Shimmer(width: 140, height: 18, radius: 6),
      const SizedBox(height: 48),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        _Shimmer(width: 90, height: 32, radius: 20),
        SizedBox(width: 12),
        _Shimmer(width: 90, height: 32, radius: 20),
        SizedBox(width: 12),
        _Shimmer(width: 90, height: 32, radius: 20),
      ]),
    ]),
  );

  // ════════════════════════════════════════════════════════
  // SEARCHING VIEW
  // ════════════════════════════════════════════════════════

  Widget _buildSearching() => Padding(
    key: const ValueKey('searching'),
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 20),
      _TopBar(onCancel: _cancelBooking, searchSecs: _searchSecs),
      const SizedBox(height: 60),
      _SpinningPulseCircle(emoji: _serviceEmoji, pulseAnim: _pulseAnim),
      const SizedBox(height: 48),
      Text(tr('searching_title'), style: const TextStyle(
        color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
      )),
      const SizedBox(height: 12),
      // ✅ ສະແດງຊື່ບໍລິການແທ້ຈິງທີ່ລູກຄ້າເລືອກ (fallback ລະຫວ່າງລໍຖ້າໂຫຼດ)
      Text(_serviceName.isNotEmpty ? _serviceName : tr('service_generic'), style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 16, fontWeight: FontWeight.w600,
      )),
      const SizedBox(height: 48),
      const _SearchingDots(),
      const SizedBox(height: 16),
      // ✅ Countdown ໃຫ້ລູກຄ້າຮູ້ວ່າລະບົບກຳລັງພະຍາຍາມຄົ້ນຫາຢູ່ — ບໍ່ຮູ້ສຶກວ່າແອັບຄ້າງ
      Text('${tr('searching_continue_prefix')} $_searchSecsLeft ${tr('sec')}', style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 13, fontWeight: FontWeight.w600,
      )),
      const SizedBox(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _InfoChip(Icons.people_outline,  tr('info_chip_online_techs')),
        const SizedBox(width: 12),
        _InfoChip(Icons.star_outline,    tr('info_chip_avg_rating')),
        const SizedBox(width: 12),
        _InfoChip(Icons.bolt_outlined,   tr('info_chip_fast_eta')),
      ]),
      const Spacer(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _cancelBooking,
          style: OutlinedButton.styleFrom(
            foregroundColor: C.dangerRed,
            side: const BorderSide(color: C.dangerRed, width: 1.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(tr('cancel_search'), style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
          )),
        ),
      ),
      const SizedBox(height: 16),
    ]),
  );

  // ════════════════════════════════════════════════════════
  // WAITING VIEW — ສົ່ງໄປ Top 3 ແລ້ວ ລໍຖ້າ
  // ════════════════════════════════════════════════════════

  Widget _buildWaiting() => Padding(
    key: const ValueKey('waiting'),
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 20),
      _TopBar(onCancel: _cancelBooking, searchSecs: _searchSecs),
      const SizedBox(height: 32),

      // Top 3 cards
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('📡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                '${tr('sent_request_prefix')} ${_top3.length} ${tr('provider')}',
                style: const TextStyle(
                  color: C.yellow, fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              tr('first_come_first_served'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ..._top3.asMap().entries.map((e) =>
                _Top3ProviderRow(
                  rank:     e.key + 1,
                  provider: e.value,
                  custLat:  _custLat,
                  custLng:  _custLng,
                ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),

      ScaleTransition(
        scale: _pulseAnim,
        child: _PulseCircle(emoji: _serviceEmoji, size: 100),
      ),
      const SizedBox(height: 24),
      Text(tr('waiting_provider_title'), style: const TextStyle(
        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800,
      )),
      const SizedBox(height: 8),
      const _SearchingDots(),
      const Spacer(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _cancelBooking,
          style: OutlinedButton.styleFrom(
            foregroundColor: C.dangerRed,
            side: const BorderSide(color: C.dangerRed, width: 1.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(tr('cancel'), style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
          )),
        ),
      ),
      const SizedBox(height: 16),
    ]),
  );

  // ════════════════════════════════════════════════════════
  // MATCHED VIEW
  // ════════════════════════════════════════════════════════

  Widget _buildMatched() {
    final p = _matchedProv!;
    return SingleChildScrollView(
      key: const ValueKey('matched'),
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 16),

        // badge
        ScaleTransition(
          scale: _matchAnim,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: C.green, borderRadius: BorderRadius.circular(30),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(tr('matched'), style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800,
              )),
            ]),
          ),
        ),
        const SizedBox(height: 28),

        // provider card
        ScaleTransition(
          scale: _matchAnim,
          child: _ProviderCard(
            provider:     p,
            serviceEmoji: _serviceEmoji,
            serviceName:  _serviceName,
            address:      _address,
          ),
        ),
        const SizedBox(height: 28),

        // countdown
        _CountdownRing(countdown: _countdown),
        const SizedBox(height: 28),

        // buttons
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: C.green, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(tr('confirm_now'), style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800,
            )),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _cancelBooking,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(tr('cancel'), style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7), fontSize: 15,
            )),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════
  // CONFIRMED VIEW
  // ════════════════════════════════════════════════════════

  Widget _buildConfirmed() {
    final p = _matchedProv!;
    return _ConfirmedView(
      key:          const ValueKey('confirmed'),
      provider:     p,
      serviceName:  _serviceName,
      serviceEmoji: _serviceEmoji,
      address:      _address,
      onTracking:   _goTracking,
      onDone:       () => Navigator.pop(context),
    );
  }

  // ════════════════════════════════════════════════════════
  // NO PROVIDER VIEW
  // ════════════════════════════════════════════════════════

  Widget _buildNoProvider() => Padding(
    key: const ValueKey('noprovider'),
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('😔', style: TextStyle(fontSize: 80)),
        const SizedBox(height: 24),
        Text(tr('no_provider'), style: const TextStyle(
          color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 12),
        Text(
          tr('no_provider_desc'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 15, height: 1.6,
          ),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _retry,
            style: ElevatedButton.styleFrom(
              backgroundColor: C.yellow, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(tr('retry'), style: const TextStyle(
              color: C.navy, fontSize: 16, fontWeight: FontWeight.w800,
            )),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('go_back'), style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5), fontSize: 15,
          )),
        ),
      ],
    ),
  );

  // ── cancel dialog ─────────────────────────────────────────

  Future<bool> _showCancelDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.navy,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(tr('cancel_booking_question'), style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w800,
        )),
        content: Text(tr('cancel_confirm_short'), style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('no'), style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
            )),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(tr('cancel'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }
}

// ════════════════════════════════════════════════════════════
// CONFIRMED VIEW (StatefulWidget — ມີ animation ຂອງຕົນເອງ)
// ════════════════════════════════════════════════════════════

class _ConfirmedView extends StatefulWidget {
  final ProviderModel provider;
  final String        serviceName;
  final String        serviceEmoji;
  final String        address;
  final VoidCallback  onTracking;
  final VoidCallback  onDone;

  const _ConfirmedView({
    super.key,
    required this.provider,
    required this.serviceName,
    required this.serviceEmoji,
    required this.address,
    required this.onTracking,
    required this.onDone,
  });

  @override
  State<_ConfirmedView> createState() => _ConfirmedViewState();
}

class _ConfirmedViewState extends State<_ConfirmedView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    );
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ✅ FIX: AndroidManifest ຕ້ອງມີ <queries> tel scheme
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

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 32),

        // success icon
        ScaleTransition(scale: _anim, child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: C.green, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color:        C.green.withValues(alpha: 0.4),
              blurRadius:   30,
              spreadRadius: 10,
            )],
          ),
          child: const Icon(Icons.check_rounded,
              color: Colors.white, size: 64),
        )),
        const SizedBox(height: 32),

        Text(tr('confirmed'), style: const TextStyle(
          color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900,
        )),
        const SizedBox(height: 12),
        Text(
          '${p.displayName} ${tr('provider_coming_suffix')}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8), fontSize: 16,
          ),
        ),
        const SizedBox(height: 32),

        // ETA card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.access_time_rounded,
                  color: C.yellow, size: 20),
              const SizedBox(width: 8),
              Text(
                '${tr('eta_estimate_prefix')} 20 ${tr('minutes_unit')}',
                style: const TextStyle(
                  color: C.yellow, fontSize: 16, fontWeight: FontWeight.w800,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _StatusStep('1', '🚗', '${p.displayName} ${tr('status_provider_going_suffix')}', true),
            const SizedBox(height: 10),
            _StatusStep('2', '📍', tr('status_step_arrived'),    false),
            const SizedBox(height: 10),
            _StatusStep('3', '🔧', tr('status_step_started'), false),
            const SizedBox(height: 10),
            _StatusStep('4', '✅', tr('status_step_done'),     false),
          ]),
        ),

        if (widget.address.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.location_on_outlined,
                  color: C.yellow, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.address, style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 13,
              ))),
            ]),
          ),
        ],
        const SizedBox(height: 32),

        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _callProvider,
            icon: const Icon(Icons.phone_outlined,
                color: Colors.white, size: 18),
            label: Text(tr('call_provider_btn'), style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700,
            )),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: widget.onTracking,
            icon: const Icon(Icons.track_changes_outlined,
                color: Colors.white, size: 18),
            label: Text(tr('track_btn'), style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800,
            )),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.yellow.withValues(alpha: 0.25),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final VoidCallback onCancel;
  final int          searchSecs;
  const _TopBar({required this.onCancel, required this.searchSecs});

  String get _timeLabel {
    final m = searchSecs ~/ 60;
    final s = searchSecs % 60;
    return m > 0
        ? '$m${tr("min_abbr")} ${s.toString().padLeft(2, '0')}${tr("sec")}'
        : '$s${tr("sec")}';
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onCancel,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 20),
        ),
      ),
    ),
    const Spacer(),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        C.yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.access_time, color: C.yellow, size: 14),
        const SizedBox(width: 4),
        Text(_timeLabel, style: const TextStyle(
          color: C.yellow, fontSize: 12, fontWeight: FontWeight.w700,
        )),
      ]),
    ),
  ]);
}

// ── pulse circle ──────────────────────────────────────────

class _PulseCircle extends StatelessWidget {
  final String emoji;
  final double size;
  const _PulseCircle({required this.emoji, this.size = 120});

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      ...List.generate(3, (i) => Container(
        width:  size + (i * 50),
        height: size + (i * 50),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: C.yellow.withValues(alpha: 0.28 - (i * 0.08)),
            width: 2,
          ),
        ),
      )),
      Container(
        width: size, height: size,
        decoration: const BoxDecoration(
            color: C.yellow, shape: BoxShape.circle),
        child: Center(child: Text(
          emoji.isNotEmpty ? emoji : '🔧',
          style: TextStyle(fontSize: size * 0.43),
        )),
      ),
    ],
  );
}

// ── spinning pulse circle (searching state) ────────────────
// ✅ Circular progress ring ໝູນອ້ອມ icon ກະແຈ — ທັນສະໄໝກວ່າ pulse rings ດ່ຽວ
class _SpinningPulseCircle extends StatefulWidget {
  final String     emoji;
  final Animation<double> pulseAnim;
  const _SpinningPulseCircle({required this.emoji, required this.pulseAnim});

  @override
  State<_SpinningPulseCircle> createState() => _SpinningPulseCircleState();
}

class _SpinningPulseCircleState extends State<_SpinningPulseCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() { _spinCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      RotationTransition(
        turns: _spinCtrl,
        child: SizedBox(
          width: 170, height: 170,
          child: CircularProgressIndicator(
            strokeWidth:     3,
            backgroundColor: Colors.transparent,
            valueColor:      const AlwaysStoppedAnimation(C.yellow),
            value:           0.25,
            strokeCap:       StrokeCap.round,
          ),
        ),
      ),
      ScaleTransition(
        scale: widget.pulseAnim,
        child: _PulseCircle(emoji: widget.emoji),
      ),
    ],
  );
}

// ── Top 3 row ─────────────────────────────────────────────

class _Top3ProviderRow extends StatelessWidget {
  final int           rank;
  final ProviderModel provider;
  final double?       custLat;
  final double?       custLng;
  const _Top3ProviderRow({
    required this.rank,
    required this.provider,
    this.custLat,
    this.custLng,
  });

  @override
  Widget build(BuildContext context) {
    final dist = provider.distanceTo(custLat, custLng);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(children: [
        // rank badge
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: rank == 1 ? C.yellow : Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(
            '#$rank',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: rank == 1 ? C.navy : Colors.white,
            ),
          )),
        ),
        const SizedBox(width: 10),
        // avatar
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: C.yellow.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(
            provider.avatarLetter,
            style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: C.yellow,
            ),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(provider.displayName, style: const TextStyle(
              color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w700,
            )),
            Row(children: [
              const Icon(Icons.star_rounded,
                  color: C.yellow, size: 12),
              const SizedBox(width: 3),
              Text(provider.ratingLabel, style: const TextStyle(
                color: C.yellow, fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
              if (dist != null) ...[
                Text('  ·  ${dist.toStringAsFixed(1)} ${tr('km_unit')}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    )),
              ],
            ]),
          ],
        )),
        // animated waiting dot
        _WaitingDot(),
      ]),
    );
  }
}

class _WaitingDot extends StatefulWidget {
  @override
  State<_WaitingDot> createState() => _WaitingDotState();
}

class _WaitingDotState extends State<_WaitingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: C.yellow.withValues(alpha: 0.4 + _ctrl.value * 0.6),
        shape: BoxShape.circle,
      ),
    ),
  );
}

// ── provider card ─────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final ProviderModel provider;
  final String        serviceEmoji;
  final String        serviceName;
  final String        address;
  const _ProviderCard({
    required this.provider,
    required this.serviceEmoji,
    required this.serviceName,
    required this.address,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color:        Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Column(children: [
      Row(children: [
        Container(
          width: 70, height: 70,
          decoration: BoxDecoration(
            color:        C.yellow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Center(child: Text(
            provider.avatarLetter,
            style: const TextStyle(
              fontSize: 32, color: C.navy, fontWeight: FontWeight.w900,
            ),
          )),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(provider.displayName, style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
            )),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.star_rounded, color: C.yellow, size: 16),
              const SizedBox(width: 4),
              Text(provider.ratingLabel, style: const TextStyle(
                color: C.yellow, fontSize: 14, fontWeight: FontWeight.w700,
              )),
              Text('  ·  ${provider.totalJobs}+ ${tr('jobs_unit')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 13,
                  )),
            ]),
            const SizedBox(height: 6),
            if (provider.isVerified)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        C.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_outlined,
                      color: C.green, size: 13),
                  const SizedBox(width: 4),
                  Text(tr('verified_badge'), style: const TextStyle(
                    color: C.green, fontSize: 11, fontWeight: FontWeight.w700,
                  )),
                ]),
              ),
          ],
        )),
      ]),
      const SizedBox(height: 16),
      const Divider(color: Colors.white24),
      const SizedBox(height: 12),
      Row(children: [
        _StatCol(serviceEmoji, serviceName, tr('services')),
        _StatCol('🕐', '~20 ${tr('minutes_unit')}', 'ETA'),
        _StatCol('📍', tr('near_you'), tr('distance_label')),
      ]),
      if (address.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.location_on_outlined,
                color: C.yellow, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(address, style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8), fontSize: 13,
            ))),
          ]),
        ),
      ],
    ]),
  );
}

class _StatCol extends StatelessWidget {
  final String emoji, value, label;
  const _StatCol(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 22)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(
      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
    ), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
    Text(label, style: TextStyle(
      color: Colors.white.withValues(alpha: 0.5), fontSize: 10,
    )),
  ]));
}

// ── countdown ring ────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final int countdown;
  const _CountdownRing({required this.countdown});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(tr('auto_confirm_in'), style: TextStyle(
      color: Colors.white.withValues(alpha: 0.6), fontSize: 13,
    )),
    const SizedBox(height: 8),
    Stack(alignment: Alignment.center, children: [
      SizedBox(
        width: 90, height: 90,
        child: CircularProgressIndicator(
          value:           countdown / 30,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation(
              countdown > 10 ? C.green : C.red),
          strokeWidth: 6,
        ),
      ),
      Text('$countdown', style: TextStyle(
        color:      countdown > 10 ? Colors.white : C.red,
        fontSize:   32,
        fontWeight: FontWeight.w900,
      )),
    ]),
    const SizedBox(height: 6),
    Text(tr('seconds_label'), style: TextStyle(
      color: Colors.white.withValues(alpha: 0.5), fontSize: 12,
    )),
  ]);
}

// ── status step ───────────────────────────────────────────

class _StatusStep extends StatelessWidget {
  final String num, emoji, label;
  final bool   isActive;
  const _StatusStep(this.num, this.emoji, this.label, this.isActive);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: isActive
            ? C.green
            : Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(child: Text(emoji,
          style: const TextStyle(fontSize: 14))),
    ),
    const SizedBox(width: 12),
    Expanded(child: Text(label, style: TextStyle(
      color: isActive
          ? Colors.white
          : Colors.white.withValues(alpha: 0.5),
      fontSize: 14,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
    ))),
    if (isActive)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        C.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tr('live_badge'), style: const TextStyle(
          color: C.green, fontSize: 10, fontWeight: FontWeight.w800,
        )),
      ),
  ]);
}

// ── info chip ─────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color:        Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 13),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
      )),
    ]),
  );
}

// ════════════════════════════════════════════════════════════
// SEARCHING DOTS  ✅ FIX: ໃຊ້ Timer ແທນ AnimationController
// ════════════════════════════════════════════════════════════

class _SearchingDots extends StatefulWidget {
  const _SearchingDots();

  @override
  State<_SearchingDots> createState() => _SearchingDotsState();
}

class _SearchingDotsState extends State<_SearchingDots> {
  int    _dot   = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // ✅ FIX: ໃຊ້ Timer ແທນ AnimationController
    // AnimationController.repeat() ບໍ່ fire AnimationStatus.completed
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _dot = (_dot + 1) % 3);
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // ✅ dispose timer
    super.dispose();
  }

  // ✅ pulse fade ໃນ-ອອກ ສະຫຼັບກັນ ແທນທີ່ຈະພຽງປ່ຽນຄວາມກວ້າງ
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve:    Curves.easeInOut,
      margin:   const EdgeInsets.symmetric(horizontal: 5),
      width:    _dot == i ? 14 : 8,
      height:   _dot == i ? 14 : 8,
      decoration: BoxDecoration(
        color: Color.lerp(
          Colors.white.withValues(alpha: 0.25),
          C.yellow,
          _dot == i ? 1.0 : 0.0,
        ),
        shape: BoxShape.circle,
        boxShadow: _dot == i
            ? [BoxShadow(
                color:      C.yellow.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              )]
            : null,
      ),
    )),
  );
}

// ════════════════════════════════════════════════════════════
// SHIMMER
// ════════════════════════════════════════════════════════════

class _Shimmer extends StatefulWidget {
  final double width, height, radius;
  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.04, end: 0.12)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width:  widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: _anim.value),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    ),
  );
}