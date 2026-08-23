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
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'theme/app_theme.dart' show AppRadius;
import 'app_locale.dart';
import 'Booking.dart' show serviceIconForCategory;
import 'booking_repository.dart';
import 'geohash_util.dart';
import 'provider_model.dart';
import 'tracking_screen.dart';
import 'widgets/app_button.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/pulsing_fade.dart';

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
  final String? initialAddress;
  final double? customerLat;
  final double? customerLng;

  const MatchScreen({
    super.key,
    required this.bookingId,
    this.initialServiceName,
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
  // ✅ [FIX H11 follow-up] serviceEmoji ຄົງໄວ້ສະເພາະສົ່ງຕໍ່ໃຫ້ TrackingScreen/
  // ReviewScreen (ຍັງອາໄສ String emoji ຢູ່) — ໜ້ານີ້ເອງສະແດງດ້ວຍ _serviceIcon
  // (Material icon, derive ຈາກ category) ບໍ່ແມ່ນ emoji ດິບອີກຕໍ່ໄປ
  String         _serviceEmoji = '🔧';
  IconData       _serviceIcon  = Icons.build_outlined;
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

  // 🔒 [AUDIT M-8 / 2026-07-27] cache — set once by _loadBookingMeta(),
  // re-used by every _findAndSendTop3() retry instead of re-fetching.
  String? _cachedCategory;

  // 🔒 [AUDIT CUST-2 / 2026-08-02 — High, fresh re-audit] booking ທີ່ຖືກສ້າງ
  // ຈາກ "ຈອງດຽວນີ້" ໃນໜ້າໂປຣໄຟລ໌ຊ່າງສະເພາະຄົນ (provider_details_screen.dart)
  // ມີ providerId ຕັ້ງໄວ້ແລ້ວຕັ້ງແຕ່ສ້າງ — ແຕ່ _findAndSendTop3() ຂ້າງລຸ່ມ ບໍ່ເຄີຍ
  // ຮູ້ຈັກຄ່ານີ້ເລີຍ, ແລ່ນ top-3 auto-match ຄືກັນທຸກ booking. ນອກຈາກຈະ "ບໍ່
  // ຮັບປະກັນ" ວ່າຊ່າງທີ່ຖືກເລືອກຈະໄດ້ຮັບຄຳຂໍ, ຍັງເປັນຊ່ອງໂຫວ່ດ້ານຄວາມປອດໄພນຳ —
  // _sendRequestToTop3() ຂຽນ sentTo=[3 ຄົນທີ່ oto-match ຫາໄດ້] ໂດຍກົງ, ເຮັດໃຫ້
  // isOpenOrTargeted()/isValidSentToTargeting() (firestore.rules) ອະນຸຍາດ
  // ຄົນອື່ນນອກຈາກຊ່າງທີ່ຖືກເລືອກ ອ່ານ/ຮັບ booking ນີ້ໄດ້ (ຂຽນທັບ providerId
  // ຂອງຕົນເອງ). ຕອນນີ້ ຖ້າ booking ມີ providerId ມາແລ້ວ, ສົ່ງຄຳຂໍໃຫ້ຄົນນັ້ນ
  // ຄົນດຽວເທົ່ານັ້ນ (ຂ້າມ top-3 search ທັງໝົດ) — ເບິ່ງ _findAndSendTop3().
  String? _directProviderId;

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
    String emoji = '🔧';
    String addr  = widget.initialAddress      ?? '';
    String category = 'ac_clean';

    try {
      final doc = await _db
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (doc.exists) {
        final d = doc.data()!;
        name     = d['serviceName']  as String? ??
            d['serviceType']  as String? ?? name;
        emoji    = d['serviceEmoji'] as String? ?? emoji;
        addr     = d['address']      as String? ?? addr;
        category = d['category']     as String? ?? category;
        _custLat ??= (d['lat'] as num?)?.toDouble();
        _custLng ??= (d['lng'] as num?)?.toDouble();
        final pid = d['providerId'] as String?;
        if (pid != null && pid.isNotEmpty) _directProviderId = pid;
      }
    } catch (e) {
      debugPrint('loadBookingMeta: $e');
    }

    // 🔒 [AUDIT M-8 / 2026-07-27] ບັນທຶກ category ໄວ້ໃນ instance field —
    // _findAndSendTop3() ຂ້າງລຸ່ມນີ້ ເຄີຍ re-fetch booking doc ນີ້ຄືນທຸກຄັ້ງທີ່
    // _scheduleRetry() ເອີ້ນມັນ (ທຸກ 4 ວິ, ສູງສຸດ ~11 ຄັ້ງພາຍໃນ 45 ວິ) ພຽງແຕ່
    // ເພື່ອອ່ານ category ດຽວກັນທີ່ບໍ່ເຄີຍປ່ຽນ — ບໍ່ຈຳເປັນ, ເສຍ Firestore read
    // ໂດຍບໍ່ມີປະໂຫຍດ.
    _cachedCategory = category;

    if (!mounted) return;
    setState(() {
      _serviceName  = name;
      _serviceEmoji = emoji;
      _serviceIcon  = serviceIconForCategory(category);
      _address      = addr;
      _state        = _MatchState.searching;
    });
  }

  // ════════════════════════════════════════════════════════
  // AUTO-MATCH: FIND TOP 3
  // ════════════════════════════════════════════════════════

  Future<void> _findAndSendTop3({bool widen = false}) async {
    try {
      // 🔒 [AUDIT CUST-2 / 2026-08-02] booking ນີ້ຖືກຈອງໃສ່ຊ່າງສະເພາະຄົນໂດຍກົງ —
      // ຂ້າມ top-3 auto-match ທັງໝົດ, ສົ່ງຄຳຂໍໃຫ້ຄົນນັ້ນຄົນດຽວ. ດຶງໂປຣໄຟລ໌ຂອງ
      // ຊ່າງຄົນນັ້ນມາໃສ່ _top3 (1 ຄົນ) ເພື່ອໃຫ້ໜ້າ "ກຳລັງລໍຖ້າ" ຂ້າງລຸ່ມສະແດງຊື່/
      // ຮູບ/ຄະແນນຊ່າງທີ່ຖືກເລືອກໄດ້ຄືເກົ່າ (ແທນທີ່ຈະຫວ່າງເປົ່າ).
      if (_directProviderId != null && _directProviderId!.isNotEmpty) {
        try {
          final pDoc = await _db.collection('providers').doc(_directProviderId!).get();
          if (pDoc.exists) _top3 = [ProviderModel.fromDoc(pDoc)];
        } catch (_) {}
        final sent = await _sendRequestToIds([_directProviderId!]);
        if (!mounted) return;
        if (!sent) {
          _scheduleRetry();
          return;
        }
        setState(() => _state = _MatchState.waiting);
        return;
      }

      // 🔒 [AUDIT M-8 / 2026-07-27] ໃຊ້ _cachedCategory ທີ່ _loadBookingMeta()
      // ຕັ້ງໄວ້ແລ້ວ ແທນການ re-fetch booking doc ນີ້ຄືນທຸກຄັ້ງທີ່ retry —
      // category ບໍ່ເຄີຍປ່ຽນຫຼັງ booking ຖືກສ້າງ. Fallback ໄປ query ຄືນສະເພາະ
      // ຖ້າຄ່າ cache ຍັງບໍ່ຖືກຕັ້ງ (ບໍ່ຄວນເກີດຂຶ້ນປົກກະຕິ — _init() await
      // _loadBookingMeta() ກ່ອນ _findAndSendTop3() ສະເໝີ — ແຕ່ເປັນ safety net).
      String category = _cachedCategory ?? 'ac_clean';
      if (_cachedCategory == null) {
        try {
          final bDoc = await _db
              .collection('bookings')
              .doc(widget.bookingId)
              .get();
          if (bDoc.exists) {
            category = bDoc.data()?['category'] as String? ?? category;
          }
        } catch (_) {}
        _cachedCategory = category;
      }

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
        // ✅ [AUDIT CRIT-3 fix] composite index ນີ້ຖືກປະກາດຢູ່
        // firestore.indexes.json ແລ້ວ (providers: isOnline Asc, serviceTypes
        // Array, geohash Asc) — deploy ດ້ວຍ `firebase deploy --only
        // firestore:indexes` ກ່ອນ release. ກ່ອນໜ້ານີ້ບໍ່ໄດ້ຖືກ track ຢູ່ນີ້ ຈຶ່ງ
        // throw FAILED_PRECONDITION ທຸກຄັ້ງນອກ project ທີ່ສ້າງ index ດ້ວຍມື.
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
      var providers = snap.docs
          .map((d) => ProviderModel.fromDoc(d))
          .toList();

      // 🔒 [AUDIT EDGE-3 / 2026-08-06] isOnline:true ອາດຄ້າງຢູ່ Firestore
      // ໂດຍ provider ບໍ່ໄດ້ອອນລາຍແທ້ (ແອັບຖືກ force-kill/ຂາດເນັດຖາວອນກ່ອນ
      // dispose() ໄດ້ຮັນ, ເບິ່ງຄໍາເຫັນຢູ່ ProviderModel.locationUpdatedAt) —
      // ກັ່ນຕອງອອກ provider ທີ່ isOnline:true ແຕ່ບໍ່ມີການອັບເດດ location ໃນ
      // ໄລຍະໃກ້ໆນີ້ (LocationService ຂຽນທຸກ 5 ວິນາທີໃນຂະນະ online ແທ້). ໃຫ້
      // provider ທີ່ບໍ່ເຄີຍມີ locationUpdatedAt ເລີຍ (ຍັງບໍ່ທັນ migrate/GPS
      // ປິດ) ຜ່ານໄດ້ຄືເກົ່າ — ບໍ່ດັ່ງນັ້ນຈະຕັດ provider ຖືກຕ້ອງອອກໂດຍບໍ່ຕັ້ງໃຈ.
      final freshnessCutoff = DateTime.now().subtract(const Duration(minutes: 10));
      providers = providers.where((p) =>
          p.locationUpdatedAt == null ||
          p.locationUpdatedAt!.isAfter(freshnessCutoff)).toList();
      if (providers.isEmpty) {
        _scheduleRetry();
        return;
      }

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
      final sent = await _sendRequestToIds(_top3.map((p) => p.uid).toList());

      if (!mounted) return;
      // 🔒 [AUDIT M-6 / 2026-07-27] ກ່ອນໜ້ານີ້ transition ໄປ 'waiting'
      // ໂດຍບໍ່ສົນວ່າ write ຈິງສຳເລັດຫຼືບໍ່ — ຖ້າອິນເຕີເນັດຂາດຊົ່ວຄາວຕອນນີ້ພໍດີ,
      // ລູກຄ້າຈະເຫັນ "ສົ່ງຄຳຂໍໃຫ້ 3 ຊ່າງແລ້ວ" ທັງໆທີ່ sentTo ບໍ່ເຄີຍຖືກຂຽນຈິງ.
      // ຕອນນີ້ _sendRequestToTop3() ສົ່ງຄືນ bool (retry ພາຍໃນ 1 ຄັ້ງກ່ອນ) —
      // ຖ້າຍັງລົ້ມເຫຼວ, ປະຕິບັດຄືກັບ "ຍັງບໍ່ພົບຊ່າງ" (ບໍ່ແມ່ນ hard failure —
      // booking ຍັງເບິ່ງເຫັນໄດ້ຢູ່ໃນ job board ເພາະ sentTo ບໍ່ຖືກຈຳກັດ) ແລ້ວ
      // retry ຕໍ່ຕາມກຳນົດເວລາເກົ່າ ແທນທີ່ຈະສະແດງ UI ທີ່ບໍ່ກົງກັບຄວາມຈິງ.
      if (!sent) {
        _scheduleRetry();
        return;
      }
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

  // 🔒 [AUDIT M-6 / 2026-07-27] ສົ່ງຄືນ bool ຄວາມສຳເລັດ (ແທນ void) ໃຫ້ caller
  // ຮູ້ໄດ້ວ່າ write ນີ້ຈິງໆສຳເລັດ ຫຼື ບໍ່ — ກ່ອນໜ້ານີ້ error ຖືກ swallow ງຽບໆຢູ່
  // ນີ້, caller ຈຶ່ງສະແດງ UI "ສົ່ງແລ້ວ" ໂດຍບໍ່ຮູ້ຕົວວ່າ write ລົ້ມເຫຼວ. retry
  // ໜຶ່ງຄັ້ງເອງພາຍໃນ (transient ອິນເຕີເນັດຂາດຊົ່ວຄາວ) ກ່ອນຍອມແພ້.
  // 🔒 [AUDIT CUST-2 / 2026-08-02] renamed from _sendRequestToTop3 — now takes
  // raw provider IDs so it can serve both the top-3 auto-match list AND a
  // single directly-chosen provider (_directProviderId) with the same
  // atomic-write/retry logic.
  Future<bool> _sendRequestToIds(List<String> ids) async {
    if (ids.isEmpty) return false;

    Future<bool> attempt() async {
      try {
        // 🔒 [AUDIT CRIT-5] ບໍ່ເຄີຍມີ timeout — ຖ້າຄ້າງ, _findAndSendTop3() ຈະ
        // ຄ້າງຢູ່ await ນີ້ໂດຍບໍ່ throw (state ບໍ່ປ່ຽນເປັນ waiting), ອາໄສແຕ່
        // _searchTimer (45s) ເປັນ safety net ດຽວ. ຕອນນີ້ timeout ໄວກວ່ານັ້ນ
        // ໃຫ້ catch block ດ້ານລຸ່ມ log ໄດ້ທັນທີ.
        // 🔒 [AUDIT BE-1 / 2026-07-30] openToAll:false ຕ້ອງຂຽນພ້ອມກັບ sentTo ໃນ
        // write ດຽວກັນ (atomic) — ນີ້ຄືສິ່ງທີ່ບອກ firestore.rules'
        // isOpenOrTargeted() ວ່າ booking ນີ້ບໍ່ແມ່ນ "ເປີດໃຫ້ທຸກຄົນ" ອີກຕໍ່ໄປ, ຈຳກັດ
        // ໃຫ້ເຫັນສະເພາະ 3 ຄົນທີ່ຖືກເລືອກ (sentTo) ເທົ່ານັ້ນ.
        // 🔒 [AUDIT BE-2 / 2026-08-06] ກ່ອນໜ້ານີ້ເປັນ .update() ທຳມະດາ (ບໍ່ແມ່ນ
        // transaction) ທີ່ບັງຄັບຂຽນ status:'pending' ໂດຍບໍ່ກວດຄ່າປັດຈຸບັນກ່ອນ —
        // ຕ່າງຈາກທຸກ write ອື່ນທີ່ປ່ຽນ status ໃນແອັບ (acceptBooking,
        // rejectBooking, ...) ທີ່ລ້ວນແຕ່ອ່ານຄືນພາຍໃນ transaction ກ່ອນຂຽນ. ຖ້າ
        // write ນີ້ commit ຝັ່ງ server ແຕ່ client timeout ໃນເຄືອຂ່າຍຊ້າ,
        // scheduler ຈະ retry ຄັ້ງນີ້ອີກ — ຖ້າໃນລະຫວ່າງນັ້ນຊ່າງໄດ້ຮັບງານໄປແລ້ວ
        // (status:'accepted'), retry ນີ້ຈະຂຽນທັບ status ກັບໄປເປັນ 'pending'
        // ໄດ້ໂດຍບໍ່ຮູ້ຕົວ — undo ການຮັບງານຂອງຊ່າງ ແລະ ອາດເປີດຊ່ອງໃຫ້ຄົນທີ 2 ຮັບ
        // ງານດຽວກັນຊ້ຳ. ຕອນນີ້ອ່ານ status ປັດຈຸບັນພາຍໃນ transaction ດຽວກັນກ່ອນ —
        // ຂຽນສະເພາະຖ້າຍັງເປັນ 'pending' ຢູ່, ບໍ່ດັ່ງນັ້ນຖືວ່າ booking ໄດ້ຖືກແກ້
        // ໄຂແລ້ວ (ຮັບ/ຍົກເລີກ) ໂດຍທາງອື່ນ, ບໍ່ຕ້ອງຂຽນທັບ.
        final ref = _db.collection('bookings').doc(widget.bookingId);
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) return;
          final currentStatus = snap.data()?['status'] as String?;
          if (currentStatus != 'pending') return;
          tx.update(ref, {
            'sentTo':     ids,
            'openToAll':  false,
            'status':     'pending',
            'updatedAt':  FieldValue.serverTimestamp(),
          });
        }).timeout(const Duration(seconds: 15));
        // TODO: ສົ່ງ FCM push ຜ່ານ Cloud Function
        // ຕອນນີ້ provider app ຈະ stream bookings
        // ທີ່ sentTo contains uid ຂອງຕົນເອງ
        return true;
      } catch (e) {
        debugPrint('sendRequestToTop3: $e');
        return false;
      }
    }

    if (await attempt()) return true;
    return attempt(); // one retry before giving up
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
        // 🔒 [PHASE0 P1] estimatedMinutes ຖືກລຶບອອກ — ProviderModel ບໍ່ມີຟິลด์
        // ນີ້ (fromMap() ບໍ່ໄດ້ອ່ານມັນ), ດັ່ງນັ້ນຄ່ານີ້ຖືກຖິ້ມຢູ່ແລ້ວໂດຍງຽບ.
        // ໜ້າ UI ທີ່ເຄີຍອີງໃສ່ຄ່ານີ້ (ETA display) ຕອນນີ້ໃຊ້ຂໍ້ຄວາມທີ່ບໍ່ອ້າງ
        // ຕົວເລກແທນ — ເບິ່ງ eta_on_the_way.
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
        _cancelSilently('ໝົດເວລາຄົ້ນຫາ (no_provider_timeout)');
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

  // 🔒 [AUDIT H8] ກ່ອນໜ້ານີ້ Cancel ຈາກໜ້ານີ້ (ທັງ X-button ຕອນຄົ້ນຫາ ແລະ
  // ປຸ່ມ Cancel ຕອນ matched/confirmed) ເອີ້ນ _updateStatus('cancelled') —
  // ຂຽນ status ດິບໆ ບໍ່ຜ່ານ transaction, ບໍ່ບັນທຶກ cancelReason/cancelledBy/
  // cancelFeeAmount ເລີຍ. CustomerBookingRepository.cancelBooking() (ຢູ່
  // booking_repository.dart) ຄິດໄລ່ຄ່າທຳນຽມ+ບັນທຶກ attribution ຢ່າງຖືກຕ້ອງ
  // ຢູ່ແລ້ວແຕ່ບໍ່ເຄີຍຖືກເອີ້ນຈາກທຸກບ່ອນນີ້ເລີຍ (dead code) — ຕອນນີ້ໃຊ້ແທນ.
  final _customerBookingRepo = CustomerBookingRepository();

  // 🔒 [AUDIT H8 follow-up] ກ່ອນໜ້ານີ້ຖ້າ cancelBooking() throw (ອອບໄລນ໌,
  // ຫຼື provider ຫາກໍ່ປິດງານໃນເວລາດຽວກັນ), catch block ນີ້ພຽງແຕ່ debugPrint
  // ແລ້ວ Navigator.pop() ຕໍ່ໄປຄືກັນກັບສຳເລັດ — ຜູ້ໃຊ້ຄິດວ່າຍົກເລີກແລ້ວ ທັງໆທີ່
  // booking ອາດຍັງ active ຢູ່ຝັ່ງ server. ຕອນນີ້ pop ສະເພາະຕອນສຳເລັດ, ສະແດງ
  // error ໃຫ້ເຫັນຖ້າລົ້ມເຫລວ (ຄືກັນກັບ booking_detail_screen.dart's _confirmCancel).
  Future<void> _cancelBooking({String reason = ''}) async {
    _countdownTimer?.cancel();
    _searchTimer?.cancel();
    _retryTimer?.cancel();
    try {
      await _customerBookingRepo.cancelBooking(
          widget.bookingId, reason.isEmpty ? 'ລູກຄ້າຍົກເລີກ' : reason);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('cancelBooking: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr("error")}: $e'),
          backgroundColor: C.red));
    }
  }

  // 🔒 [FOLLOWUP-D] ກ່ອນໜ້ານີ້ເມື່ອຄົ້ນຫາໝົດເວລາ (45s) ຫຼືລູກຄ້າກົດ "ຍ້ອນກັບ" ຈາກ
  // ໜ້າ "ບໍ່ພົບຊ່າງ", booking doc ບໍ່ເຄີຍຖືກຍົກເລີກເລີຍ — ຄົງເປັນ status:'pending'
  // ຈົນກວ່າຈະໝົດອາຍຸເອງ (ເຖິງ 10 ນາທີ), ຊ່າງທີ່ຫາກໍ່ອອນລາຍໃນຊ່ວງນັ້ນຍັງສາມາດຮັບໄດ້
  // ທັງໆທີ່ລູກຄ້າຄິດວ່າການຄົ້ນຫາລົ້ມເຫລວແລ້ວ. ໃຊ້ method ນີ້ (ບໍ່ໃຊ້ _cancelBooking()
  // ໂດຍກົງ) ເພາະທາງນີ້ຕ້ອງ "ຄ້າງຢູ່ໜ້າຈໍ" ໃຫ້ເຫັນ noProvider state, ບໍ່ pop ອອກ.
  Future<void> _cancelSilently(String reason) async {
    try {
      await _customerBookingRepo.cancelBooking(widget.bookingId, reason);
    } catch (e) {
      debugPrint('cancelSilently: $e');
    }
  }

  // ✅ [FIX H8] ເກັບເຫດຜົນຍົກເລີກ (ບໍ່ບັງຄັບ) ກ່ອນ cancel — ໃຊ້ຢູ່ຈຸດທີ່ booking
  // ຖືກ accept ໄປແລ້ວ (matched/confirmed) ຄືກັນກັບ business rule ຈິງ
  Future<void> _confirmAndCancelWithReason() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.primaryDeepWash,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        title: Text(tr('cancel_booking_question'), style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w800,
        )),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('cancel_confirm_short'), style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
          )),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLength: 200,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: tr('cancel_reason_hint'),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
            ),
            child: Text(tr('cancel'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed == true && mounted) {
      await _cancelBooking(reason: reason);
    }
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
        serviceIcon:  _serviceIcon,
        address:      _address,
      ),
    ));
  }

  // ── Firestore write ───────────────────────────────────────

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
      }).timeout(const Duration(seconds: 15));
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
          await _confirmAndCancelWithReason();
        }
      },
      child: Scaffold(
        backgroundColor: C.primaryDeepWash,
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

  // ✅ [Redesign] "ac_clean"/"house_clean" (raw Firestore category slug)
  // ໄດ້ຫຼຸດເຂົ້າມາເປັນ _serviceName ຢູ່ບາງ booking ທີ່ບໍ່ມີ field
  // 'serviceName' ຂຽນໄວ້ (ມີແຕ່ 'serviceType' ເປັນ slug) — ແປງເປັນຊື່ອ່ານງ່າຍ
  // ກ່ອນສະແດງ, ບໍ່ແຕະຕ້ອງ pipeline ການສ້າງ booking ເອງ.
  static const _rawSlugToKey = {
    'ac_clean':    'svc_ac_clean',
    'house_clean': 'svc_house_clean',
  };
  static const _englishHint = {
    'svc_ac_clean':    'AC Cleaning',
    'svc_house_clean': 'House Cleaning',
  };

  String get _displayServiceName {
    final raw = _serviceName.trim();
    if (raw.isEmpty) return tr('service_generic');
    final key = _rawSlugToKey[raw];
    if (key == null) return raw; // ຊື່ແທ້ທີ່ອ່ານໄດ້ຢູ່ແລ້ວ — ສະແດງຄືເດີມ
    final label = tr(key);
    final hint = _englishHint[key];
    return (AppLocale.instance.lang == AppLang.lo && hint != null)
        ? '$label ($hint)'
        : label;
  }

  Widget _buildSearching() => Container(
    key: const ValueKey('searching'),
    width: double.infinity,
    height: double.infinity,
    // ✅ [Theme] gradient ຂຽວແບຣນ LinTho (C.green) ໄລ່ລົງຫາຂຽວທະເລເຂັ້ມ —
    // ແທນທີ່ navy/sky ເດີມ, ໃຫ້ຄວາມເລິກ/ບັນຍາກາດເຂົ້າກັບເອກະລັກແບຣນຫຼາຍຂຶ້ນ
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.35),
        radius: 1.15,
        colors: [
          Color.lerp(C.primaryDeepWash, C.green, 0.4)!,
          C.primaryDeepWash,
        ],
      ),
    ),
    // 🔒 [AUDIT H-6 / 2026-07-27] ກ່ອນໜ້ານີ້ Column ນີ້ຢູ່ໃນ Padding ທຳມະດາ
    // (ບໍ່ scroll ໄດ້) ພ້ອມ flexible-spacer widget — ບົນຈໍນ້ອຍ (iPhone SE-class),
    // ຂໍ້ຄວາມທີ່ຍາວ (ຊື່ບໍລິການ 2 ແຖວ), ຫຼື font scale ໃຫຍ່ກວ່າ 1.0, ເນື້ອຫາເກີນ
    // viewport ໄດ້ — ປຸ່ມ "cancel_search" (ທາງດຽວທີ່ຍົກເລີກໄດ້, PopScope ດັກ back
    // gesture ໄວ້ຄືກັນ) ຖືກດັນອອກຈາກຈໍ, ລູກຄ້າອາດຄ້າງຢູ່ໜ້ານີ້ໂດຍບໍ່ມີທາງອອກ.
    // ຕອນນີ້ຫຸ້ມດ້ວຍ SingleChildScrollView (ຄືກັນກັບ _buildMatched()/
    // _ConfirmedView ທີ່ຖືກຕ້ອງຢູ່ແລ້ວ) — flexible-spacer ຖືກປ່ຽນເປັນ SizedBox
    // ຄົງທີ່ ເພາະ Expanded/flexible-spacer ໃຊ້ໃນ
    // Column ພາຍໃນ scroll view ບໍ່ໄດ້ (unbounded height constraint).
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 20),
        _TopBar(onCancel: _cancelBooking, searchSecs: _searchSecs),
        const SizedBox(height: 48),
        _RadarPulse(icon: _serviceIcon),
        const SizedBox(height: 40),
        Text(tr('searching_title'), style: const TextStyle(
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
        )),
        const SizedBox(height: 12),
        // ✅ ສະແດງຊື່ບໍລິການແທ້ຈິງທີ່ລູກຄ້າເລືອກ (fallback ລະຫວ່າງລໍຖ້າໂຫຼດ)
        Text(_displayServiceName, textAlign: TextAlign.center, style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 16, fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 40),
        const _SearchingDots(),
        const SizedBox(height: 16),
        // ✅ Countdown ໃຫ້ລູກຄ້າຮູ້ວ່າລະບົບກຳລັງພະຍາຍາມຄົ້ນຫາຢູ່ — ບໍ່ຮູ້ສຶກວ່າແອັບຄ້າງ
        Text('${tr('searching_continue_prefix')} $_searchSecsLeft ${tr('sec')}', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13, fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(child: _GlassStat(Icons.people_outline,  tr('info_chip_online_techs'))),
          const SizedBox(width: 10),
          Expanded(child: _GlassStat(Icons.star_outline,    tr('info_chip_avg_rating'))),
          const SizedBox(width: 10),
          Expanded(child: _GlassStat(Icons.bolt_outlined,   tr('info_chip_fast_eta'))),
        ]),
        const SizedBox(height: 40),
        const SizedBox(height: 12),
        _SoftCancelButton(onPressed: _cancelBooking, label: tr('cancel_search')),
        const SizedBox(height: 16),
      ]),
    ),
  );

  // ════════════════════════════════════════════════════════
  // WAITING VIEW — ສົ່ງໄປ Top 3 ແລ້ວ ລໍຖ້າ
  // ════════════════════════════════════════════════════════

  // 🔒 [AUDIT H-6 / 2026-07-27] ຄືກັນກັບ _buildSearching() — ຫຸ້ມ
  // SingleChildScrollView ແທນ Padding ທຳມະດາ, flexible-spacer ປ່ຽນເປັນ SizedBox
  // ຄົງທີ່ (ເບິ່ງເຫດຜົນເຕັມຢູ່ _buildSearching()).
  Widget _buildWaiting() => SingleChildScrollView(
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
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.wifi_tethering, color: C.yellow, size: 18),
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
        child: _PulseCircle(icon: _serviceIcon, size: 100),
      ),
      const SizedBox(height: 24),
      Text(tr('waiting_provider_title'), style: const TextStyle(
        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800,
      )),
      const SizedBox(height: 8),
      const _SearchingDots(),
      const SizedBox(height: 40),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _cancelBooking,
          style: OutlinedButton.styleFrom(
            foregroundColor: C.dangerRed,
            side: const BorderSide(color: C.dangerRed, width: 1.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card)),
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
              color: C.green, borderRadius: BorderRadius.circular(AppRadius.sheet),
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
            provider:    p,
            serviceIcon: _serviceIcon,
            serviceName: _serviceName,
            address:     _address,
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
                  borderRadius: BorderRadius.circular(AppRadius.card)),
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
            // ✅ [FIX H8] provider ໄດ້ accept ໄປແລ້ວ (ຢູ່ໃນ 30s confirm window)
            // — cancel ຈາກຈຸດນີ້ຕ້ອງຜ່ານ confirm dialog + ບັນທຶກເຫດຜົນ
            onPressed: _confirmAndCancelWithReason,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card)),
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
      key:         const ValueKey('confirmed'),
      provider:    p,
      serviceName: _serviceName,
      address:     _address,
      onTracking:  _goTracking,
      onDone:      () => Navigator.pop(context),
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
        Icon(Icons.sentiment_dissatisfied_outlined,
            size: 80, color: Colors.white.withValues(alpha: 0.7)),
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
        // 🔒 [PHASE1] yellow → AppButton.primary — ທຸກ primary CTA ອື່ນຢູ່ໜ້ານີ້
        // (ລວມທັງ "Confirm Now" ຢູ່ _buildMatched) ໃຊ້ green ຢູ່ແລ້ວ, ມີແຕ່ອັນນີ້
        // ທີ່ແຕກຕ່າງໂດຍບໍ່ມີເຫດຜົນ
        AppButton.primary(
          label: tr('retry'),
          onPressed: _retry,
        ),
        const SizedBox(height: 12),
        TextButton(
          // 🔒 [FOLLOWUP-D] `_buildNoProvider()` ສະແດງໄດ້ພຽງ 2 ທາງ: (1) timer
          // ໝົດເວລາ — ຕອນນີ້ _cancelSilently() ຖືກເອີ້ນກ່ອນເຂົ້າ state ນີ້ (ເບິ່ງ
          // _startSearchTimer ຂ້າງເທິງ), ຫຼື (2) _watchBooking() ເຫັນ booking ຖືກ
          // cancelled/rejected ໄປແລ້ວ (ໂດຍຄົນອື່ນ/ອັດຕະໂນມັດ) — ທັງສອງທາງ booking
          // ຖືກຍົກເລີກແລ້ວກ່ອນຮອດ state ນີ້ຢູ່ແລ້ວ, ຈຶ່ງພຽງແຕ່ pop ອອກໄດ້ເລີຍ
          // (ບໍ່ຄວນເອີ້ນ cancelBooking() ຊ້ຳອີກ — ມັນ throw ຖ້າ status ຖືກຍົກເລີກ
          // ໄປແລ້ວ, ຈະສະແດງ error toast ໃຫ້ຜູ້ໃຊ້ເຫັນຢ່າງບໍ່ຈຳເປັນ).
          onPressed: () => Navigator.pop(context),
          child: Text(tr('go_back'), style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5), fontSize: 15,
          )),
        ),
      ],
    ),
  );

}

