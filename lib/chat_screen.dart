// ============================================================
// chat_screen.dart — LinTho
// Fixes:
//   ✅ [FIX-1] CircularProgressIndicator → _SendingSkeleton
//              ໃນ send button ຕອນ _sending = true
// ── Rules (kept) ────────────────────────────────────────────
//   ✅ withValues(alpha:) ທຸກຈຸດ
//   ✅ InkWell + Material ທຸກ tap
//   ✅ Skeleton loading ທຸກຈຸດ
//   ✅ _sending debounce
//   ✅ _chatId sorted key
//   ✅ dispose() ທຸກ controller
//   ✅ mounted check
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'fcm_service.dart';
import 'widgets/skeleton_box.dart';
import 'widgets/error_state_view.dart';

// ════════════════════════════════════════════════════════════
// MODEL
// ════════════════════════════════════════════════════════════

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final int    timestamp;
  final bool   read;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.read,
  });

  factory ChatMessage.fromMap(String id, Map<dynamic, dynamic> map) {
    return ChatMessage(
      id:         id,
      senderId:   map['senderId']   as String? ?? '',
      senderName: map['senderName'] as String? ?? '',
      text:       map['text']       as String? ?? '',
      timestamp:  map['timestamp']  as int?    ?? 0,
      read:       map['read']       as bool?   ?? false,
    );
  }
}

// ════════════════════════════════════════════════════════════
// CHAT LIST SCREEN
// ════════════════════════════════════════════════════════════

// ── CHAT LIST BODY (reusable) ────────────────────────────────
// ✅ [Notification feature 2026-08-03] ຍົກ body ອອກຈາກ ChatListScreen ເປັນ
// widget ແຍກຕ່າງຫາກ — ໃຫ້ NotificationScreen's "Chat" tab embed ໄດ້ໂດຍກົງ
// (ໃຊ້ chats collection ດຽວກັນ, query ດຽວກັນ, ບໍ່ສ້າງ data source ຊ້ຳ).
// ChatListScreen ຂ້າງລຸ່ມຍັງເຮັດວຽກຄືເກົ່າ 100% (Scaffold+AppBar+FAB ຫຸ້ມ
// widget ນີ້).
class ChatListBody extends StatefulWidget {
  const ChatListBody({super.key});

  @override
  State<ChatListBody> createState() => _ChatListBodyState();
}

class _ChatListBodyState extends State<ChatListBody> {
  // 🔒 [AUDIT EDGE-4 / 2026-08-02 — Low, fresh re-audit] bumped by the retry
  // button below to force the StreamBuilder to resubscribe — this screen has
  // no Riverpod provider to invalidate() (raw Firestore stream), so a
  // ValueKey change is the mechanism.
  int _retryTick = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_retryTick),
      // 🔒 [AUDIT PERF-2 / 2026-08-02 — Medium, fresh re-audit] ບໍ່ເຄີຍມີ
      // .limit() ຢູ່ນີ້ — ຕ່າງຈາກ query ອື່ນທຸກອັນໃນແອັບທີ່ຈຳກັດຂອບເຂດໝົດ
      // (booking_repository.dart ໃຊ້ .limit(30/50) ທົ່ວໄປ). ຜູ້ໃຊ້ທີ່ມີ
      // ຫ້ອງແຊັດຫຼາຍຮ້ອຍຫ້ອງຈະດາວໂຫຼດ/ hold ໄວ້ໃນ memory ໝົດທຸກຄັ້ງທີ່ເປີດໜ້ານີ້.
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('members', arrayContains: user?.uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SkeletonChatList();
        }
        // 🔒 [AUDIT EDGE-4 / 2026-08-02 — Low, fresh re-audit] previously
        // an error fell into the same branch as "no chats yet" below —
        // indistinguishable to the user, and no way to retry a real
        // failure (offline, permission change) short of leaving the screen.
        if (snapshot.hasError) {
          return ErrorStateView(
              onRetry: () => setState(() => _retryTick++));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const _EmptyChatList();
        }
        final chats = snapshot.data!.docs;
        return ListView.builder(
          padding:     const EdgeInsets.all(16),
          itemCount:   chats.length,
          itemBuilder: (_, i) {
            final chat       = chats[i].data() as Map<String, dynamic>;
            final chatId     = chats[i].id;
            final isCustomer = user?.uid == chat['customerId'];
            final otherName  = isCustomer
                ? (chat['providerName']  as String? ?? 'ຊ່າງ')
                : (chat['customerName'] as String? ?? 'ລູກຄ້າ');
            final lastMsg    = chat['lastMessage']          as String? ?? '';

            return _ChatListTile(
              chatId:      chatId,
              otherName:   otherName,
              serviceName: chat['serviceName'] as String? ?? '',
              lastMsg:     lastMsg,
              myUid:       user?.uid,
            );
          },
        );
      },
    );
  }
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.cream,
      appBar: AppBar(
        elevation:   0,
        centerTitle: true,
        title: Text(tr('chat_title'), style: const TextStyle(
          color: C.primary, fontWeight: FontWeight.w800, fontSize: 18,
        )),
      ),
      body: const ChatListBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: C.primary,
        onPressed:       () => _showNewChatHint(context),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  void _showNewChatHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(tr('chat_book_first_hint')),
      backgroundColor: C.primary,
      behavior:        SnackBarBehavior.floating,
    ));
  }
}

