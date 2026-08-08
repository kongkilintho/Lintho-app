// ============================================================
// online_provider.dart — LinTho Provider App
// Online/Offline Status + GPS Tracking
//
// Fixes:
//   ✅ _uid: currentUser?.uid ?? '' — ບໍ່ ! crash ຖ້າ logout
//   ✅ LocationService: inject uid ຜ່ານ method ບໍ່ getter
//   ✅ setOnline: guard ຖ້າ state ດຽວກັນ (ບໍ່ double-subscribe)
//   ✅ writeLocation: throttle 5 ວິ — ບໍ່ write ທຸກ GPS event
//   ✅ onDisconnect handler ຮອງຮັບ Firestore ດ້ວຍ (ບໍ່ແຕ່ RTDB)
//   ✅ currentPositionProvider: ຍ້າຍ .map cast ອອກ (redundant)
// ============================================================

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'booking_provider.dart' show currentUidProvider;
import 'geohash_util.dart';

// ── LOCATION SERVICE ─────────────────────────────────────────

// ✅ ໃຫ້ UI ຮູ້ສາເຫດທີ່ແທ້ຈິງ ເມື່ອກົດ Online ບໍ່ສຳເລັດ (ບໍ່ silent fail)
enum OnlineToggleResult {
  success,
  locationServiceDisabled,
  permissionDenied,
  writeFailed,
}

class LocationService {
  final _db = FirebaseFirestore.instance;