// ════════════════════════════════════════════════════════════
// CONFIRMED VIEW (StatefulWidget — ມີ animation ຂອງຕົນເອງ)
// ════════════════════════════════════════════════════════════

class _ConfirmedView extends StatefulWidget {
  final ProviderModel provider;
  final String        serviceName;
  final String        address;
  final VoidCallback  onTracking;
  final VoidCallback  onDone;

  const _ConfirmedView({
    super.key,
    required this.provider,
    required this.serviceName,
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
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.directions_car_filled_outlined,
                  color: C.yellow, size: 20),
              const SizedBox(width: 8),
              // 🔒 [PHASE0 P1] ເຄີຍສະແດງ "ຄາດວ່າຈະຮອດ ≈ 20 ນາທີ" ຄົງທີ່ —
              // ບໍ່ແມ່ນຄ່າຄິດໄລ່ແທ້ (ບໍ່ມີແຫຼ່ງຂໍ້ມູນໄລຍະທາງ/ຄວາມໄວແທ້ໆ). ໃຊ້
              // ຂໍ້ຄວາມທີ່ບໍ່ອ້າງຕົວເລກແທນ.
              Text(
                tr('eta_on_the_way'),
                style: const TextStyle(
                  color: C.yellow, fontSize: 16, fontWeight: FontWeight.w800,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _StatusStep('1', Icons.directions_car_outlined,
                '${p.displayName} ${tr('status_provider_going_suffix')}', true),
            const SizedBox(height: 10),
            _StatusStep('2', Icons.location_on_outlined,
                tr('status_step_arrived'), false),
            const SizedBox(height: 10),
            _StatusStep('3', Icons.build_outlined,
                tr('status_step_started'), false),
            const SizedBox(height: 10),
            _StatusStep('4', Icons.check_circle_outline,
                tr('status_step_done'), false),
          ]),
        ),

