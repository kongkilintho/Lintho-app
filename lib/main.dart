// ============================================================
// main.dart — LinTho App
// Fixes:
//   ✅ [FIX-1] import provider_model.dart + tracking_screen.dart
//   ✅ [FIX-3] ReviewScreen constructor — ໃຊ້ ProviderModel ຖືກຕ້ອງ
//   ✅ [FIX-4] import 'provider model.dart' → 'provider_model.dart'
//   ✅ [FIX-5] ລຶບ unused imports ອອກ
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'provider_dashboard.dart';
import 'firestore_service.dart';
import 'review_screen.dart';
import 'welcome_screen.dart';
import 'pending_approval_screen.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'rewards_provider.dart';
import 'rewards_screen.dart';
import 'coupon_list_screen.dart';
import 'coupon_repository.dart';
import 'language_selector.dart';
import 'booking_form_screen.dart';
import 'booking_display_helpers.dart';
import 'booking_detail_screen.dart';
import 'fcm_service.dart';
import 'cloudinary_service.dart';
import 'quick_booking_screen.dart';
import 'package:intl/intl.dart';
import 'lao_phone.dart';
import 'widgets/pulsing_fade.dart';
import 'theme/app_theme.dart';

const firebaseOptions = FirebaseOptions(
  apiKey:            "AIzaSyD-bIErOqCC6vHqn45oHhtL52Cw54O8SMs",
  authDomain:        "sabee-app-35d99.firebaseapp.com",
  projectId:         "sabee-app-35d99",
  storageBucket:     "sabee-app-35d99.firebasestorage.app",
  messagingSenderId: "759333413622",
  appId:             "1:759333413622:web:48e4cd177bf4f215a842d7",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // firebaseOptions ແມ່ນ web config — Android/iOS ຕ້ອງໃຊ້ native
  // google-services.json / GoogleService-Info.plist ແທນ ບໍ່ດັ່ງນັ້ນ
  // Firebase.initializeApp() ຈະ throw ແລະ ເຮັດໃຫ້ໜ້າຈໍດຳ.
  if (kIsWeb) {
    await Firebase.initializeApp(options: firebaseOptions);
  } else {
    await Firebase.initializeApp();
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await AppLocale.loadSaved();
  runApp(const ProviderScope(child: LinThoApp()));
}

class LinThoApp extends StatelessWidget {
  const LinThoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ ListenableBuilder ຄຸມທັງ app ເພື່ອໃຫ້ທຸກໜ້າ rebuild ທັນທີ
    // ເມື່ອປ່ຽນພາສາ, ບໍ່ຕ້ອງເພີ່ມ wrapper ແຍກໃນແຕ່ລະໜ້າຈໍ.
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: FCMService.navigatorKey ??= GlobalKey<NavigatorState>(),
          title: 'LinTho',
          debugShowCheckedModeBanner: false,
          // ✅ [Phase 2] ThemeData ລວມສູນ — ເບິ່ງ lib/theme/app_theme.dart.
          // ກ່ອນໜ້ານີ້ບ່ອນນີ້ກຳນົດແຕ່ colorScheme/primaryColor/background,
          // ບໍ່ມີ AppBar/Card/Button/Input/BottomSheet/Dialog theme ກາງ.
          theme: AppTheme.light,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: _SplashSkeleton()),
                );
              }
              if (snapshot.hasData) return const RoleRouter();
              return const WelcomeScreen();
            },
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
// SKELETON
// ════════════════════════════════════════════════════════════

class _SplashSkeleton extends StatefulWidget {
  const _SplashSkeleton();
  @override
  State<_SplashSkeleton> createState() => _SplashSkeletonState();
}

class _SplashSkeletonState extends State<_SplashSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A7BFF), Color(0xFF0B4FCC)],
        ),
      ),
      child: FadeTransition(
        opacity: _fade,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Image.asset(
            'assets/icons/lintho_logo_3d.png',
            width: 96,
            height: 96,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          const Text(
            'LinTho',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ທຸກເລື່ອງຊ່າງ ຈົບງ່າຍໃນແອັບດຽວ',
            style: TextStyle(color: Color(0xFFD6E4FF), fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ROLE ROUTER
// ════════════════════════════════════════════════════════════

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});
  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  @override
  void initState() {
    super.initState();
    FCMService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();
    if (user.email == 'admin@sabee.la') return const _AdminRedirectScreen();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: C.bg,
            body: _RoleRouterSkeleton(),
          );
        }
        final data   = snapshot.data?.data() as Map<String, dynamic>?;
        final role   = data?['role'] as String? ?? 'customer';
        final status = data?['status'] as String? ?? 'active';
        if (role == 'provider') {
          if (status == 'pending') return const PendingApprovalScreen();
          return const ProviderDashboard();
        }
        return const MainShell();
      },
    );
  }
}

// ✅ [lib/widgets/ ExAMPLE] ປ່ຽນຈາກ StatefulWidget ທີ່ຂຽນ AnimationController
// ເອງ (46 ແຖວ) ໄປໃຊ້ PulsingFade ຈາກ lib/widgets/pulsing_fade.dart ແທນ —
// ຮູບແບບດຽວກັນນີ້ສາມາດໃຊ້ແທນ _ButtonLoadingSkeleton ແລະ skeleton loader
// ອື່ນໆທີ່ຊ້ຳກັນຢູ່ໃນ main.dart, booking_form_screen.dart, ແລະອື່ນໆ
class _RoleRouterSkeleton extends StatelessWidget {
  const _RoleRouterSkeleton();

  @override
  Widget build(BuildContext context) {
    return const PulsingFade(
      duration: Duration(milliseconds: 800),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _SkeletonBox(width: 72, height: 72, radius: 22,
              color: C.blue, alpha: 0.12),
          SizedBox(height: 16),
          _SkeletonBox(width: 120, height: 14, radius: 6,
              color: C.muted, alpha: 0.2),
        ]),
      ),
    );
  }
}

