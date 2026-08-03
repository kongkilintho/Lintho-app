import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_colors.dart';
import 'app_locale.dart';
import 'language_selector.dart';
import 'legal_content_provider.dart';
import 'main.dart' show LoginPage;
import 'register_otp.dart';

/// Welcome / landing screen — the very first thing a guest sees.
/// Single-screen, no scrolling: logo + language switcher on top, a soft
/// AC/cleaning illustration in the middle, and the two primary CTAs pinned
/// to the bottom.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  // ✅ [Brand color audit 2026-07-27 v2] #F8FAFC ເປັນຄ່າ drift ໃກ້ຄຽງ C.bg
  // (#F8FAFF) ໂດຍບໍ່ຕັ້ງໃຈ — ລວມເປັນ token ດຽວ
  static const _bg = C.bg;
  static const _primary = C.primary;
  static const _mint = Color(0xFFB7F0D8); // illustration-only pastel, ບໍ່ແມ່ນ brand token

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: _bg,
        body: Container(
          // ✅ Redesign 2026-07-31: soft brand gradient — mint-green wash
          // easing into white top→bottom, ບໍ່ໃຫ້ໜ້າຈໍຂາວແປນຄືເກົ່າ
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.55],
              colors: [Color(0xFFDCFBEE), Colors.white],
            ),
          ),
          child: SafeArea(
            // ✅ [FIX HI-AUTH-2] ກ່ອນໜ້ານີ້ໃຊ້ Column+Expanded ໂດຍບໍ່ scroll ແລະ
            // ບໍ່ lock orientation — ຈໍນ້ອຍ ຫຼື ໝູນຈໍນອນ (landscape) ພື້ນທີ່ສູງ
            // ບໍ່ພຽງພໍໃຫ້ illustration ຂະໜາດຄົງທີ່ 300x300 + header + ປຸ່ມ ຈະ
            // overflow. ຕອນນີ້ໃຊ້ SingleChildScrollView + FittedBox ໃຫ້ illustration
            // ຫຼຸດຂະໜາດແທນ clip, ແລະ ໜ້າຈໍ scroll ໄດ້ຖ້າພື້ນທີ່ບໍ່ພໍ.
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    // ✅ [Customer UX pass 2026-08-03] ປ່ຽນຈາກ globe icon ທົ່ວໄປ
                    // ເປັນທຸງຂອງພາສາທີ່ເລືອກຢູ່ປັດຈຸບັນ (AppLangLabel.flag ຈາກ
                    // language_selector.dart) — ໜ້ານີ້ຢູ່ໃນ ListenableBuilder
                    // ຢູ່ແລ້ວ ຈຶ່ງ rebuild ອັດຕະໂນມັດທັນທີທີ່ປ່ຽນພາສາ.
                    child: IconButton(
                      icon: Text(AppLocale.instance.lang.flag,
                          style: const TextStyle(fontSize: 22)),
                      tooltip: tr('change_language_semantic'), // ✅ [FIX ME-AUTH-5]
                      onPressed: () => LanguageSelector.show(context),
                    ),
                  ),
                  const _WelcomeHeader(),
                  const SizedBox(height: 20),
                  const Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 300, height: 300,
                        child: _WelcomeIllustration(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _WelcomeActionButtons(),
                  const SizedBox(height: 18),
                  const _WelcomeFooter(),
                  const SizedBox(height: 8),
                ],
              ),
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
                color: WelcomeScreen._primary.withValues(alpha: 0.24),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                blurRadius: 2,
                offset: const Offset(-3, -3),
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
        const SizedBox(height: 18),
        Text(
          tr('app_name'),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            height: 1.0,
            color: C.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr('welcome_slogan'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.3,
            color: C.muted,
          ),
        ),
      ],
    );
  }
}

/// MIDDLE AREA — a layered, dimensional graphic for AC cleaning & freshness.
/// Built from shapes/icons (blue + mint) so no extra art asset is required.
/// Adds a slow, gentle float/breathe loop so the graphic feels alive without
/// being distracting.
class _WelcomeIllustration extends StatefulWidget {
  const _WelcomeIllustration();

  @override
  State<_WelcomeIllustration> createState() => _WelcomeIllustrationState();
}

