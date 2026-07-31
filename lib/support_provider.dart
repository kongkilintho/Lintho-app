// ============================================================
// support_provider.dart — LinTho
// ອ່ານ Support contact info + FAQ list ແບບ real-time ຈາກ Firestore ແທນ
// hardcode ໃນ lib/support_help.dart (admin ຕັ້ງຄ່າຜ່ານ lintho-admin).
//
// Schema (ໃຫ້ lintho-admin ໃຊ້ອ້າງອີງເວລາເພີ່ມໜ້າ Manage FAQ & Support):
//
//   settings/support (document, ຢູ່ໃນ collection `settings` ທີ່ມີຢູ່ແລ້ວ —
//   ຄືຮູບແບບດຽວກັບ settings/legal):
//     phone         : string  — ເບີໂທຮູບແບບ tel: (ບໍ່ມີຊ່ອງວ່າງ), e.g. "8562012345678"
//     phoneDisplay  : string  — ເບີໂທຮູບແບບສະແດງຜົນ, e.g. "020 1234 5678"
//     whatsapp      : string  — ເບີ WhatsApp ຮູບແບບສາກົນ (ບໍ່ມີ +), e.g. "8562099999999"
//     email         : string  — e.g. "support@lintho.app"
//     hours         : string  — ເວລາເປີດບໍລິການ, e.g. "ຈັນ–ເສົາ 08:00–18:00"
//
//   faqs (top-level collection, ອ່ານໄດ້ໂດຍ authenticated user ທຸກຄົນ):
//     each document:
//       question : string  — required
//       answer   : string  — required
//       category : string  — optional, default "" → ຈັດເປັນກຸ່ມ "ທົ່ວໄປ"
//       order    : number  — ລຳດັບສະແດງຜົນ (ນ້ອຍ→ຫຼາຍ), default 0
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SupportInfo {
  final String phone;
  final String phoneDisplay;
  final String whatsapp;
  final String email;
  final String hours;

  const SupportInfo({
    this.phone = '',
    this.phoneDisplay = '',
    this.whatsapp = '',
    this.email = '',
    this.hours = '',
  });

  factory SupportInfo.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const SupportInfo();
    return SupportInfo(
      phone:        d['phone'] as String? ?? '',
      phoneDisplay: d['phoneDisplay'] as String? ?? '',
      whatsapp:     d['whatsapp'] as String? ?? '',
      email:        d['email'] as String? ?? '',
      hours:        d['hours'] as String? ?? '',
    );
  }
}

class FaqItem {
  final String id;
  final String question;
  final String answer;
  final String category;
  final int order;

  const FaqItem({
    required this.id,
    required this.question,
    required this.answer,
    this.category = '',
    this.order = 0,
  });

  factory FaqItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return FaqItem(
      id:       doc.id,
      question: d['question'] as String? ?? '',
      answer:   d['answer'] as String? ?? '',
      category: d['category'] as String? ?? '',
      order:    (d['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// ຂໍ້ມູນຕິດຕໍ່ Support — real-time, ອັບເດດທັນທີຕອນ admin ເຊຟ.
final supportInfoProvider = StreamProvider<SupportInfo>((ref) {
  return FirebaseFirestore.instance.collection('settings').doc('support')
      .snapshots().map((s) => SupportInfo.fromMap(s.data()));
});

/// ລາຍການ FAQ — ຮຽງຕາມ order index, real-time.
final faqListProvider = StreamProvider<List<FaqItem>>((ref) {
  return FirebaseFirestore.instance.collection('faqs')
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs.map(FaqItem.fromDoc).toList());
});
