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
import 'package:firebase_database/firebase_database.dart';
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
  final _db   = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;

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

  // ✅ fix: return ຄວາມສຳເລັດ ແທນ swallow silent — ໃຫ້ caller ຮູ້ ແລະ rollback state ໄດ້
  Future<bool> setOnlineStatus(bool isOnline) async {
    if (_uid.isEmpty) return false;
    bool ok = true;

    // Firestore
    try {
      await _db.collection('providers').doc(_uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      ok = false;
    }

    // RTDB presence
    try {
      final ref = _rtdb.ref('presence/$_uid');
      if (isOnline) {
        await ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
        // ✅ onDisconnect: update ທັງ RTDB presence ແລະ Firestore
        await ref.onDisconnect()
            .update({'online': false, 'lastSeen': ServerValue.timestamp});
      } else {
        await ref.update({'online': false, 'lastSeen': ServerValue.timestamp});
        await ref.onDisconnect().cancel();
      }
    } catch (_) {
      ok = false;
    }

    return ok;
  }
}

// ── ONLINE STATUS NOTIFIER ───────────────────────────────────

class OnlineStatusNotifier extends StateNotifier<bool> {
  final LocationService _svc;
  StreamSubscription<Position>? _gpsSub;

  OnlineStatusNotifier(this._svc) : super(false);

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