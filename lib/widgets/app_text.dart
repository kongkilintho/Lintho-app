// ============================================================
// lib/widgets/app_text.dart — LinTho
// ▸ [PHASE1] AppTypography (lib/theme/app_theme.dart) ມີ 6 role ແລ້ວ ແຕ່ບໍ່ມີ
//   ໜ້າຈໍໃດອ້າງອີງໂດຍກົງ (0 ຄັ້ງ ໃນທຸກ 45 ໄຟລ໌ທີ່ກວດ — ເບິ່ງ Re-Audit
//   2026-08-23 §Design System Audit) — ເພາະການໃຊ້ AppTypography.title ຕ້ອງ
//   ຂຽນ `Text(x, style: AppTypography.title)` ຍາວກວ່າ ແລະ ບໍ່ຈື່ຊື່ໄດ້ງ່າຍ
//   ເທົ່າ `TextStyle(fontSize: 22, fontWeight: FontWeight.w600)`. AppText ເຮັດ
//   ໃຫ້ token ເປັນເສັ້ນທາງທີ່ງ່າຍກວ່າ (constructor ຕໍ່ role) ແທນທີ່ຈະເປັນ
//   ທາງເລືອກທີ່ຕ້ອງຈື່.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppText extends StatelessWidget {
  final String text;
  final TextStyle _base;
  final Color? color;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppText.display(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.display, super(key: key);

  const AppText.title(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.title, super(key: key);

  const AppText.heading(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.heading, super(key: key);

  const AppText.body(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.body, super(key: key);

  const AppText.label(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.label, super(key: key);

  const AppText.caption(this.text, {
    Key? key, this.color, this.fontWeight, this.textAlign,
    this.maxLines, this.overflow,
  }) : _base = AppTypography.caption, super(key: key);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: _base.copyWith(color: color, fontWeight: fontWeight),
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow ?? (maxLines != null ? TextOverflow.ellipsis : null),
      );
}