// ── CHAT LIST TILE ───────────────────────────────────────────

class _ChatListTile extends StatelessWidget {
  final String  chatId;
  final String  otherName;
  final String  serviceName;
  final String  lastMsg;
  final String? myUid;
  const _ChatListTile({
    required this.chatId,
    required this.otherName,
    required this.serviceName,
    required this.lastMsg,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset:     const Offset(0, 3),
        )],
      ),
      child: Material(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId:         chatId,
              otherName:      otherName,
              bookingService: serviceName,
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [C.primary, C.gold],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: Text(
                  otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: C.text,
                  )),
                  const SizedBox(height: 3),
                  Text(serviceName, style: const TextStyle(
                    fontSize: 11, color: C.gold, fontWeight: FontWeight.w600,
                  )),
                  const SizedBox(height: 2),
                  Text(lastMsg,
                    style:    const TextStyle(fontSize: 12, color: C.muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              )),
              // 🔒 [FOLLOWUP-E] unread count ຕອນນີ້ຢູ່ Realtime Database
              // (chats/$chatId/meta/unread_$myUid, ຂຽນໂດຍ _sendMessage())
              // ບໍ່ແມ່ນ Firestore ອີກຕໍ່ໄປ — field Firestore ເກົ່າບໍ່ເຄີຍຖືກຂຽນ
              // ໂດຍໃຜເລີຍ, badge ຈຶ່ງອ່ານໄດ້ 0 ຕະຫຼອດ.
              if (myUid != null && myUid!.isNotEmpty)
                StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('chats/$chatId/meta/unread_$myUid')
                      .onValue,
                  builder: (context, snap) {
                    final unread =
                        (snap.data?.snapshot.value as num?)?.toInt() ?? 0;
                    if (unread <= 0) return const SizedBox.shrink();
                    return Container(
                      width: 22, height: 22,
                      decoration: const BoxDecoration(
                        color: C.primary, shape: BoxShape.circle,
                      ),
                      child: Center(child: Text('$unread',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      )),
                    );
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// CHAT SCREEN
// ════════════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  final String  chatId;
  final String  otherName;
  final String  bookingService;
  final String? receiverId;
  final String? receiverName;

  const ChatScreen({
    super.key,
    this.chatId         = '',
    this.otherName      = '',
    this.bookingService = '',
    this.receiverId,
    this.receiverName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _user       = FirebaseAuth.instance.currentUser;

  late final DatabaseReference _msgsRef;
  late final DatabaseReference _chatMetaRef;

  bool _sending = false;

  // 🔒 [AUDIT EDGE-5 / 2026-08-02 — Low, fresh re-audit] the messages
  // StreamBuilder below showed _SkeletonMessages() for as long as
  // ConnectionState stayed 'waiting' with no timeout — a device stuck
  // offline (RTDB doesn't quickly emit a connectivity error the way
  // Firestore does) saw an infinite skeleton with no way to tell something
  // was wrong or retry.
  Timer? _msgTimeoutTimer;
  bool   _msgLoadTimedOut = false;

  void _startMsgTimeoutTimer() {
    _msgTimeoutTimer?.cancel();
    _msgLoadTimedOut = false;
    _msgTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _msgLoadTimedOut = true);
    });
  }

  // 🔒 [AUDIT CUST-5 / 2026-08-02] ດຶງໄວ້ຄັ້ງດຽວຕອນເປີດໜ້າ (ຈາກ Firestore
  // chats/{id} doc — ChatService.createOrGetChat() ຂຽນ bookingId/customerId/
  // providerId ໄວ້ຢູ່ນັ້ນ) ເພື່ອໃຫ້ _sendMessage() ຮູ້ຈັກ targetRole ຂອງອີກຝ່າຍ
  // ແທ້ (ບໍ່ hardcode 'customer' ຄືເກົ່າ — ແຊັດແມ່ນສອງທິດທາງ) ແລະ bookingId ແທ້
  // (ບໍ່ແມ່ນ chatId) ໃຫ້ notification tap-navigation ໃຊ້ໄດ້.
  String? _bookingId;
  String? _chatProviderId;

  String get _displayName => widget.receiverName ?? widget.otherName;

  // ✅ sorted key ປ້ອງກັນ A_B vs B_A duplicate room
  String get _chatId {
    if (widget.chatId.isNotEmpty) return widget.chatId;
    final ids = [_user?.uid ?? '', widget.receiverId ?? '']..sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    _msgsRef     = FirebaseDatabase.instance.ref('chats/$_chatId/messages');
    _chatMetaRef = FirebaseDatabase.instance.ref('chats/$_chatId/meta');
    _ensureIdentitySeeded();
    _loadChatMeta();
    _startMsgTimeoutTimer();
  }

  Future<void> _loadChatMeta() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats').doc(_chatId).get()
          .timeout(const Duration(seconds: 15));
      final d = doc.data();
      if (d == null || !mounted) return;
      setState(() {
        _bookingId      = d['bookingId'] as String?;
        _chatProviderId = d['providerId'] as String?;
      });
    } catch (e) {
      debugPrint('ChatScreen: _loadChatMeta failed: $e');
    }
  }

  // 🔒 [AUDIT H5] database.rules.json ອະນຸຍາດອ່ານ/ຂຽນ meta/messages ສະເພາະ
  // 2 ຄົນທີ່ຖືກບັນທຶກເປັນ meta/customerId ແລະ meta/providerId ເທົ່ານັ້ນ (ຄ່າ
  // immutable ຫຼັງຕັ້ງຄັ້ງທຳອິດ) — ບໍ່ໄດ້ໃຊ້ members map ແບບ self-add ອີກຕໍ່ໄປ
  // (ການອອກແບບເດີມນັ້ນມີຊ່ອງໂຫວ່: user ໃດກໍໄດ້ສາມາດຂຽນ members/{ຕົນເອງ}:true
  // ໃສ່ຫ້ອງແຊັດຄົນອື່ນໄດ້ໂດຍກົງ, ບໍ່ມີການກວດວ່າຕົນເອງແມ່ນ 1 ໃນ 2 ຄົນທີ່ຖືກເຊີນ).
  // ບາງ entry point (ເຊັ່ນ provider_details_screen.dart's "ແຊັດ" ປຸ່ມ) ເປີດ
  // ChatScreen ໂດຍກົງ ບໍ່ຜ່ານ ChatService.createOrGetChat() ມາກ່ອນ — seed
  // customerId/providerId ຢູ່ນີ້ (best-effort; ຖ້າ doc ມີແລ້ວດ້ວຍຄ່າອື່ນ ການຂຽນ
  // ຊ້ຳຈະຖືກ rules ປະຕິເສດຢ່າງປອດໄພ ເພາະ .validate ບັງຄັບ immutable — ບໍ່ເປັນຫຍັງ
  // ເພາະ uid ຂອງເຮົາເອງກໍຖືກບັນທຶກໄວ້ແລ້ວໃນຄັ້ງທຳອິດຢູ່ດີ).
  Future<void> _ensureIdentitySeeded() async {
    final uid = _user?.uid;
    final other = widget.receiverId;
    if (uid == null || other == null || other.isEmpty) {
      await _markAsRead();
      return;
    }
    try {
      await _chatMetaRef.update({
        'customerId': uid,
        'providerId': other,
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('ChatScreen: _ensureIdentitySeeded failed (likely already seeded): $e');
    }
    await _markAsRead();
  }

  @override
  void dispose() {
    _msgTimeoutTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    // ✅ [FIX] ບໍ່ມີ try/catch ມາກ່ອນ — ຖ້າອອບໄລນ໌/ບໍ່ມີສິດຂຽນ ຈະເກີດ
    // unhandled Future error ທຸກຄັ້ງທີ່ເປີດຫ້ອງແຊັດ (ບໍ່ຮ້າຍແຮງ, ແຕ່ບໍ່ຄວນ crash)
    try {
      await _chatMetaRef.update({'unread_${_user?.uid}': 0})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('ChatScreen: _markAsRead failed: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _msgCtrl.clear();

    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // 🔒 [AUDIT CRIT-5] ບໍ່ເຄີຍມີ timeout ຢູ່ນີ້ — ຖ້າອອບໄລນ໌, Realtime
      // Database ຈະ queue write ໄວ້ລໍຖ້າ sync ໂດຍບໍ່ reject Future ເລີຍ,
      // _sending ຄ້າງ true ຕະຫຼອດໄປ (ປຸ່ມສົ່ງ loading ບໍ່ຢຸດ) ໂດຍບໍ່ເຄີຍເຂົ້າ
      // catch block ທີ່ມີຢູ່ແລ້ວຂ້າງລຸ່ມນີ້.
      await _msgsRef.push().set({
        'senderId':   _user?.uid,
        'senderName': _user?.displayName ?? 'User',
        'text':       text,
        'timestamp':  now,
        'read':       false,
      }).timeout(const Duration(seconds: 15));

      await _chatMetaRef.update({
        'lastMessage':   text,
        'lastMessageAt': now,
      }).timeout(const Duration(seconds: 15));

      // 🔒 [FOLLOWUP-E] ກ່ອນໜ້ານີ້ບໍ່ມີບ່ອນໃດ increment unread counter ເລີຍ
      // (_markAsRead() ຂ້າງເທິງພຽງແຕ່ reset ເປັນ 0) — badge "ບໍ່ອ່ານ" ຢູ່ໜ້າ
      // ChatListScreen ຈຶ່ງອ່ານຄ່າ 0 ຕະຫຼອດໄປ. ຂຽນໃສ່ RTDB (ບໍ່ແມ່ນ Firestore —
      // database.rules.json ອະນຸຍາດໃຫ້ member ຄົນໃດຄົນໜຶ່ງຂຽນ field ໃດກໍໄດ້ພາຍໃຕ້
      // meta, ລວມທັງ counter ຂອງອີກຝ່າຍ) — best-effort, ບໍ່ຄວນເຮັດໃຫ້ຂໍ້ຄວາມທີ່
      // ສົ່ງແລ້ວກາຍເປັນ "ລົ້ມເຫລວ" ຖ້າ increment ນີ້ລົ້ມເຫລວ.
      if (widget.receiverId != null && widget.receiverId!.isNotEmpty) {
        try {
          await _chatMetaRef
              .update({'unread_${widget.receiverId}': ServerValue.increment(1)})
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('ChatScreen: unread increment failed: $e');
        }

        // 🔒 [AUDIT CUST-5 / 2026-08-02 — Medium, fresh re-audit]
        // NotificationSender.chatMessage() ຖືກຂຽນໄວ້ (fcm_service.dart) ແຕ່
        // ບໍ່ເຄີຍຖືກເອີ້ນຈາກຈຸດນີ້ຈັກເທື່ອ — ຝ່າຍທີ່ບໍ່ໄດ້ເປີດແອັບ/ຫ້ອງແຊັດຢູ່ ບໍ່ເຄີຍ
        // ໄດ້ຮັບ push ຈາກຂໍ້ຄວາມແຊັດເລີຍ. best-effort — ຄວາມລົ້ມເຫຼວບໍ່ຄວນເຮັດໃຫ້
        // ຂໍ້ຄວາມທີ່ສົ່ງແລ້ວ (ຂຽນ Firestore/RTDB ສຳເລັດແລ້ວຂ້າງເທິງ) ກາຍເປັນ error.
        try {
          final targetRole = widget.receiverId == _chatProviderId
              ? 'provider'
              : 'customer';
          await NotificationSender.chatMessage(
            targetUserId: widget.receiverId!,
            targetRole:   targetRole,
            bookingId:    _bookingId ?? _chatId,
            senderName:   _user?.displayName ?? 'User',
            message:      text,
          );
        } catch (e) {
          debugPrint('ChatScreen: chat push notification failed: $e');
        }
      }

      try {
        // 🔒 [AUDIT CRIT-5 follow-up] ບໍ່ເຄີຍມີ timeout ຢູ່ນີ້ — ຖ້າຄ້າງ,
        // await ນີ້ຈະຄ້າງ _sending ໄວ້ (finally ຂ້າງລຸ່ມຍັງບໍ່ທັນເຖິງ) ຄືກັນກັບ
        // ບັນຫາເດີມ, ພຽງແຕ່ຄ້າງຢູ່ write ຕໍ່ໄປແທນ.
        // ✅ [Bonus fix — found while verifying H5] ບໍ່ຂຽນ 'members' ຢູ່ນີ້
        // ອີກຕໍ່ໄປ — firestore.rules ບັງຄັບ members immutable ຫຼັງສ້າງ chat
        // ຄັ້ງທຳອິດ (request.resource.data.members == resource.data.members).
        // ກ່ອນໜ້ານີ້ຂຽນ [_user.uid, receiverId] ຊ້ຳທຸກຄັ້ງ — ຖ້າ provider ເປັນ
        // ຄົນສົ່ງຂໍ້ຄວາມ, order ນີ້ກັບກັນກັບຄ່າເດີມ [customerId, providerId] —
        // ຂຽນລົ້ມເຫລວງຽບໆ (catch ຂ້າງລຸ່ມ) ເຮັດໃຫ້ lastMessage/lastMessageAt
        // ບໍ່ອັບເດດຕອນ provider ຕອບ, ໜ້າ chat list ຂອງລູກຄ້າຈຶ່ງບໍ່ອັບເດດຄືກັນ.
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .set({
          'lastMessage':   text,
          'lastMessageAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('ChatScreen: Firestore metadata update failed: $e');
      }

      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    } catch (e) {
      // ✅ [FIX] ກ່ອນໜ້ານີ້ບໍ່ມີ catch ເລີຍ — ຂໍ້ຄວາມທີ່ພິມແລ້ວຖືກລຶບອອກຈາກ
      // ຊ່ອງພິມ (_msgCtrl.clear() ຂ້າງເທິງ) ກ່ອນຮູ້ວ່າສົ່ງລົ້ມເຫລວ ເຮັດໃຫ້
      // ຂໍ້ຄວາມຫາຍໄປງຽບໆ. ຕອນນີ້ຄືນຂໍ້ຄວາມກັບຄືນຊ່ອງພິມ ແລະ ແຈ້ງເຕືອນຜູ້ໃຊ້.
      _msgCtrl.text = text;
      // 🔒 [AUDIT EDGE-6 / 2026-08-02 — Low, fresh re-audit] every failure
      // (offline, timeout, a real permission-denied from database.rules.json
      // — e.g. this chat's meta was seeded with a different pair of
      // participants than expected) previously showed the same generic
      // "send failed, please retry" with the raw exception appended —
      // technically accurate but misleading for permission-denied, which
      // retrying can never fix. Distinguish it with a clearer message.
      final isPermissionDenied = e is FirebaseException && e.code == 'permission-denied';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isPermissionDenied
              ? tr('chat_send_permission_denied')
              : 'ສົ່ງຂໍ້ຄວາມລົ້ມເຫລວ, ກະລຸນາລອງໃໝ່: $e'),
          backgroundColor: C.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.cream,
      appBar: AppBar(
        elevation:   0,
        centerTitle: true,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios, color: C.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(children: [
          Text(_displayName, style: const TextStyle(
            color: C.primary, fontWeight: FontWeight.w800, fontSize: 16,
          )),
          if (widget.bookingService.isNotEmpty)
            Text(widget.bookingService,
                style: const TextStyle(color: C.muted, fontSize: 11)),
        ]),
        actions: [
          Container(
            margin:  const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color:        C.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.circle, color: C.green, size: 8),
              SizedBox(width: 4),
              Text('Live', style: TextStyle(
                color: C.green, fontSize: 10, fontWeight: FontWeight.w700,
              )),
            ]),
          ),
        ],
      ),
      body: Column(children: [

        // ── Messages ──
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            stream: _msgsRef.orderByChild('timestamp').limitToLast(50).onValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                if (_msgLoadTimedOut) {
                  return ErrorStateView(
                      onRetry: () => setState(_startMsgTimeoutTimer));
                }
                return const _SkeletonMessages();
              }
              // stream produced data or an error — no longer "loading"
              _msgTimeoutTimer?.cancel();
              if (snapshot.hasError) {
                return ErrorStateView(
                    onRetry: () => setState(_startMsgTimeoutTimer));
              }
              final data = snapshot.data?.snapshot.value;
              if (data == null) return const _EmptyChat();

              final rawMap = data as Map<dynamic, dynamic>;
              final messages = rawMap.entries
                  .map((e) => ChatMessage.fromMap(
                e.key.toString(),
                Map<dynamic, dynamic>.from(e.value as Map),
              ))
                  .toList()
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

              return ListView.builder(
                controller: _scrollCtrl,
                padding:    const EdgeInsets.all(16),
                itemCount:  messages.length,
                itemBuilder: (_, i) => _MessageBubble(
                  message: messages[i],
                  isMe:    messages[i].senderId == _user?.uid,
                ),
              );
            },
          ),
        ),

        // ── Input Bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(
              color:      Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset:     const Offset(0, -3),
            )],
          ),
          child: SafeArea(
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color:        C.cream,
                    borderRadius: BorderRadius.circular(24),
                    border:       Border.all(color: C.border),
                  ),
                  child: TextField(
                    controller:      _msgCtrl,
                    style:           const TextStyle(
                        fontSize: 14, color: C.text),
                    maxLines:        null,
                    textInputAction: TextInputAction.send,
                    onSubmitted:     (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText:  'ພິມຂໍ້ຄວາມ...',
                      hintStyle: TextStyle(color: C.muted, fontSize: 14),
                      border:    InputBorder.none,
                      isDense:   true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ✅ [FIX-1] ປ່ຽນ CircularProgressIndicator → _SendingSkeleton
              Material(
                color:        Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _sending ? null : _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _sending
                            ? [C.muted, C.muted]
                            : const [C.primary, C.gold],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _sending ? [] : [BoxShadow(
                        color:      C.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset:     const Offset(0, 3),
                      )],
                    ),
                    // ✅ [FIX-1] Skeleton pulse ແທນ CircularProgressIndicator
                    child: _sending
                        ? const _SendingSkeleton()
                        : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// SENDING SKELETON
// ✅ [FIX-1] ແທນ CircularProgressIndicator ໃນ send button
// ════════════════════════════════════════════════════════════

class _SendingSkeleton extends StatefulWidget {
  const _SendingSkeleton();

  @override
  State<_SendingSkeleton> createState() => _SendingSkeletonState();
}

class _SendingSkeletonState extends State<_SendingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Center(
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color:  Colors.white.withValues(alpha: _anim.value),
          shape:  BoxShape.circle,
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool        isMe;
  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final dt      = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color:        C.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: C.primary,
                ),
              )),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? C.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset:     const Offset(0, 2),
                    )],
                  ),
                  child: Text(message.text, style: TextStyle(
                    fontSize: 14,
                    color:    isMe ? Colors.white : C.text,
                  )),
                ),
                const SizedBox(height: 4),
                Text(timeStr, style: const TextStyle(
                  fontSize: 10, color: C.muted,
                )),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// EMPTY / SKELETON STATES