  // ✅ fix: ?.uid ?? '' — ບໍ່ ! crash ຖ້າ user logout ກ່ອນ dispose
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  // ✅ ແຍກສາເຫດ: GPS ປິດຢູ່ vs permission ຖືກປະຕິເສດ
  Future<OnlineToggleResult> checkLocationReadiness() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return OnlineToggleResult.locationServiceDisabled;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    final granted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
    return granted
        ? OnlineToggleResult.success
        : OnlineToggleResult.permissionDenied;
  }

  Stream<Position> get positionStream => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy:       LocationAccuracy.high,
      distanceFilter: 20,
    ),
  );

  // ✅ fix: throttle — ບໍ່ write Firestore ທຸກ GPS event (ທຸກ 5 ວິ)
  DateTime? _lastWrite;

  Future<void> writeLocation(Position pos) async {
    if (_uid.isEmpty) return;
    final now = DateTime.now();
    if (_lastWrite != null &&
        now.difference(_lastWrite!).inSeconds < 5) return;
    _lastWrite = now;

    try {
      await _db.collection('providers').doc(_uid).update({
        'location':          GeoPoint(pos.latitude, pos.longitude),
        'lat':      pos.latitude,
        'lng':      pos.longitude,
        // precision 6 (≈1.2km cell) — ຕ້ອງກົງກັບ precision ທີ່
        // match_screen.dart ໃຊ້ຄົ້ນຫາ (neighborsOf), ບໍ່ດັ່ງນັ້ນ query
        // geohash whereIn ຈະບໍ່ພົບ provider ນີ້ເລີຍ ແລະ matching ຈະ
        // ຕົກໄປໃຊ້ fallback (ບໍ່ຈັດລຳດັບຕາມໄລຍະທາງ) ຢູ່ຕະຫຼອດ
        'geohash':           GeohashUtil.encode(pos.latitude, pos.longitude, 6),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // 🔒 [AUDIT SEC-4 / 2026-08-06 — ພົບລະຫວ່າງແກ້ໄຂ, ຮ້າຍແຮງກວ່າທີ່ audit ເດີມ
  // ບອກໄວ້] database.rules.json ບໍ່ມີ rule ອະນຸຍາດໃຫ້ຂຽນ presence/{uid} ເລີຍ
  // (root ເປັນ .write:false, ບໍ່ມີ child ຍົກເວັ້ນ) — RTDB block ຂ້າງລຸ່ມນີ້
  // (ຖືກລຶບອອກແລ້ວ) ຖືກ permission-denied ທຸກຄັ້ງ, ຕັ້ງ ok=false ໂດຍບໍ່ຂຶ້ນກັບ
  // ວ່າ Firestore write ຂ້າງເທິງສຳເລັດຫຼືບໍ່ — ໝາຍຄວາມວ່າ setOnlineStatus()
  // ຄືນ false ຢູ່ຕະຫຼອດທຸກຄັ້ງທີ່ຖືກເອີ້ນ, ເຮັດໃຫ້ OnlineStatusNotifier.setOnline()
  // (ຂ້າງລຸ່ມ) return OnlineToggleResult.writeFailed ຢູ່ຕະຫຼອດ — state ທ້ອງຖິ່ນ
  // ບໍ່ເຄີຍຖືກຕັ້ງເປັນ online, GPS stream ບໍ່ເຄີຍເລີ່ມ, ຜູ້ໃຊ້ເຫັນ error ຢູ່ຕະຫຼອດ
  // — ທັງໆທີ່ Firestore isOnline:true ຂຽນສຳເລັດແທ້ (ບໍ່ຖືກ rollback, ເປັນ write
  // ແຍກຕ່າງຫາກ) — ຊ່າງຖືກນັບວ່າ online ໃນ backend ໂດຍທີ່ແອັບເອງຄິດວ່າ toggle
  // ລົ້ມເຫລວ ແລະ ບໍ່ສົ່ງ GPS location ອັບເດດເລີຍ. ນີ້ຄືບັນຫາທີ່ EDGE-3 ພະຍາຍາມ
  // ຫຼຸດຜ່ອນຜົນກະທົບ (freshness filter ໃນ match_screen.dart) ແຕ່ນີ້ຄືສາເຫດຮາກ —
  // ລຶບ RTDB presence write ອອກທັງໝົດ (Firestore isOnline + locationUpdatedAt
  // ເປັນ source of truth ດຽວແລ້ວ, ບໍ່ຕ້ອງການ RTDB presence ອີກເລີຍ).
  Future<bool> setOnlineStatus(bool isOnline) async {
    if (_uid.isEmpty) return false;
    try {
      await _db.collection('providers').doc(_uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ── ONLINE STATUS NOTIFIER ───────────────────────────────────

class OnlineStatusNotifier extends StateNotifier<bool> {
  final LocationService _svc;
  StreamSubscription<Position>? _gpsSub;
  bool _synced = false;

  OnlineStatusNotifier(this._svc) : super(false);

  // 🔒 [Availability persistence fix] state ເລີ່ມຕົ້ນ super(false) ສະເໝີ —
  // ບໍ່ເຄີຍອ່ານຄ່າ isOnline ທີ່ບັນທຶກໄວ້ໃນ Firestore ຕອນເປີດແອັບ/login ໃໝ່,
  // ເຮັດໃຫ້ UI ສະແດງ "Offline" ຢູ່ສະເໝີຈົນກວ່າຜູ້ໃຊ້ຈະກົດ toggle ເອງ — ແລະຖ້າ
  // ຜູ້ໃຊ້ກົດປິດຕອນນັ້ນ (state ທ້ອງຖິ່ນ false ຢູ່ແລ້ວ) guard `state == online`
  // ຈະ no-op ໂດຍບໍ່ຂຽນ Firestore ເລີຍ — ຄ້າງ isOnline:true ຢູ່ backend ໂດຍບໍ່ມີ
  // GPS stream ແລ່ນຄຽງຄູ່. ເອີ້ນຄັ້ງດຽວຫຼັງ profile stream ໂຫລດຄັ້ງທຳອິດ ເພື່ອ
  // seed state ໃຫ້ກົງກັບຄ່າຈິງ (ProviderDashboard ເອີ້ນຜ່ານ ref.listen).
  void syncFromRemote(bool remoteIsOnline) {
    if (_synced) return;
    _synced = true;
    if (remoteIsOnline == state) return;
    state = remoteIsOnline;
    if (remoteIsOnline) {
      _gpsSub?.cancel();
      _gpsSub = _svc.positionStream.listen(
            (pos) => _svc.writeLocation(pos),
        onError: (_) {},
        cancelOnError: false,
      );
    }
  }

  Future<OnlineToggleResult> toggle() => setOnline(!state);

  Future<OnlineToggleResult> setOnline(bool online) async {
    // ✅ fix: guard — ບໍ່ re-subscribe ຖ້າ state ດຽວກັນ
    if (state == online) return OnlineToggleResult.success;

    if (online) {
      final readiness = await _svc.checkLocationReadiness();
      if (readiness != OnlineToggleResult.success) {
        return readiness; // ຢ່າ set online ຖ້າ GPS ປິດ ຫຼື permission ຖືກປະຕິເສດ
      }
    }

    // ✅ fix: ລໍຢືນຢັນ backend ກ່ອນ — rollback state ຖ້າ write ລົ້ມເຫລວ
    final ok = await _svc.setOnlineStatus(online);
    if (!ok) return OnlineToggleResult.writeFailed;
    state = online;

    if (online) {
      // ✅ cancel ກ່ອນ subscribe ໃໝ່ (safety)
      await _gpsSub?.cancel();
      _gpsSub = _svc.positionStream.listen(
            (pos) => _svc.writeLocation(pos),
        onError: (_) {},
        cancelOnError: false,
      );
    } else {
      await _gpsSub?.cancel();
      _gpsSub = null;
    }
    return OnlineToggleResult.success;
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _svc.setOnlineStatus(false).ignore();
    super.dispose();
  }
}

// ── PROVIDERS ────────────────────────────────────────────────

final locationServiceProvider = Provider((_) => LocationService());

final onlineStatusProvider =
StateNotifierProvider<OnlineStatusNotifier, bool>((ref) {
  // ✅ [FIX account-switch] ບໍ່ watch ຄ່ານີ້ໄວ້, state=true ຈາກບັນຊີເກົ່າຈະ
  // ຄ້າງຢູ່ຫຼັງສະຫຼັບບັນຊີ — toggle() ຈະອ່ານ state ເກົ່າ (true) ແລ້ວສັ່ງ
  // setOnline(false) ໃສ່ບັນຊີໃໝ່ແທນ (ເບິ່ງຄືກົດ "Online" ແລ້ວບໍ່ມີຫຍັງເກີດຂຶ້ນ).
  ref.watch(currentUidProvider);
  return OnlineStatusNotifier(ref.read(locationServiceProvider));
});

// ✅ fix: ຍ້າຍ .map((p) => p as Position?) ອອກ — redundant cast
final currentPositionProvider = StreamProvider<Position?>((ref) async* {
  final granted = await ref.read(locationServiceProvider).requestPermission();
  if (!granted) {
    yield null;
    return;
  }
  yield* ref.read(locationServiceProvider).positionStream;
});