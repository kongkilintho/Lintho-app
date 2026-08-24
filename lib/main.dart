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
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'Booking.dart' show serviceIconForCategory;
import 'provider_dashboard.dart';
import 'firestore_service.dart';
import 'review_screen.dart';
import 'welcome_screen.dart';
import 'pending_approval_screen.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'rewards_provider.dart';
import 'legal_content_provider.dart';
import 'rewards_screen.dart';
import 'coupon_list_screen.dart';
import 'coupon_repository.dart';
import 'language_selector.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'booking_form_screen.dart';
import 'booking_display_helpers.dart';
import 'booking_provider.dart' show customerBookingCountProvider;
import 'map_picker_screen.dart';
import 'register_otp.dart' show RegisterPage;
import 'saved_address.dart';
import 'booking_detail_screen.dart';
import 'pricing_repository.dart';
import 'payment_config_provider.dart';
import 'notification_screen.dart';
import 'fcm_service.dart';
import 'cloudinary_service.dart';
import 'quick_booking_screen.dart';
import 'referral_screen.dart';
import 'package:intl/intl.dart';
import 'lao_phone.dart';
import 'widgets/pulsing_fade.dart';
import 'widgets/error_state_view.dart';
import 'widgets/empty_state_view.dart';
import 'widgets/app_button.dart';
import 'widgets/app_section.dart';
import 'theme/app_theme.dart';
import 'app_navigation_state.dart';
import 'phone_verification.dart';
import 'support_help.dart';
import 'support_provider.dart';

const firebaseOptions = FirebaseOptions(
  apiKey:            "AIzaSyD-bIErOqCC6vHqn45oHhtL52Cw54O8SMs",
  authDomain:        "sabee-app-35d99.firebaseapp.com",
  projectId:         "sabee-app-35d99",
  storageBucket:     "sabee-app-35d99.firebasestorage.app",
  messagingSenderId: "759333413622",
  appId:             "1:759333413622:web:48e4cd177bf4f215a842d7",
);

// 🔒 [AUDIT PERF-7 / 2026-08-02 — Low, fresh re-audit] previously no
// FlutterError.onError/runZonedGuarded anywhere — a framework build error or
// an uncaught async error outside any try/catch was invisible in production
// (default behavior dumps to stderr, which nobody sees on a real device).
// This installs the standard Flutter hooks and centralizes every such error
// through one function. NOTE: this alone does not give the team remote crash
// visibility — _reportError() below only debugPrints. Wiring a real reporter
// (Crashlytics/Sentry) needs adding that package plus native Android/iOS
// build config, which wasn't done here as it can't be verified without a
// full native build; _reportError() is the single point to plug one in.
void _reportError(Object error, StackTrace stack, {String? context}) {
  debugPrint('UNCAUGHT ERROR${context != null ? ' [$context]' : ''}: $error\n$stack');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportError(details.exception, details.stack ?? StackTrace.empty,
        context: 'FlutterError');
  };
  runZonedGuarded(() async {
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
  }, (error, stack) => _reportError(error, stack, context: 'runZonedGuarded'));
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
      // ✅ [Phase 3 — brand consistency] ເຄີຍໃຊ້ gradient blue
      // (#1A7BFF→#0B4FCC) ທີ່ບໍ່ກົງກັບສີໃດໆອື່ນໃນແອັບ — ຕອນນີ້ໃຊ້ navy
      // ດຽວກັນກັບ splash/launcher config (pubspec.yaml) ແລະ AppColors.navy.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.splashGradientStart, AppColors.navy],
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
            style: TextStyle(color: C.splashSubtext, fontSize: 15, fontWeight: FontWeight.w700),
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
  // 🔒 [AUDIT PERF-7b / 2026-08-02 — Low, fresh re-audit] bumped by the
  // retry button below to force the StreamBuilder to resubscribe.
  int _retryTick = 0;

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
      key: ValueKey(_retryTick),
      stream: FirebaseFirestore.instance
          .collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: C.background,
            body: _RoleRouterSkeleton(),
          );
        }
        // 🔒 [AUDIT PERF-7b / 2026-08-02] a transient stream error (network
        // blip, momentary rules hiccup) previously fell into the
        // `!exists` branch below, misleadingly showing "incomplete
        // registration" — with a sign-out button — to a fully-registered
        // user, instead of a retryable error state.
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: C.background,
            body: ErrorStateView(
                onRetry: () => setState(() => _retryTick++)),
          );
        }
        if (snapshot.data?.exists != true) {
          return const _IncompleteRegistrationScreen();
        }
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final role = data?['role'] as String? ?? 'customer';
        // 🔒 [AUDIT ADM-2 / 2026-08-02 — High, fresh re-audit] users/{uid}.status
        // ('pending' ຕັ້ງຄັ້ງດຽວຕອນລົງທະບຽນ ໂດຍ technician_register_screen.dart —
        // ບໍ່ມີບ່ອນໃດອື່ນຂຽນທັບຄືນອີກ) ບໍ່ກົງກັບສິ່ງທີ່ lintho-admin (Approve/
        // Reject/Suspend Provider) ຂຽນຈິງ — admin ຂຽນ providers/{uid}.kycStatus
        // ເທົ່ານັ້ນ. ຜົນຄື ຊ່າງທີ່ຖືກອະນຸມັດແລ້ວຄ້າງຢູ່ PendingApprovalScreen
        // ຕະຫຼອດໄປ (ບໍ່ມີຫຍັງໄປປ່ຽນ users.status ໃຫ້). ຕອນນີ້ອ່ານ
        // providers/{uid}.kycStatus ໂດຍກົງແທນ — field ດຽວກັນກັບທີ່
        // isVerifiedProvider() ຢູ່ firestore.rules ໃຊ້ຕັດສິນວ່າຊ່າງຮັບງານໄດ້ບໍ່
        // ຢູ່ແລ້ວ (single source of truth ດຽວກັນ, ບໍ່ຕ້ອງເພິ່ງ 2 field ທີ່ອາດ
        // drift ຈາກກັນ). ເປັນ bonus fix ນຳ: reject/suspend ຕອນນີ້ບັງຄັບແທ້
        // (ກ່ອນໜ້ານີ້ status != 'pending' ໝາຍຄວາມວ່າຊ່າງທີ່ຖືກ reject/suspend
        // ຍັງເຂົ້າ ProviderDashboard ໄດ້ຢູ່ດີ ເພາະ status ບໍ່ເຄີຍຖືກຂຽນເປັນຄ່າອື່ນ
        // ນອກຈາກ 'pending' ເລີຍ).
        if (role == 'provider') {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('providers').doc(user.uid).snapshots(),
            builder: (context, provSnapshot) {
              if (provSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: C.background,
                  body: _RoleRouterSkeleton(),
                );
              }
              final kycStatus = (provSnapshot.data?.data()
                  as Map<String, dynamic>?)?['kycStatus'] as String?;
              if (kycStatus == 'verified') return const ProviderDashboard();
              return const PendingApprovalScreen();
            },
          );
        }
        return const MainShell();
      },
    );
  }
}