// ════════════════════════════════════════════════════════════

class _ChatIllustration extends StatelessWidget {
  final double size;
  const _ChatIllustration({this.size = 100});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                C.primary.withValues(alpha: 0.10),
                C.gold.withValues(alpha: 0.18),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: size * 0.62, height: size * 0.62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [C.primary, C.gold]),
            borderRadius: BorderRadius.circular(size * 0.2),
            boxShadow: [BoxShadow(
              color: C.primary.withValues(alpha: 0.25),
              blurRadius: 14, offset: const Offset(0, 6),
            )],
          ),
          child: Icon(Icons.chat_bubble_rounded,
              color: Colors.white, size: size * 0.3),
        ),
        Positioned(
          right: size * 0.06, top: size * 0.04,
          child: Container(
            width: size * 0.22, height: size * 0.22,
            decoration: BoxDecoration(
              color: C.gold,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.favorite, color: Colors.white,
                size: size * 0.12),
          ),
        ),
      ]),
    );
  }
}

class _EmptyChatList extends StatelessWidget {
  const _EmptyChatList();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _ChatIllustration(),
        const SizedBox(height: 18),
        const Text('ຍັງບໍ່ມີການສົນທະນາ', style: TextStyle(
          fontSize: 16, color: C.text, fontWeight: FontWeight.w800,
        )),
        const SizedBox(height: 4),
        Text('ການສົນທະນາ​ກັບ​ຊ່າງ ​ຈະ​ປະກົດ​ຢູ່​ນີ້',
            style: TextStyle(
                fontSize: 12.5, color: C.muted.withValues(alpha: 0.9))),
      ],
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _ChatIllustration(size: 84),
        const SizedBox(height: 14),
        const Text('ເລີ່ມການສົນທະນາ!',
            style: TextStyle(color: C.text, fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

// 🔒 [AUDIT UI-5 / 2026-08-02 — Medium, fresh re-audit] previously each of
// these hand-rolled its own AnimationController+Tween+dispose() shimmer —
// now built on the shared SkeletonBox (which already wraps PulsingFade).
class _SkeletonChatList extends StatelessWidget {
  const _SkeletonChatList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding:     const EdgeInsets.all(16),
      itemCount:   5,
      itemBuilder: (_, __) => Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const SkeletonBox(width: 50, height: 50, radius: 16),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 120, height: 13, radius: 4),
              SizedBox(height: 6),
              SkeletonBox(width: 80,  height: 10, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 160, height: 10, radius: 4),
            ],
          )),
        ]),
      ),
    );
  }
}

