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
import 'app_locale.dart';
import 'widgets/app_button.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(tr('enable_gps_first')),
          backgroundColor: C.red,
        ));
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (perm == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(tr('gps_blocked')),
          backgroundColor: C.red,
        ));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _picked = loc);
      _mapController.move(loc, 16);
    } catch (e) {
      // 🔒 [AUDIT M-7 / 2026-07-27] ກ່ອນໜ້ານີ້ catch-all ນີ້ log ຢູ່ debug console
      // ເທົ່ານັ້ນ — GPS timeout (ພົບເລື້ອຍພາຍໃນຕຶກ/underground) ຫຼືຄວາມຜິດພາດອື່ນ
      // ນອກ 2 ກໍລະນີຂ້າງເທິງ (service disabled/permission denied forever) ຈະເຮັດ
      // ໃຫ້ spinner ວິ່ງແປບໜຶ່ງແລ້ວກັບຄືນເປັນປົກກະຕິ ໂດຍບໍ່ມີ feedback ຫຍັງ ໃຫ້
      // ຜູ້ໃຊ້ເລີຍ — ຄືກັນກັບ pattern ທີ່ໃຊ້ຢູ່ແລ້ວໃນ booking_form_screen.dart
      // _useGps()'s catch-all.
      debugPrint('goToMyLocation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('${tr("gps_error")}: $e'),
          backgroundColor: C.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation:       0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios,
              color: C.navy, size: 20),
          tooltip:   tr('back_semantic'),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('map_picker_title'), style: const TextStyle(
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
            // ✅ [Phase 2 / Batch A] mini FAB was 40×40, below the 44dp
            // minimum tap target — default (non-mini) size is 56dp.
            tooltip:         tr('use_current_location'),
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
          // ✅ [Phase 2 / Batch A] was a raw navy ElevatedButton — this is
          // the screen's primary action, so it must render LinTho green
          // like every other primary CTA (AppButton.primary can't be
          // recolored, which is the point).
          child: AppButton.primary(
            label:     tr('confirm_this_address'),
            onPressed: () => Navigator.pop(context, _picked),
          ),
        ),
      ]),
    );
  }
}