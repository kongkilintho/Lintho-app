import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_locale.dart';
import 'language_selector.dart';
import 'main.dart' show LoginPage;
import 'register_otp.dart';

/// Welcome / landing screen — the very first thing a guest sees.
/// Single-screen, no scrolling: logo + language switcher on top, a soft
/// AC/cleaning illustration in the middle, and the two primary CTAs pinned
/// to the bottom.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _bg = Color(0xFFF8FAFC);
  static const _primary = C.primary;
  static const _mint = Color(0xFFB7F0D8);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.language, color: Color(0xFF0F172A)),
                    onPressed: () => LanguageSelector.show(context),
                  ),
                ),
                const _WelcomeHeader(),
                const Expanded(child: Center(child: _WelcomeIllustration())),
                const _WelcomeActionButtons(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// TOP AREA — logo mark, app name, slogan (all localized via tr()).
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: WelcomeScreen._primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset(
              'assets/icons/lintho_logo_3d.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('app_name'),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr('welcome_slogan'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }
}

/// MIDDLE AREA — a layered, dimensional graphic for AC cleaning & freshness.
/// Built from shapes/icons (blue + mint) so no extra art asset is required.
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    const primary = WelcomeScreen._primary;
    const mint = WelcomeScreen._mint;
    const skyBlue = Color(0xFF8FD9F2);
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Deepest layer — large, faint, off-center circle for background depth
          Positioned(
            top: 4,
            right: 8,
            child: Container(
              width: 286,
              height: 286,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Outer ambient glow ring — soft shadow lifts it off the background
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primary.withValues(alpha: 0.10),
                  primary.withValues(alpha: 0.0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          // Mid ring — primary blue easing into sky-blue/mint for "fresh air"
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [C.teal, mint],
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          // Central card — elevated, AC unit glyph with a 3D gradient fill
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.22),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.9),
                  blurRadius: 1,
                  offset: const Offset(-4, -4),
                ),
              ],
            ),
            child: Center(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primary, skyBlue],
                ).createShader(bounds),
                child: const Icon(
                  Icons.ac_unit_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Cool-air sweep accents
          const Positioned(
            top: 14,
            left: 36,
            child: _OrbitIcon(
              size: 30,
              icon: Icons.air_rounded,
              bg: Colors.white,
              fg: primary,
            ),
          ),
          Positioned(
            top: 30,
            right: 16,
            child: _OrbitIcon(
              size: 34,
              icon: Icons.cleaning_services_rounded,
              bg: mint,
              fg: const Color(0xFF0F172A),
            ),
          ),
          const Positioned(
            bottom: 28,
            left: 14,
            child: _OrbitIcon(
              size: 26,
              icon: Icons.water_drop_rounded,
              bg: Colors.white,
              fg: primary,
            ),
          ),
          const Positioned(
            bottom: 10,
            right: 30,
            child: _OrbitIcon(
              size: 24,
              icon: Icons.auto_awesome_rounded,
              bg: Colors.white,
              fg: primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitIcon extends StatelessWidget {
  final double size;
  final IconData icon;
  final Color bg;
  final Color fg;

  const _OrbitIcon({
    required this.size,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: WelcomeScreen._primary.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.52, color: fg),
    );
  }
}

/// BOTTOM AREA — "ລົງທະບຽນ" (filled) and "ເຂົ້າລະບົບ" (outlined) side-by-side.
class _WelcomeActionButtons extends StatelessWidget {
  const _WelcomeActionButtons();

  @override
  Widget build(BuildContext context) {
    const primary = WelcomeScreen._primary;
    const radius = 18.0;
    const height = 56.0;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
              child: Text(
                tr('register_submit'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: SizedBox(
            height: height,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                side: const BorderSide(color: primary, width: 1.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
              child: Text(
                tr('login'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