class _SkeletonMessages extends StatelessWidget {
  const _SkeletonMessages();

  @override
  Widget build(BuildContext context) {
    final widths = [160.0, 200.0, 120.0, 180.0, 140.0];
    final rights = [false, true, false, true, false];
    return ListView.builder(
      padding:   const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: rights[i]
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            SkeletonBox(width: widths[i], height: 40, radius: 14),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// CHAT SERVICE
// ════════════════════════════════════════════════════════════

class ChatService {
  static Future<String> createOrGetChat({
    required String bookingId,
    required String customerId,
    required String customerName,
    required String providerId,
    required String providerName,
    required String serviceName,
  }) async {
    final chatId  = '${bookingId}_chat';
    final chatRef = FirebaseFirestore.instance
        .collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();

    if (!chatDoc.exists) {
      await chatRef.set({
        'bookingId':     bookingId,
        'customerId':    customerId,
        'customerName':  customerName,
        'providerId':    providerId,
        'providerName':  providerName,
        'serviceName':   serviceName,
        'members':       [customerId, providerId],
        'lastMessage':   'ເລີ່ມການສົນທະນາ',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt':     FieldValue.serverTimestamp(),
      });
    }

    // 🔒 [AUDIT H5] ບໍ່ເຄີຍມີ database.rules.json ຢູ່ໃນ repo ນີ້ — ຂໍ້ຄວາມແຊັດຈິງ
    // (ອາດມີເບີໂທ, ທີ່ຢູ່, ການຕໍ່ລອງລາຄາ) ຈຶ່ງບໍ່ມີ rule ໃດກວດສອບເລີຍ. ຕອນນີ້ເພີ່ມ
    // database.rules.json ຈຳກັດອ່ານ/ຂຽນສະເພາະ meta/customerId ແລະ meta/
    // providerId (immutable ຫຼັງຕັ້ງຄັ້ງທຳອິດ) — ຂຽນຢູ່ນີ້ຄັ້ງດຽວຕອນສ້າງຫ້ອງແຊັດ.
    await FirebaseDatabase.instance
        .ref('chats/$chatId/meta')
        .update({
      'customerId':  customerId,
      'providerId':  providerId,
      'serviceName': serviceName,
      'createdAt':   DateTime.now().millisecondsSinceEpoch,
    });

    return chatId;
  }
}