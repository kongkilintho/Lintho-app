// ============================================================
// lib/widgets/pulsing_fade.dart — LinTho
// ✅ ໜຶ່ງໃນ widget ຮ່ວມກັນຊຸດທຳອິດໃນ lib/widgets/ — ຫຼຸດການຊ້ຳຂອງ
// AnimationController + Tween<double> + dispose() boilerplate ທີ່ເຄີຍຖືກ
// ຂຽນແຍກກັນຢູ່ຫຼາຍບ່ອນໃນ main.dart (ເຊັ່ນ _RoleRouterSkeletonState,
// _ButtonLoadingSkeletonState) ສຳລັບ skeleton/loading widget ແບບ pulse-fade.
// ============================================================

import 'package:flutter/material.dart';

class PulsingFade extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double begin;
  final double end;
  final Curve curve;

  const PulsingFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
    this.begin = 0.4,
    this.end = 0.9,
    this.curve = Curves.easeInOut,
  });

  @override
  State<PulsingFade> createState() => _PulsingFadeState();
}

class _PulsingFadeState extends State<PulsingFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _fade = Tween<double>(begin: widget.begin, end: widget.end)
        .animate(CurvedAnimation(parent: _anim, curve: widget.curve));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: widget.child);
}
