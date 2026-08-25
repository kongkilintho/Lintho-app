// ============================================================
// fcm_service.dart — LinTho App
// NO flutter_local_notifications — ໃຊ້ FCM ໂດຍກົງ
// ============================================================

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'main.dart' show firebaseOptions, resolvePostAuthDestination;
import 'app_colors.dart';
import 'app_locale.dart';
import 'Booking.dart';
import 'job_workflow_Screen.dart';
import 'booking_detail_screen.dart';
import 'chat_screen.dart';
import 'provider_dashboard.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  if (Firebase.apps.isEmpty) {
    if (kIsWeb) {
      await Firebase.initializeApp(options: firebaseOptions);
    } else {
      await Firebase.initializeApp();
    }
  }
  debugPrint('📬 Background: ${msg.notification?.title}');
}

class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  final _messaging = FirebaseMessaging.instance;
  final _db        = FirebaseFirestore.instance;

  static GlobalKey<NavigatorState>? navigatorKey;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    // 🔒 [AUDIT N-13 / 2026-08-08 — Low, notification E2E audit] alert:true
    // ນີ້ມີຜົນສະເພາະ iOS/macOS ເທົ່ານັ້ນ (Android ບໍ່ໃຊ້ API ນີ້ເລີຍ, ຈຶ່ງປ່ຽນ
    // ໂດຍບໍ່ຕ້ອງ platform-check) — ກ່ອນໜ້ານີ້ iOS ຈະສະແດງທັງ native banner
    // (ຈາກ flag ນີ້) ແລະ custom SnackBar (_onForeground → _showInAppBanner)
    // ພ້ອມກັນ ສຳລັບ push ດຽວກັນ. alert:false ປິດ native banner, ເຫຼືອແຕ່
    // custom banner ດຽວ — ຄືກັນກັບພຶດຕິກຳຂອງ Android ຢູ່ແລ້ວ.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false, badge: true, sound: true,
    );
    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);
    _messaging.onTokenRefresh.listen(saveToken);

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onTap);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onTap(initial);
  }

  // 🔒 [AUDIT N-02 / 2026-08-08 — High, notification E2E audit] _watchFCMQueue()
  // ເຄີຍຢູ່ບ່ອນນີ້ — listener ໃສ່ collection('fcm_queue') ຂອງຕົນເອງ, ຫວັງໃຫ້ຂຶ້ນ
  // in-app banner ທັນທີທີ່ doc ຖືກ queue. firestore.rules ຂອງ fcm_queue ແມ່ນ
  // `allow read: if false` ສະເໝີ (ຖືກຕັ້ງໃຈ — doc ອາດມີ title/body ຂອງ user ຄົນອື່ນ
  // ຢູ່ຊ່ວງ sent==false) ຈຶ່ງ permission-denied ທຸກຄັ້ງ, ຖືກ catch ໄວ້ໃນ onError
  // ແລ້ວ debugPrint ຖິ້ມ — ບໍ່ເຄີຍເຮັດວຽກຈັກເທື່ອ, ບໍ່ມີຜົນຫຍັງຕໍ່ user ຈິງ. In-app
  // banner ຕົວຈິງມາຈາກ FirebaseMessaging.onMessage (_onForeground ຂ້າງລຸ່ມ) ເຊິ່ງ
  // ບໍ່ອີງໃສ່ການອ່ານ Firestore ເລີຍ ແລະ ເຮັດວຽກປົກກະຕິຢູ່ແລ້ວ — ລຶບ dead code ນີ້ອອກ.

  void _showInAppBanner({
    required String title,
    required String body,
    required String type,
    required String bookingId,
  }) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    final ctx = nav.context;
    final color = switch (type) {
      'new_booking'        => C.notifBooking,
      'payment'            => C.notifPayment,
      'additional_charges' => C.notifCharge,
      'chat'               => C.notifChat,
      _                    => C.notifDefault,
    };

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white, fontSize: 13)),
            Text(body, style: TextStyle(
              // ✅ withOpacity → withValues
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12)),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        action: bookingId.isNotEmpty
            ? SnackBarAction(
          label: 'ເບິ່ງ',
          textColor: Colors.white,
          onPressed: () => _navigate(
              {'type': type, 'bookingId': bookingId}),
        )
            : null,
      ),
    );
  }

  Future<void> saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 🔒 [AUDIT N-11 / 2026-08-08 — Medium, notification E2E audit] ກ່ອນໜ້ານີ້
    // token ຖືກ mirror ໃສ່ providers/{uid} ນຳ (ນອກເໜືອຈາກ users/{uid}) —
    // providers/{uid} ອ່ານໄດ້ໂດຍ user login ຄົນໃດກໍໄດ້ (firestore.rules, ຈຳເປັນ
    // ສຳລັບ job board) ຈຶ່ງເຮັດໃຫ້ FCM token ຂອງທຸກຊ່າງຮົ່ວອອກໄປໃຫ້ທຸກຄົນອ່ານໄດ້.
    // users/{uid} ອ່ານໄດ້ສະເພາະເຈົ້າຂອງ/admin ຢູ່ແລ້ວ (ບໍ່ຮົ່ວ) ແລະ
    // processFCMQueue (functions/index.js) ຕອນນີ້ອ່ານ token ຈາກ users/{uid}
    // ສະເໝີບໍ່ວ່າ role ໃດ — mirror ໃສ່ providers/{uid} ຈຶ່ງບໍ່ຈຳເປັນອີກຕໍ່ໄປ, ລຶບອອກ.
    await _db.collection('users').doc(uid).set({
      'fcmTokens':        FieldValue.arrayUnion([token]),
      'lastTokenUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeToken() async {
    final uid   = FirebaseAuth.instance.currentUser?.uid;
    final token = await _messaging.getToken();
    if (uid == null || token == null) return;
    await _db.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
    // 🔒 [AUDIT N-06 / N-11 / 2026-08-08] ບໍ່ຖືກເອີ້ນຈັກເທື່ອມາກ່ອນ (dead code) —
    // ຕອນນີ້ຖືກເອີ້ນຈາກທຸກ logout call site (main.dart/profile_tab.dart/
    // pending_approval_screen.dart). ຄ້າຍໆນຳ providers/{uid}.fcmTokens ນຳ
    // best-effort — token ເກົ່າອາດຍັງຄ້າງຢູ່ນັ້ນຈາກກ່ອນ N-11 fix (saveToken()
    // ບໍ່ຂຽນໃສ່ບ່ອນນັ້ນອີກຕໍ່ໄປ) — ລ້າງອອກເທື່ອລະໜ້ອຍຕອນຜູ້ໃຊ້ logout. ບໍ່ແມ່ນ
    // provider ຫຼື doc ບໍ່ມີ field ນີ້ → update() throw, ຖືກ catch ຖິ້ມໄດ້ຢ່າງປອດໄພ.
    try {
      await _db.collection('providers').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {}
    await _messaging.deleteToken();
  }

  void _onForeground(RemoteMessage msg) {
    final data      = msg.data;
    final type      = data['type']      as String? ?? '';
    final bookingId = data['bookingId'] as String? ?? '';
    final title     = msg.notification?.title ?? 'LinTho';
    final body      = msg.notification?.body  ?? '';
    _showInAppBanner(
        title: title, body: body,
        type: type, bookingId: bookingId);
  }

  void _onTap(RemoteMessage msg) => _navigate(msg.data);

  // 🔒 [AUDIT CRIT-4] ກ່ອນໜ້ານີ້ໃຊ້ named-route navigation (job-workflow,
  // chat, earnings) ແຕ່ MaterialApp (main.dart) ບໍ່ມີ `routes:` ຫຼື
  // `onGenerateRoute` ຖືກປະກາດໄວ້ເລີຍ — ນຳທາງດ້ວຍຊື່ route ທີ່ບໍ່ຮູ້ຈັກຈະ throw
  // ທັນທີ. ໝາຍຄວາມວ່າການກົດແຈ້ງເຕືອນ (ຫຼືປຸ່ມ "ເບິ່ງ" ໃນ in-app banner) ຈະ
  // crash ແທນທີ່ຈະໄປໜ້າທີ່ຖືກຕ້ອງ, ທຸກຄັ້ງ, ໂດຍບໍ່ມີຂໍ້ຍົກເວັ້ນ.
  // ✅ ຕອນນີ້ນຳທາງໂດຍກົງດ້ວຍ Navigator.push(MaterialPageRoute(...)), ດຶງ
  // booking doc ທີ່ຈຳເປັນມາກ່ອນ (ມີ timeout + error handling), ແລະ ເລືອກໜ້າຈໍ
  // ໃຫ້ຖືກຕ້ອງຕາມ role ຂອງຜູ້ຮັບ notification ຈິງ — 'new_booking' ສົ່ງຫາ
  // provider ເທົ່ານັ້ນ (ໄປ JobWorkflowScreen); 'booking_update' ແລະ
  // 'additional_charges' ສົ່ງຫາ customer ເທົ່ານັ້ນ (ໄປ BookingDetailScreen) —
  // ກ່ອນໜ້ານີ້ທັງສາມ type ນີ້ຖືກສົ່ງໄປໜ້າດຽວກັນ (job-workflow, ໜ້າສະເພາະ
  // provider) ເຊິ່ງຈະ permission-denied ຖ້າ customer ກົດ action ໃດໆໃນນັ້ນ.
  Future<void> _navigate(Map<String, dynamic> data) async {
    final type      = data['type']      as String? ?? '';
    final bookingId = data['bookingId'] as String? ?? '';
    final nav       = navigatorKey?.currentState;
    if (nav == null) return;
    final ctx = nav.context;

    void showNavError() {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(tr('error_try_again')),
          backgroundColor: C.red));
    }

    try {
      if (type == 'new_booking' && bookingId.isNotEmpty) {
        // 🔒 [FIX NAV-1b / Batch G] JobWorkflowScreen used to be pushed
        // unconditionally for whoever is currently signed in — no role/
        // kycStatus check. Reuses resolvePostAuthDestination(), the same
        // single source of truth RoleRouter/_login()/_loginWithGoogle()
        // already use, instead of duplicating a role/kyc lookup here. If
        // the signed-in user isn't actually a verified provider, route
        // them to wherever they actually belong instead.
        final dest = await resolvePostAuthDestination();
        if (!ctx.mounted) return;
        if (dest is! ProviderDashboard) {
          nav.push(MaterialPageRoute(builder: (_) => dest));
          return;
        }
        final doc = await _db.collection('bookings').doc(bookingId).get()
            .timeout(const Duration(seconds: 10));
        if (!doc.exists) return showNavError();
        final booking = Booking.fromFirestore(doc);
        if (!ctx.mounted) return;
        nav.push(MaterialPageRoute(
            builder: (_) => JobWorkflowScreen(initialBooking: booking)));
      } else if ((type == 'booking_update' || type == 'additional_charges') &&
          bookingId.isNotEmpty) {
        nav.push(MaterialPageRoute(
            builder: (_) => BookingDetailScreen(bookingId: bookingId)));
      } else if (type == 'chat' && bookingId.isNotEmpty) {
        final doc = await _db.collection('bookings').doc(bookingId).get()
            .timeout(const Duration(seconds: 10));
        if (!doc.exists) return showNavError();
        final booking = Booking.fromFirestore(doc);
        final me       = FirebaseAuth.instance.currentUser?.uid;
        final isMeProvider = me != null && me == booking.providerId;

        // ✅ Booking.dart ບໍ່ມີ field providerName (ບໍ່ຖືກຂຽນໂດຍ
        // acceptBooking() ຕົວຈິງ) — ຖ້າຄົນເປີດແຊັດເປັນລູກຄ້າ, ດຶງຊື່ຊ່າງແທ້ຈາກ
        // providers/{providerId}.displayName ແທນທີ່ຈະປ່ອຍ otherName ວ່າງເປົ່າ
        var otherName = booking.customerName;
        if (!isMeProvider && booking.providerId.isNotEmpty) {
          try {
            final providerDoc = await _db.collection('providers')
                .doc(booking.providerId).get()
                .timeout(const Duration(seconds: 10));
            otherName = providerDoc.data()?['displayName'] as String? ?? '';
          } catch (_) {
            otherName = '';
          }
        }

        if (!ctx.mounted) return;
        nav.push(MaterialPageRoute(builder: (_) => ChatScreen(
          chatId:         '${bookingId}_chat',
          otherName:      otherName,
          bookingService: booking.serviceType,
          receiverId:     isMeProvider ? booking.customerId : booking.providerId,
          receiverName:   otherName,
        )));
      } else if (type == 'payment') {
        // ✅ ຄ່າແຮງ/wallet notification ສົ່ງຫາ provider ເທົ່ານັ້ນ — ໄປ
        // ProviderDashboard tab ລາຍຮັບ (index 2, ເບິ່ງ provider_dashboard.dart)
        // 🔒 [FIX NAV-1 / Batch G] same fix as new_booking above — verify via
        // resolvePostAuthDestination() before assuming ProviderDashboard is
        // the right screen for whoever is currently signed in, instead of
        // hardcoding it unconditionally.
        final dest = await resolvePostAuthDestination();
        if (!ctx.mounted) return;
        if (dest is ProviderDashboard) {
          ProviderScope.containerOf(ctx, listen: false)
              .read(navIndexProvider.notifier).state = 2;
        }
        nav.push(MaterialPageRoute(builder: (_) => dest));
      } else {
        // 🔒 [AUDIT N-07 / 2026-08-08 — Medium, notification E2E audit] type
        // ທີ່ບໍ່ຮູ້ຈັກ (ໂດຍສະເພາະ 'admin_broadcast' — Admin Panel ບໍ່ເຄີຍສົ່ງ
        // ປາຍທາງມານຳ) ບໍ່ເຄີຍມີ branch ຈັດການ — ກົດ notification ແລ້ວບໍ່ເຮັດ
        // ຫຍັງເລີຍ. ຕອນນີ້ກັບໄປໜ້າຫຼັກ (pattern ດຽວກັນກັບ popUntil ຕອນ logout
        // ຢູ່ main.dart/profile_tab.dart) ແທນທີ່ຈະປ່ອຍໃຫ້ການກົດບໍ່ມີຜົນຫຍັງເລີຍ.
        nav.popUntil((route) => route.isFirst);
      }
    } on TimeoutException {
      showNavError();
    } catch (e) {
      debugPrint('FCMService._navigate error: $e');
      showNavError();
    }
  }
}