        if (widget.address.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.card),
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
                  borderRadius: BorderRadius.circular(AppRadius.card)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
          const SizedBox(width: 12),
          // 🔒 [PHASE1] translucent yellow → AppButton.primary — ຄືກັນກັບ
          // Retry button ຂ້າງເທິງ
          Expanded(child: AppButton.primary(
            label: tr('track_btn'),
            icon: Icons.track_changes_outlined,
            onPressed: widget.onTracking,
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
    // 🔒 [PHASE1] ເຄີຍ 40×40 (ຕ່ຳກວ່າ 44dp ຂັ້ນຕ່ຳ) ບໍ່ມີ Semantics/tooltip —
    // ນີ້ຄືທາງດຽວທີ່ຍົກເລີກ/ອອກໄດ້ຕອນກຳລັງຊອກຊ່າງ. AppIconButton ບັງຄັບ 44dp
    // + label ໂດຍອັດຕະໂນມັດ, ໃຫ້ color:white ເພື່ອຮັກສາໜ້າຕາ translucent-white
    // ເທິງພື້ນ gradient ເຂັ້ມໄວ້ຄືເກົ່າ
    AppIconButton(
      icon:  Icons.close,
      color: Colors.white,
      label: tr('cancel_search'),
      onTap: onCancel,
    ),
    const Spacer(),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        C.yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sheet),
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
  final IconData icon;
  final double   size;
  const _PulseCircle({required this.icon, this.size = 120});

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
        child: Center(child: Icon(
          icon, color: Colors.white, size: size * 0.43,
        )),
      ),
    ],
  );
}

