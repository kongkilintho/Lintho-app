// ============================================================
// lib/widgets/status_stepper.dart — LinTho
// ▸ ຄວາມຄືບໜ້າວຽກດຽວກັນ (accepted → on the way → arrived → working →
//   completed) ຖືກສ້າງແຍກກັນ 2 ຄັ້ງ, ອິດສະຫຼະຈາກກັນ: job_workflow_Screen.dart
//   (ຝັ່ງຊ່າງ, ແນວນອນ, ໃຊ້ emoji + C.navy) ແລະ tracking_screen.dart (ຝັ່ງ
//   ລູກຄ້າ, ແນວຕັ້ງ, ໃຊ້ emoji + C.green/C.primary) — logic ສີ/label ບໍ່
//   ກົງກັນ, ສ່ຽງໃຫ້ຊ່າງ ແລະ ລູກຄ້າເຫັນສະຖານະດຽວກັນຄົນລະຮູບແບບ.
// ▸ StatusStepper ນີ້ຮັບຂໍ້ມູນ step ແບບກາງ (icon/label, ບໍ່ອີງ enum ສະເພາະ
//   ຝັ່ງໃດ) ເພື່ອໃຫ້ທັງສອງຝັ່ງເອີ້ນໃຊ້ໄດ້ດ້ວຍ widget ດຽວກັນ, ຮອງຮັບທັງ
//   ແນວນອນ ແລະ ແນວຕັ້ງ.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusStep {
  final IconData icon;
  final String label;
  const StatusStep({required this.icon, required this.label});
}

class StatusStepper extends StatelessWidget {
  final List<StatusStep> steps;
  final int currentIndex; // index ໃນ [steps] ຂອງສະຖານະປັດຈຸບັນ
  final Axis axis;
  final Color activeColor;

  const StatusStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.axis = Axis.horizontal,
    this.activeColor = AppColors.navy,
  });

  @override
  Widget build(BuildContext context) =>
      axis == Axis.horizontal ? _horizontal() : _vertical();

  Widget _horizontal() {
    return Row(children: List.generate(steps.length, (i) {
      final done  = i <= currentIndex;
      final isCur = i == currentIndex;
      final step  = steps[i];
      return Expanded(child: Column(children: [
        Row(children: [
          if (i > 0)
            Expanded(child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 3,
              decoration: BoxDecoration(
                color: done ? activeColor : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
          _dot(done: done, isCur: isCur, icon: step.icon),
          if (i < steps.length - 1)
            Expanded(child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 3,
              decoration: BoxDecoration(
                color: i < currentIndex ? activeColor : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(step.label,
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9,
                fontWeight: isCur ? FontWeight.w800 : FontWeight.w500,
                color: done ? activeColor : AppColors.muted)),
      ]));
    }));
  }

  Widget _vertical() {
    return Column(
      children: List.generate(steps.length, (i) {
        final done   = i < currentIndex;
        final isCur  = i == currentIndex;
        final isLast = i == steps.length - 1;
        final step   = steps[i];
        return Column(children: [
          Row(children: [
            _dot(done: done || isCur, isCur: isCur, icon: step.icon, small: true),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(step.label, style: TextStyle(
                fontSize: 13,
                fontWeight: isCur ? FontWeight.w800 : FontWeight.w500,
                color: (done || isCur) ? activeColor : AppColors.muted))),
            if (done) Icon(Icons.check_circle_rounded, color: activeColor, size: 16),
          ]),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 2, height: 20,
                  color: done ? activeColor : AppColors.border,
                ),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _dot({required bool done, required bool isCur, required IconData icon, bool small = false}) {
    final size = small ? 34.0 : (isCur ? 40.0 : 32.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size, height: size,
      decoration: BoxDecoration(
        color: done ? activeColor : AppColors.border.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        boxShadow: isCur ? [BoxShadow(
            color: activeColor.withValues(alpha: 0.3),
            blurRadius: 8, offset: const Offset(0, 3))] : null,
      ),
      child: done
          ? Icon(icon, color: Colors.white, size: small ? 16 : (isCur ? 18 : 14))
          : null,
    );
  }
}