// ✅ [C-1 fix] ຖ້າ Firebase Auth ມີ user ແຕ່ບໍ່ມີ users/{uid} doc (ລົງທະບຽນ
// ບໍ່ສຳເລັດ — ປິດແອັບກາງຄັນຫຼັງ OTP ແຕ່ກ່ອນ _finish() ຂຽນ Firestore),
// ຫ້າມ default ໄປເປັນ role:customer/status:active ເພາະ Firestore rules
// ຫ້າມປ່ຽນ role ພາຍຫຼັງ — ຈະລັອກເບີໂທນັ້ນເປັນ customer ຖາວອນ.
class _IncompleteRegistrationScreen extends StatelessWidget {
  const _IncompleteRegistrationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_add_alt_1, size: 64, color: AppColors.navy),
              const SizedBox(height: 20),
              Text(
                tr('incomplete_registration_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                tr('incomplete_registration_msg'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                // 🔒 [AUDIT N-06 / 2026-08-08] removeToken() ຖືກເອີ້ນກ່ອນ
                // signOut() ສະເໝີ — ຕ້ອງເອີ້ນຕອນຍັງ login ຢູ່ (ອ່ານ currentUser).
                onPressed: () async {
                  await FCMService.instance.removeToken();
                  await FirebaseAuth.instance.signOut();
                },
                child: Text(tr('back_to_registration')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ [lib/widgets/ ExAMPLE] ປ່ຽນຈາກ StatefulWidget ທີ່ຂຽນ AnimationController
// ເອງ (46 ແຖວ) ໄປໃຊ້ PulsingFade ຈາກ lib/widgets/pulsing_fade.dart ແທນ —
// ຮູບແບບດຽວກັນນີ້ໄດ້ຖືກໃຊ້ແທນ skeleton loader ອື່ນໆທີ່ຊ້ຳກັນຢູ່ໃນ main.dart,
// booking_form_screen.dart, ແລະອື່ນໆແລ້ວ (ເບິ່ງ AUDIT UI-5 2026-08-02);
// _ButtonLoadingSkeleton ທີ່ເຄີຍຢູ່ໄຟລ໌ນີ້ຖືກລຶບອອກ — ບໍ່ມີບ່ອນໃດເອີ້ນໃຊ້ເລີຍ.
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
    // 🔒 [AUDIT QA-2 / CR2-AUTH] ກ່ອນໜ້ານີ້ບໍ່ໄດ້ຕັດ space/ຕົວອັກສອນອອກ —
    // ຊ່ອງນີ້ແນະນຳໃຫ້ພິມແບບມີວັກ ('020 7X XXX XXX') ແຕ່ registration ໃຊ້
    // laoPhoneDigitsOnly() ສ້າງ synthetic email, ເຮັດໃຫ້ບັນຊີທີ່ຖືກຕ້ອງ login
    // ບໍ່ໄດ້ (invalid-email) ຖ້າພິມຕາມ hint ຂອງຊ່ອງນີ້ເອງ. ຕອນນີ້ໃຊ້ function
    // ດຽວກັນນຳ ໃຫ້ຄ່າກົງກັນສະເໝີ.
    final email = input.contains('@')
        ? input.toLowerCase()
        : '${laoPhoneDigitsOnly(input)}@lintho.app';
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: pass);
      if (!mounted) return;
      // 🔒 [FIX] popUntil(isFirst) ອີງໃສ່ StreamBuilder<User?> ຢູ່ root
      // (LinThoApp) ອັບເດດ home widget ໃຫ້ທັນເວລາກ່ອນ pop animation ຈະແລ້ວ —
      // ຖ້າ authStateChanges() event ມາຊ້າກວ່າ (race), ໜ້າ WelcomeScreen ເກົ່າ
      // ຈະຄ້າງໂຜ່ຢູ່ຈົນກວ່າຈະ hot reload/rebuild. Navigate ໄປ MainShell ກົງໆ
      // ແລະລຶບ route stack ທັງໝົດ ບໍ່ຕ້ອງອີງໃສ່ timing ຂອງ stream ເລີຍ.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
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
      final googleSignIn = GoogleSignIn();
      // ✅ [FIX] signIn() ຈະ silent sign-in ດ້ວຍບັນຊີເກົ່າທີ່ cache ໄວ້ໃນເຄື່ອງ
      // ໂດຍອັດຕະໂນມັດ ຖ້າບໍ່ signOut() ກ່ອນ — ບໍ່ຂຶ້ນ Account Picker ໃຫ້ເລືອກ
      // Email ອື່ນເລີຍ. signOut() ລ້າງ session cache ນັ້ນ, ບັງຄັບໃຫ້ dialog
      // ເລືອກ Account ຂຶ້ນມາທຸກຄັ້ງທີ່ກົດປຸ່ມນີ້.
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
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
      String role = 'customer';
      // 🔒 [AUDIT ADM-2 / 2026-08-02] users/{uid}.status ບໍ່ກົງກັບສິ່ງທີ່ admin
      // approve/reject/suspend ຂຽນຈິງ (providers/{uid}.kycStatus) — ເບິ່ງ
      // ຄໍາເຫັນລະອຽດຢູ່ _RoleRouterState.build ຂ້າງເທິງ. ໃຊ້ kycStatus ດຽວກັນນຳ
      // ບ່ອນນີ້ ເພື່ອບໍ່ໃຫ້ຊ່າງທີ່ login ຜ່ານ Google ຖືກຕັດສິນຜິດ.
      String? kycStatus;
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
        } else {
          final data = snap.data();
          role = data?['role'] as String? ?? 'customer';
          if (role == 'provider') {
            final provSnap = await FirebaseFirestore.instance
                .collection('providers').doc(user.uid).get();
            kycStatus = provSnap.data()?['kycStatus'] as String?;
          }
        }
      }
      if (!mounted) return;
      // ✅ [FIX] ບັນຊີ Provider ບາງບັນຊີ login ດ້ວຍ Google — ກວດ role ໃນ
      // Firestore ທັນທີຫຼັງ sign-in ແລ້ວໂດດໄປ Provider Dashboard ໂດຍກົງ,
      // ບໍ່ຕ້ອງລໍ RoleRouter stream ອັບເດດ.
      if (role == 'provider') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => kycStatus == 'verified'
                ? const ProviderDashboard()
                : const PendingApprovalScreen(),
          ),
          (route) => false,
        );
      } else {
        // 🔒 [BUG FIX] popUntil(isFirst) ອີງໃສ່ StreamBuilder<User?> ຢູ່ root
        // (LinThoApp) rebuild home widget ຈາກ WelcomeScreen → RoleRouter ໃຫ້
        // ທັນກ່ອນ pop animation ຈະແລ້ວ. Google Sign-In ຜ່ານ account picker
        // (Custom Tab/WebView) ເຮັດໃຫ້ແອັບ pause/resume ກາງທາງ — authStateChanges()
        // event ບາງຄັ້ງມາຊ້າກວ່າ pop ນີ້ (race condition), ເຮັດໃຫ້ WelcomeScreen
        // ເກົ່າຄ້າງໂຜ່ຢູ່ຈົນກວ່າຈະ hot reload. ແກ້ໂດຍ navigate ໄປ MainShell ກົງໆ
        // ແລະລຶບ route stack ທັງໝົດ (ຄືກັນກັບ branch 'provider' ຂ້າງເທິງ),
        // ບໍ່ຕ້ອງອີງໃສ່ timing ຂອງ stream ເລີຍ.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${tr("error")}: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // 🔒 [AUDIT QA-2 / CR1-AUTH] ກ່ອນໜ້ານີ້ທັງ success ແລະ error ຄືກັນຫມົດຈະ
  // pop(true) ໃຫ້ຂຶ້ນ "ສົ່ງລິ້ງແລ້ວ" ສະເໝີ — ບໍ່ວ່າ sendPasswordResetEmail ຈະ
  // throw ຫຼືບໍ່. ນອກນັ້ນ dialog ຍັງ prefill ດ້ວຍຄ່າຈາກຊ່ອງ login (ຮັບເບີໂທ,
  // ບໍ່ແມ່ນ email) ເຊິ່ງບໍ່ມີທາງເປັນ email ທີ່ຖືກຕ້ອງໄດ້ເລີຍ. ຕອນນີ້:
  //  1) prefill ສະເພາະຖ້າຄ່າເດີມມີ '@' ຢູ່ແລ້ວ (email ຈິງ, ບໍ່ແມ່ນເບີໂທ)
  //  2) ກວດຮູບແບບ email ກ່ອນເອີ້ນ Firebase
  //  3) ສະແດງ error ຈິງໃນ dialog ຖ້າ throw, ປິດ dialog ດ້ວຍ "ສຳເລັດ" ສະເພາະ
  //     ຕອນ sendPasswordResetEmail() ຜ່ານແທ້ໆເທົ່ານັ້ນ
  Future<void> _forgotPassword() async {
    final initial = _emailCtrl.text.trim();
    final ctrl = TextEditingController(text: initial.contains('@') ? initial : '');
    String? dialogError;
    var sending = false;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              if (dialogError != null) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, color: C.red, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(dialogError!,
                      style: const TextStyle(color: C.red, fontSize: 12))),
                ]),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: C.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: sending ? null : () async {
                final email = ctrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  setDialogState(
                      () => dialogError = tr('reset_password_invalid_email'));
                  return;
                }
                setDialogState(() { sending = true; dialogError = null; });
                try {
                  await FirebaseAuth.instance
                      .sendPasswordResetEmail(email: email);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on FirebaseAuthException catch (e) {
                  // 🔒 [AUDIT SEC-5 / 2026-08-02 — Low, fresh re-audit]
                  // 'user-not-found' previously showed a distinct
                  // reset_password_not_found message, letting anyone probe
                  // whether an email is registered. Treated the same as
                  // success (silent pop) — the account holder gets nothing
                  // extra to click, and a prober can't tell the difference.
                  if (e.code == 'user-not-found') {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                    return;
                  }
                  setDialogState(() {
                    sending = false;
                    dialogError = switch (e.code) {
                      'invalid-email'  => tr('reset_password_invalid_email'),
                      _ => '${tr("error")} (${e.code})',
                    };
                  });
                } catch (e) {
                  setDialogState(() {
                    sending = false;
                    dialogError = '${tr("error")}: $e';
                  });
                }
              },
              child: sending
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('send_reset_link'),
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
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
        // ✅ [Brand color audit 2026-07-27 v2] #F8FAFC ເປັນຄ່າ drift ໃກ້ຄຽງ
        // ໜ້າຈໍອື່ນ — ລວມເປັນ Background token ດຽວກັນ
        backgroundColor: C.background,
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
                      // ✅ [FIX] ຮອງຮັບທັງເບີໂທ ແລະ Email — ບາງບັນຊີ Provider
                      // ຖືກສ້າງດ້ວຍ Gmail, keyboardType.phone ກ່ອນໜ້ານີ້ເຮັດໃຫ້
                      // ພິມ '@'/ຕົວອັກສອນບໍ່ໄດ້ ຈຶ່ງ login ບໍ່ຜ່ານ
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(
                          fontSize: 15, color: C.text),
                      decoration: _fieldDecoration(
                        hint: '020 7X XXX XXX',
                        icon: Icons.person_outline,
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
                          // ✅ [FIX ME-AUTH-5]
                          tooltip: _obscure
                              ? tr('show_password_semantic')
                              : tr('hide_password_semantic'),
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
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tr('no_account_yet'),
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 14)),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: _loading || _googleLoading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const RegisterPage())),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 2),
                              child: Text(tr('register_now'),
                                  style: const TextStyle(
                                      color: C.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                            ),
                          ),
                        ),
                      ],
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

// ════════════════════════════════════════════════════════════
// MAIN SHELL
// ════════════════════════════════════════════════════════════

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    // ✅ ດຶງ tab index ຈາກ mainShellTabIndexProvider (app_navigation_state.dart)
    // ແທນ local state — ໃຫ້ໜ້າຈໍອື່ນ (ເຊັ່ນ booking_form_screen.dart ຕອນກົດ
    // "ແກ້ໄຂ" ເບີໂທ) ສາມາດພາຜູ້ໃຊ້ໄປໜ້າ Profile ໄດ້ໂດຍ set provider ນີ້ ແລ້ວ
    // pop ກັບຄືນ MainShell
    final idx = ref.watch(mainShellTabIndexProvider);
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
      // ✅ extendBody: true — ໃຫ້ body ແຜ່ລົງໄປເຕັມຈໍ (ຢູ່ດ້ານໃຕ້ floating nav
      // bar), ບໍ່ດັ່ງນັ້ນ Scaffold ຈະຫຍໍ້ body ໄວ້ເທິງ bottomNavigationBar
      // ແລະ BackdropFilter blur ຈະບໍ່ມີ content ໃຫ້ blur ຜ່ານ
      extendBody: true,
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
          child: _FloatingNavBar(
            index: idx,
            onTap: (i) => ref.read(mainShellTabIndexProvider.notifier).state = i,
          ),
        ),
      ),
    );
  }
}

// ── FLOATING GLASSMORPHISM BOTTOM NAV (Fastwork-style) ─────────
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, 'home'),
    (Icons.receipt_long_outlined, 'booking'),
    (Icons.person_outline_rounded, 'profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 24, offset: const Offset(0, 6),
        )],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        // ✅ [Glassmorphism pass] sigma 10→12 + background ໂປ່ງແສງຫຼາຍຂຶ້ນ
        // (0.85→0.55 mint-tinted white) ໃຫ້ content ດ້ານຫຼັງເບິ່ງເຫັນມົວແທ້ໆຜ່ານ
        // BackdropFilter, ບໍ່ແມ່ນແຕ່ສີພື້ນທຶບໆຄືເກົ່າ
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            decoration: BoxDecoration(
              // ✅ ຍັງຄົງໂຕນສີ mint ຂອງແບຣນ LinTho ໄວ້ ແຕ່ໂປ່ງແສງຂຶ້ນຫຼາຍ
              // (alpha 0.55) ໃຫ້ blur ດ້ານຫຼັງເຫັນຜ່ານໄດ້ຈິງ
              color: Color.lerp(Colors.white, C.mint, 0.3)!
                  .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Row(children: List.generate(_items.length, (i) {
              final (icon, key) = _items[i];
              return Expanded(
                child: _navItem(
                  sel: index == i,
                  icon: icon,
                  label: tr(key),
                  onTap: () => onTap(i),
                ),
              );
            })),
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required bool sel,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    // ✅ [Phase 2 / Batch A] no Semantics on the nav tabs previously — icon+
    // label already reads to screen readers via child order, but marking
    // button/selected explicitly makes VoiceOver/TalkBack announce state.
    return Semantics(
      button: true,
      selected: sel,
      label: label,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              // ✅ ແທັບທີ່ເລືອກໃຊ້ soft pill ສີຂຽວແບຣນ ໃຫ້ສອດຄ່ອງກັບ Grab/
              // Foodpanda/Airbnb ທີ່ໃຊ້ສີແບຣນຫຼັກເປັນຕົວບົ່ງບອກແທັບທີ່ເລືອກຢູ່
              color: sel ? const Color(0xFFE8F5E9) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: sel ? C.primary : C.muted, size: 24),
              const SizedBox(height: 3),
              Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: sel ? C.primary : C.muted,
                ),
              ),
            ]),
          ),
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
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: C.border, borderRadius: BorderRadius.circular(AppRadius.chip)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(tr('city_picker_title'), style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: AppSpacing.sm),
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
    // ✅ [Green gradient header] ໜ້ານີ້ຖືກໃຊ້ຢູ່ເທິງພື້ນຫຼັງ gradient ຂຽວ
    // ຂອງ Home ເທົ່ານັ້ນ (ບໍ່ໄດ້ໃຊ້ຊ້ຳບ່ອນອື່ນ) — ຕອນນີ້ເປັນ pill ແກ້ວໃສ
    // ສີຂາວໂປ່ງແສງ + ໂຕໜັງສື/ໄອຄອນຂາວ ແທນ bg/text ສີເຂັ້ມເກົ່າ ໃຫ້ contrast
    // ພຽງພໍເທິງພື້ນຫຼັງຂຽວ.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        onTap: _showPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on_rounded, color: Colors.white, size: 14),
            const SizedBox(width: AppSpacing.xs),
            Text(city, style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.85), size: 16),
          ]),
        ),
      ),
    );
  }
}