// ── radar pulse (searching state) ───────────────────────────
// ✅ [Redesign] ແທນທີ່ _SpinningPulseCircle (progress ring ໝູນ + pulse ຄົງທີ່)
// ດ້ວຍ radar sonar ແທ້ໆ — 3 ວົງແຫວນຂະຫຍາຍອອກຈາງລົງເປັນຈັງຫວະຊ້ອນກັນ (staggered)
// ໃຫ້ຄວາມຮູ້ສຶກວ່າລະບົບກຳລັງສະແກນຫາຢູ່ຈິງ, ບໍ່ແມ່ນແຕ່ໝູນວົງ static.
class _RadarPulse extends StatefulWidget {
  final IconData icon;
  const _RadarPulse({required this.icon});

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse>
    with TickerProviderStateMixin {
  static const _ringDuration = Duration(milliseconds: 2400);
  static const _stagger      = Duration(milliseconds: 800);
  late final List<AnimationController> _rings;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();
    _rings = List.generate(3, (i) {
      final c = AnimationController(vsync: this, duration: _ringDuration);
      Future.delayed(_stagger * i, () { if (mounted) c.repeat(); });
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _rings) c.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const coreSize = 108.0;
    const maxGrowth = 118.0;
    return SizedBox(
      width: coreSize + maxGrowth,
      height: coreSize + maxGrowth,
      child: Stack(alignment: Alignment.center, children: [
        // ✅ ວົງແຫວນ radar 3 ວົງ — ຂະຫຍາຍ+ຈາງລົງ, ຊ້ອນຈັງຫວະກັນ 800ms
        for (final ring in _rings)
          AnimatedBuilder(
            animation: ring,
            builder: (_, __) {
              final t = Curves.easeOut.transform(ring.value);
              return Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width:  coreSize + maxGrowth * t,
                  height: coreSize + maxGrowth * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: C.gold, width: 1.6),
                  ),
                ),
              );
            },
          ),
        // ✅ ວົງແຫວນບາງໝູນຮອບນອກ — ຄື "ລະບົບກຳລັງເຮັດວຽກ" ຢ່າງຕໍ່ເນື່ອງ
        RotationTransition(
          turns: _spinCtrl,
          child: SizedBox(
            width: coreSize + 34, height: coreSize + 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(C.gold.withValues(alpha: 0.85)),
              value: 0.22,
              strokeCap: StrokeCap.round,
            ),
          ),
        ),
        // ✅ ແສງນວນວ໌ນຫຼັງ core — ໃຫ້ຄວາມເລິກແທນວົງແຫນນແປນສີດຽວ
        Container(
          width: coreSize, height: coreSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              C.gold.withValues(alpha: 0.9), C.gold,
            ]),
            boxShadow: [BoxShadow(
              color: C.gold.withValues(alpha: 0.45),
              blurRadius: 28, spreadRadius: 2,
            )],
          ),
          child: Center(child: Icon(
            widget.icon, color: Colors.white, size: 42,
          )),
        ),
      ]),
    );
  }
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
            borderRadius: BorderRadius.circular(AppRadius.chip),
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
  final IconData      serviceIcon;
  final String        serviceName;
  final String        address;
  const _ProviderCard({
    required this.provider,
    required this.serviceIcon,
    required this.serviceName,
    required this.address,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color:        Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Column(children: [
      Row(children: [
        Container(
          width: 70, height: 70,
          decoration: BoxDecoration(
            color:        C.yellow,
            borderRadius: BorderRadius.circular(AppRadius.sheet),
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
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
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
        _StatCol(serviceIcon, serviceName, tr('services')),
        // 🔒 [PHASE0 P1] ເຄີຍ "~20 ນາທີ" ຄົງທີ່ — ບໍ່ແມ່ນຄ່າຄິດໄລ່ແທ້, ນຳໃຊ້
        // key ດຽວກັນກັບ step-1 status label ຂ້າງລຸ່ມ (ຄຳສັ້ນ, ບໍ່ອ້າງຕົວເລກ)
        _StatCol(Icons.directions_car_filled_outlined,
            tr('status_provider_going_suffix'), 'ETA'),
        _StatCol(Icons.near_me_outlined, tr('near_you'), tr('distance_label')),
      ]),
      if (address.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
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
  final IconData icon;
  final String   value, label;
  const _StatCol(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Icon(icon, color: Colors.white, size: 22),
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
  final String   num, label;
  final IconData icon;
  final bool     isActive;
  const _StatusStep(this.num, this.icon, this.label, this.isActive);

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
      child: Center(child: Icon(icon, color: Colors.white, size: 14)),
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
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(tr('live_badge'), style: const TextStyle(
          color: C.green, fontSize: 10, fontWeight: FontWeight.w800,
        )),
      ),
  ]);
}

// ── glass stat card (searching state) ──────────────────────
// ✅ [Redesign] ແທນທີ່ _InfoChip (ໂປ່ງໃສທຳມະດາ, ຂະໜາດບໍ່ເທົ່າກັນ, ອັດກັນຢູ່
// ກາງ) ດ້ວຍ glassmorphism card ຄວາມກວ້າງເທົ່າກັນ 3 ໃບ — BackdropFilter blur
// ແທ້ໆ (ບໍ່ແມ່ນແຕ່ສີໂປ່ງໃສ), ຂອບບາງແສງ, ຈັດກາງທັງ icon+label.
class _GlassStat extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _GlassStat(this.icon, this.label);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.card),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: [BoxShadow(
            color:      Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset:     const Offset(0, 6),
          )],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: C.gold, size: 18),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}

// ── soft cancel button (searching state) ───────────────────
// ✅ [Theme] glass pill ສີແດງອ່ອນ (BackdropFilter blur ຄືກັນກັບ _GlassStat)
// ແທນທີ່ pill ແດງທຶບເດີມ — ອ່ານອອກວ່າເປັນ destructive action ແຕ່ dễ ເຂົ້າກັບ
// gradient ຂຽວແບຣນຫຼັງ, ຮູ້ສຶກເປັນສ່ວນໜຶ່ງຂອງ theme ໃໝ່ ບໍ່ແມ່ນປຸ່ມແປະຕ່າງຫາກ
class _SoftCancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String       label;
  const _SoftCancelButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: C.dangerRed.withValues(alpha: 0.16),
          child: InkWell(
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                border: Border.all(color: C.dangerRed.withValues(alpha: 0.35)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.close_rounded, color: C.dangerRed.withValues(alpha: 0.95), size: 16),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(
                  color: C.dangerRed.withValues(alpha: 0.95),
                  fontSize: 14, fontWeight: FontWeight.w700,
                )),
              ]),
            ),
          ),
        ),
      ),
    ),
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

// 🔒 [AUDIT UI-5 / 2026-08-02 — Medium, fresh re-audit] previously its own
// AnimationController+Tween+dispose() — now built on the shared PulsingFade
// primitive. Kept as its own widget (rather than switching to widgets/
// skeleton_box.dart's SkeletonBox) because this screen's shimmer is a subtle
// white overlay on a colored background (opacity 0.04-0.12), not
// SkeletonBox's gray-box-on-white-card look (opacity 0.35-0.85) — PulsingFade
// is the lower-level primitive both are built from.
class _Shimmer extends StatelessWidget {
  final double width, height, radius;
  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) => PulsingFade(
    duration: const Duration(milliseconds: 1200),
    begin: 0.04,
    end: 0.12,
    child: Container(
      width:  width,
      height: height,
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}