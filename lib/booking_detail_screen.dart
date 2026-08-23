// ============================================================
// booking_detail_screen.dart — LinTho
// ▸ ໜ້າລາຍລະອຽດການຈອງ (ຝັ່ງລູກຄ້າ) — ເປີດຈາກການກົດກາດໃນ BookingScreen.
// ▸ ປຸ່ມ "ຍົກເລີກການຈອງ" ຢູ່ນີ້ ແທນທີ່ຈະຢູ່ໃນ Card List ຫຼັກ ເພື່ອປ້ອງກັນ
//   ການເຜີກົດ — ແລະ ສະແດງໃຫ້ກົດໄດ້ສະເພາະຕອນ status == 'pending' ເທົ່ານັ້ນ.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'Booking.dart' show serviceIconForCategory;
import 'app_colors.dart';
import 'app_locale.dart';
import 'booking_display_helpers.dart';
import 'booking_repository.dart';
import 'provider_details_screen.dart';
import 'review_screen.dart';
import 'tracking_screen.dart';
import 'widgets/app_button.dart';
import 'widgets/app_card.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _cancelling = false;
  final _customerBookingRepo = CustomerBookingRepository();

  // 🔒 [AUDIT H8] ກ່ອນໜ້ານີ້ FirestoreService.updateBookingStatus() ຂຽນ
  // status ດິບໆ ໂດຍກົງ (ບໍ່ມີ transaction, ບໍ່ກວດ status ປັດຈຸບັນຄືນ, ບໍ່ບັນທຶກ
  // cancelReason/cancelledBy/cancelFeeAmount) ແລະ ບໍ່ມີ catch — error ໃດກໍໄດ້
  // ຈະບໍ່ຖືກຈັບ. ຕອນນີ້ໃຊ້ CustomerBookingRepository.cancelBooking() ແທນ
  // (transaction-safe, ບັນທຶກ attribution+fee ຢ່າງຖືກຕ້ອງ) ພ້ອມເກັບເຫດຜົນ
  // (ບໍ່ບັງຄັບ) ແລະ ຈັບ error ໃຫ້ຜູ້ໃຊ້ເຫັນ.
  Future<void> _confirmCancel(String status) async {
    if (!bookingIsCancelable(status)) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(tr('cancel_booking_title'), style: const TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('cancel_booking_confirm_msg'),
              style: const TextStyle(color: C.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLength: 200,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: tr('cancel_reason_hint'),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('no'), style: const TextStyle(color: C.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('confirm'), style: const TextStyle(
                color: C.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await _customerBookingRepo.cancelBooking(
          widget.bookingId, reason.isEmpty ? 'ລູກຄ້າຍົກເລີກ' : reason);
      if (!mounted) return;
      // 🔒 [PHASE1] navy → AppColors.success — ນີ້ຄື feedback ວ່າ "ສຳເລັດ",
      // ບໍ່ແມ່ນ brand/navigation context ທີ່ navy ຄວນໃຊ້
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('cancel_booking_success')),
        backgroundColor: C.success,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr("error")}: $e'),
        backgroundColor: C.red,
      ));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      // 🔒 [PHASE1] title style ເຄີຍພິມຄືນຄ່າ AppTypography.appBarTitle ດ້ວຍມື —
      // AppBarTheme ຕັ້ງຄ່ານີ້ໃຫ້ແລ້ວ, drop override ໃຫ້ອີງໃສ່ theme ໂດຍກົງ
      appBar: AppBar(
        elevation: 0,
        title: Text(tr('booking_detail_title')),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // ✅ [Brand color audit 2026-07-27] ລົບ color: C.navy hardcode —
            // ໃຫ້ໃຊ້ progressIndicatorTheme ກາງ (ສີຂຽວແບຣນ) ຄືກັບ spinner ອື່ນໆ
            return const Center(child: CircularProgressIndicator());
          }
          // ✅ [FIX] ກ່ອນໜ້ານີ້ error ບໍ່ຖືກເຊັກ — Firestore permission/network
          // ຜິດພາດຈະຕົກລົງ "ບໍ່ພົບການຈອງ" ຄືກັນກັບ booking ຖືກລຶບ, ເຮັດໃຫ້ຜູ້ໃຊ້
          // ເຂົ້າໃຈຜິດ. ແຍກ error ອອກມາຕ່າງຫາກ ພ້ອມປຸ່ມລອງໃໝ່.
          if (snapshot.hasError) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_outlined, size: 48, color: C.muted),
                const SizedBox(height: 12),
                Text(tr('load_failed'),
                    style: const TextStyle(color: C.muted, fontSize: 15)),
                const SizedBox(height: 16),
                // 🔒 [PHASE1] navy foreground/border ຄືກັນເປ໊ະກັບ
                // OutlinedButtonTheme default ຢູ່ແລ້ວ — override ນີ້ບໍ່ຈຳເປັນ
                AppButton.outline(
                  label: tr('retry'),
                  icon: Icons.refresh,
                  fullWidth: false,
                  onPressed: () => setState(() {}),
                ),
              ],
            ));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text(tr('no_booking'),
                style: const TextStyle(color: C.muted, fontSize: 15)));
          }

          final doc    = snapshot.data!;
          final b      = doc.data() as Map<String, dynamic>;
          final status = b['status'] as String? ?? 'pending';
          final style  = bookingStatusStyle(status);
          final hasProvider = (b['providerId'] as String? ?? '').isNotEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(child: Text(bookingCode(doc.id), style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: C.muted, letterSpacing: 0.3))),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: style.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(bookingStatusLabel(status), style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold,
                        color: style.fg)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${tr('booking_id_label')}: ${doc.id}', style: const TextStyle(
                    fontSize: 11, color: C.muted)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: C.border),
                ),
                Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: C.bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // ✅ [FIX H11] Icon ຈາກ category ແທນ raw emoji ທີ່ເກັບໄວ້ໃນ doc
                    child: Center(child: Icon(
                        serviceIconForCategory(b['category'] as String? ?? ''),
                        size: 26, color: C.navy)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bookingServiceName(b), style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900,
                          color: C.text)),
                      const SizedBox(height: 3),
                      Text(bookingQuantityLabel(b), style: const TextStyle(
                          fontSize: 12, color: C.muted,
                          fontWeight: FontWeight.w500)),
                    ],
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: C.muted),
                  const SizedBox(width: 6),
                  Text(bookingScheduleLabel(b), style: const TextStyle(
                      fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                ]),
                if ((b['address'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_outlined,
                        size: 15, color: C.muted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(b['address'] as String,
                        style: const TextStyle(fontSize: 13, color: C.muted))),
                  ]),
                ],
              ])),

              const SizedBox(height: 12),

              // ✅ [FIX H14] ກົດຊື່/ຮູບຊ່າງ → ໄປໜ້າໂປຣໄຟລ໌ຊ່າງ (ProviderDetailsScreen,
              // ຫາກ່ອນນີ້ບໍ່ເຄີຍຖືກ navigate ໄປຫາຈາກຈຸດໃດເລີຍ)
              if (hasProvider)
                _card(child: Row(children: [
                  Expanded(child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ProviderDetailsScreen(
                              providerId: b['providerId'] as String))),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: C.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: C.gold.withValues(alpha: 0.3)),
                          ),
                          child: Center(child: Text(
                              ((b['providerName'] as String? ?? '?').isNotEmpty
                                  ? (b['providerName'] as String).substring(0, 1)
                                  : '?').toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900,
                                  color: C.gold))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b['providerName'] as String? ?? tr('provider'),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800,
                                    color: C.text)),
                            const SizedBox(height: 2),
                            Text(tr('provider'), style: const TextStyle(
                                fontSize: 12, color: C.muted)),
                          ],
                        )),
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: C.muted),
                      ]),
                    ),
                  )),
                  if (bookingIsTrackable(status)) ...[
                    const SizedBox(width: 8),
                    // 🔒 [PHASE1] navy → AppButton.primary (brand green) —
                    // ຄືກັນກັບ CTA color drift ທີ່ພົບຢູ່ Quick Booking
                    AppButton.primary(
                      label: tr('track_btn'),
                      icon: Icons.map_rounded,
                      fullWidth: false,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => TrackingScreen(
                            bookingId:    doc.id,
                            provider:     providerFromBooking(b),
                            serviceName:  bookingServiceName(b),
                            serviceEmoji: b['serviceEmoji'] as String? ?? '🔧',
                            serviceIcon:  serviceIconForCategory(
                                b['category'] as String? ?? ''),
                            address:      b['address'] as String? ?? '',
                          ))),
                    ),
                  ],
                ])),

              if (hasProvider) const SizedBox(height: 12),

              _card(child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('price'), style: const TextStyle(
                      fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                  Text(bookingTotalLabel(b), style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
                ],
              )),

              if (status == 'cancelled' &&
                  (b['cancelReason'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: C.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b['cancelReason'] as String,
                        style: const TextStyle(fontSize: 13, color: C.muted))),
                  ]),
                  // 🔒 [AUDIT CUST-7 / 2026-08-02 — Low, fresh re-audit]
                  // cancelFeeAmount was computed/persisted by
                  // CustomerBookingRepository.cancelBooking() but never
                  // rendered anywhere — the customer had no way to see
                  // whether/how much a cancellation fee was assessed.
                  if ((b['cancelFeeAmount'] as num? ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const SizedBox(width: 24),
                      Expanded(child: Text(
                          '${tr("cancel_fee_label")}: ₭ ${NumberFormat('#,###').format(b['cancelFeeAmount'])}',
                          style: const TextStyle(fontSize: 13, color: C.red,
                              fontWeight: FontWeight.w700))),
                    ]),
                  ],
                ])),
              ],

              const SizedBox(height: 20),

              if (status == 'completed' &&
                  (b['reviewed'] as bool? ?? false) == false)
                // 🔒 [PHASE1] navy → AppButton.primary (brand green)
                AppButton.primary(
                  label: tr('rate'),
                  icon: Icons.star_rounded,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ReviewScreen(
                        bookingId:    doc.id,
                        provider:     providerFromBooking(b),
                        serviceName:  bookingServiceName(b),
                        serviceIcon:  serviceIconForCategory(
                            b['category'] as String? ?? ''),
                      ))),
                ),

              // ▸ ປຸ່ມຍົກເລີກ — ສະແດງສະເພາະຕອນ status == 'pending' ເທົ່ານັ້ນ,
              // ຫາຍໄປທັນທີເມື່ອຊ່າງຮັບງານ (accepted/onTheWay/arrived/inProgress)
              if (bookingIsCancelable(status)) ...[
                if (status == 'completed' &&
                    (b['reviewed'] as bool? ?? false) == false)
                  const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _cancelling ? null : () => _confirmCancel(status),
                    icon: _cancelling
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: C.red))
                        : const Icon(Icons.close_rounded, color: C.red, size: 18),
                    label: Text(tr('cancel_booking_title'), style: const TextStyle(
                        color: C.red, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: C.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // 🔒 [PHASE1] ເຄີຍ hand-roll Container(radius:18, custom 4%-opacity shadow)
  // ຂອງຕົນເອງ — ບໍ່ກົງກັບ AppCard/CardTheme (radius 16, 6%-opacity shadow).
  // ດຽວນີ້ delegate ໄປ AppCard ບ່ອນດຽວ ບໍ່ຕ້ອງແກ້ທຸກຈຸດທີ່ເອີ້ນ _card()
  Widget _card({required Widget child}) => SizedBox(
    width: double.infinity,
    child: AppCard(child: child),
  );
}
