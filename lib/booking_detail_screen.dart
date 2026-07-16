// ============================================================
// booking_detail_screen.dart — LinTho
// ▸ ໜ້າລາຍລະອຽດການຈອງ (ຝັ່ງລູກຄ້າ) — ເປີດຈາກການກົດກາດໃນ BookingScreen.
// ▸ ປຸ່ມ "ຍົກເລີກການຈອງ" ຢູ່ນີ້ ແທນທີ່ຈະຢູ່ໃນ Card List ຫຼັກ ເພື່ອປ້ອງກັນ
//   ການເຜີກົດ — ແລະ ສະແດງໃຫ້ກົດໄດ້ສະເພາະຕອນ status == 'pending' ເທົ່ານັ້ນ.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'booking_display_helpers.dart';
import 'firestore_service.dart';
import 'review_screen.dart';
import 'tracking_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _cancelling = false;

  Future<void> _confirmCancel(String status) async {
    if (!bookingIsCancelable(status)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(tr('cancel_booking_title'), style: const TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: Text(tr('cancel_booking_confirm_msg'),
            style: const TextStyle(color: C.muted)),
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
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await FirestoreService.updateBookingStatus(widget.bookingId, 'cancelled');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('cancel_booking_success')),
        backgroundColor: C.navy,
      ));
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(tr('booking_detail_title'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: C.navy));
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
                OutlinedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('retry')),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: C.navy,
                      side: const BorderSide(color: C.navy)),
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
                    child: Center(child: Text(
                        b['serviceEmoji'] as String? ?? '🏠',
                        style: const TextStyle(fontSize: 26))),
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

              if (hasProvider)
                _card(child: Row(children: [
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
                  if (bookingIsTrackable(status))
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => TrackingScreen(
                            bookingId:    doc.id,
                            provider:     providerFromBooking(b),
                            serviceName:  bookingServiceName(b),
                            serviceEmoji: b['serviceEmoji'] as String? ?? '🔧',
                            address:      b['address'] as String? ?? '',
                          ))),
                      icon: const Icon(Icons.map_rounded, size: 16),
                      label: Text(tr('track_btn')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.navy, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
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
                _card(child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: C.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b['cancelReason'] as String,
                      style: const TextStyle(fontSize: 13, color: C.muted))),
                ])),
              ],

              const SizedBox(height: 20),

              if (status == 'completed' &&
                  (b['reviewed'] as bool? ?? false) == false)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ReviewScreen(
                          bookingId:    doc.id,
                          provider:     providerFromBooking(b),
                          serviceName:  bookingServiceName(b),
                          serviceEmoji: b['serviceEmoji'] as String? ?? '🔧',
                        ))),
                    icon: const Icon(Icons.star_rounded, color: C.yellow),
                    label: Text(tr('rate'), style: const TextStyle(
                        fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.navy, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
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

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8, offset: const Offset(0, 3),
      )],
    ),
    child: child,
  );
}