class _WelcomeIllustrationState extends State<_WelcomeIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = WelcomeScreen._primary;
    const mint = WelcomeScreen._mint;
    const skyBlue = Color(0xFF8FD9F2);
    return SizedBox(
      width: 300,
      height: 300,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          // Gentle breathing scale for the outer glow ring.
          final breathe = 1.0 + 0.03 * math.sin(t);
          return Stack(
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
              // Outer ambient glow ring — soft shadow lifts it off the background,
              // breathes slowly for a subtle sense of life.
              Transform.scale(
                scale: breathe,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primary.withValues(alpha: 0.12),
                        primary.withValues(alpha: 0.0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.10),
                        blurRadius: 36,
                        spreadRadius: 4,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
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
              // Central card — elevated, AC unit glyph with a 3D gradient fill,
              // floats up/down very slightly on its own gentle rhythm.
              Transform.translate(
                offset: Offset(0, 4 * math.sin(t)),
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.26),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
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
              ),
              // Cool-air sweep accents — each floats on its own phase offset so
              // they drift out of sync, like they're orbiting loosely.
              Positioned(
                top: 14,
                left: 36,
                child: Transform.translate(
                  offset: Offset(0, 6 * math.sin(t + math.pi / 2)),
                  child: const _OrbitIcon(
                    size: 30,
                    icon: Icons.air_rounded,
                    bg: Colors.white,
                    fg: primary,
                  ),
                ),
              ),
              Positioned(
                top: 30,
                right: 16,
                child: Transform.translate(
                  offset: Offset(0, 6 * math.sin(t + math.pi)),
                  child: const _OrbitIcon(
                    size: 34,
                    icon: Icons.cleaning_services_rounded,
                    bg: mint,
                    fg: C.text,
                  ),
                ),
              ),
              Positioned(
                bottom: 28,
                left: 14,
                child: Transform.translate(
                  offset: Offset(0, 6 * math.sin(t + 3 * math.pi / 2)),
                  child: const _OrbitIcon(
                    size: 26,
                    icon: Icons.water_drop_rounded,
                    bg: Colors.white,
                    fg: primary,
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                right: 30,
                child: Transform.translate(
                  offset: Offset(0, 6 * math.sin(t)),
                  child: const _OrbitIcon(
                    size: 24,
                    icon: Icons.auto_awesome_rounded,
                    bg: Colors.white,
                    fg: primary,
                  ),
                ),
              ),
            ],
          );
        },
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

/// BOTTOM AREA — "ລົງທະບຽນ" (solid brand green) and "ເຂົ້າລະບົບ" (light
/// container, tinted) side-by-side, deliberately contrasting styles so the
/// primary action reads first.
class _WelcomeActionButtons extends StatefulWidget {
  const _WelcomeActionButtons();

  @override
  State<_WelcomeActionButtons> createState() => _WelcomeActionButtonsState();
}

class _WelcomeActionButtonsState extends State<_WelcomeActionButtons> {
  // ✅ [FIX Medium-9] ກັນກົດຮ້ອງທັນທີໆຫຼາຍເທື່ອ — ບໍ່ໃຫ້ push route ຊ້ຳກັນ
  bool _navigating = false;

  Future<void> _push(Widget page) async {
    if (_navigating) return;
    _navigating = true;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _navigating = false;
  }

  @override
  Widget build(BuildContext context) {
    const primary = WelcomeScreen._primary;
    const radius = 18.0;
    const height = 56.0;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.32),
                  blurRadius: 22,
                  spreadRadius: -2,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () => _push(const RegisterPage()),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
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
              onPressed: () => _push(const LoginPage()),
              style: OutlinedButton.styleFrom(
                backgroundColor: primary.withValues(alpha: 0.08),
                foregroundColor: primary,
                side: BorderSide.none,
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

/// FOOTER — muted "Terms & Privacy" link, tappable, opens the same legal
/// bottom sheet used on the register screen (see register_otp.dart).
class _WelcomeFooter extends StatefulWidget {
  const _WelcomeFooter();

  @override
  State<_WelcomeFooter> createState() => _WelcomeFooterState();
}

class _WelcomeFooterState extends State<_WelcomeFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _showTermsPrivacy(context);
    _privacyTap = TapGestureRecognizer()..onTap = () => _showTermsPrivacy(context);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: tr('register_legal_prefix')),
        TextSpan(
          text: tr('terms_conditions_full'),
          style: const TextStyle(color: C.muted, fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
          recognizer: _termsTap,
        ),
        TextSpan(text: tr('register_legal_and')),
        TextSpan(
          text: tr('privacy_policy'),
          style: const TextStyle(color: C.muted, fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
          recognizer: _privacyTap,
        ),
        TextSpan(text: tr('register_legal_suffix')),
      ]),
      textAlign: TextAlign.center,
      style: const TextStyle(color: C.muted, fontSize: 12, height: 1.5),
    );
  }

  void _showTermsPrivacy(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75, minChildSize: 0.4, maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: C.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(tr('terms_privacy'), style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
            const SizedBox(height: 20),
            Consumer(builder: (context, ref, _) {
              final legal = ref.watch(legalContentProvider).value;
              final terms = (legal != null && legal.terms.isNotEmpty)
                  ? legal.terms : tr('terms_content');
              final privacy = (legal != null && legal.privacy.isNotEmpty)
                  ? legal.privacy : tr('privacy_content');
              return Column(children: [
                _legalSection(Icons.description, tr('terms_conditions_full'), terms),
                const SizedBox(height: 14),
                _legalSection(Icons.privacy_tip_outlined, tr('privacy_policy'), privacy),
              ]);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _legalSection(IconData icon, String title, String content) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.border, width: 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: C.navy, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: C.text)),
          ]),
          const SizedBox(height: 10),
          Text(content, style: const TextStyle(
              fontSize: 13, color: C.muted, height: 1.5)),
        ]),
      );
}
