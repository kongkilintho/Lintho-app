// ============================================================
// payment_config_provider.dart — LinTho App
// Shared BCEL One bank/QR config — admin sets this in lintho-admin
// (Settings > Payment), read here by both the provider Top-up sheet
// (earnings_tab.dart) and the customer Booking Payment screen
// (booking_form_screen.dart) so both surfaces always agree.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentConfig {
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String? qrImageUrl;

  const PaymentConfig({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    this.qrImageUrl,
  });

  // ✅ ຄ່າ fallback ຖ້າ admin ຍັງບໍ່ທັນຕັ້ງຄ່າ settings/payment_config —
  // ໜ້າ Top-up/Payment ຍັງໃຊ້ໄດ້ຄືເກົ່າ (QR ຖືກສ້າງຈາກຂໍ້ຄວາມທ້ອງຖິ່ນແທນຮູບຈິງ)
  static const fallback = PaymentConfig(
    bankName: 'BCEL One',
    accountName: 'LinTho Co., Ltd',
    accountNumber: '010-12-00-00000000-0',
  );

  factory PaymentConfig.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return fallback;
    final d = doc.data() as Map<String, dynamic>?;
    if (d == null) return fallback;
    return PaymentConfig(
      bankName: (d['bankName'] as String?)?.trim().isNotEmpty == true
          ? d['bankName'] as String
          : fallback.bankName,
      accountName: (d['accountName'] as String?)?.trim().isNotEmpty == true
          ? d['accountName'] as String
          : fallback.accountName,
      accountNumber: (d['accountNumber'] as String?)?.trim().isNotEmpty == true
          ? d['accountNumber'] as String
          : fallback.accountNumber,
      qrImageUrl: d['qrImageUrl'] as String?,
    );
  }
}

final paymentConfigProvider = StreamProvider<PaymentConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('payment_config')
      .snapshots()
      .map(PaymentConfig.fromFirestore);
});
