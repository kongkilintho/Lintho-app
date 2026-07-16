import 'package:flutter/material.dart';

/// Brand mark tile — renders the app logo image, reused wherever the logo
/// appears in-app (login, register) so the look stays consistent everywhere.
class BrandMarkTile extends StatelessWidget {
  final double size;
  final double? radius;

  const BrandMarkTile({super.key, required this.size, this.radius});

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.28;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.asset(
        'assets/icons/lintho_logo_3d.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