// ════════════════════════════════════════════════════════════
// NOTIFICATION SENDER
// ════════════════════════════════════════════════════════════

class NotificationSender {
  static final _db = FirebaseFirestore.instance;

  static Future<void> _send({
    required String targetUserId,
    required String targetRole,
    required String type,
    required String title,
    required String body,
    String? bookingId,
  }) async {
    try {
      await _db.collection('fcm_queue').add({
        'targetUserId': targetUserId,
        'targetRole':   targetRole,
        'type':         type,
        'title':        title,
        'body':         body,
        'bookingId':    bookingId ?? '',
        'data':         {'type': type, 'bookingId': bookingId ?? ''},
        'createdAt':    FieldValue.serverTimestamp(),
        'sent':         false,
      });
    } catch (e) {
      debugPrint('NotificationSender error: $e');
    }
  }

  static Future<void> newBooking({
    required String providerId, required String bookingId,
    required String serviceName, required String customerName,
  }) => _send(
    targetUserId: providerId, targetRole: 'provider',
    type: 'new_booking', bookingId: bookingId,
    title: '🔔 ງານໃໝ່ມາ!',
    body:  '$customerName ຕ້ອງການ $serviceName · ຕອບໃນ 30ວ',
  );

  static Future<void> paymentReceived({
    required String providerId, required String bookingId,
    required double amount, required String serviceName,
  }) => _send(
    targetUserId: providerId, targetRole: 'provider',
    type: 'payment', bookingId: bookingId,
    title: '💰 ລາຍຮັບເຂົ້າ Wallet!',
    body:  '₭${amount.toStringAsFixed(0)} ຈາກ $serviceName',
  );