/// ✅ ອີກ pattern ໜຶ່ງທີ່ຊ້ຳກັນຫຼາຍບ່ອນ (Container + BoxDecoration ສີບາງໆ) —
/// ລວມເປັນ widget ດຽວແທນທີ່ຈະຂຽນ Container/BoxDecoration ຊ້ຳທຸກບ່ອນ
class _SkeletonBox extends StatelessWidget {
  final double width, height, radius, alpha;
  final Color color;
  const _SkeletonBox({
    required this.width, required this.height,
    required this.radius, required this.color,
    this.alpha = 0.15,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

// ════════════════════════════════════════════════════════════
// LOGIN
// ════════════════════════════════════════════════════════════

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool    _loading = false;
  bool    _googleLoading = false;
  bool    _obscure = true;
  String? _error;

  late final AnimationController _entrance;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final input = _emailCtrl.text.trim();
    final pass  = _passCtrl.text.trim();
    if (input.isEmpty || pass.isEmpty) {
      setState(() => _error = tr('fill_all'));
      return;
    }
    // ✅ ຊ່ອງນີ້ຮັບເບີໂທ — ແປງເປັນ synthetic email ໃຫ້ກົງກັບ
    // ການລົງທະບຽນ (register_otp.dart). ຮອງຮັບ email ກົງໆນຳ (admin/legacy).
    final email = input.contains('@') ? input : '$input@lintho.app';
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: pass);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch(e.code) {
        'user-not-found' || 'wrong-password' || 'invalid-credential'
            => tr('wrong_pass'),
        _   => '${tr("error")} (${e.code})',
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // ຜູ້ໃຊ້ກົດຍົກເລີກ — ບໍ່ຕ້ອງສະແດງ error
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCred.user;
      if (user != null) {
        final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final snap = await doc.get();
        if (!snap.exists) {
          await doc.set({
            'uid':         user.uid,
            'displayName': user.displayName ?? '',
            'email':       user.email ?? '',
            'role':        'customer',
            'photoUrl':    user.photoURL ?? '',
            'createdAt':   FieldValue.serverTimestamp(),
          });
        }
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${tr("error")}: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('reset_password'), style: const TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('reset_password_hint'),
                style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _fieldDecoration(
                  hint: 'example@email.com', icon: Icons.email_outlined),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (_) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: Text(tr('send_reset_link'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('reset_link_sent'))),
      );
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: C.muted, fontSize: 14),
      prefixIcon: Icon(icon, color: C.teal, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: C.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: C.teal, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('login'), style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold,
                        color: C.text)),
                    const SizedBox(height: 6),
                    Text(tr('welcome'),
                        style: const TextStyle(
                            color: C.muted, fontSize: 14)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                          fontSize: 15, color: C.text),
                      decoration: _fieldDecoration(
                        hint: '020 7X XXX XXX',
                        icon: Icons.phone_android_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(
                          fontSize: 15, color: C.text),
                      decoration: _fieldDecoration(
                        hint: '••••••••',
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: C.muted,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: _loading ? null : _forgotPassword,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 2),
                            child: Text(tr('forgot_password'),
                                style: const TextStyle(
                                    color: C.teal,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: C.red.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: C.red.withValues(alpha: 0.4)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline,
                                      color: C.red, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error ?? '',
                                        style: const TextStyle(
                                            color: C.red,
                                            fontSize: 13)),
                                  ),
                                ]),
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: C.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Text(tr('login'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      const Expanded(child: Divider(color: C.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(tr('or_continue_with'),
                            style: const TextStyle(
                                color: C.muted, fontSize: 12)),
                      ),
                      const Expanded(child: Divider(color: C.border)),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity, height: 52,
                      child: OutlinedButton(
                        onPressed: _googleLoading ? null : _loginWithGoogle,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _googleLoading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: C.muted),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/google_logo.svg',
                                    width: 20, height: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(tr('continue_with_google'),
                                      style: const TextStyle(
                                          color: C.text,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonLoadingSkeleton extends StatefulWidget {
  const _ButtonLoadingSkeleton();
  @override
  State<_ButtonLoadingSkeleton> createState() => _ButtonLoadingSkeletonState();
}

class _ButtonLoadingSkeletonState extends State<_ButtonLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.4, end: 1.0).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        width: 100, height: 14,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// MAIN SHELL
// ════════════════════════════════════════════════════════════

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    // ✅ ສ້າງ page widgets ໃໝ່ທຸກຄັ້ງທີ່ build() — ບໍ່ cache ເປັນ const list,
    // ບໍ່ດັ່ງນັ້ນ Flutter ຈະເບິ່ງເຫັນ widget instance ດຽວກັນແລ້ວບໍ່ rebuild
    // subtree ນັ້ນເມື່ອປ່ຽນພາສາ (AppLocale notify ຈາກ root ListenableBuilder).
    // ✅ ບໍ່ໃຊ້ const — ຕ້ອງເປັນ instance ໃໝ່ທຸກຄັ້ງ ບໍ່ດັ່ງນັ້ນ Flutter ຈະ
    // canonicalize const widget ເປັນ instance ດຽວກັນ ແລະ skip rebuild
    // (ເບິ່ງ Element.updateChild: `child.widget == newWidget` → skip).
    final pages = [
      HomeScreen(),
      BookingScreen(),
      ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _idx, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20, offset: const Offset(0, -4),
          )],
        ),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            _nav(0, Icons.home_rounded,           tr('home')),
            _nav(1, Icons.receipt_long_outlined,  tr('booking')),
            _nav(2, Icons.person_outline_rounded, tr('profile')),
          ]),
        )),
      ),
    );
  }

  Widget _nav(int i, IconData icon, String label) {
    final sel = _idx == i;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _idx = i),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? C.navy.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: sel ? C.navy : C.muted, size: 24),
              const SizedBox(height: 3),
              Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: sel ? C.navy : C.muted,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// HOME
// ════════════════════════════════════════════════════════════

// ── LOCATION SELECTOR ───────────────────────────────────────

