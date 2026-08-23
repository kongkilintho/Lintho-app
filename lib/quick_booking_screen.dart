import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'Booking.dart' show serviceIconForCategory;
import 'app_colors.dart';
import 'theme/app_theme.dart' show AppRadius, AppSpacing;
import 'app_locale.dart';
import 'app_navigation_state.dart';
import 'map_picker_screen.dart';
import 'match_screen.dart';
import 'phone_verification.dart';
import 'quick_booking_provider.dart';
import 'saved_address.dart';
import 'widgets/app_button.dart';

class QuickBookingFlow extends ConsumerWidget {
  const QuickBookingFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ [Phone-verified booking] ບໍ່ອະນຸຍາດໃຫ້ຈອງຖ້າບັນຊີຍັງບໍ່ມີ/ຍັງບໍ່ໄດ້
    // ຢືນຢັນເບີໂທ — ເບິ່ງ phone_verification.dart
    if (verifiedPhoneNumber() == null) {
      return PhoneRequiredGate(
          onGoToProfile: () => goToProfileTab(context, ref));
    }
    final draft = ref.watch(quickBookingProvider);

    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: draft.step == QuickBookingStep.service
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: C.text),
                onPressed: () => ref.read(quickBookingProvider.notifier).backTo(
                    draft.step == QuickBookingStep.checkout
                        ? QuickBookingStep.schedule
                        : QuickBookingStep.service),
              ),
        title: Text(_titleFor(draft.step),
            style: const TextStyle(
                color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: IndexedStack(
        index: draft.step.index,
        children: const [
          _StepService(),
          _StepSchedule(),
          _StepCheckout(),
        ],
      ),
    );
  }

  String _titleFor(QuickBookingStep step) => switch (step) {
        QuickBookingStep.service => tr('step_select_service'),
        QuickBookingStep.schedule => tr('step_datetime_address'),
        QuickBookingStep.checkout => tr('step_summary_confirm'),
      };
}

// ── STEP 1 — ບໍລິການ ────────────────────────────────────────

const _pkgNameKeys = {
  'ac_general_clean':      'pkg_ac_general_name',
  'house_general_clean':   'pkg_house_general_name',
  'ac_deep_clean_quick':   'pkg_ac_deep_name',
};
const _pkgDescKeys = {
  'ac_general_clean':      'pkg_ac_general_desc',
  'house_general_clean':   'pkg_house_general_desc',
  'ac_deep_clean_quick':   'pkg_ac_deep_desc',
};

class _StepService extends ConsumerWidget {
  const _StepService();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ໃຊ້ literal fallback ທັນທີ (valueOrNull ??) ບໍ່ໃຫ້ກະພິບ spinner —
    // ຖ້າ fetch ຈາກ Firestore ສຳເລັດ (admin ປ່ຽນ basePrice) ຈະອັບເດດອັດຕະໂນມັດ.
    final packages =
        ref.watch(quickBookingPackagesProvider).valueOrNull ?? defaultQuickPackages;
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: packages.length,
      itemBuilder: (context, i) {
        final pkg = packages[i];
        final serviceId = pkg['serviceId'] as String?;
        final pkgName = _pkgNameKeys[serviceId] != null
            ? tr(_pkgNameKeys[serviceId]!)
            : pkg['type'] as String;
        final pkgDesc = _pkgDescKeys[serviceId] != null
            ? tr(_pkgDescKeys[serviceId]!)
            : pkg['desc'] as String;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => ref.read(quickBookingProvider.notifier).selectService(
                type: pkgName,
                emoji: pkg['emoji'] as String,
                price: pkg['price'] as double,
                category: pkg['category'] as String),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(children: [
                // 🔒 [PHASE1] emoji → Icon derived from category, ຄືກັນກັບ
                // ຮູບແບບທີ່ Booking.serviceIconForCategory() ໃຊ້ຢູ່ 5+ ໜ້າຈໍ
                // ອື່ນແລ້ວ (booking_detail_screen.dart/match_screen.dart/
                // profile_tab.dart/main.dart)
                Icon(serviceIconForCategory(pkg['category'] as String),
                    size: 28, color: C.primary),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkgName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: C.text)),
                    const SizedBox(height: 2),
                    Text(pkgDesc,
                        style: const TextStyle(fontSize: 11, color: C.muted)),
                  ],
                )),
                Text(formatKip(pkg['price'] as double),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: C.navy)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ── STEP 2 — ວັນ-ເວລາ + ທີ່ຢູ່ ───────────────────────────────