  static Future<void> bookingAccepted({
    required String customerId, required String bookingId,
    required String providerName,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'booking_update', bookingId: bookingId,
    title: '✅ ຊ່າງຮັບງານແລ້ວ!',
    body:  '$providerName ກຳລັງກຽມໄປ',
  );

  static Future<void> providerOnTheWay({
    required String customerId, required String bookingId,
    required String providerName,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'booking_update', bookingId: bookingId,
    title: '🚗 ຊ່າງກຳລັງໄປ!',
    body:  '$providerName ກຳລັງເດີນທາງ',
  );

  static Future<void> providerArrived({
    required String customerId, required String bookingId,
    required String providerName,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'booking_update', bookingId: bookingId,
    title: '📍 ຊ່າງຮອດແລ້ວ!',
    body:  '$providerName ຢູ່ໜ້ານາງ',
  );

  static Future<void> jobCompleted({
    required String customerId, required String bookingId,
    required String serviceName,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'booking_update', bookingId: bookingId,
    title: '🎉 ວຽກສຳເລັດ!',
    body:  '$serviceName ສຳເລັດ · ກະລຸນາໃຫ້ຄະແນນ',
  );

  static Future<void> additionalCharges({
    required String customerId, required String bookingId,
    required double amount, required String note,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'additional_charges', bookingId: bookingId,
    title: '⚠️ ຄ່າໃຊ້ຈ່າຍເພີ່ມ',
    body:  '₭${amount.toStringAsFixed(0)} · $note · ກະລຸນາຢືນຢັນ',
  );

  static Future<void> bookingRejected({
    required String customerId, required String bookingId,
    required String serviceName,
  }) => _send(
    targetUserId: customerId, targetRole: 'customer',
    type: 'booking_update', bookingId: bookingId,
    title: '❌ ຖືກປະຕິເສດ',
    body:  '$serviceName ຖືກປະຕິເສດ',
  );

  static Future<void> reviewReceived({
    required String providerId, required String bookingId,
    required int rating,
  }) => _send(
    targetUserId: providerId, targetRole: 'provider',
    type: 'review', bookingId: bookingId,
    title: '⭐ ມີຣີວິວໃໝ່!',
    body:  'ລູກຄ້າໃຫ້ $rating ດາວ · ກົດເພື່ອເບິ່ງ',
  );

  // 🔒 [AUDIT CUST-5 / 2026-08-02 — Medium, fresh re-audit] ຟັງຊັນນີ້ຖືກຂຽນໄວ້
  // ແຕ່ບໍ່ເຄີຍຖືກເອີ້ນຈາກ chat_screen.dart._sendMessage() ຈັກເທື່ອ — ຂໍ້ຄວາມແຊັດ
  // ບໍ່ເຄີຍສົ່ງ push ຫາຝ່າຍທີ່ບໍ່ໄດ້ເປີດແອັບຢູ່ເລີຍ. `targetRole` ຖືກ hardcode
  // ເປັນ 'customer' ຕະຫຼອດມາ — ຜິດເມື່ອຝ່າຍທີ່ຮັບເປັນຊ່າງ (chat ແມ່ນສອງທິດທາງ) —
  // ຕອນນີ້ຮັບ targetRole ເປັນ parameter ແທນ.
  static Future<void> chatMessage({
    required String targetUserId, required String targetRole,
    required String bookingId,
    required String senderName, required String message,
  }) => _send(
    targetUserId: targetUserId, targetRole: targetRole,
    type: 'chat', bookingId: bookingId,
    title: '💬 $senderName', body: message,
  );
}