class _LocationSelector extends StatefulWidget {
  const _LocationSelector();
  @override
  State<_LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<_LocationSelector> {
  String? _city;
  List<String> get _cities => [
        tr('city_vientiane'),
        tr('city_luangprabang'),
        tr('city_pakse'),
        tr('city_savannakhet'),
      ];

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: C.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text(tr('city_picker_title'), style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 8),
          ..._cities.map((c) => ListTile(
            title: Text(c, style: const TextStyle(
                color: C.text, fontWeight: FontWeight.w600)),
            trailing: c == _city
                ? const Icon(Icons.check_circle, color: C.sky)
                : null,
            onTap: () {
              setState(() => _city = c);
              Navigator.pop(context);
            },
          )),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final city = _city ?? _cities.first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _showPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(city, style: const TextStyle(
                color: C.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: C.sky, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── PROMO BANNER CAROUSEL ────────────────────────────────────

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();
  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _ctrl = PageController();
  Timer? _timer;
  int _page = 0;

  List<Map<String, Object>> get _promos => [
    {
      'title': tr('promo1_title'),
      'sub': tr('promo1_sub'),
      'emoji': '🎉',
      'colors': [C.primary, C.teal],
    },
    {
      'title': tr('promo2_title'),
      'sub': tr('promo2_sub'),
      'emoji': '❄️',
      'colors': [Color(0xFF0EA5E9), Color(0xFF22C55E)],
    },
    {
      'title': tr('promo3_title'),
      'sub': tr('promo3_sub'),
      'emoji': '🎁',
      'colors': [Color(0xFFF97316), Color(0xFFFBBF24)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_page + 1) % _promos.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  static const _referralIndex = 2;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 144,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: _promos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final p = _promos[i];
            final colors = p['colors'] as List<Color>;
            final isReferral = i == _referralIndex;
            final isMonthly = i == 1;
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                  color: colors.first.withValues(alpha: 0.25),
                  blurRadius: 16, offset: const Offset(0, 8),
                )],
              ),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(p['title'] as String, style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(p['sub'] as String, style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isReferral ? 15 : 12)),
                  ],
                )),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(p['emoji'] as String,
                      style: TextStyle(
                          fontSize: isReferral ? 44 : (isMonthly ? 48.6 : 36))),
                ),
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_promos.length, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _page == i ? 18 : 6, height: 6,
          decoration: BoxDecoration(
            color: _page == i ? C.sky : C.border,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
      ),
    ]);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static List<Map<String, Object>> get _cats => [
    {
      'icon': '❄️', 'label': tr('svc_ac_clean'), 'sub': tr('cat_ac_sub'),
      'color': const Color(0xFFEFF6FF), 'accent': const Color(0xFF1D4ED8),
      'category': ServiceCategory.acCleaning,
    },
    {
      'icon': '🧹', 'label': tr('svc_house_clean'), 'sub': tr('cat_house_sub'),
      'color': const Color(0xFFF0FDF4), 'accent': const Color(0xFF15803D),
      'category': ServiceCategory.homeCleaning,
    },
  ];

  static List<Map<String, Object>> get _popular => [
    {
      'emoji': '❄️', 'name': tr('svc_ac_general_full'),
      'price': '${tr('starting_from')} 300,000', 'rating': 4.9,
      'time': '45–60 ${tr('minutes_unit')}',
      'color': const Color(0xFFEFF6FF), 'accent': const Color(0xFF1D4ED8),
      'category': ServiceCategory.acCleaning,
    },
    {
      'emoji': '🧹', 'name': tr('svc_house_general_full'),
      'price': '${tr('starting_from')} 180,000', 'rating': 4.8,
      'time': '1–3 ${tr('hours_unit')}',
      'color': const Color(0xFFF0FDF4), 'accent': const Color(0xFF15803D),
      'category': ServiceCategory.homeCleaning,
    },
  ];

  static BookingOrder _quickOrderFor(ServiceCategory category) {
    if (category == ServiceCategory.acCleaning) {
      return BookingOrder(category: ServiceCategory.acCleaning)
        ..acCart.add(AcCartItem(
            type: AcServiceType.standard, btuSize: AcBtuSize.small, qty: 1));
    }
    return BookingOrder(category: ServiceCategory.homeCleaning)
      ..cleanType = HomeCleaningType.general
      ..priceMode = PriceMode.hourly
      ..hours     = 2;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on_outlined, color: C.text, size: 18),
                    const SizedBox(width: 6),
                    Text(user?.displayName ?? tr('default_user_name'),
                        style: const TextStyle(
                            color: C.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    const Icon(Icons.notifications_none_rounded,
                        color: Color(0xFF475569), size: 24),
                  ]),
                  const SizedBox(height: 6),
                  const _LocationSelector(),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const QuickBookingFlow())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: C.navy,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          const Text('🚀', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('quick_book_banner_title'), style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white, fontSize: 14)),
                              Text(tr('quick_book_banner_sub'),
                                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ],
                          )),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _PromoCarousel(),
                ]),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('categories'), style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
                const SizedBox(height: 16),
                Builder(builder: (context) {
                final cats = _cats;
                return IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cats.map((cat) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: cat == cats.first ? 8 : 0,
                        left:  cat == cats.last  ? 8 : 0,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => BookingFormScreen(
                                    initialOrder: BookingOrder(
                                        category: cat['category'] as ServiceCategory),
                                    initialStep: 1,
                                  ))),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 22, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  cat['category'] == ServiceCategory.acCleaning
                                      ? const Color(0xFFE3F2FD)
                                      : const Color(0xFFFFF3E0),
                                  Colors.white,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: (cat['accent'] as Color)
                                      .withValues(alpha: 0.08)),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 15, offset: const Offset(0, 8),
                              )],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat['icon'] as String,
                                      style: const TextStyle(fontSize: 53)),
                                  const SizedBox(height: 12),
                                  Text(cat['label'] as String, textAlign: TextAlign.center,
                                      style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800,
                                      color: C.sky)),
                                  const SizedBox(height: 2),
                                  Text(cat['sub'] as String, textAlign: TextAlign.center,
                                      style: const TextStyle(
                                      fontSize: 11, color: C.muted)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                      }).toList()));
                }),

                const SizedBox(height: 44),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr('popular'), style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const BookingFormScreen())),
                          child: Text(tr('see_all'), style: const TextStyle(
                              color: C.sky,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                        ),
                      ),
                    ]),
                const SizedBox(height: 16),
                ..._popular.map((s) => _PopularCard(service: s)),
              ]),
        )),
      ]),
    );
  }
}

// ── Popular Card ─────────────────────────────────────────────

class _PopularCard extends StatelessWidget {
  final Map<String, dynamic> service;
  const _PopularCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => BookingFormScreen(
              initialOrder: HomeScreen._quickOrderFor(
                  s['category'] as ServiceCategory),
              initialStep: 2,
            ))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
              color: (s['accent'] as Color).withValues(alpha: 0.08),
              blurRadius: 18, offset: const Offset(0, 8),
            )],
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: s['color'] as Color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: Text(s['emoji'] as String,
                  style: const TextStyle(fontSize: 28))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['name'] as String, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900,
                    color: C.text)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: C.yellow, size: 14),
                  const SizedBox(width: 3),
                  Text('${s['rating']}', style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: C.muted)),
                  const SizedBox(width: 10),
                  const Icon(Icons.access_time, color: C.muted, size: 13),
                  const SizedBox(width: 3),
                  Text(s['time'] as String,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w500, color: C.muted)),
                ]),
                const SizedBox(height: 6),
                Text(s['price'] as String, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: C.blue)),
              ],
            )),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: C.muted, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// BOOKING LIST