class _StepSchedule extends ConsumerStatefulWidget {
  const _StepSchedule();

  @override
  ConsumerState<_StepSchedule> createState() => _StepScheduleState();
}

class _StepScheduleState extends ConsumerState<_StepSchedule> {
  DateTime? _dateTime;
  GeoPoint? _location;
  String? _address;
  bool _saveDefault = false;
  final _labelCtrl = TextEditingController(text: tr('default_address_label'));

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    // 🔒 [AUDIT CUST-3 / 2026-08-02 — Medium, fresh re-audit] showDatePicker's
    // firstDate blocks past dates, but showTimePicker has no such bound — if
    // today's date is picked with a time already elapsed, this fix (already
    // applied to the main booking flow — see booking_form_screen.dart's
    // AUDIT CUST-1 comment) was never mirrored here, so Quick Booking could
    // schedule a job in the past with no client or server check.
    if (picked.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('past_scheduled_time_error')),
          backgroundColor: C.red));
      return;
    }
    setState(() => _dateTime = picked);
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<LatLng>(
        context, MaterialPageRoute(builder: (_) => const MapPickerScreen()));
    if (picked == null || !mounted) return;
    var addr =
        'GPS: ${picked.latitude.toStringAsFixed(4)}, ${picked.longitude.toStringAsFixed(4)}';
    try {
      final places =
          await placemarkFromCoordinates(picked.latitude, picked.longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        final joined = [p.street, p.subLocality, p.locality]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (joined.isNotEmpty) addr = joined;
      }
    } catch (_) {}
    setState(() {
      _location = GeoPoint(picked.latitude, picked.longitude);
      _address = addr;
    });
  }

  // ✅ [FIX ME-14] ກ່ອນໜ້ານີ້ທຸກ failure branch ຄືນແບບງຽບໆ (ບໍ່ມີ SnackBar) —
  // ຜູ້ໃຊ້ກົດປຸ່ມ GPS ແລ້ວບໍ່ມີຫຍັງເກີດຂຶ້ນ ອາດຄິດວ່າແອັບເສຍ. ຕອນນີ້ສະແດງຂໍ້ຄວາມ
  // ໃຫ້ທຸກ branch, ຄືກັນກັບ booking_form_screen.dart's _useGps().
  Future<void> _useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('enable_gps_first')), backgroundColor: C.orange));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('gps_blocked')), backgroundColor: C.orange));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      var addr =
          'GPS: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        final places =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          final joined = [p.street, p.subLocality, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          if (joined.isNotEmpty) addr = joined;
        }
      } catch (_) {}
      setState(() {
        _location = GeoPoint(pos.latitude, pos.longitude);
        _address = addr;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr("gps_error")}: $e'), backgroundColor: C.red));
    }
  }

  // ✅ [FIX ME-16] SavedAddress ຕອນນີ້ອາດມີ GeoPoint ແທ້ (ບັນທຶກໄວ້ຕັ້ງແຕ່
  // ຕອນສ້າງ) — ໃຊ້ຄ່ານັ້ນຖ້າມີ. ຖ້າບໍ່ມີ (ທີ່ຢູ່ເກົ່າກ່ອນແກ້ໄຂນີ້), ແຈ້ງເຕືອນ
  // ໃຫ້ຜູ້ໃຊ້ຮູ້ວ່າກຳລັງໃຊ້ພິກັດປະມານ ແທນທີ່ຈະງຽບໆໃຊ້ພິກັດຜິດ.
  void _useSavedAddress(SavedAddress saved) {
    setState(() {
      _address = saved.address;
      _labelCtrl.text = saved.label;
      _location = saved.location ?? _location ?? const GeoPoint(17.9757, 102.6331);
    });
    if (saved.location == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('saved_address_no_location_warning'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedAddresses = ref.watch(savedAddressesProvider).valueOrNull ?? [];
    final canContinue =
        _dateTime != null && _location != null && _address != null;

    // ✅ Expanded+SingleChildScrollView ແທນ Spacer — ກັນ overflow ຕອນແປ້ນພິມເປີດ
    // (ເບິ່ງ _StepCheckoutState ສຳລັບເຫດຜົນລະອຽດ)
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionLabel(tr('datetime_label')),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.event_outlined),
              label: Text(_dateTime == null
                  ? tr('select_datetime')
                  : '${_dateTime!.day}/${_dateTime!.month}/${_dateTime!.year} ${_dateTime!.hour}:${_dateTime!.minute.toString().padLeft(2, '0')}'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: C.text,
                  side: const BorderSide(color: C.border)),
            ),
            const SizedBox(height: 20),
            _SectionLabel(tr('address')),
            const SizedBox(height: AppSpacing.sm),
            if (savedAddresses.isNotEmpty) ...[
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: savedAddresses
                      .map((a) => ActionChip(
                            label: Text(a.label),
                            avatar: const Icon(Icons.bookmark, size: 16),
                            onPressed: () => _useSavedAddress(a),
                          ))
                      .toList()),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(tr('pin_on_map')),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: C.text,
                    side: const BorderSide(color: C.border)),
              )),
              const SizedBox(width: AppSpacing.sm),
              // 🔒 [PHASE1] icon-only button ນີ້ບໍ່ມີ Semantics/tooltip ມາກ່ອນ —
              // ຂະໜາດ 48dp ຜ່ານຢູ່ແລ້ວ ແຕ່ບໍ່ມີ label ໃຫ້ screen reader
              Tooltip(
                message: tr('use_current_location'),
                child: OutlinedButton(
                  onPressed: _useCurrentLocation,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: C.text,
                      side: const BorderSide(color: C.border)),
                  child: const Icon(Icons.my_location),
                ),
              ),
            ]),
            if (_address != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Row(children: [
                  const Icon(Icons.location_on, color: C.sky, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(_address!,
                          style: const TextStyle(fontSize: 13, color: C.text))),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Checkbox(
                  value: _saveDefault,
                  onChanged: (v) => setState(() => _saveDefault = v ?? false),
                ),
                Text(tr('save_as_default_address'),
                    style: const TextStyle(fontSize: 13, color: C.text)),
                if (_saveDefault) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                      hintText: tr('address_label_hint'),
                      isDense: true,
                      filled: true,
                      fillColor: C.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          borderSide: const BorderSide(color: C.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          borderSide: const BorderSide(color: C.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          borderSide:
                              const BorderSide(color: C.sky, width: 1.5)),
                    ),
                  )),
                ],
              ]),
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // 🔒 [PHASE1] navy → AppButton.primary (brand green) — ແກ້ CTA color
        // drift ທີ່ Re-Audit ລະບຸ (Quick Booking ເປັນ 1 ໃນ 3 ໜ້າທີ່ override
        // ເປັນ navy ໃນຂະນະທີ່ Booking Form/Tracking/Match ໃຊ້ green ຢູ່ແລ້ວ)
        child: AppButton.primary(
          label: tr('next_btn'),
          onPressed: canContinue
              ? () {
                  ref.read(quickBookingProvider.notifier).setSchedule(
                      scheduledAt: _dateTime!,
                      location: _location!,
                      address: _address!,
                      saveAsDefault: _saveDefault,
                      label: _labelCtrl.text.trim());
                }
              : null,
        ),
      ),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: C.text));
}