// ── PROMO BANNER CAROUSEL (real-photo banners) ───────────────
// ✅ [Home banner photo redesign] ປ່ຽນຈາກ solid-gradient+emoji card ເປັນ
// ຮູບພາບຈິງ (Cloudinary/CDN, ຜ່ານ CachedNetworkImage) + gradient overlay
// ຊ້າຍ (Emerald/Navy) → ຂວາ (ຮູບຈິງຊັດ), ຂໍ້ຄວາມ+CTA ຢູ່ຊ້າຍ. ໂຄງສ້າງ
// carousel/auto-play/indicator/tap-navigation ເກົ່າຍັງຄົງໄວ້ຄືເດີມ.

class _PromoBannerData {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String imageUrl;
  final Color  overlayColor;
  final void Function(BuildContext) onTap;
  const _PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.imageUrl,
    required this.overlayColor,
    required this.onTap,
  });
}

// ✅ ຂະໜາດຮູບຄົງທີ່ (w=1200) — ພໍດີກັບຄວາມກວ້າງ banner ໃນທຸກຂະໜາດຈໍ ໂດຍບໍ່
// ຕ້ອງ decode ຮູບເຕັມຄວາມລະອຽດຈາກແຫຼ່ງຕົ້ນທາງ.
const _acCleaningBannerImg = 'https://images.unsplash.com/photo-1737012197886-7d5a52ded45b?auto=format&fit=crop&w=1200&q=75';
const _homeCleaningBannerImg = 'https://images.unsplash.com/photo-1758273705627-937374bfa978?auto=format&fit=crop&w=1200&q=75';
const _promotionBannerImg = 'https://images.unsplash.com/photo-1669387448840-610c588f003d?auto=format&fit=crop&w=1200&q=75';
const _membershipBannerImg = 'https://images.unsplash.com/photo-1758687126877-b37052a20a4d?auto=format&fit=crop&w=1200&q=75';

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();
  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _ctrl = PageController();
  Timer? _timer;
  int _page = 0;
  bool _userInteracting = false;

  // 🔒 [PHASE1] promoBannerBlue/Green/Orange (app_theme.dart) ຖືກສ້າງຂຶ້ນ
  // ສະເພາະສຳລັບ carousel ນີ້ ("Home promo banner carousel" ຕາມ doc comment
  // ຂອງມັນເອງ) ແຕ່ບໍ່ເຄີຍຖືກໃຊ້ຈັກເທື່ອ — ທຸກ banner ໃຊ້ C.primary/C.navy ຊ້ຳກັນ
  // ແທນ. ດຽວນີ້ແຕ່ລະ banner ມີສີຂອງຕົນເອງ, ຈັບຄູ່ກັບຄວາມໝາຍ (AC=blue ຄືກັນກັບ
  // categoryAcAccent, ທຳຄວາມສະອາດ=green ຄືກັນກັບ categoryCleanAccent,
  // promotion=orange ຄື convention ທົ່ວໄປສຳລັບ urgency/promo) — membership
  // ຄົງ navy ໄວ້ໂດຍເຈດຕະນາ (premium/VIP branding, ບໍ່ແມ່ນໜຶ່ງໃນ 3 token ນີ້)
  List<_PromoBannerData> get _banners => [
    _PromoBannerData(
      title:    tr('promo_ac_title'),
      subtitle: tr('promo_ac_sub'),
      ctaLabel: tr('cta_book_now'),
      imageUrl: _acCleaningBannerImg,
      overlayColor: C.promoBannerBlue,
      onTap: (context) => Navigator.push(context, MaterialPageRoute(
          builder: (_) => BookingFormScreen(
              initialOrder: BookingOrder(category: ServiceCategory.acCleaning),
              initialStep: 1))),
    ),
    _PromoBannerData(
      title:    tr('promo_clean_title'),
      subtitle: tr('promo_clean_sub'),
      ctaLabel: tr('cta_choose_service'),
      imageUrl: _homeCleaningBannerImg,
      overlayColor: C.promoBannerGreen,
      onTap: (context) => Navigator.push(context, MaterialPageRoute(
          builder: (_) => BookingFormScreen(
              initialOrder: BookingOrder(category: ServiceCategory.homeCleaning),
              initialStep: 1))),
    ),
    _PromoBannerData(
      title:    tr('promo_promotion_title'),
      subtitle: tr('promo_promotion_sub'),
      ctaLabel: tr('cta_view_promotion'),
      imageUrl: _promotionBannerImg,
      overlayColor: C.promoBannerOrange,
      onTap: (context) => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const CouponListScreen())),
    ),
    _PromoBannerData(
      title:    tr('promo_membership_title'),
      subtitle: tr('promo_membership_sub'),
      ctaLabel: tr('cta_view_rewards'),
      imageUrl: _membershipBannerImg,
      overlayColor: C.navy,
      onTap: (context) => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const ReferralScreen())),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoplay();
    // ✅ preload ຮູບ banner ຖັດໄປ (index 1) ລ່ວງໜ້າ — ບໍ່ໃຫ້ກະພິບຕອນ
    // auto-play ຂ້າມໄປໜ້າ 2 ຄັ້ງທຳອິດ
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadImage(1));
  }

  void _startAutoplay() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _userInteracting) return;
      final next = (_page + 1) % _banners.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
    });
  }

  void _preloadImage(int index) {
    if (!mounted || index >= _banners.length) return;
    precacheImage(CachedNetworkImageProvider(_banners[index].imageUrl), context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = _banners;
    return Column(children: [
      SizedBox(
        height: 172,
        child: NotificationListener<ScrollNotification>(
          // ✅ ຢຸດ auto-play ເມື່ອຜູ້ໃຊ້ກຳລັງ swipe ດ້ວຍນິ້ວມືເອງ (dragDetails
          // ບໍ່ວ່າງ = user-initiated), ແລ້ວກັບຄືນເມື່ອປ່ອຍນິ້ວ
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) {
              _userInteracting = true;
            } else if (n is ScrollEndNotification) {
              _userInteracting = false;
            }
            return false;
          },
          child: PageView.builder(
            controller: _ctrl,
            itemCount: banners.length,
            onPageChanged: (i) {
              setState(() => _page = i);
              _preloadImage((i + 1) % banners.length);
            },
            itemBuilder: (_, i) => _PromoBannerCard(banner: banners[i]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(banners.length, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _page == i ? 18 : 6, height: 6,
          decoration: BoxDecoration(
            color: _page == i ? C.primary : C.border,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
      ),
    ]);
  }
}

class _PromoBannerCard extends StatelessWidget {
  final _PromoBannerData banner;
  const _PromoBannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        onTap: () => banner.onTap(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(
              imageUrl: banner.imageUrl,
              fit: BoxFit.cover,
              // ✅ ຈຸດສຳຄັນຂອງຮູບ (ຄົນ/subject) ຢູ່ດ້ານຂວາ — ຂໍ້ຄວາມຢູ່ຊ້າຍ
              alignment: Alignment.centerRight,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) => Container(color: banner.overlayColor.withValues(alpha: 0.12)),
              errorWidget: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [banner.overlayColor, banner.overlayColor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(child: Icon(Icons.image_not_supported_outlined,
                    color: Colors.white54, size: 32)),
              ),
            ),
            // ✅ Gradient overlay: ຊ້າຍ (ສີແບຣນ ~80% opacity) → ຂວາ (ໂປ່ງໃສ, ຮູບຈິງຊັດ)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    banner.overlayColor.withValues(alpha: 0.85),
                    banner.overlayColor.withValues(alpha: 0.55),
                    banner.overlayColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(banner.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.15,
                          letterSpacing: -0.2,
                          fontWeight: FontWeight.w800)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(banner.subtitle,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          height: 1.3)),
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: () => banner.onTap(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 7),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(banner.ctaLabel, style: TextStyle(
                                  color: banner.overlayColor, fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                              const SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded,
                                  color: banner.overlayColor, size: 12),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── SEARCH BAR (Fastwork style) ──────────────────────────────
// ▸ ບໍ່ພິມຢູ່ບ່ອນນີ້ອີກຕໍ່ໄປ — ກົດແລ້ວພາໄປ SearchScreen ເຕັມໜ້າຈໍທັນທີ
// (ຄືກັບ Fastwork/Grab), ຄົ້ນຫາຈິງເກີດຢູ່ SearchScreen ບ່ອນດຽວ.
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar();

  @override
  Widget build(BuildContext context) {
    // 🔒 [PHASE1] ເນື້ອຫາທີ່ເບິ່ງເຫັນທັງໝົດແມ່ນ _RotatingSearchHint ທີ່ປ່ຽນ
    // ຂໍ້ຄວາມທຸກ 2.8s — ບໍ່ມີ static label ໃຫ້ screen reader ມາກ່ອນ, ໝາຍຄວາມວ່າ
    // ຊື່ທີ່ປະກາດອາດປ່ຽນລະຫວ່າງທີ່ຜູ້ໃຊ້ກຳລັງໂຕ້ຕອບຢູ່. ຫຸ້ມ Semantics ດ້ວຍ
    // label ຄົງທີ່ (ຄືກັນກັບ notification bell ຂ້າງເທິງທີ່ແກ້ໄປແລ້ວ)
    return Semantics(
      button: true,
      label: tr('search_placeholder'),
      child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SearchScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10, offset: const Offset(0, 3),
            )],
          ),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: C.muted, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _RotatingSearchHint(hints: [
              tr('search_hint_1'),
              tr('search_hint_2'),
              tr('search_hint_3'),
              tr('search_hint_4'),
            ])),
          ]),
        ),
      ),
      ),
    );
  }
}

// ── ROTATING SEARCH HINT (Fastwork-style vertical ticker) ────
// ▸ ໝູນວຽນ hint text ພາຍໃນກ່ອງຄົ້ນຫາ — ໂຕເກົ່າເລື່ອນຂຶ້ນ+ຈາງຫາຍ, ໂຕໃໝ່ເລື່ອນ
// ຂຶ້ນມາຈາກລຸ່ມ+ຈາງເຂົ້າ ພ້ອມກັນ (ທິດທາງດຽວກັນ — ຄືກັນກັບ ticker ຂອງ Fastwork).
// ໄອຄອນຄົ້ນຫາ/ຕອງ ຂ້າງນອກ widget ນີ້ບໍ່ຖືກກະທົບ, ມີແຕ່ text ນີ້ທີ່ animate.
class _RotatingSearchHint extends StatefulWidget {
  final List<String> hints;
  const _RotatingSearchHint({required this.hints});

  @override
  State<_RotatingSearchHint> createState() => _RotatingSearchHintState();
}