// ════════════════════════════════════════════════════════════

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  BookingTab _tab = BookingTab.ongoing;

  Map<BookingTab, String> get _tabLabels => {
    BookingTab.ongoing:   tr('tab_ongoing'),
    BookingTab.completed: tr('tab_completed_done'),
    BookingTab.cancelled: tr('cancel'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Text(tr('booking'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: Column(children: [
        _buildStatusTabs(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirestoreService.getMyBookings(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _BookingListSkeleton();
              }
              // ✅ [FIX] ກ່ອນໜ້ານີ້ error ບໍ່ຖືກເຊັກ — Firestore ຜິດພາດຈະຕົກລົງ
              // ເປັນ list ຫວ່າງງຽບໆ, ເຮັດໃຫ້ຄືກັບບໍ່ມີການຈອງທັງໆທີ່ແທ້ຈິງໂຫລດບໍ່ໄດ້.
              if (snapshot.hasError) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 48, color: C.muted),
                    const SizedBox(height: 12),
                    Text(tr('load_failed'), style: const TextStyle(
                        fontSize: 15, color: C.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: Text(tr('retry')),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: C.navy,
                          side: const BorderSide(color: C.navy)),
                    ),
                  ],
                ));
              }
              final allDocs = snapshot.data?.docs ?? [];
              final docs = allDocs.where((d) {
                final b = d.data() as Map<String, dynamic>;
                final status = b['status'] as String? ?? 'pending';
                return bookingTabOf(status) == _tab;
              }).toList();

              if (docs.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: C.sky.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: Text('📋', style: TextStyle(fontSize: 36)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('no_booking_in_category'),
                        style: const TextStyle(
                            fontSize: 16, color: C.muted,
                            fontWeight: FontWeight.w600)),
                  ],
                ));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc    = docs[i];
                  final b      = doc.data() as Map<String, dynamic>;
                  final status = b['status'] as String? ?? 'pending';
                  final style  = bookingStatusStyle(status);
                  final cardBody = Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8, offset: const Offset(0, 3),
                      )],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // ▸ ດ້ານເທິງ: ລະຫັດໃບຈອງ + ວັນທີ-ເວລາ
                      Row(children: [
                        Text(bookingCode(doc.id), style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: C.muted, letterSpacing: 0.3)),
                        const Spacer(),
                        const Icon(Icons.schedule_rounded,
                            size: 13, color: C.muted),
                        const SizedBox(width: 4),
                        Text(bookingScheduleLabel(b), style: const TextStyle(
                            fontSize: 12, color: C.muted,
                            fontWeight: FontWeight.w600)),
                      ]),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: C.border),
                      ),
                      // ▸ ສ່ວນກາງ: ໄອຄອນ + ຊື່ບໍລິການ + ຈຳນວນ
                      Row(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: C.bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(child: Text(
                              b['serviceEmoji'] as String? ?? '🏠',
                              style: const TextStyle(fontSize: 26))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bookingServiceName(b),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w900,
                                    color: C.text)),
                            const SizedBox(height: 3),
                            Text(bookingQuantityLabel(b),
                                style: const TextStyle(
                                    fontSize: 12, color: C.muted,
                                    fontWeight: FontWeight.w500)),
                          ],
                        )),
                      ]),
                      const SizedBox(height: 14),
                      // ▸ ດ້ານລຸ່ມ: ລາຄາລວມສຸດທິ + ປ້າຍສະຖານະ
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(bookingTotalLabel(b), style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900,
                              color: C.text)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: style.bg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(bookingStatusLabel(status),
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold,
                                    color: style.fg)),
                          ),
                        ],
                      ),
                      if (status == 'completed' &&
                          (b['reviewed'] as bool? ?? false) == false) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ReviewScreen(
                                  bookingId:    doc.id,
                                  provider:     providerFromBooking(b),
                                  serviceName:  b['serviceName']  as String? ??
                                      b['serviceType']  as String? ??
                                      tr('service_generic'),
                                  serviceEmoji: b['serviceEmoji'] as String? ??
                                      '🔧',
                                ))),
                            icon: const Icon(Icons.star_rounded,
                                color: C.yellow, size: 16),
                            label: Text(tr('rate'), style: const TextStyle(
                                color: C.navy, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: C.navy),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  );

                  // ▸ ບໍ່ມີປຸ່ມຍົກເລີກຢູ່ໜ້າ list ນີ້ອີກຕໍ່ໄປ (ປ້ອງກັນການ
                  // ເຜີກົດ) — ກົດກາດເພື່ອໄປໜ້າລາຍລະອຽດ, ຍົກເລີກໄດ້ຢູ່ນັ້ນ
                  // ສະເພາະຕອນສະຖານະຍັງ 'pending' ເທົ່ານັ້ນ
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                              BookingDetailScreen(bookingId: doc.id))),
                      child: cardBody,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: BookingTab.values.map((t) {
          final selected = _tab == t;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _tab = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? C.navy : C.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_tabLabels[t]!, textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : C.muted)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BookingListSkeleton extends StatefulWidget {
  const _BookingListSkeleton();
  @override
  State<_BookingListSkeleton> createState() => _BookingListSkeletonState();
}

class _BookingListSkeletonState extends State<_BookingListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: C.muted.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 13,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(width: 80, height: 11,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(5))),
              ],
            )),
            Container(width: 56, height: 26,
                decoration: BoxDecoration(
                    color: C.muted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20))),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PROFILE