// ── STEP 3 — ສະຫຼຸບ & ຢືນຢັນ ─────────────────────────────────

class _StepCheckout extends ConsumerStatefulWidget {
  const _StepCheckout();

  @override
  ConsumerState<_StepCheckout> createState() => _StepCheckoutState();
}

class _StepCheckoutState extends ConsumerState<_StepCheckout> {
  final _nameCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('please_login_first'))));
      return;
    }
    // ✅ [Phone-verified booking] ເບີໂທຢືນຢັນແລ້ວຂອງບັນຊີ — ໜ້ານີ້ຖືກ
    // PhoneRequiredGate ຫຸ້ມຢູ່ QuickBookingFlow.build() ຢູ່ແລ້ວ, ກວດຄືນນີ້ຄື
    // defense-in-depth ກ່ອນ write ຈິງ
    final phone = verifiedPhoneNumber() ?? '';
    final name = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (user.displayName ?? tr('customer'));
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('phone_verification_required_title'))));
      return;
    }

    final draft = ref.read(quickBookingProvider);
    setState(() => _submitting = true);
    final id = await ref.read(quickBookingProvider.notifier).confirmBooking(
        customerId: user.uid, customerName: name, customerPhone: phone);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (id != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => MatchScreen(
                bookingId: id,
                initialServiceName: draft.serviceType,
                initialAddress: draft.address,
                customerLat: draft.location?.latitude,
                customerLng: draft.location?.longitude,
              )));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('booking_failed_retry')), backgroundColor: C.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(quickBookingProvider);
    final user = FirebaseAuth.instance.currentUser;

    // ✅ Expanded+SingleChildScrollView ແທນ Spacer ໃນ Column ທຳມະດາ —
    // ກັນ "bottom overflowed" ຕອນແປ້ນພິມເປີດ (keyboard ຫຸດພື້ນທີ່ Scaffold,
    // Spacer ບໍ່ສາມາດຫຸດເປັນລົບໄດ້ ເຮັດໃຫ້ Column ລົ້ນ)
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SummaryCard(
              // 🔒 [PHASE1] emoji → Icon derived from category
              icon: serviceIconForCategory(draft.category ?? ''),
              serviceType: draft.serviceType ?? '-',
              price: draft.packagePrice ?? 0,
              discount: draft.couponDiscount?.toDouble(),
              scheduledAt: draft.scheduledAt,
              address: draft.address ?? '-',
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(tr('contact_info')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: tr('name_short'),
                filled: true,
                fillColor: C.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(tr('discount_code_label')),
            const SizedBox(height: AppSpacing.sm),
            if (draft.couponCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                decoration: BoxDecoration(
                  color: C.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: C.green),
                ),
                child: Row(children: [
                  const Icon(Icons.local_offer, color: C.green, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(
                          '${draft.couponCode} · -${formatKip(draft.couponDiscount ?? 0)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: C.green))),
                  // 🔒 [PHASE1] ບໍ່ມີ tooltip ມາກ່ອນ
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: C.green),
                    tooltip: tr('cancel'),
                    onPressed: () =>
                        ref.read(quickBookingProvider.notifier).clearCoupon(),
                  ),
                ]),
              )
            else
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _couponCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: tr('enter_code_hint'),
                      errorText: draft.couponError,
                      filled: true,
                      fillColor: C.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  height: 48,
                  // 🔒 [PHASE1] navy → AppButton.primary — ຄືກັນກັບ CTA ອື່ນໆ
                  // ໃນໜ້ານີ້
                  child: AppButton.primary(
                    label: tr('checking'),
                    fullWidth: false,
                    loading: draft.checkingCoupon,
                    onPressed: () => ref
                        .read(quickBookingProvider.notifier)
                        .applyCoupon(_couponCtrl.text),
                  ),
                ),
              ]),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (draft.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(draft.error!,
                  style: const TextStyle(color: C.red, fontSize: 12)),
            ),
          // 🔒 [PHASE1] navy → AppButton.primary — ຄືກັນກັບ CTA ອື່ນໆໃນໜ້ານີ້
          AppButton.primary(
            label: tr('confirm_book'),
            icon: Icons.check_circle,
            loading: _submitting,
            onPressed: user == null ? null : _confirm,
          ),
        ]),
      ),
    ]);
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String serviceType;
  final double price;
  final double? discount;
  final DateTime? scheduledAt;
  final String address;

  const _SummaryCard({
    required this.icon,
    required this.serviceType,
    required this.price,
    this.discount,
    required this.scheduledAt,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 24, color: C.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(serviceType,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: C.text))),
        ]),
        const Divider(height: 24),
        _Row(
            Icons.event_outlined,
            scheduledAt == null
                ? '-'
                : '${scheduledAt!.day}/${scheduledAt!.month}/${scheduledAt!.year} ${scheduledAt!.hour}:${scheduledAt!.minute.toString().padLeft(2, '0')}'),
        const SizedBox(height: AppSpacing.sm),
        _Row(Icons.location_on_outlined, address),
        const Divider(height: 24),
        if (discount != null && discount! > 0) ...[
          Row(children: [
            Text(tr('price'), style: const TextStyle(fontSize: 13, color: C.muted)),
            const Spacer(),
            Text(formatKip(price),
                style: const TextStyle(
                    fontSize: 13, color: C.muted,
                    decoration: TextDecoration.lineThrough)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Row(children: [
            Text(tr('discount_label'), style: const TextStyle(fontSize: 13, color: C.green)),
            const Spacer(),
            Text('-${formatKip(discount!)}',
                style: const TextStyle(fontSize: 13, color: C.green)),
          ]),
          const SizedBox(height: AppSpacing.xs),
        ],
        Row(children: [
          Text(tr('total_price_label'), style: const TextStyle(fontSize: 14, color: C.muted)),
          const Spacer(),
          Text(formatKip((price - (discount ?? 0)).clamp(0, double.infinity)),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: C.navy)),
        ]),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: C.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: C.text))),
      ]);
}