class _RotatingSearchHintState extends State<_RotatingSearchHint>
    with SingleTickerProviderStateMixin {
  static const _kHintHeight = 18.0;
  late final AnimationController _ctrl;
  Timer? _timer;
  int _index = 0;
  int _nextIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _nextIndex = widget.hints.length > 1 ? 1 : 0;
    _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) => _advance());
  }

  void _advance() {
    if (!mounted || widget.hints.length < 2) return;
    _nextIndex = (_index + 1) % widget.hints.length;
    _ctrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _index = _nextIndex;
        _ctrl.value = 0;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _line(String text) => Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: C.muted, fontSize: 13.5)));

  @override
  Widget build(BuildContext context) {
    if (widget.hints.isEmpty) return const SizedBox.shrink();
    return ClipRect(
      child: SizedBox(
        height: _kHintHeight,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            return Stack(children: [
              Transform.translate(
                offset: Offset(0, -_kHintHeight * t),
                child: Opacity(opacity: 1 - t, child: _line(widget.hints[_index])),
              ),
              if (widget.hints.length > 1)
                Transform.translate(
                  offset: Offset(0, _kHintHeight * (1 - t)),
                  child: Opacity(opacity: t, child: _line(widget.hints[_nextIndex])),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SEARCH SCREEN — dedicated full-screen search (Fastwork style)
// ════════════════════════════════════════════════════════════
// ▸ ຄົ້ນຫາຢູ່ໃນ HomeScreen._popular (ຊື່ບໍລິການ) + HomeScreen._cats (ຊື່ໝວດ) —
// ນີ້ຄື service data source ດຽວທີ່ HomeScreen ມີຢູ່ແລ້ວ, ບໍ່ສ້າງ list ໃໝ່ຊ້ຳ.
// ▸ ຢູ່ໃນ main.dart ນຳ HomeScreen (ບໍ່ແຍກ file ຄືໜ້າຈໍອື່ນໆ) ເພາະໃຊ້
// HomeScreen._cats/_popular ແລະ _PopularCard/_PriceLine ຮ່ວມກັນ — ທຸກອັນເປັນ
// library-private (underscore), import ຂ້າມ file ບໍ່ໄດ້ໂດຍບໍ່ປ່ຽນເປັນ public.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  // ▸ ບໍ່ມີ query → ສະແດງບໍລິການທັງໝົດ (ຂໍ້ມູນຈິງ, ບໍ່ແມ່ນ placeholder) —
  // ຄືກັນກັບ Fastwork ທີ່ສະແດງ suggestion ກ່ອນຜູ້ໃຊ້ພິມຫຍັງ.
  List<Map<String, Object>> get _results {
    final all = HomeScreen._popular;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((s) {
      final name = (s['name'] as String).toLowerCase();
      if (name.contains(q)) return true;
      final cat = s['category'] as ServiceCategory;
      return HomeScreen._cats.any((c) =>
          c['category'] == cat && (c['label'] as String).toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        backgroundColor: C.background,
        elevation: 0,
        titleSpacing: 0,
        title: Container(
          height: 44,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10, offset: const Offset(0, 3),
            )],
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            onChanged: _onChanged,
            style: const TextStyle(fontSize: 14, color: C.text),
            decoration: InputDecoration(
              hintText: tr('search_placeholder'),
              hintStyle: const TextStyle(color: C.muted, fontSize: 13.5),
              prefixIcon: const Icon(Icons.search_rounded, color: C.muted, size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: C.muted, size: 18),
                      tooltip: tr('clear_search_semantic'),
                      onPressed: () {
                        _ctrl.clear();
                        _debounce?.cancel();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
            ),
          ),
        ),
      ),
      body: results.isEmpty
          ? EmptyStateView(
              icon:  Icons.search_off_rounded,
              title: tr('search_no_results'),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: results.map((s) => _PopularCard(service: s)).toList(),
            ),
    );
  }
}

// ── TRUST SECTION ───────────────────────────────────────────
class _TrustSection extends StatelessWidget {
  const _TrustSection();

  static const _items = [
    (Icons.verified_user_rounded, 'trust_verified_title'),
    (Icons.star_rounded,          'trust_reviews_title'),
    (Icons.build_rounded,         'trust_guarantee_title'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: C.mint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: C.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: _items.map((item) {
          final (icon, key) = item;
          return Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: C.primary, size: 22),
              const SizedBox(height: 6),
              Text(tr(key), textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: C.text)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ✅ [FIX — Phase 3 icon system] 'icon'/'emoji' ເຄີຍເປັນ String emoji
  // (❄️🧹) — ອ່ານໄດ້ຄືຕົ້ນແບບ ບໍ່ແມ່ນສິນຄ້າສຳເລັດ, ບໍ່ມີ Semantics, ແລະ render
  // ບໍ່ຄົງທີ່ຂ້າມ platform/font. ຕອນນີ້ໃຊ້ IconData (Material icon set).
  static List<Map<String, Object>> get _cats => [
    {
      'icon': Icons.ac_unit_rounded, 'label': tr('svc_ac_clean'), 'sub': tr('cat_ac_sub'),
      'color': C.categoryAcBg, 'accent': C.categoryAcAccent,
      'category': ServiceCategory.acCleaning,
    },
    {
      'icon': Icons.cleaning_services_rounded, 'label': tr('svc_house_clean'), 'sub': tr('cat_house_sub'),
      'color': C.categoryCleanBg, 'accent': C.categoryCleanAccent,
      'category': ServiceCategory.homeCleaning,
    },
  ];

  // 🔒 [AUDIT CUST-8 / 2026-08-02 — Low, fresh re-audit] 'rating' previously
  // hardcoded 4.9/4.8 as static literals unrelated to any real aggregate —
  // these cards represent a whole service *category*, not one provider, and
  // no category-level rating aggregate is computed anywhere in this app
  // (only per-provider ratings exist). Removed rather than fabricated;
  // _PopularCard no longer renders a rating.
  static List<Map<String, Object>> get _popular => [
    {
      'icon': Icons.ac_unit_rounded, 'name': tr('svc_ac_general_full'),
      'time': '45–60 ${tr('minutes_unit')}',
      'color': C.categoryAcBg, 'accent': C.categoryAcAccent,
      'category': ServiceCategory.acCleaning,
    },
    {
      'icon': Icons.cleaning_services_rounded, 'name': tr('svc_house_general_full'),
      'time': '1–3 ${tr('hours_unit')}',
      'color': C.categoryCleanBg, 'accent': C.categoryCleanAccent,
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
    // ✅ [Canva-style green gradient header] ຫົວ Home (greeting/location/
    // ຄົ້ນຫາ) ດຽວນີ້ມີພື້ນຫຼັງ gradient ຂຽວແທນສີຂາວ — Container ນີ້ບໍ່ຢູ່ໃນ
    // Padding ຂອບ 20px ອີກຕໍ່ໄປ (ໃຫ້ gradient ເຕັມຄວາມກວ້າງໜ້າຈໍແທ້ໆ), ແລະ
    // padding ເທິງໃຊ້ MediaQuery.padding.top ແທນຄ່າ hardcode ເກົ່າ (48) ໃຫ້
    // gradient ແຕ້ມຂຶ້ນໄປຫາ status bar ຢ່າງບໍ່ມີຮອຍຕໍ່. AnnotatedRegion ຂ້າງລຸ່ມ
    // ປ່ຽນໄອຄອນ status bar ເປັນສີຂາວໃຫ້ເບິ່ງເຫັນເທິງພື້ນຫຼັງຂຽວສົດ.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    20, MediaQuery.of(context).padding.top + 16, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [C.primary, Color(0xFF00C9A7)],
                  ),
                  borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(AppRadius.sheet),
                      bottomRight: Radius.circular(AppRadius.sheet)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ [Notification feature 2026-08-03] ໂຕກະດິ່ງເຄີຍຖືກລຶບອອກ
                    // (FOLLOWUP-J2) ຍ້ອນບໍ່ມີໜ້າຈໍ notification-center ໃຫ້ໄປ —
                    // ຕອນນີ້ NotificationScreen ສ້າງແລ້ວ (3 tabs: Chat/News/
                    // Customer Service, ທຸກ tab ໃຊ້ຂໍ້ມູນຈິງ) ຈຶ່ງເພີ່ມກັບຄືນ.
                    Row(children: [
                      Expanded(child: Text(
                          '${tr('greeting_hello')}, ${user?.displayName ?? tr('default_user_name')}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                      // 🔒 [AUDIT UI-2 / 2026-08-06] Padding.all(8) ອ້ອມ icon
                      // 20dp ໃຫ້ພື້ນທີ່ກົດພຽງ 36×36dp, ຕ່ຳກວ່າມາດຕະຖານ 44dp
                      // ຂອງແອັບເອງ (ບັງຄັບຢູ່ແລ້ວຢູ່ home_tab.dart's
                      // _OnlineToggle — AUDIT UI-13). ຕອນນີ້ໃຊ້ pattern ດຽວກັນ:
                      // SizedBox+Center ຂະຫຍາຍພື້ນທີ່ກົດເປັນ 44dp ໂດຍບໍ່ປ່ຽນ
                      // ຂະໜາດພາບ, ພ້ອມ Semantics label ໃຫ້ screen reader.
                      Semantics(
                        label: tr('notifications'),
                        button: true,
                        child: SizedBox(
                          width: 44, height: 44,
                          child: Center(child: Material(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.card),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const NotificationScreen())),
                              child: const Padding(
                                padding: EdgeInsets.all(AppSpacing.sm),
                                child: Icon(Icons.notifications_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          )),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    // 🔒 [PHASE1] Colors.white70 ເທິງ gradient ຂຽວ/ຟ້າ ≈ 2:1
                    // contrast — ຕ່ຳກວ່າ WCAG AA (4.5:1). ໃຊ້ opacity ດຽວກັນ
                    // ກັບ Quick-Book banner subtitle ຂ້າງລຸ່ມ (fix UI-3) ທີ່
                    // ແກ້ບັນຫາດຽວກັນນີ້ໄປແລ້ວແຕ່ບໍ່ໄດ້ຍົກຂຶ້ນມາຫາ header ນີ້
                    Text(tr('greeting_subtitle'), style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    const _LocationSelector(),
                    const SizedBox(height: AppSpacing.md),
                    const _HomeSearchBar(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const QuickBookingFlow())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [C.quickBookGradientStart, C.quickBookGradientEnd],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            boxShadow: [BoxShadow(
                              color: C.quickBookGradientStart.withValues(alpha: 0.35),
                              blurRadius: 16, offset: const Offset(0, 6),
                            )],
                          ),
                          child: Row(children: [
                            const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 24),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr('quick_book_banner_title'),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white, fontSize: 18,
                                    height: 1.1, letterSpacing: -0.2)),
                                const SizedBox(height: 3),
                                // 🔒 [AUDIT UI-3 / 2026-08-06] white70 (70%
                                // alpha) ພຽງພໍເທິງພື້ນ navy ເກົ່າ ແຕ່ບໍ່ພຽງພໍ
                                // ເທິງ gradient ສີສົ້ມທີ່ສະຫວ່າງກວ່າ — ຍົກ
                                // opacity ຂຶ້ນເພື່ອຮັກສາ contrast.
                                Text(tr('quick_book_banner_sub'),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.92))),
                              ],
                            )),
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(Icons.chevron_right, color: Colors.white),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _PromoCarousel(),
                    const SizedBox(height: 20),
                    const _TrustSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          // ✅ bottom: 120 — extendBody:true (MainShell) ດຽວນີ້ໃຫ້ body ແຜ່ລົງ
          // ໃຕ້ floating glass nav bar, ຕ້ອງເພີ່ມ padding ລຸ່ມໃຫ້ພຽງພໍ ບໍ່ດັ່ງນັ້ນ
          // ບັດ Popular ອັນສຸດທ້າຍຈະຖືກເບິ່ງບັງ
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔒 [PHASE1] AppSection ແທນ Text header ຂຽນມືອ — spacing ຄົງທີ່
                AppSection(
                  title: tr('categories'),
                  child: Builder(builder: (context) {
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
                          borderRadius: BorderRadius.circular(AppRadius.sheet),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => BookingFormScreen(
                                    initialOrder: BookingOrder(
                                        category: cat['category'] as ServiceCategory),
                                    initialStep: 1,
                                  ))),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 22, horizontal: AppSpacing.md),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  cat['category'] == ServiceCategory.acCleaning
                                      ? C.homeCardAcTint
                                      : C.homeCardOtherTint,
                                  Colors.white,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.sheet),
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
                                  Icon(cat['icon'] as IconData, size: 44,
                                      color: cat['accent'] as Color),
                                  const SizedBox(height: AppSpacing.md),
                                  // 🔒 [PHASE1] C.sky → C.text — card title ນີ້
                                  // ເປັນ blue ຄົນດຽວ ໃນຂະນະທີ່ card title ອື່ນ
                                  // ທົ່ວໜ້ານີ້ (_PopularCard, _ActiveBookingCard)
                                  // ໃຊ້ C.text ຢູ່ແລ້ວ — ອ່ານຄືເປັນ leftover
                                  // ບໍ່ຕັ້ງໃຈ, ບໍ່ແມ່ນ accent ທີ່ຈົງໃຈ
                                  Text(cat['label'] as String, textAlign: TextAlign.center,
                                      style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800,
                                      color: C.text)),
                                  const SizedBox(height: 2),
                                  Text(cat['sub'] as String, textAlign: TextAlign.center,
                                      style: const TextStyle(
                                      fontSize: 11, color: C.muted)),
                                  const SizedBox(height: AppSpacing.xs),
                                  _PriceLine(
                                      category: cat['category'] as ServiceCategory,
                                      compact: true),
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
                ),

                const SizedBox(height: 44),
                // 🔒 [PHASE1] AppSection ແທນ Row+Text header ຂຽນມືອ — "ເບິ່ງທັງໝົດ"
                // ດຽວນີ້ຜ່ານ AppSection's actionLabel (44dp tap target ບັງຄັບ
                // ໃນຕົວ, ອັນເກົ່າ borderRadius:4 ອ້ອມ Text ຢ່າງດຽວແຄບກວ່ານັ້ນຫຼາຍ)
                AppSection(
                  title: tr('popular'),
                  actionLabel: tr('see_all'),
                  onAction: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const BookingFormScreen())),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _popular.map((s) => _PopularCard(service: s)).toList()),
                ),
              ]),
        )),
      ]),
      ),
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => BookingFormScreen(
              initialOrder: HomeScreen._quickOrderFor(
                  s['category'] as ServiceCategory),
              initialStep: 2,
            ))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
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
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Center(child: Icon(s['icon'] as IconData, size: 26,
                  color: s['accent'] as Color)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['name'] as String, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900,
                    color: C.text)),
                const SizedBox(height: AppSpacing.xs),
                Row(children: [
                  const Icon(Icons.access_time, color: C.muted, size: 13),
                  const SizedBox(width: 3),
                  Text(s['time'] as String,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w500, color: C.muted)),
                ]),
                const SizedBox(height: 6),
                _PriceLine(category: s['category'] as ServiceCategory),
              ],
            )),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right, color: C.muted, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── ລາຄາເລີ່ມຕົ້ນ (real-time, ບໍ່ hardcode) ──────────────────
