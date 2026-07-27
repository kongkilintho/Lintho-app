// ============================================================
// legal_content_provider.dart — LinTho Customer App
// ອ່ານ Terms & Conditions / Privacy Policy ແບບ real-time ຈາກ
// `settings/legal` (admin ຕັ້ງຜ່ານ lintho-admin/src/app/settings/page.tsx,
// tab "Legal Content" — ເບິ່ງ useLegalContent/useUpdateLegalContent
// ໃນ lintho-admin/src/lib/hooks/index.ts).
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LegalContent {
  final String terms;
  final String privacy;

  const LegalContent({this.terms = '', this.privacy = ''});

  factory LegalContent.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const LegalContent();
    return LegalContent(
      terms: d['terms'] as String? ?? '',
      privacy: d['privacy'] as String? ?? '',
    );
  }
}

/// ເນື້ອຫາ Terms & Conditions / Privacy Policy — real-time, ອັບເດດທັນທີຕອນ admin ເຊຟ.
final legalContentProvider = StreamProvider<LegalContent>((ref) {
  return FirebaseFirestore.instance.collection('settings').doc('legal')
      .snapshots().map((s) => LegalContent.fromMap(s.data()));
});
