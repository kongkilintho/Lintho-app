// ============================================================
// lib/widgets/error_state_view.dart — LinTho
// ▸ ຮູບແບບ icon + message + retry ຖືກຄັດລອກຢູ່ home_tab.dart ແລະ jobs_tab.dart
//   ໂດຍແຍກກັນປະກາດ, ແລະ ຫຼາຍໜ້າຈໍ (booking list, booking detail, coupon list,
//   earnings) ບໍ່ມີ error state ຈິງເລີຍ — Firestore error ຖືກປອມເປັນ empty/
//   not-found. ນີ້ຄືມາດຕະຖານດຽວ, ໃຊ້ໄດ້ທັງ full-screen ແລະ inline (compact).
// ============================================================

import 'package:flutter/material.dart';
import '../app_locale.dart';
import '../theme/app_theme.dart';

class ErrorStateView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;
  final bool compact;

  const ErrorStateView({
    super.key,
    required this.onRetry,
    this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 36.0 : 56.0;
    final gap = compact ? AppSpacing.sm : AppSpacing.md;

    return Center(child: Padding(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: iconSize, color: AppColors.muted),
          SizedBox(height: gap),
          Text(message ?? tr('load_failed'),
              textAlign: TextAlign.center,
              style: compact ? AppTypography.caption : AppTypography.body.copyWith(
                  color: AppColors.muted, fontWeight: FontWeight.w600)),
          SizedBox(height: gap + AppSpacing.xs),
          compact
              ? TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr('retry')),
                )
              : OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('retry')),
                ),
        ],
      ),
    ));
  }
}