// 🔒 [Customer UX pass 2026-08-03] ກ່ອນໜ້ານີ້ HomeScreen._popular ຂຽນລາຄາເປັນ
// literal string ('${starting_from} 300,000') ບໍ່ກ່ຽວຂ້ອງກັບ Firestore ເລີຍ —
// ອາດຄາດເຄື່ອນຈາກລາຄາຈິງທີ່ admin ຕັ້ງໄວ້. ຕອນນີ້ດຶງຈາກ PricingRepository ດຽວກັນ
// ກັບ booking_form_screen.dart (ServicePricing.startingPrice — ຄ່າຕ່ຳສຸດຈິງ
// ຈາກທຸກ tier), ບໍ່ສະແດງຫຍັງເລີຍຖ້າ fetch ບໍ່ໄດ້/ບໍ່ມີຂໍ້ມູນ.
// 🔒 [PHASE1] ເຄີຍເປັນ StatelessWidget ທີ່ເອີ້ນ fetchPricing() ໂດຍກົງໃນ
// build() — ເຖິງແມ່ນ PricingRepository ຈະ cache ພາຍໃນ (TTL 5 ນາທີ), ການເອີ້ນ
// async function ຄືນໃໝ່ທຸກຄັ້ງຍັງສ້າງ Future object ໃໝ່ສະເໝີ (async function
// ຄືນ Future ໃໝ່ທຸກຄັ້ງ ເຖິງແມ່ນ resolve ທັນທີ). MainShell ສ້າງ HomeScreen()
// instance ໃໝ່ທຸກຄັ້ງທີ່ rebuild (ປ່ຽນ tab/ພາສາ), ດັ່ງນັ້ນລາຄາຈະກະພິບຫາຍໄປ
// ແລ້ວກັບມາທຸກຄັ້ງທີ່ກັບຄືນມາ Home tab. ດຽວນີ້ສ້າງ Future ຄັ້ງດຽວໃນ initState()
// ແທນ.
class _PriceLine extends StatefulWidget {
  final ServiceCategory category;
  final bool compact;
  const _PriceLine({required this.category, this.compact = false});

  @override
  State<_PriceLine> createState() => _PriceLineState();
}

class _PriceLineState extends State<_PriceLine> {
  late final Future<ServicePricing?> _future =
      PricingRepository.instance.fetchPricing(widget.category.key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ServicePricing?>(
      future: _future,
      builder: (context, snap) {
        final price = snap.data?.startingPrice;
        if (price == null) return const SizedBox.shrink();
        final text =
            '${tr('starting_from')} ₭${NumberFormat('#,###').format(price)}';
        return Text(text,
            textAlign: widget.compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
                fontSize: widget.compact ? 11 : 14,
                fontWeight: FontWeight.w900,
                color: C.blue));
      },
    );
  }
}

