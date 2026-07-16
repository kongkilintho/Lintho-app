// ============================================================
// map_picker_screen.dart — LinTho
// Fixes:
//   ✅ [FIX-1] ລຶບ _mapController.dispose() ອອກ
//              MapController (flutter_map) ບໍ່ມີ .dispose()
// ── Rules (kept) ────────────────────────────────────────────
//   ✅ Skeleton ແທນ CircularProgressIndicator
//   ✅ _shimmerCtrl.dispose() ຖືກຕ້ອງ
//   ✅ mounted check ຫຼັງ async
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'app_colors.dart';

const _vientianeCenter = LatLng(17.9757, 102.6331);

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen>
    with SingleTickerProviderStateMixin {
  LatLng _picked  = _vientianeCenter;
  bool   _loading = false;

  final _mapController = MapController();

  late final AnimationController _shimmerCtrl;
  late final Animation<double>   _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _shimmerAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    // ✅ [FIX-1] ລຶບ _mapController.dispose() ອອກ
    // MapController ບໍ່ມີ .dispose() — call ແລ້ວ crash
    _shimmerCtrl.dispose(); // ✅ AnimationController ມີ .dispose()
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    setState(() => _loading = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('ກະລຸນາເປີດ GPS ກ່ອນ'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (perm == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('ກະລຸນາເປີດອະນຸຍາດ GPS ໃນ Settings'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _picked = loc);
      _mapController.move(loc, 16);
    } catch (e) {
      debugPrint('goToMyLocation: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation:       0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('ເລືອກທີ່ຢູ່ຂອງທ່ານ', style: TextStyle(
          color:      C.navy,
          fontWeight: FontWeight.w800,
          fontSize:   18,
        )),
        centerTitle: true,
      ),
      body: Stack(children: [

        // ── Map ──
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _vientianeCenter,
            initialZoom:   13,
            onTap: (_, point) => setState(() => _picked = point),
          ),
          children: [
            TileLayer(
              urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lintho.app',
            ),
            MarkerLayer(markers: [
              Marker(
                point:  _picked,
                width:  48,
                height: 48,
                child: const Icon(
                  Icons.location_pin,
                  color: C.orange,
                  size:  48,
                ),
              ),
            ]),
          ],
        ),

        // ── GPS Button ──
        Positioned(
          right: 16, bottom: 120,
          child: FloatingActionButton(
            mini:            true,
            backgroundColor: Colors.white,
            onPressed:       _loading ? null : _goToMyLocation,
            child: _loading
                ? AnimatedBuilder(
              animation: _shimmerAnim,
              builder: (_, __) => Opacity(
                opacity: _shimmerAnim.value,
                child: const Icon(
                  Icons.my_location,
                  color: C.orange,
                ),
              ),
            )
                : const Icon(Icons.my_location, color: C.orange),
          ),
        ),

        // ── Confirm Button ──
        Positioned(
          left: 16, right: 16, bottom: 30,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _picked),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.navy,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('📍 ຢືນຢັນທີ່ຢູ່ນີ້', style: TextStyle(
              color:      Colors.white,
              fontSize:   15,
              fontWeight: FontWeight.w700,
            )),
          ),
        ),
      ]),
    );
  }
}