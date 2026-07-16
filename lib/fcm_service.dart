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
import 'dart:async';
import 'main.dart' show firebaseOptions;

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
  StreamSubscription? _queueSub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );
    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);
    _messaging.onTokenRefresh.listen(saveToken);

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onTap);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onTap(initial);

    _watchFCMQueue();
  }

  void _watchFCMQueue() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _queueSub?.cancel();
    _queueSub = _db
        .collection('fcm_queue')
        .where('targetUserId', isEqualTo: uid)
        .where('sent', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final data      = doc.data();
        final title     = data['title']     as String? ?? 'LinTho';
        final body      = data['body']      as String? ?? '';
        final type      = data['type']      as String? ?? '';
        final bookingId = data['bookingId'] as String? ?? '';

        _showInAppBanner(
            title: title, body: body,
            type: type, bookingId: bookingId);
        // ✅ [FIX] ບໍ່ມີ try/catch ມາກ່ອນ — ຖ້າ update() ລົ້ມເຫລວ (offline/
        // permission) doc ນີ້ຈະຄ້າງ sent=false ຕະຫຼອດໄປ ແລະ banner ອາດຂຶ້ນຊ້ຳ
        // ທຸກຄັ້ງທີ່ snapshot ອັບເດດໃໝ່
        try {
          await doc.reference.update({'sent': true});
        } catch (e) {
          debugPrint('FCMService: failed to mark fcm_queue doc as sent: $e');
        }
      }
    }, onError: (Object e) {
      // ✅ [FIX] ບໍ່ມີ onError ມາກ່ອນ — stream listener error (ເຊັ່ນ Firestore
      // permission-denied) ຈະກາຍເປັນ unhandled async error ແທນທີ່ຈະຖືກ log
      debugPrint('FCMService: fcm_queue listener error: $e');
    });
  }

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
      'new_booking'        => const Color(0xFF1565C0),
      'payment'            => const Color(0xFF4A7C59),
      'additional_charges' => const Color(0xFFF97316),
      'chat'               => const Color(0xFF7C3AED),
      _                    => const Color(0xFF0D1B4B),
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

    await _db.collection('users').doc(uid).set({
      'fcmTokens':        FieldValue.arrayUnion([token]),
      'lastTokenUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final doc  = await _db.collection('users').doc(uid).get();
    final role = doc.data()?['role'] as String? ?? 'customer';
    if (role == 'provider') {
      await _db.collection('providers').doc(uid).set({
        'fcmTokens':        FieldValue.arrayUnion([token]),
        'lastTokenUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> removeToken() async {
    final uid   = FirebaseAuth.instance.currentUser?.uid;
    final token = await _messaging.getToken();
    if (uid == null || token == null) return;
    await _db.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
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

  void _navigate(Map<String, dynamic> data) {
    final type      = data['type']      as String? ?? '';
    final bookingId = data['bookingId'] as String? ?? '';
    final nav       = navigatorKey?.currentState;
    if (nav == null) return;

    if (['new_booking', 'booking_update', 'additional_charges']
        .contains(type) && bookingId.isNotEmpty) {
      nav.pushNamed('/job-workflow', arguments: bookingId);
    } else if (type == 'chat' && bookingId.isNotEmpty) {
      nav.pushNamed('/chat', arguments: bookingId);
    } else if (type == 'payment') {
      nav.pushNamed('/earnings');
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

  static Future<void> chatMessage({
    required String targetUserId, required String bookingId,
    required String senderName, required String message,
  }) => _send(
    targetUserId: targetUserId, targetRole: 'customer',
    type: 'chat', bookingId: bookingId,
    title: '💬 $senderName', body: message,
  );
}