// ── ACTIVE BOOKING HIGHLIGHT ─────────────────────────────────
// ▸ ສະແດງເໜືອ tabs ເມື່ອລູກຄ້າມີ booking ຢູ່ໃນສະຖານະ trackable (ຮັບແລ້ວ→
// ກຳລັງເຮັດ) — ອ່ານ field ດຽວກັນກັບ booking_detail_screen.dart
// (providerName/category/scheduledAt) ບໍ່ສ້າງ schema ໃໝ່. ການກະທຳ (ຍົກເລີກ/
// ຕິດຕໍ່ຊ່າງ/ຕິດຕາມ) ຄົງຢູ່ໃນ BookingDetailScreen ບ່ອນທີ່ business rule ຖືກ
// ບັງຄັບໃຊ້ຢູ່ແລ້ວ (bookingIsCancelable/bookingIsTrackable) — card ນີ້ພຽງແຕ່
// ສະຫຼຸບ + ພາໄປ.
class _ActiveBookingCard extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  const _ActiveBookingCard({required this.bookingId, required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'pending';
    final style = bookingStatusStyle(status);
    final providerName = booking['providerName'] as String?;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: style.fg.withValues(alpha: 0.3), width: 1.4),
        boxShadow: [BoxShadow(
          color: style.fg.withValues(alpha: 0.10),
          blurRadius: 14, offset: const Offset(0, 6),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(tr('active_booking_title'), style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: C.muted,
              letterSpacing: 0.3)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
                color: style.bg, borderRadius: BorderRadius.circular(AppRadius.sheet)),
            child: Text(bookingStatusLabel(status), style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: style.fg)),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: C.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Center(child: Icon(
                serviceIconForCategory(booking['category'] as String? ?? ''),
                size: 22, color: C.navy)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bookingServiceName(booking), style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: C.text)),
              const SizedBox(height: 3),
              Text(bookingScheduleLabel(booking), style: const TextStyle(
                  fontSize: 12, color: C.muted, fontWeight: FontWeight.w600)),
              if (providerName != null && providerName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.person_rounded, size: 12, color: C.muted),
                  const SizedBox(width: 3),
                  Text(providerName, style: const TextStyle(
                      fontSize: 12, color: C.muted, fontWeight: FontWeight.w600)),
                ]),
              ],
            ],
          )),
        ]),
        const SizedBox(height: AppSpacing.md),
        // ✅ [Phase 2 / Batch B] was a raw ElevatedButton (already correctly
        // green) — now the shared AppButton.primary component.
        AppButton.primary(
          label: tr('view_details_link'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: bookingId))),
        ),
      ]),
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
    // ✅ [Phase 2 / Batch B] was tr('cancel') — the imperative verb
    // ("Cancel") on a tab that lists already-cancelled bookings; EN/TH/ZH
    // all distinguish the verb from the status adjective. 'cancelled' is
    // the exact key bookingStatusLabel() already uses for this status.
    BookingTab.cancelled: tr('cancelled'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        title: Text(tr('booking'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.getMyBookings(),
        builder: (context, outerSnapshot) {
          // ✅ [Customer UX pass 2026-08-03] Active-booking highlight card ດຶງ
          // ຈາກ snapshot ດຽວກັນນີ້ (ບໍ່ເປີດ listener ໃໝ່) — ຫາ booking ທຳອິດ
          // (createdAt ລ່າສຸດສຸດ, getMyBookings() ຈັດລຽງໄວ້ແລ້ວ) ທີ່ຢູ່ໃນ
          // ສະຖານະ trackable (ຮັບແລ້ວ→ກຳລັງເຮັດ).
          Map<String, dynamic>? activeBooking;
          String? activeBookingId;
          if (outerSnapshot.hasData) {
            for (final doc in outerSnapshot.data!.docs) {
              final b = doc.data() as Map<String, dynamic>;
              final status = b['status'] as String? ?? 'pending';
              if (bookingIsTrackable(status)) {
                activeBooking = b;
                activeBookingId = doc.id;
                break;
              }
            }
          }
          return Column(children: [
            if (activeBooking != null)
              _ActiveBookingCard(bookingId: activeBookingId!, booking: activeBooking),
            _buildStatusTabs(),
            Expanded(
              child: Builder(builder: (context) {
              final snapshot = outerSnapshot;
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _BookingListSkeleton();
              }
              // ✅ [FIX] ກ່ອນໜ້ານີ້ error ບໍ່ຖືກເຊັກ — Firestore ຜິດພາດຈະຕົກລົງ
              // ເປັນ list ຫວ່າງງຽບໆ, ເຮັດໃຫ້ຄືກັບບໍ່ມີການຈອງທັງໆທີ່ແທ້ຈິງໂຫລດບໍ່ໄດ້.
              // ✅ [Phase 2 / Batch B] ad hoc error UI → shared ErrorStateView
              // (this file already uses it correctly elsewhere, e.g. Home).
              if (snapshot.hasError) {
                return ErrorStateView(onRetry: () => setState(() {}));
              }
              final allDocs = snapshot.data?.docs ?? [];
              final docs = allDocs.where((d) {
                final b = d.data() as Map<String, dynamic>;
                final status = b['status'] as String? ?? 'pending';
                return bookingTabOf(status) == _tab;
              }).toList();

              if (docs.isEmpty) {
                // ✅ [Phase 2 / Batch B] ad hoc empty UI → shared EmptyStateView,
                // CTA → AppButton (was a raw ElevatedButton, already correctly
                // green — now the shared component, not full-width by default
                // since this action sits inside a centered empty state, not a
                // bottom action bar).
                return EmptyStateView(
                  icon:    Icons.assignment_outlined,
                  accent:  C.sky,
                  title:   tr('no_booking_in_category'),
                  action:  Consumer(builder: (context, ref, _) => AppButton.primary(
                    fullWidth: false,
                    label: tr('booking_empty_cta'),
                    onPressed: () {
                      ref.read(mainShellTabIndexProvider.notifier).state = 0;
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    },
                  )),
                );
              }

              return ListView.builder(
                // ✅ bottom: 116 — ໃຫ້ພຽງພໍບໍ່ໃຫ້ບັດສຸດທ້າຍຖືກເບິ່ງບັງໂດຍ
                // floating glass nav bar (extendBody:true ຢູ່ MainShell)
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 116),
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
                      borderRadius: BorderRadius.circular(AppRadius.card),
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
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          // ✅ [FIX H11] Icon ຈາກ category ແທນ raw emoji
                          child: Center(child: Icon(
                              serviceIconForCategory(b['category'] as String? ?? ''),
                              size: 26, color: C.navy)),
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
                              borderRadius: BorderRadius.circular(AppRadius.sheet),
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
                        // ✅ [Phase 2 / Batch B] was a raw OutlinedButton.icon
                        // — now AppButton.outline. Rating is a secondary
                        // action on this card (the card itself opens detail),
                        // matching outline's semantic role.
                        AppButton.outline(
                          label: tr('rate'),
                          icon:  Icons.star_rounded,
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => ReviewScreen(
                                bookingId:    doc.id,
                                provider:     providerFromBooking(b),
                                serviceName:  b['serviceName']  as String? ??
                                    b['serviceType']  as String? ??
                                    tr('service_generic'),
                                serviceIcon:  serviceIconForCategory(
                                    b['category'] as String? ?? ''),
                              ))),
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: C.border),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(tr('view_details_link'), style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700,
                              color: C.sky)),
                          const SizedBox(width: 3),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 14, color: C.sky),
                        ],
                      ),
                    ]),
                  );

                  // ▸ ບໍ່ມີປຸ່ມຍົກເລີກຢູ່ໜ້າ list ນີ້ອີກຕໍ່ໄປ (ປ້ອງກັນການ
                  // ເຜີກົດ) — ກົດກາດເພື່ອໄປໜ້າລາຍລະອຽດ, ຍົກເລີກໄດ້ຢູ່ນັ້ນ
                  // ສະເພາະຕອນສະຖານະຍັງ 'pending' ເທົ່ານັ້ນ
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                              BookingDetailScreen(bookingId: doc.id))),
                      child: cardBody,
                    ),
                  );
                },
              );
              })),
          ]);
        },
      ),
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
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => setState(() => _tab = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? C.navy : C.bg,
                    borderRadius: BorderRadius.circular(AppRadius.card),
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
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: C.muted.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 13,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.chip))),
                const SizedBox(height: 8),
                Container(width: 80, height: 11,
                    decoration: BoxDecoration(
                        color: C.muted.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.chip))),
              ],
            )),
            Container(width: 56, height: 26,
                decoration: BoxDecoration(
                    color: C.muted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sheet))),
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
            title: Text(tr('profile_choose_from_gallery')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: C.navy),
            title: Text(tr('profile_take_new_photo')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      )),
    );
    if (source == null || !context.mounted) return;

    // 🔒 [AUDIT H-5 / 2026-07-27] ຈຳກັດ 800px — ຮູບໂປຣໄຟລ໌ສະແດງເປັນ avatar
    // ນ້ອຍໆເທົ່ານັ້ນ, ບໍ່ຈຳເປັນຕ້ອງອັບໂຫລດເຕັມຄວາມລະອຽດຈາກກ້ອງ
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 75, maxWidth: 800, maxHeight: 800);
    if (picked == null || !context.mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await CloudinaryService.instance
          .uploadCustomerPhoto(File(picked.path));
      if (url == null) throw Exception('Upload failed');
      await FirebaseAuth.instance.currentUser?.reload();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('profile_photo_updated')),
        backgroundColor: C.success,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr("photo_upload_failed")}: $e'),
        backgroundColor: C.red,
      ));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ✅ [Phone-verified booking] ເບີໂທ "ຢືນຢັນແລ້ວ" ອິງໃສ່ FirebaseAuth
  // currentUser.phoneNumber ໂດຍກົງ (ເບິ່ງ phone_verification.dart) — ບໍ່ແມ່ນ
  // field 'phone' ໃນ Firestore users/{uid} ອີກຕໍ່ໄປ (field ນັ້ນເປັນ contact
  // info ທົ່ວໄປທີ່ຜູ້ໃຊ້ແກ້ໄຂເອງໄດ້ ບໍ່ຜ່ານການຢືນຢັນ). ໜ້ານີ້ຄືຈຸດດຽວທີ່ຢືນຢັນ/
  // ປ່ຽນເບີໄດ້ — booking_form_screen.dart/quick_booking_screen.dart ອ່ານແຕ່
  // ຄ່ານີ້ ແລະ ພາຜູ້ໃຊ້ກັບມາໜ້ານີ້ຖ້າຍັງບໍ່ໄດ້ຢືນຢັນ.
  Future<void> _openPhoneVerification(BuildContext context) async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => const PhoneVerificationScreen()));
    if (result == true && mounted) setState(() {});
  }

  Widget _phoneStatusRow(BuildContext context) {
    final phone = verifiedPhoneNumber();
    if (phone != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(phone, style: const TextStyle(
            color: Colors.black54, fontSize: 13)),
        const SizedBox(width: 6),
        Text(tr('verified_badge'), style: const TextStyle(
            color: C.green, fontSize: 11, fontWeight: FontWeight.w700)),
      ]);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPhoneVerification(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 14, color: C.orange),
            const SizedBox(width: 4),
            Text(tr('phone_not_verified_badge'), style: const TextStyle(
                color: C.orange, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(tr('verify_phone_title'), style: const TextStyle(
                color: C.navy, fontSize: 12, fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: C.background,
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
          padding: EdgeInsets.fromLTRB(20, topPad + 18, 20, 20),
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
                      : Center(
                          child: user?.displayName?.isNotEmpty == true
                              ? Text(user!.displayName![0].toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 36, color: C.navy,
                                      fontWeight: FontWeight.w800))
                              : const Icon(Icons.person_outline,
                                  size: 36, color: C.navy)),
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
            Text(user?.displayName ?? tr('default_lintho_user'),
                style: const TextStyle(
                    color: Colors.black87, fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(user?.email ?? '',
                style: const TextStyle(
                    color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 4),
            _phoneStatusRow(context),
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 🔒 [FOLLOWUP-I1] ນີ້ເຄີຍເປັນ literal '5' ຄົງທີ່ — ຕອນນີ້ນັບຈິງ
                // ຈາກ bookings/{customerId==uid} ດ້ວຍ aggregate count().
                Consumer(builder: (context, ref, _) {
                  final count =
                      ref.watch(customerBookingCountProvider).value ?? 0;
                  return _stat(Icons.calendar_month_rounded, C.blue,
                      '$count', tr('bookings_count_label'),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const BookingScreen())));
                }),
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
            // 🔒 [AUDIT CUST-6 / 2026-08-02 — Low, fresh re-audit] "Favorite
            // Providers" entry point removed — FavoriteProvidersScreen always
            // rendered an empty state with no real feature behind it (no
            // heart affordance or Firestore write path existed anywhere in
            // the app). Removed rather than half-implemented; the screen
            // class stays in case the feature is built for real later.
            _group(tr('manage_account'), [
              _tile(Icons.location_on_outlined,
                  tr('my_addresses'), tr('my_addresses_sub'), iconColor: C.navy,
                  onTap: () => _showAddr(context)),
              _tile(Icons.payments_outlined,
                  tr('payment_methods_title'), tr('payment_methods_sub'), iconColor: C.green,
                  onTap: () => _showPaymentMethods(context)),
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
                  trailing: '${AppLocale.instance.lang.flag} '
                      '${AppLocale.instance.lang.displayName}',
                  onTap: () => LanguageSelector.show(context)),
              _tile(Icons.vpn_key_outlined, tr('security'),
                  tr('security_sub'), iconColor: C.green,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout_rounded, color: C.red, size: 20),
                        const SizedBox(width: 8),
                        Text(tr('logout'), style: const TextStyle(
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
        title: Text(tr('logout_confirm_title'), style: const TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: Text(tr('logout_confirm_body'),
            style: const TextStyle(color: C.muted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'),
                style: const TextStyle(color: C.muted)),
          ),
          AppButton.destructive(
            fullWidth: false,
            label: tr('confirm'),
            onPressed: () async {
              // 🔒 [AUDIT CUST-2 / 2026-08-06] ຄືກັນກັບ "Provider logout
              // stuck-in-app fix" ຢູ່ profile_tab.dart — signOut() ຄົນດຽວ
              // ແກ້ບໍ່ໄດ້ຖ້າມີ route ອື່ນຄ້າງຢູ່ເທິງ stack (ຕົວຢ່າງ: ເປີດຈາກ
              // notification ຜ່ານ FCMService.navigatorKey ໃນຈັງຫວະດຽວກັນ) —
              // popUntil ລ້າງ route ຄ້າງ (ລວມທັງ dialog ນີ້ນຳ) ແລ້ວ
              // pushAndRemoveUntil ໄປ WelcomeScreen ໂດຍກົງ ເປັນການຮັບປະກັນຊ້ຳ
              // ບໍ່ອີງໃສ່ຈັງຫວະ auth-state stream ຢ່າງດຽວ.
              Navigator.of(context, rootNavigator: true)
                  .popUntil((route) => route.isFirst);
              // 🔒 [AUDIT N-06 / 2026-08-08] removeToken() ຖືກເອີ້ນກ່ອນ
              // signOut() ສະເໝີ — ຕ້ອງເອີ້ນຕອນຍັງ login ຢູ່ (ອ່ານ currentUser).
              await FCMService.instance.removeToken();
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  // 🔒 [FOLLOWUP-I4] ປຸ່ມ "ຢືນຢັນ" ນີ້ເຄີຍພຽງແຕ່ Navigator.pop — ບໍ່ລຶບຫຍັງເລີຍ
  // (ບໍ່ FirebaseAuth deletion, ບໍ່ Firestore cleanup). ຕອນນີ້ເອີ້ນ Cloud
  // Function deleteOwnAccount (functions/index.js), ແລ້ວ sign out ໄປ
  // WelcomeScreen ຕອນສຳເລັດ.
  void _confirmDeleteAccount(BuildContext context) {
    bool deleting = false;
    String? error;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setS) => AlertDialog(
          title: Text(tr('delete_account_confirm_title'), style: const TextStyle(
              fontWeight: FontWeight.w800, color: C.text)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('delete_account_confirm_body'),
                style: const TextStyle(color: C.muted, fontSize: 14)),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: C.red, fontSize: 13)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogCtx),
              child: Text(tr('cancel'),
                  style: const TextStyle(color: C.muted)),
            ),
            AppButton.destructive(
              fullWidth: false,
              loading: deleting,
              label: tr('confirm'),
              onPressed: deleting ? null : () async {
                setS(() { deleting = true; error = null; });
                try {
                  await FirebaseFunctions.instance
                      .httpsCallable('deleteOwnAccount')
                      .call()
                      .timeout(const Duration(seconds: 20));
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                      (route) => false);
                } catch (e) {
                  setS(() {
                    deleting = false;
                    error = '${tr("delete_account_failed")}: $e';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSecurity(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    // 🔒 [AUDIT PERF-6 / 2026-08-06] ບໍ່ເຄີຍ dispose() controllers ເຫຼົ່ານີ້
    // ມາກ່ອນ — ຕ່າງຈາກ pattern ດຽວກັນນີ້ຢູ່ _forgotPassword() ຂ້າງລຸ່ມ ແລະ
    // job_workflow_Screen.dart's _showChargesSheet() ທີ່ dispose ຢູ່ແລ້ວ.
    showModalBottomSheet(
      context: context, isScrollControlled: true,
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
          Text(tr('security'), style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 20),
          TextField(
            controller: currentCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: tr('current_password'),
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
              child: Text(tr('forgot_password'), style: const TextStyle(
                  color: C.sky, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: newCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: tr('new_password'),
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
              labelText: tr('confirm_password'),
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
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(tr('fill_all')),
                    backgroundColor: C.red));
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(tr('password_mismatch')),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('password_changed_success')),
                    backgroundColor: C.success,
                    behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('${tr('error')}: $e'),
                    backgroundColor: C.red));
              }
            },
            // ✅ [Phase 2 / Batch C] was C.navy — this is the primary action
            // of this focused security sheet, so it renders LinTho green.
            style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(tr('save'), style: const TextStyle(
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
    ).whenComplete(() {
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    });
  }

  // ✅ ລືມລະຫັດຜ່ານ — ສົ່ງ OTP ໄປເບີໂທຂອງບັນຊີປັດຈຸບັນ ໂດຍບໍ່ຕ້ອງກອກລະຫັດເກົ່າ
  Future<void> _forgotPassword(BuildContext context) async {
    final user  = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber;
    if (user == null || phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('phone_not_linked')),
          backgroundColor: C.red));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('otp_sending')),
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
            content: Text('${tr('otp_send_failed')}: ${e.code}'),
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
            Text(tr('otp_verify_title'), style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
            const SizedBox(height: 6),
            Text('${tr('otp_sent_to')} $phone', style: const TextStyle(
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
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(tr('fill_all')),
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
                      content: Text('${tr('otp_invalid')}: ${e.code}'),
                      backgroundColor: C.red));
                }
              },
              // ✅ [Phase 2 / Batch C] was C.navy — primary action of this
              // OTP-confirm sheet.
              style: ElevatedButton.styleFrom(
                  backgroundColor: C.primary, elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card))),
              child: loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(tr('confirm'), style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800,
                      fontSize: 16)),
            )),
          ]),
        ),
      ),
      // 🔒 [AUDIT PERF-6 / 2026-08-06]
    ).whenComplete(() => otpCtrl.dispose());
  }

  // ✅ Bottom Sheet ຕັ້ງລະຫັດຜ່ານໃໝ່ ຫຼັງຈາກຢືນຢັນຕົວຕົນຜ່ານ OTP ສຳເລັດແລ້ວ
  void _showResetPasswordSheet(BuildContext context) {
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
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
          Text(tr('set_new_password_title'), style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: C.text)),
          const SizedBox(height: 20),
          TextField(
            controller: newCtrl, obscureText: true,
            decoration: InputDecoration(
              labelText: tr('new_password'),
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
              labelText: tr('confirm_password'),
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
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(tr('fill_all')),
                    backgroundColor: C.red));
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(tr('password_mismatch')),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('password_changed_success')),
                    backgroundColor: C.success,
                    behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('${tr('error')}: $e'),
                    backgroundColor: C.red));
              }
            },
            // ✅ [Phase 2 / Batch C] was C.navy — primary action of this
            // reset-password sheet.
            style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card)),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(tr('save'), style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800,
                fontSize: 16)),
          )),
        ]),
      ),
      // 🔒 [AUDIT PERF-6 / 2026-08-06]
    ).whenComplete(() {
      newCtrl.dispose();
      confirmCtrl.dispose();
    });
  }

  Future<void> _editProfile(BuildContext context, User? user) async {
    if (user == null) return;

    // ✅ [FIX] ດຶງຂໍ້ມູນເບີໂທ/ອາຍຸ/ເພດ/ທີ່ຢູ່ທີ່ບັນທຶກໄວ້ແລ້ວມາ prefill ກ່ອນ —
    // ບໍ່ດັ່ງນັ້ນຖ້າຜູ້ໃຊ້ກົດບັນທຶກໂດຍບໍ່ໄດ້ພິມຫຍັງ ຈະໄປຂຽນທັບຄ່າເກົ່າດ້ວຍຄ່າວ່າງ
    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    final data = userDoc.data() ?? <String, dynamic>{};

    final nameCtrl  = TextEditingController(text: user.displayName ?? '');
    final ageCtrl   = TextEditingController(text: data['age'] as String? ?? '');
    final addrCtrl  = TextEditingController(text: data['address'] as String? ?? '');
    String gender   = data['gender'] as String? ?? 'ຊາຍ';
    bool   saving   = false;

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
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
              // ✅ [Phone-verified booking] ເບີໂທບໍ່ໃຫ້ແກ້ໄຂໂດຍກົງທີ່ນີ້ອີກຕໍ່ໄປ —
              // ຕ້ອງຜ່ານການຢືນຢັນ OTP (PhoneVerificationScreen) ເທົ່ານັ້ນ, ບໍ່ດັ່ງນັ້ນ
              // booking.contactPhone ຈະບໍ່ກົງກັບເບີທີ່ຜູ້ໃຊ້ພິມໄວ້ໃນນີ້
              const Text('ເບີໂທ', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 6),
              Material(
                color: C.bg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openPhoneVerification(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    child: Row(children: [
                      const Icon(Icons.phone_outlined,
                          color: C.muted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                          verifiedPhoneNumber() ?? tr('phone_not_verified_badge'),
                          style: const TextStyle(
                              fontSize: 13.5, color: C.text))),
                      Text(tr('verify_phone_title'), style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700,
                          color: C.navy)),
                    ]),
                  ),
                ),
              ),
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
                    setS(() => saving = true);
                    // ✅ [FIX] ບັນທຶກ name/age/gender/address ລົງ Firestore ແທ້ໆ —
                    // ກ່ອນໜ້ານີ້ມີແຕ່ updateDisplayName() ເຮັດໃຫ້ຂໍ້ມູນທີ່ພິມໃສ່
                    // ຫາຍໄປທັງໆທີ່ໜ້າຈໍສະແດງ "✅ ບັນທຶກແລ້ວ!"
                    // ✅ [Phone-verified booking] 'phone' ບໍ່ຢູ່ໃນ update ນີ້ອີກຕໍ່
                    // ໄປ — ຖືກຈັດການແຍກຕ່າງຫາກຜ່ານ PhoneVerificationScreen ເທົ່ານັ້ນ
                    try {
                      await user.updateDisplayName(nameCtrl.text.trim());
                      await FirebaseFirestore.instance
                          .collection('users').doc(user.uid).update({
                        'displayName': nameCtrl.text.trim(),
                        'age':         ageCtrl.text.trim(),
                        'gender':      gender,
                        'address':     addrCtrl.text.trim(),
                        'updatedAt':   FieldValue.serverTimestamp(),
                      });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Row(children: [
                                Icon(Icons.check_circle, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('ບັນທຶກແລ້ວ!'),
                              ]),
                              backgroundColor: C.success));
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
                  // ✅ [Phase 2 / Batch C] was C.navy — primary action of
                  // this edit-profile sheet.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.primary, elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.save_outlined, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('ບັນທຶກ', style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800,
                              fontSize: 16)),
                        ]),
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

  // 🔒 [FOLLOWUP-I2] ນີ້ເຄີຍສະແດງທີ່ຢູ່ 2 ອັນຄົງທີ່ (hardcode) ບໍ່ໄດ້ອ່ານຈາກ
  // Firestore ເລີຍ, "ເພີ່ມທີ່ຢູ່ໃໝ່" ພຽງແຕ່ Navigator.pop ໂດຍບໍ່ບັນທຶກຫຍັງ.
  // savedAddressesProvider (saved_address.dart) ມີແລ້ວ, ພຽງແຕ່ບໍ່ເຄີຍຖືກໃຊ້ຢູ່
  // ໜ້ານີ້ — ຕອນນີ້ອ່ານ/ລຶບຈິງຈາກ users/{uid}/addresses (rule ອະນຸຍາດ
  // read/create/delete ໃຫ້ເຈົ້າຂອງແລ້ວ, ເບິ່ງ firestore.rules:161). ເພີ່ມທີ່ຢູ່
  // ໃໝ່ໃຊ້ MapPickerScreen + reverse-geocode ດຽວກັນກັບ
  // quick_booking_screen.dart._pickOnMap().
  // ✅ [Customer UX pass 2026-08-03] ໜ້ານີ້ບໍ່ໄດ້ຮ້ອງ `.update()` ຢູ່
  // users/{uid}/addresses/{addrId} ເລີຍ — firestore.rules:433 ຕັ້ງ
  // `allow update: if false;` ໂດຍເຈດຕະນາ (ບໍ່ໄດ້ຢູ່ໃນຂອບເຂດວຽກນີ້ໃຫ້ແກ້
  // rules). ດັ່ງນັ້ນ "ແກ້ໄຂ"/"ຕັ້ງເປັນຄ່າເລີ່ມຕົ້ນ" ທັງສອງໃຊ້ delete+create
  // (ທັງສອງອະນຸຍາດແລ້ວ) ພາຍໃນ WriteBatch ດຽວ ແທນ update ໂດຍກົງ — ຄົງຄ່າ
  // createdAt ເດີມໄວ້ບໍ່ໃຫ້ລຳດັບໃນ list ປ່ຽນໂດຍບໍ່ຕັ້ງໃຈ.
  Future<void> _rewriteAddress(String uid, String addrId,
      Map<String, dynamic> fieldChanges) async {
    final addressesRef = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('addresses');
    final oldDoc = await addressesRef.doc(addrId).get();
    final data = {...(oldDoc.data() ?? {}), ...fieldChanges};
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(addressesRef.doc(addrId));
    batch.set(addressesRef.doc(), data);
    await batch.commit();
  }

  Future<void> _setDefaultAddress(
      String uid, SavedAddress target, List<SavedAddress> all) async {
    for (final a in all) {
      if (a.id != target.id && a.isDefault) {
        await _rewriteAddress(uid, a.id, {'isDefault': false});
      }
    }
    await _rewriteAddress(uid, target.id, {'isDefault': true});
  }

  Future<String?> _pickAddressLabel(BuildContext context, {String? initial}) {
    final options = [
      tr('address_label_home'), tr('address_label_office'),
      tr('address_label_condo'), tr('address_label_other'),
    ];
    String selected = options.contains(initial) ? initial! : options.first;
    return showDialog<String>(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('address_edit_title'), style: const TextStyle(
            fontWeight: FontWeight.w800, color: C.text)),
        content: Wrap(spacing: 8, runSpacing: 8, children: options.map((o) =>
            ChoiceChip(
              label: Text(o),
              selected: selected == o,
              onSelected: (_) => setS(() => selected = o),
              selectedColor: C.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                  color: selected == o ? C.primary : C.text,
                  fontWeight: FontWeight.w700),
            )).toList()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(tr('no'), style: const TextStyle(color: C.muted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(dCtx, selected),
              style: ElevatedButton.styleFrom(backgroundColor: C.primary),
              child: Text(tr('confirm'),
                  style: const TextStyle(color: Colors.white))),
        ],
      )),
    );
  }

  void _showAddr(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('my_addresses'), style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          Consumer(builder: (context, ref, _) {
            final addresses = ref.watch(savedAddressesProvider).value ?? [];
            if (addresses.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('ຍັງບໍ່ມີທີ່ຢູ່ທີ່ບັນທຶກໄວ້',
                    style: TextStyle(color: C.muted, fontSize: 13)),
              );
            }
            // 🔒 [AUDIT M-13 / 2026-07-27] ກ່ອນໜ້ານີ້ list ນີ້ບໍ່ມີ scroll
            // fallback ເລີຍ — ຫຼາຍທີ່ຢູ່ ຫຼື ທີ່ຢູ່ຍາວ ອາດເກີນຄວາມສູງທີ່ sheet
            // ມີ ໂດຍບໍ່ມີທາງ scroll ໄປເບິ່ງລາຍການ/ປຸ່ມທີ່ຢູ່ລຸ່ມ. ຈຳກັດຄວາມສູງ
            // ແລະ ຫຸ້ມ SingleChildScrollView, ພ້ອມຈຳກັດ subtitle ໃຫ້ 2 ແຖວ.
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(children: addresses.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      a.isDefault ? Icons.star_rounded : Icons.location_on_outlined,
                      color: a.isDefault ? C.gold : C.navy),
                  title: Row(children: [
                    Flexible(child: Text(a.label.isEmpty ? 'ທີ່ຢູ່' : a.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (a.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: C.mint, borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('address_default_badge'), style: const TextStyle(
                            fontSize: 10, color: C.primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  subtitle: Text(a.address,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: C.muted, size: 20),
                    onSelected: (action) async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      if (action == 'default') {
                        await _setDefaultAddress(uid, a, addresses);
                      } else if (action == 'edit') {
                        final newLabel = await _pickAddressLabel(context, initial: a.label);
                        if (newLabel == null) return;
                        await _rewriteAddress(uid, a.id, {'label': newLabel});
                      } else if (action == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('ລຶບທີ່ຢູ່ນີ້?'),
                            content: Text(
                                'ທ່ານແນ່ໃຈບໍວ່າຕ້ອງການລຶບ "${a.label.isEmpty ? a.address : a.label}"?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  child: const Text('ຍົກເລີກ')),
                              TextButton(
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  child: const Text('ລຶບ',
                                      style: TextStyle(color: C.red))),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await FirebaseFirestore.instance
                            .collection('users').doc(uid)
                            .collection('addresses').doc(a.id).delete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(tr('address_edit_title'))),
                      if (!a.isDefault)
                        PopupMenuItem(value: 'default', child: Text(tr('address_set_default'))),
                      const PopupMenuItem(value: 'delete', child: Text('ລຶບ',
                          style: TextStyle(color: C.red))),
                    ],
                  ),
                )).toList()),
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await Navigator.push<LatLng>(ctx,
                  MaterialPageRoute(builder: (_) => const MapPickerScreen()));
              if (picked == null) return;
              var addr = 'GPS: ${picked.latitude.toStringAsFixed(4)}, '
                  '${picked.longitude.toStringAsFixed(4)}';
              try {
                final places = await placemarkFromCoordinates(
                    picked.latitude, picked.longitude);
                if (places.isNotEmpty) {
                  final p = places.first;
                  final joined = [p.street, p.subLocality, p.locality]
                      .where((s) => s != null && s.isNotEmpty)
                      .join(', ');
                  if (joined.isNotEmpty) addr = joined;
                }
              } catch (_) {}
              if (!ctx.mounted) return;
              final label = await _pickAddressLabel(ctx) ?? tr('address_label_other');
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              await FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('addresses').add({
                'label':     label,
                'address':   addr,
                'location':  GeoPoint(picked.latitude, picked.longitude),
                'createdAt': Timestamp.fromDate(DateTime.now()),
                'isDefault': false,
              });
            },
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

  // ✅ [Customer UX pass 2026-08-03] read-only — ສະແດງແຕ່ວິທີຊຳລະທີ່ແອັບຮອງຮັບ
  // ຈິງຢູ່ໜ້າຈອງ (booking_form_screen.dart: 'cash'/'bcel') ໂດຍໃຊ້ tr() key
  // ດຽວກັນ + paymentConfigProvider ດຽວກັນກັບ earnings_tab.dart's top-up sheet —
  // ບໍ່ມີ Firestore read ໃໝ່, ບໍ່ໃຫ້ເລືອກ (ການເລືອກວິທີຊຳລະຢູ່ໜ້າຈອງເທົ່ານັ້ນ).
  void _showPaymentMethods(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('payment_methods_title'), style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: C.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.payments_outlined, color: C.green),
            ),
            title: Text(tr('payment_cash_title'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('payment_cash_sub')),
          ),
          const Divider(height: 1, color: C.border),
          Consumer(builder: (context, ref, _) {
            final config = ref.watch(paymentConfigProvider).valueOrNull
                ?? PaymentConfig.fallback;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: C.sky.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: C.sky),
              ),
              title: Text(tr('payment_bcel_title'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${tr('payment_bcel_sub')}\n'
                  '${config.bankName} · ${config.accountNumber}'),
              isThreeLine: true,
            );
          }),
        ]),
      ),
    );
  }

  // 🔒 [FOLLOWUP-I3] ທຸກ Switch ນີ້ເຄີຍເປັນ onChanged:(_){} — ບໍ່ບັນທຶກຫຍັງເລີຍ,
  // ຄ່າກັບຄືນເປັນ default ທຸກຄັ້ງທີ່ເປີດ sheet ຄືນໃໝ່. ບໍ່ມີ schema
  // notifPrefs ຢູ່ໃສມາກ່ອນ (ຄົ້ນຫາທົ່ວ repo ບໍ່ພົບ) — ນີ້ແມ່ນ schema ໃໝ່,
  // ບັນທຶກໃສ່ users/{uid}.notifPrefs.{key} (ບໍ່ຈຳເປັນຕ້ອງແກ້ firestore.rules
  // ເພີ່ມ — field ໃໝ່ໃນ users/{uid} ຖືກອະນຸຍາດແກ້ໄຂເອງຢູ່ແລ້ວ ນອກຈາກ
  // rewardPoints/role/status ທີ່ຖືກປ້ອງກັນໄວ້).
  static const _notifPrefKeys = [
    ('newBooking', 'ການຈອງໃໝ່', true),
    ('status',     'ສະຖານະ',    true),
    ('promo',      'ໂປໂມ',      false),
    ('news',       'ຂ່າວ',      false),
  ];

  void _showNotif(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ການແຈ້ງເຕືອນ', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
          const SizedBox(height: 16),
          if (uid == null)
            const Text('ກະລຸນາເຂົ້າສູ່ລະບົບກ່ອນ', style: TextStyle(color: C.muted))
          else
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snap) {
                final prefs = (snap.data?.data() as Map<String, dynamic>?)
                        ?['notifPrefs'] as Map<String, dynamic>? ??
                    const {};
                return Column(children: _notifPrefKeys.map((k) {
                  final (key, label, defaultValue) = k;
                  final value = prefs[key] as bool? ?? defaultValue;
                  return ListTile(
                      title: Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      // ✅ [Brand color audit 2026-07-27] ລົບ activeColor: C.sky
                      // (ສີຟ້າ) hardcode — ໃຫ້ Switch ໃຊ້ switchTheme ກາງ
                      // (ສີຂຽວແບຣນ) ຈາກ theme/app_theme.dart ແທນ
                      trailing: Switch(
                          value: value,
                          onChanged: (v) => FirebaseFirestore.instance
                              .collection('users').doc(uid)
                              .set({'notifPrefs': {key: v}}, SetOptions(merge: true))));
                }).toList());
              },
            ),
        ]),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final info = ref.watch(supportInfoProvider)
              .valueOrNull ?? const SupportInfo();
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('help'), style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: C.text)),
              if (info.hours.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(info.hours, style: const TextStyle(
                    fontSize: 12, color: C.muted)),
              ],
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone, color: C.navy),
                title: Text(tr('call_support')),
                subtitle: Text(info.phoneDisplay),
                onTap: () {
                  Navigator.pop(ctx);
                  callSupport(context, info.phone);
                },
              ),
              if (info.whatsapp.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, color: C.navy),
                  title: Text(tr('whatsapp_support')),
                  onTap: () {
                    Navigator.pop(ctx);
                    whatsappSupport(context, info.whatsapp);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: C.navy),
                title: Text(tr('chat_support')),
                subtitle: Text(info.email),
                onTap: () {
                  Navigator.pop(ctx);
                  chatSupport(context, info.email);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: C.navy),
                title: const Text('FAQ'),
                onTap: () {
                  Navigator.pop(ctx);
                  showFaqSheet(context);
                },
              ),
            ]),
          );
        },
      ),
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
                _legalSection(Icons.description, tr('terms_conditions'), terms),
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
            return Text('${_formatPointsCompact(points)} ${tr("points_unit")}', style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: C.text));
          }),
          const SizedBox(height: 6),
          Text(tr('points_sheet_sub'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: C.muted)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const RewardsScreen()));
            },
            // ✅ [Phase 2 / Batch C] was C.navy — primary action of this
            // points sheet.
            style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card)),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(tr('points_history_and_redeem'), style: const TextStyle(
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
      {VoidCallback? onTap, String? badge, Color? iconColor, String? trailing}) {
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
                  Flexible(child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: C.text))),
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
                  // 🔒 [AUDIT UI-9 / 2026-08-02 — Low, fresh re-audit] raw
                  // Colors.grey[600] → C.muted design-system token.
                  Text(sub, style: const TextStyle(
                      fontSize: 11, color: C.muted)),
              ],
            )),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing, style: const TextStyle(
                  fontSize: 12.5, color: C.muted, fontWeight: FontWeight.w600)),
            ],
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
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        title: Text(tr('favorite_providers'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      // ✅ [Phase 2 / Batch A] style-only migration to the shared empty
      // state — this screen's nav entry point was already removed (🔒 AUDIT
      // CUST-6 / 2026-08-02, see comment above its call site) since no real
      // favorites feature exists behind it. Preserved as-is, no data/backend
      // logic added; see OUT_OF_SCOPE_FINDINGS.md.
      body: EmptyStateView(
        icon:     Icons.favorite_outline,
        accent:   C.red,
        title:    tr('no_favorite_providers'),
        subtitle: tr('no_favorite_providers_sub'),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// PAYMENT HISTORY SCREEN
// ════════════════════════════════════════════════════════════

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  // ✅ [Phase 2 / Batch A] the StreamBuilder below previously had no error
  // branch — a stream failure left the screen stuck on its last frame
  // (loading spinner or blank) with no feedback and no way to recover.
  // `_streamKey` forces a fresh subscription (a real retry, not just a
  // repaint) when the user taps "retry" on the new ErrorStateView.
  int _streamKey = 0;

  String _scheduleLabel(Map<String, dynamic> b) {
    final ts = b['scheduledAt'] as Timestamp? ?? b['createdAt'] as Timestamp?;
    if (ts == null) return '';
    return DateFormat('dd/MM/yyyy · HH:mm').format(ts.toDate());
  }

  // 🔒 [FOLLOWUP-J1] ນີ້ເຄີຍມີ logic ຂອງຕົນເອງແຍກອອກຈາກ bookingTotalLabel()
  // (booking_display_helpers.dart) — ໃຫ້ priority grandTotal (ຍອດກ່ອນຫັກ
  // coupon) ຊະນະ, ເຮັດໃຫ້ໜ້ານີ້ສະແດງລາຄາຜິດ (ບໍ່ຫັກສ່ວນຫຼຸດ) ທັງໆທີ່
  // bookingTotalLabel() ຖືກແກ້ໄຂແລ້ວທຸກບ່ອນອື່ນ (ME-15). ໃຊ້ helper ດຽວກັນແທນ.
  String _totalLabel(Map<String, dynamic> b) => bookingTotalLabel(b);

  String _serviceNameOf(Map<String, dynamic> b) =>
      (b['serviceName'] as String?) ??
      (b['serviceType'] as String?) ??
      tr('service_generic');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.background,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: C.text, size: 20),
          tooltip: tr('back_semantic'),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('payment_history'), style: const TextStyle(
            color: C.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        key: ValueKey(_streamKey),
        stream: FirestoreService.getMyBookings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // ✅ [Phase 2 / Batch A] previously unhandled — see class doc comment.
          if (snapshot.hasError) {
            return ErrorStateView(
              onRetry: () => setState(() => _streamKey++),
            );
          }
          final docs = (snapshot.data?.docs ?? []).where((d) {
            final b = d.data() as Map<String, dynamic>;
            return (b['status'] as String? ?? '') == 'completed';
          }).toList();

          if (docs.isEmpty) {
            return EmptyStateView(
              icon:  Icons.receipt_long_outlined,
              title: tr('no_payment_history'),
            );
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: C.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.card)),
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
                          borderRadius: BorderRadius.circular(AppRadius.chip)),
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
      backgroundColor: C.vipDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: C.vipGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Icon(Icons.shield_outlined, size: 44, color: C.vipGold),
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
                color: C.vipGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: C.vipGold.withValues(alpha: 0.4)),
              ),
              child: const Text('lintho-admin.vercel.app',
                  style: TextStyle(
                      color: C.vipGold, fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 32),
            TextButton(
              // 🔒 [AUDIT N-06 / 2026-08-08] removeToken() ຖືກເອີ້ນກ່ອນ
              // signOut() ສະເໝີ — ຕ້ອງເອີ້ນຕອນຍັງ login ຢູ່ (ອ່ານ currentUser).
              onPressed: () async {
                await FCMService.instance.removeToken();
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('ອອກຈາກລະບົບ',
                  style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}
