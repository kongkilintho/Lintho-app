// ============================================================
// provider_map_screen.dart — LinTho
// Fixes:
//   ✅ [FIX-1] ລຶບ _mapController.dispose() ອອກ
//              MapController ບໍ່ມີ .dispose() method
// ── Rules (kept) ────────────────────────────────────────────
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ InkWell + Material ແທນ GestureDetector
//   ✅ dispose() _posSub?.cancel()
//   ✅ mounted check ຫຼັງ async ທຸກຈຸດ
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'geohash_util.dart';

class ProviderMapScreen extends StatefulWidget {
  const ProviderMapScreen({super.key});
  @override
  State<ProviderMapScreen> createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen>
    with WidgetsBindingObserver {
  final _mapController = MapController();
  LatLng? _myPos;
  bool    _isOnline = false;
  StreamSubscription<Position>? _posSub;
  DateTime? _lastWriteAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    // ✅ [FIX-1] ບໍ່ call _mapController.dispose()
    // MapController (flutter_map) ບໍ່ມີ method .dispose()
    super.dispose();
  }

  // ✅ ຢຸດ/ສືບຕໍ່ GPS stream ຕາມສະຖານະແອັບ — ປະຢັດແບັດເຕີຣີ່ຕອນ background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_posSub == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _posSub!.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_posSub!.isPaused) _posSub!.resume();
    }
  }

  Future<void> _toggleOnline() async {
    if (_isOnline) {
      _posSub?.cancel();
      await _setOffline();
      if (!mounted) return;
      setState(() => _isOnline = false);
    } else {
      final ok = await _requestPermission();
      if (!mounted) return;
      if (!ok) return;
      setState(() => _isOnline = true);
      await _startTracking();
    }
  }

  Future<bool> _requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(tr('please_enable_gps')),
        backgroundColor: Colors.orange,
      ));
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }

    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(tr('enable_location_in_settings')),
        backgroundColor: Colors.red,
      ));
      return false;
    }
    return true;
  }

  Future<void> _startTracking() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final loc = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() => _myPos = loc);
      _mapController.move(loc, 15);
      await _updateFirestore(loc);

      const LocationSettings locationSettings = LocationSettings(
        accuracy:       LocationAccuracy.high,
        distanceFilter: 10,
      );

      _posSub = Geolocator.getPositionStream(
          locationSettings: locationSettings)
          .listen((Position position) async {
        final l = LatLng(position.latitude, position.longitude);
        if (!mounted) return;
        setState(() => _myPos = l);
        await _updateFirestore(l);
      });
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
    }
  }

  // ✅ throttle — ຈຳກັດການຂຽນ Firestore ຢ່າງໜ້ອຍທຸກ 20 ວິນາທີ
  // ປ້ອງກັນ write storm ຕອນຂັບລົດ/ມໍຕໍ່ໄຊ (distanceFilter ຢ່າງດຽວບໍ່ພຽງພໍ)
  static const _minWriteInterval = Duration(seconds: 20);

  Future<void> _updateFirestore(LatLng loc) async {
    final now = DateTime.now();
    if (_lastWriteAt != null &&
        now.difference(_lastWriteAt!) < _minWriteInterval) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('providers')
          .doc(uid)
          .set({
        'lat':         loc.latitude,
        'lng':         loc.longitude,
        // ✅ geohash precision 6 (≈1.2km cell) — ສຳລັບ bounding-box query
        // ກ່ອນ limit() ໃນ match_screen.dart, ບໍ່ໃຫ້ provider ໄກໆຖືກ
        // ເລືອກກ່ອນ provider ໃກ້ (Firestore limit ບໍ່ຮູ້ຈັກໄລຍະທາງ)
        'geohash':     GeohashUtil.encode(loc.latitude, loc.longitude, 6),
        'isOnline':    true,
        'updatedAt':   FieldValue.serverTimestamp(),
        'displayName': FirebaseAuth.instance.currentUser?.displayName ?? tr('provider'),
      }, SetOptions(merge: true));
      _lastWriteAt = now;
    } catch (e) {
      debugPrint('Firestore update error: $e');
    }
  }

  Future<void> _setOffline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('providers')
          .doc(uid)
          .set({'isOnline': false}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore set offline error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.primary,
        elevation:       0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('my_location_title'), style: const TextStyle(
          color:      Colors.white,
          fontWeight: FontWeight.w800,
          fontSize:   18,
        )),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap:        _toggleOnline,
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isOnline
                        ? C.green
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Icon(
                      Icons.circle,
                      color: _isOnline
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
                      size: 8,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isOnline ? tr('online') : tr('offline'),
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(children: [

        // ── Map ──
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(17.9757, 102.6331),
            initialZoom:   13,
          ),
          children: [
            TileLayer(
              urlTemplate:          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lintho.app',
            ),
            if (_myPos != null)
              MarkerLayer(markers: [
                Marker(
                  point:  _myPos!,
                  width:  60,
                  height: 60,
                  child: Container(
                    width:  40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:  C.primary,
                      shape:  BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(
                        color:      C.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                      )],
                    ),
                    child: const Center(
                      child: Text('🔧',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ]),
          ],
        ),

        // ── Status Card ──
        Positioned(
          left: 16, right: 16, bottom: 30,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color:      Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset:     const Offset(0, 8),
              )],
            ),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _isOnline
                        ? C.green.withValues(alpha: 0.1)
                        : C.cream,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Icon(
                      _isOnline
                          ? Icons.location_on
                          : Icons.location_off,
                      color: _isOnline ? C.green : C.muted,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isOnline ? tr('currently_online') : tr('currently_offline'),
                      style: TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w800,
                        color: _isOnline ? C.green : C.muted,
                      ),
                    ),
                    Text(
                      _isOnline
                          ? tr('customers_can_see_you')
                          : tr('tap_online_to_start'),
                      style: const TextStyle(
                          fontSize: 11, color: C.muted),
                    ),
                  ],
                )),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _toggleOnline,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isOnline ? C.red : C.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isOnline ? tr('stop_online_btn') : tr('start_online_btn'),
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}