// ════════════════════════════════════════════════════════════

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingPhoto = false;

  // ✅ ກົດໄອຄອນກ້ອງ → ເລືອກຮູບຈາກຄັງ/ກ້ອງ → ອັບໂຫລດ Cloudinary
  Future<void> _pickProfilePhoto(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: C.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: C.navy),
            title: const Text('ເລືອກຈາກຄັງຮູບພາບ'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: C.navy),
            title: const Text('ຖ່າຍຮູບໃໝ່'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      )),
    );
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 75);
    if (picked == null || !context.mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await CloudinaryService.instance
          .uploadCustomerPhoto(File(picked.path));
      if (url == null) throw Exception('Upload failed');
      await FirebaseAuth.instance.currentUser?.reload();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ປ່ຽນຮູບໂປຣໄຟລ໌ສຳເລັດ'),
        backgroundColor: C.green,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ອັບໂຫລດຮູບລົ້ມເຫລວ: $e'),
        backgroundColor: C.red,
      ));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: C.bg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
                bottomLeft:  Radius.circular(32),
                bottomRight: Radius.circular(32)),
            boxShadow: [BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16, offset: Offset(0, 6))],
          ),
          padding: EdgeInsets.fromLTRB(20, topPad + 24, 20, 24),
          child: Column(children: [
            SizedBox(
              width: 88, height: 88,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: C.navy.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: C.navy.withValues(alpha: 0.15),
                        width: 2),
                    image: user?.photoURL != null
                        ? DecorationImage(
                            image: NetworkImage(user!.photoURL!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: user?.photoURL != null
                      ? null
                      : Center(child: Text(
                          user?.displayName?.isNotEmpty == true
                              ? user!.displayName![0].toUpperCase()
                              : '👤',
                          style: const TextStyle(
                              fontSize: 36, color: C.navy,
                              fontWeight: FontWeight.w800))),
                ),
                if (_uploadingPhoto)
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(child: SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )),
                  ),
                // ✅ ປຸ່ມປ່ຽນຮູບ — ກອບ/ພື້ນຫຼັງສີຂາວ ມຸມຂວາລຸ່ມ ແບບ FB/LINE
                Positioned(
                  right: -2, bottom: -2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _uploadingPhoto
                          ? null
                          : () => _pickProfilePhoto(context),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: C.navy, width: 2),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4, offset: const Offset(0, 2),
                          )],
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: C.sky, size: 15),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(user?.displayName ?? 'ຜູ້ໃຊ້ LinTho',
                style: const TextStyle(
                    color: Colors.black87, fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(user?.email ?? '',
                style: const TextStyle(
                    color: Colors.black54, fontSize: 13)),
            if ((user?.phoneNumber ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(user!.phoneNumber!,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _editProfile(context, user),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_outlined,
                        color: C.navy, size: 13),
                    const SizedBox(width: 5),
                    Text(tr('edit_profile'), style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: C.navy)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat(Icons.calendar_month_rounded, C.blue,
                    '5', tr('bookings_count_label'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const BookingScreen()))),
                _vDiv(),
                Consumer(builder: (context, ref, _) {
                  final points = ref.watch(rewardPointsProvider).value ?? 0;
                  return _stat(Icons.monetization_on_rounded, C.yellow,
                      _formatPointsCompact(points), tr('points_label'),
                      onTap: () => _showPointsSheet(context));
                }),
                _vDiv(),
                _couponBadge(),
              ],
            ),
          ]),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
          child: Column(children: [
            _group(tr('manage_account'), [
              _tile(Icons.favorite_outline,
                  tr('favorite_providers'), tr('favorite_providers_sub'), iconColor: C.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const FavoriteProvidersScreen()))),
              _tile(Icons.receipt_long,
                  tr('payment_history'), tr('payment_history_sub'), iconColor: C.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const PaymentHistoryScreen()))),
            ]),
            const SizedBox(height: 20),
            _group(tr('settings'), [
              _tile(Icons.notifications_outlined, tr('notifications'), '',
                  iconColor: C.orange,
                  onTap: () => _showNotif(context)),
              _tile(Icons.help_outline, tr('help_support'), tr('faq_support_sub'),
                  iconColor: C.muted,
                  onTap: () => _showHelp(context)),
              _tile(Icons.description, tr('terms_privacy'), tr('terms_privacy_sub'),
                  iconColor: C.muted,
                  onTap: () => _showTermsPrivacy(context)),
              _tile(Icons.language, tr('language'), '',
                  iconColor: C.sky,
                  onTap: () => LanguageSelector.show(context)),
              _tile(Icons.vpn_key_outlined, 'ຕັ້ງຄ່າຄວາມປອດໄພ',
                  'ປ່ຽນລະຫັດຜ່ານ / ຄວາມປອດໄພ', iconColor: C.green,
                  onTap: () => _showSecurity(context)),
            ]),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 3),
                )],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _confirmLogout(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: C.red, size: 20),
                        SizedBox(width: 8),
                        Text('ອອກຈາກລະບົບ', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: C.red)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('app_version'), style: TextStyle(
                fontSize: 11, color: C.muted.withValues(alpha: 0.6))),
          ]),
        )),
      ]),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('ອອກຈາກລະບົບ?', style: TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: const Text('ທ່ານຕ້ອງການອອກຈາກລະບົບແມ່ນບໍ່?',
            style: TextStyle(color: C.muted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ',
                style: TextStyle(color: C.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ຢືນຢັນ', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('ລຶບບັນຊີຜູ້ໃຊ້', style: TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: const Text(
            'ທ່ານຕ້ອງການລຶບບັນຊີຂອງທ່ານແມ່ນບໍ່? ການກະທຳນີ້ບໍ່ສາມາດກັບຄືນໄດ້.',
            style: TextStyle(color: C.muted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ',
                style: TextStyle(color: C.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.red, elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ຢືນຢັນ', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSecurity(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: C.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('ຕັ້ງຄ່າຄວາມປອດໄພ', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 20),
          TextField(
            controller: currentCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: 'ລະຫັດຜ່ານປັດຈຸບັນ',
              prefixIcon: const Icon(Icons.lock_outline, color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _forgotPassword(context);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('ລືມລະຫັດຜ່ານ?', style: TextStyle(
                  color: C.sky, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: newCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: 'ລະຫັດຜ່ານໃໝ່',
              prefixIcon: const Icon(Icons.lock_outline, color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: 'ຢືນຢັນລະຫັດຜ່ານໃໝ່',
              prefixIcon: const Icon(Icons.lock_outline, color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final current = currentCtrl.text.trim();
              final newPass = newCtrl.text.trim();
              final confirm = confirmCtrl.text.trim();
              if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('ກະລຸນາໃສ່ຂໍ້ມູນໃຫ້ຄົບ'),
                    backgroundColor: C.red));
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('ລະຫັດຜ່ານໃໝ່ບໍ່ຕົງກັນ'),
                    backgroundColor: C.red));
                return;
              }
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) return;
              try {
                final cred = EmailAuthProvider.credential(
                    email: user.email!, password: current);
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newPass);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('ບັນທຶກສຳເລັດ'),
                    backgroundColor: C.green,
                    behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
                    backgroundColor: C.red));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('💾 ບັນທຶກ', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 16)),
          )),
          const SizedBox(height: 28),
          Container(height: 1, color: C.border),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteAccount(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: C.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: C.red, size: 19),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('delete_account'), style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: C.red)),
                      Text(tr('delete_account_sub'), style: const TextStyle(
                          fontSize: 11, color: C.muted)),
                    ],
                  )),
                  const Icon(Icons.chevron_right_rounded,
                      color: C.muted, size: 20),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ✅ ລືມລະຫັດຜ່ານ — ສົ່ງ OTP ໄປເບີໂທຂອງບັນຊີປັດຈຸບັນ ໂດຍບໍ່ຕ້ອງກອກລະຫັດເກົ່າ
  Future<void> _forgotPassword(BuildContext context) async {
    final user  = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber;
    if (user == null || phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ບໍ່ພົບເບີໂທທີ່ຜູກກັບບັນຊີນີ້'),
          backgroundColor: C.red));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ກຳລັງສົ່ງລະຫັດ OTP...'),
        behavior: SnackBarBehavior.floating));

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await user.reauthenticateWithCredential(credential);
          if (!context.mounted) return;
          _showResetPasswordSheet(context);
        } catch (e) {
          debugPrint('[ForgotPassword] auto verify reauth FAILED: $e');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        debugPrint('[ForgotPassword] verifyPhoneNumber FAILED: '
            '${e.code} — ${e.message}');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('ສົ່ງ OTP ບໍ່ສຳເລັດ: ${e.code}'),
            backgroundColor: C.red));
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!context.mounted) return;
        _showOtpResetSheet(context,
            verificationId: verificationId, phone: phone);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // ✅ Bottom Sheet ກອກລະຫັດ OTP ເພື່ອຢືນຢັນຕົວຕົນ ແລ້ວໄປໜ້າຕັ້ງລະຫັດໃໝ່
  void _showOtpResetSheet(BuildContext context,
      {required String verificationId, required String phone}) {
    final otpCtrl = TextEditingController();
    bool loading = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: C.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('ຢືນຢັນ OTP', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
            const SizedBox(height: 6),
            Text('ລະຫັດຖືກສົ່ງໄປທີ່ $phone', style: const TextStyle(
                fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 20),
            TextField(
              controller: otpCtrl, keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, letterSpacing: 6,
                  fontWeight: FontWeight.w800, color: C.text),
              decoration: InputDecoration(
                hintText: '──────',
                filled: true, fillColor: C.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
              onPressed: loading ? null : () async {
                final code = otpCtrl.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('ກະລຸນາໃສ່ລະຫັດ OTP'),
                      backgroundColor: C.red));
                  return;
                }
                setS(() => loading = true);
                try {
                  final credential = PhoneAuthProvider.credential(
                      verificationId: verificationId, smsCode: code);
                  final user = FirebaseAuth.instance.currentUser;
                  await user?.reauthenticateWithCredential(credential);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  _showResetPasswordSheet(context);
                } on FirebaseAuthException catch (e) {
                  setS(() => loading = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('ລະຫັດ OTP ບໍ່ຖືກຕ້ອງ: ${e.code}'),
                      backgroundColor: C.red));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: C.navy, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Text('ຢືນຢັນ', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800,
                      fontSize: 16)),
            )),
          ]),
        ),
      ),
    );
  }

  // ✅ Bottom Sheet ຕັ້ງລະຫັດຜ່ານໃໝ່ ຫຼັງຈາກຢືນຢັນຕົວຕົນຜ່ານ OTP ສຳເລັດແລ້ວ
  void _showResetPasswordSheet(BuildContext context) {
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: C.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('ຕັ້ງລະຫັດຜ່ານໃໝ່', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 20),
          TextField(
            controller: newCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: 'ລະຫັດຜ່ານໃໝ່',
              prefixIcon: const Icon(Icons.lock_outline, color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: 'ຢືນຢັນລະຫັດຜ່ານໃໝ່',
              prefixIcon: const Icon(Icons.lock_outline, color: C.muted),
              filled: true, fillColor: C.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              final newPass = newCtrl.text.trim();
              final confirm = confirmCtrl.text.trim();
              if (newPass.isEmpty || confirm.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('ກະລຸນາໃສ່ຂໍ້ມູນໃຫ້ຄົບ'),
                    backgroundColor: C.red));
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('ລະຫັດຜ່ານໃໝ່ບໍ່ຕົງກັນ'),
                    backgroundColor: C.red));
                return;
              }
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              try {
                // ✅ ຜູ້ໃຊ້ໄດ້ reauthenticate ດ້ວຍ OTP ໄປແລ້ວໃນຂັ້ນຕອນກ່ອນໜ້າ —
                // ການ reauthenticate ຄືນດ້ວຍ credential ດຽວກັນຈະລົ້ມເຫລວ
                // (verification code ຖືກໃຊ້ໄປແລ້ວ), ຈຶ່ງ updatePassword ກົງໆ
                await user.updatePassword(newPass);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('ປ່ຽນລະຫັດຜ່ານສຳເລັດ'),
                    backgroundColor: C.green,
                    behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
                    backgroundColor: C.red));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('💾 ບັນທຶກ', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 16)),
          )),
        ]),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, User? user) async {
    if (user == null) return;

    // ✅ [FIX] ດຶງຂໍ້ມູນເບີໂທ/ອາຍຸ/ເພດ/ທີ່ຢູ່ທີ່ບັນທຶກໄວ້ແລ້ວມາ prefill ກ່ອນ —
    // ບໍ່ດັ່ງນັ້ນຖ້າຜູ້ໃຊ້ກົດບັນທຶກໂດຍບໍ່ໄດ້ພິມຫຍັງ ຈະໄປຂຽນທັບຄ່າເກົ່າດ້ວຍຄ່າວ່າງ
    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? <String, dynamic>{};

    final nameCtrl  = TextEditingController(text: user.displayName ?? '');
    final phoneCtrl = TextEditingController(
        text: data['phone'] as String? ?? user.phoneNumber ?? '');
    final ageCtrl   = TextEditingController(text: data['age'] as String? ?? '');
    final addrCtrl  = TextEditingController(text: data['address'] as String? ?? '');
    String gender   = data['gender'] as String? ?? 'ຊາຍ';
    bool   saving   = false;

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: C.border, borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 16),
              const Text('ແກ້ໄຂໂປຣໄຟລ໌', style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: C.text)),
              const SizedBox(height: 20),
              _ef(nameCtrl, 'ຊື່-ນາມສະກຸນ', Icons.person_outline),
              const SizedBox(height: 12),
              _ef(phoneCtrl, 'ເບີໂທ', Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _ef(ageCtrl, 'ອາຍຸ', Icons.cake_outlined,
                    keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ເພດ', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: C.text)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: C.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.border, width: 1.5),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: gender, isExpanded: true,
                          items: ['ຊາຍ', 'ຍິງ', 'ອື່ນໆ'].map((g) =>
                              DropdownMenuItem(value: g,
                                  child: Text(g))).toList(),
                          onChanged: (v) => setS(() => gender = v!),
                          style: const TextStyle(
                              fontSize: 14, color: C.text),
                        ),
                      ),
                    ),
                  ],
                )),
              ]),
              const SizedBox(height: 12),
              _ef(addrCtrl, 'ທີ່ຢູ່', Icons.location_on_outlined),
              const SizedBox(height: 12),
              Material(
                color: C.bg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showAddr(ctx),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.location_on_outlined,
                          color: C.orange, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text('ຈັດການທີ່ຢູ່ທີ່ບັນທຶກໄວ້',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700,
                              color: C.text))),
                      Icon(Icons.chevron_right_rounded,
                          color: C.muted, size: 20),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  // ✅ [FIX] ກັນກົດຊ້ຳຂະນະກຳລັງບັນທຶກ (loading-state guard)
                  onPressed: saving ? null : () async {
                    final phone = phoneCtrl.text.trim();
                    // ✅ [FIX] ກວດເບີໂທດ້ວຍ regex ເບີລາວແທ້ (isValidLaoPhone) —
                    // ບໍ່ດັ່ງນັ້ນເບີບໍ່ຖືກຕ້ອງຈະຖືກບັນທຶກລົງຖານຂໍ້ມູນໄດ້
                    if (phone.isNotEmpty && !isValidLaoPhone(phone)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('ເບີໂທບໍ່ຖືກຕ້ອງ'),
                          backgroundColor: C.red));
                      return;
                    }
                    setS(() => saving = true);
                    // ✅ [FIX] ບັນທຶກ phone/age/gender/address ລົງ Firestore ແທ້ໆ —
                    // ກ່ອນໜ້ານີ້ມີແຕ່ updateDisplayName() ເຮັດໃຫ້ຂໍ້ມູນທີ່ພິມໃສ່
                    // ຫາຍໄປທັງໆທີ່ໜ້າຈໍສະແດງ "✅ ບັນທຶກແລ້ວ!"
                    try {
                      await user.updateDisplayName(nameCtrl.text.trim());
                      await FirebaseFirestore.instance
                          .collection('users').doc(user.uid).update({
                        'displayName': nameCtrl.text.trim(),
                        'phone':       phone,
                        'age':         ageCtrl.text.trim(),
                        'gender':      gender,
                        'address':     addrCtrl.text.trim(),
                        'updatedAt':   FieldValue.serverTimestamp(),
                      });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('✅ ບັນທຶກແລ້ວ!'),
                              backgroundColor: C.green));
                      setState(() {});
                    } catch (e) {
                      // ✅ [FIX] ບໍ່ມີ error handling ມາກ່ອນ — ຖ້າອອບໄລນ໌/ຂຽນລົ້ມເຫລວ
                      // ຈະ crash ແບບງຽບ ໂດຍຜູ້ໃຊ້ບໍ່ຮູ້ວ່າມີຫຍັງຜິດພາດ
                      if (!ctx.mounted) return;
                      setS(() => saving = false);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('ບັນທຶກລົ້ມເຫລວ, ກະລຸນາລອງໃໝ່: $e'),
                          backgroundColor: C.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.navy, elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Text('💾 ບັນທຶກ', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    ).whenComplete(() {
      // ✅ [FIX H8] dispose ຢູ່ whenComplete() ແທນໃນປຸ່ມ Save — ຮັບປະກັນວ່າ
      // controllers ຈະຖືກລ້າງທຸກກໍລະນີທີ່ sheet ຖືກປິດ (swipe/back/tap-outside)
      // ບໍ່ພຽງແຕ່ຕອນກົດ Save ເທົ່ານັ້ນ (ກັນ memory leak)
      nameCtrl.dispose();
      phoneCtrl.dispose();
      ageCtrl.dispose();
      addrCtrl.dispose();
    });
  }

  Widget _ef(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: keyboard,
          style: const TextStyle(fontSize: 14, color: C.text),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: C.muted, size: 18),
            filled: true, fillColor: C.bg,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: C.border, width: 1.5)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: C.border, width: 1.5)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: C.sky, width: 2)),
          ),
        ),
      ]);

  void _showAddr(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ທີ່ຢູ່ຂອງຂ້ອຍ', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.home_outlined, color: C.navy),
            title: Text('ບ້ານ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('ບ້ານໂພນສິມ, ວຽງຈັນ'),
            trailing: Icon(Icons.edit_outlined, color: C.muted, size: 18),
          ),
          const ListTile(
            leading: Icon(Icons.work_outline, color: C.navy),
            title: Text('ບ່ອນເຮັດວຽກ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('ດາວຄຳ, ວຽງຈັນ'),
            trailing: Icon(Icons.edit_outlined, color: C.muted, size: 18),
          ),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.add_location_alt_outlined,
                color: C.navy),
            label: const Text('ເພີ່ມທີ່ຢູ່ໃໝ່', style: TextStyle(
                color: C.navy, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: C.navy),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
        ]),
      ),
    );
  }

  void _showNotif(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ການແຈ້ງເຕືອນ', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          ...[
            ['ການຈອງໃໝ່', true],
            ['ສະຖານະ', true],
            ['ໂປໂມ', false],
            ['ຂ່າວ', false],
          ].map((i) => ListTile(
              title: Text(i[0] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Switch(
                  value: i[1] as bool,
                  onChanged: (_) {},
                  activeColor: C.sky))),
        ]),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ຊ່ວຍເຫຼືອ', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.phone, color: C.navy),
            title: const Text('ໂທຫາ Support'),
            subtitle: const Text('020 XXXX XXXX'),
            onTap: () => Navigator.pop(ctx),
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined, color: C.navy),
            title: const Text('Chat Support'),
            onTap: () => Navigator.pop(ctx),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: C.navy),
            title: const Text('FAQ'),
            onTap: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
  }

  void _showTermsPrivacy(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
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
            _legalSection(Icons.description, tr('terms_conditions'),
                tr('terms_content')),
            const SizedBox(height: 14),
            _legalSection(Icons.privacy_tip_outlined, tr('privacy_policy'),
                tr('privacy_content')),
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

  Widget _stat(IconData icon, Color color, String v, String l,
      {VoidCallback? onTap}) =>
      Expanded(child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: color.withValues(alpha: 0.12),
          highlightColor: color.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(height: 6),
                Text(v, textAlign: TextAlign.center, style: const TextStyle(
                    color: C.text, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(l, textAlign: TextAlign.center, style: const TextStyle(
                    color: C.muted, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ));

  Widget _couponBadge() {
    return Expanded(child: Consumer(builder: (context, ref, _) {
      final count = ref.watch(myCouponCountProvider);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CouponListScreen())),
          borderRadius: BorderRadius.circular(14),
          splashColor: C.orange.withValues(alpha: 0.12),
          highlightColor: C.orange.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: C.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.local_offer_rounded,
                      color: C.orange, size: 16),
                ),
                const SizedBox(height: 6),
                Text('$count ${tr('coupon_unit')}', textAlign: TextAlign.center, style: const TextStyle(
                    color: C.text, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(tr('coupons_label'), textAlign: TextAlign.center, style: const TextStyle(
                    color: C.muted, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
    }));
  }

  void _showPointsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: C.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
                color: C.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.monetization_on_rounded,
                color: C.yellow, size: 28),
          ),
          const SizedBox(height: 14),
          Consumer(builder: (context, ref, _) {
            final points = ref.watch(rewardPointsProvider).value ?? 0;
            return Text('${_formatPointsCompact(points)} ແຕ້ມສະສົມ', style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: C.text));
          }),
          const SizedBox(height: 6),
          const Text('ສະສົມແຕ້ມຈາກທຸກການຈອງ ເພື່ອແລກສ່ວນຫຼຸດ ແລະ ສິດທິພິເສດ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: C.muted)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const RewardsScreen()));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: C.navy, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('ເບິ່ງປະຫວັດ ແລະ ແລກແຕ້ມ', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
          )),
        ]),
      )),
    );
  }

  String _formatPointsCompact(int points) {
    final s = points.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _vDiv() => Container(height: 36, width: 1, color: C.border);

  Widget _group(String title, List<Widget> items) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8, offset: const Offset(0, 3),
      )],
    ),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: C.muted, letterSpacing: 0.5)),
        ),
      ),
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0)
          const Divider(height: 1, indent: 16, endIndent: 16, color: C.border),
        items[i],
      ],
      const SizedBox(height: 4),
    ]),
  );

  Widget _tile(IconData icon, String title, String sub,
      {VoidCallback? onTap, String? badge, Color? iconColor}) {
    final color = iconColor ?? C.navy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: C.text)),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: C.orange,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge, style: const TextStyle(
                          fontSize: 9, color: Colors.white,
                          fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(
                      fontSize: 11, color: Colors.grey[600])),
              ],
            )),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: C.muted, size: 18),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// FAVORITE PROVIDERS (ຊ່າງຖືກໃຈ)
