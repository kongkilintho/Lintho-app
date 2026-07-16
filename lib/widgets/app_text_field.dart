// ============================================================
// lib/widgets/app_text_field.dart — LinTho
// ▸ ກ່ອນໜ້ານີ້ filled/fillColor/border/enabledBorder/focusedBorder block
//   ດຽວກັນ (radius 12 ຫຼື 14, C.border/C.sky) ຖືກຄັດລອກຢູ່ booking_form_screen
//   (10+ ຄັ້ງ), main.dart, profile_tab.dart, earnings_tab.dart ແລະອື່ນໆ.
//   ຄ່າພວກນີ້ຕອນນີ້ຢູ່ໃນ AppTheme.light.inputDecorationTheme ແລ້ວ — widget
//   ນີ້ຫຸ້ມ TextField ດ້ວຍ parameter ທົ່ວໄປທີ່ໃຊ້ຊ້ຳກັນຫຼາຍທີ່ສຸດ.
// ============================================================

import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? prefixText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool enabled;

  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.focusNode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      onChanged: onChanged,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixText: prefixText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
