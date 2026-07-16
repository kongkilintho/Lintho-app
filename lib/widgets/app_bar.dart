// ============================================================
// lib/widgets/app_bar.dart — LinTho
// ▸ ກ່ອນໜ້ານີ້ AppBar(backgroundColor: Colors.white, elevation: 0,
//   centerTitle: true, title: Text(x, style: TextStyle(color: C.text,
//   fontWeight: FontWeight.w800, fontSize: 18))) ຖືກພິມຊ້ຳ 15+ ຄັ້ງທົ່ວແອັບ.
//   ຄ່າພວກນີ້ຕອນນີ້ຢູ່ໃນ AppTheme.light.appBarTheme ແລ້ວ, ສະນັ້ນ
//   AppBar(title: Text(x)) ທຳມະດາກໍ່ໄດ້ຮູບແບບດຽວກັນໂດຍອັດຕະໂນມັດ — widget
//   ນີ້ເປັນ convenience wrapper ໃຫ້ constructor ສັ້ນລົງ ແລະ ບັງຄັບຄວາມສະໝ່ຳສະເໝີ.
// ============================================================

import 'package:flutter/material.dart';

class LinThoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const LinThoAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