// ════════════════════════════════════════════════════════════

class FavoriteProvidersScreen extends StatelessWidget {
  const FavoriteProvidersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('ຊ່າງຖືກໃຈ', style: TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                color: C.red.withValues(alpha: 0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.favorite_outline,
                color: C.red, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('ຍັງບໍ່ມີຊ່າງທີ່ທ່ານກົດໃຈ', style: TextStyle(
              color: C.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('ກົດໃຈຊ່າງ ຫຼື ແມ່ບ້ານປະຈຳຫຼັງຈົບງານ\nເພື່ອບັນທຶກໄວ້ທີ່ນີ້',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 13)),
        ],
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PAYMENT HISTORY SCREEN
// ════════════════════════════════════════════════════════════

class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  String _scheduleLabel(Map<String, dynamic> b) {
    final ts = b['scheduledAt'] as Timestamp? ?? b['createdAt'] as Timestamp?;
    if (ts == null) return '';
    return DateFormat('dd/MM/yyyy · HH:mm').format(ts.toDate());
  }

  String _totalLabel(Map<String, dynamic> b) {
    final total = b['grandTotal'] ?? b['priceDisplay'] ?? b['price'];
    if (total is num) return '₭ ${NumberFormat('#,###').format(total)}';
    return '₭ ${total ?? 0}';
  }

  String _serviceNameOf(Map<String, dynamic> b) =>
      (b['serviceName'] as String?) ??
      (b['serviceType'] as String?) ??
      tr('service_generic');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('payment_history'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.getMyBookings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = (snapshot.data?.docs ?? []).where((d) {
            final b = d.data() as Map<String, dynamic>;
            return (b['status'] as String? ?? '') == 'completed';
          }).toList();

          if (docs.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🧾', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(tr('no_payment_history'), style: const TextStyle(
                    color: C.muted, fontSize: 15,
                    fontWeight: FontWeight.w600)),
              ],
            ));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final b = docs[i].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: C.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.receipt_long,
                        color: C.green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_serviceNameOf(b), style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: C.text)),
                      const SizedBox(height: 3),
                      Text(_scheduleLabel(b), style: const TextStyle(
                          fontSize: 12, color: C.muted)),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: C.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(tr('paid'), style: const TextStyle(
                          fontSize: 10, color: C.green,
                          fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 4),
                    Text(_totalLabel(b), style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: C.navy)),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SHARED
// ════════════════════════════════════════════════════════════

class _AdminRedirectScreen extends StatelessWidget {
  const _AdminRedirectScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D23),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFC9A84C).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Text('🛡️', style: TextStyle(fontSize: 44)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('LinTho Admin', style: TextStyle(
                color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('ກະລຸນາໃຊ້ Web Dashboard',
                style: TextStyle(color: Colors.white60, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFC9A84C).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFC9A84C).withValues(alpha: 0.4)),
              ),
              child: const Text('lintho-admin.vercel.app',
                  style: TextStyle(
                      color: Color(0xFFC9A84C), fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('ອອກຈາກລະບົບ',
                  style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}