// ============================================================
// lib/widgets/app_text_field.dart — LinTho
// ▸ ກ່ອນໜ້ານີ້ filled/fillColor/border/enabledBorder/focusedBorder block
//   ດຽວກັນ (radius 12 ຫຼື 14, C.border/C.sky) ຖືກຄັດລອກຢູ່ booking_form_screen
//   (10+ ຄັ້ງ), main.dart, profile_tab.dart, earnings_tab.dart ແລະອື່ນໆ.
//   ຄ່າພວກນີ້ຕອນນີ້ຢູ່ໃນ AppTheme.light.inputDecorationTheme ແລ້ວ — widget
//   ນີ້ຫຸ້ມ TextField ດ້ວຍ parameter ທົ່ວໄປທີ່ໃຊ້ຊ້ຳກັນຫຼາຍທີ່ສຸດ.
//
// ▸ customer_register_flow.dart ແລະ technician_register_screen.dart ມີ
//   _TextField ຂອງຕົນເອງແຍກກັນ (ຄືກັນເປັ໊ະ) ດ້ວຍ style ທີ່ບໍ່ກົງກັບ theme
//   default (fillColor ຂາວ, radius 14, focus border ສີ teal) — override
//   parameter ຂ້າງລຸ່ມນີ້ ໃຫ້ທັງ 2 ໜ້ານັ້ນຄົງໜ້າຕາເກົ່າໄວ້ຄັກໆ ຫຼັງລວມເຂົ້າ
//   widget ດຽວ (ບໍ່ປ່ຽນ visual).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;
  final List<String>? autofillHints;

  // Overrides — when null, falls back to AppTheme.light.inputDecorationTheme.
  // Set these to replicate a call site's pre-existing custom look exactly.
  final TextStyle? style;
  final TextStyle? hintStyle;
  final Color? fillColor;
  final double? borderRadius;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final double focusedBorderWidth;
  final Color? iconColor;
  final double? iconSize;
  final EdgeInsetsGeometry? contentPadding;
  final bool hideCounter;

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
    this.maxLength,
    this.onChanged,
    this.focusNode,
    this.enabled = true,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.style,
    this.hintStyle,
    this.fillColor,
    this.borderRadius,
    this.borderColor,
    this.focusedBorderColor,
    this.focusedBorderWidth = 2,
    this.iconColor,
    this.iconSize,
    this.contentPadding,
    this.hideCounter = false,
  });

  OutlineInputBorder? _border(Color? color, double width) =>
      borderRadius == null || color == null ? null : OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius!),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      enabled: enabled,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      style: style,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: hintStyle,
        prefixText: prefixText,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: iconColor, size: iconSize),
        suffixIcon: suffixIcon,
        counterText: hideCounter ? '' : null,
        filled: fillColor != null ? true : null,
        fillColor: fillColor,
        contentPadding: contentPadding,
        border: _border(borderColor, 1),
        enabledBorder: _border(borderColor, 1),
        focusedBorder: _border(focusedBorderColor, focusedBorderWidth),
      ),
    );
  }
}
