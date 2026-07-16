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

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_colors.dart';

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

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: C.cream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation:   0,
        centerTitle: true,
        title: const Text('ຂໍ້ຄວາມ 💬', style: TextStyle(
          color: C.primary, fontWeight: FontWeight.w800, fontSize: 18,
        )),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('members', arrayContains: user?.uid)
            .orderBy('lastMessageAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SkeletonChatList();
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
              final unread     = chat['unread_${user?.uid}'] as int?    ?? 0;

              return _ChatListTile(
                chatId:      chatId,
                otherName:   otherName,
                serviceName: chat['serviceName'] as String? ?? '',
                lastMsg:     lastMsg,
                unread:      unread,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: C.primary,
        onPressed:       () => _showNewChatHint(context),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  void _showNewChatHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:         Text('ຈອງບໍລິການກ່ອນ ຈາກນັ້ນ chat ຈະເປີດອັດຕະໂນມັດ'),
      backgroundColor: C.primary,
      behavior:        SnackBarBehavior.floating,
    ));
  }
}

// ── CHAT LIST TILE ───────────────────────────────────────────

class _ChatListTile extends StatelessWidget {
  final String chatId;
  final String otherName;
  final String serviceName;
  final String lastMsg;
  final int    unread;
  const _ChatListTile({
    required this.chatId,
    required this.otherName,
    required this.serviceName,
    required this.lastMsg,
    required this.unread,
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
              if (unread > 0)
                Container(
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
    _markAsRead();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    // ✅ [FIX] ບໍ່ມີ try/catch ມາກ່ອນ — ຖ້າອອບໄລນ໌/ບໍ່ມີສິດຂຽນ ຈະເກີດ
    // unhandled Future error ທຸກຄັ້ງທີ່ເປີດຫ້ອງແຊັດ (ບໍ່ຮ້າຍແຮງ, ແຕ່ບໍ່ຄວນ crash)
    try {
      await _chatMetaRef.update({'unread_${_user?.uid}': 0});
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
      await _msgsRef.push().set({
        'senderId':   _user?.uid,
        'senderName': _user?.displayName ?? 'User',
        'text':       text,
        'timestamp':  now,
        'read':       false,
      });

      await _chatMetaRef.update({
        'lastMessage':   text,
        'lastMessageAt': now,
      });

      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .set({
          'lastMessage':   text,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'members': [_user?.uid ?? '', widget.receiverId ?? ''],
        }, SetOptions(merge: true));
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ສົ່ງຂໍ້ຄວາມລົ້ມເຫລວ, ກະລຸນາລອງໃໝ່: $e'),
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
        backgroundColor: Colors.white,
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
                return const _SkeletonMessages();
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

class _SkeletonChatList extends StatefulWidget {
  const _SkeletonChatList();
  @override
  State<_SkeletonChatList> createState() => _SkeletonChatListState();
}

class _SkeletonChatListState extends State<_SkeletonChatList>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.builder(
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
            _Shimmer(w: 50, h: 50, r: 16, op: _anim.value),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(w: 120, h: 13, r: 4, op: _anim.value),
                const SizedBox(height: 6),
                _Shimmer(w: 80,  h: 10, r: 4, op: _anim.value),
                const SizedBox(height: 5),
                _Shimmer(w: 160, h: 10, r: 4, op: _anim.value),
              ],
            )),
          ]),
        ),
      ),
    );
  }
}

class _SkeletonMessages extends StatefulWidget {
  const _SkeletonMessages();
  @override
  State<_SkeletonMessages> createState() => _SkeletonMessagesState();
}

class _SkeletonMessagesState extends State<_SkeletonMessages>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final widths = [160.0, 200.0, 120.0, 180.0, 140.0];
    final rights = [false, true, false, true, false];
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.builder(
        padding:   const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: rights[i]
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              _Shimmer(w: widths[i], h: 40, r: 14, op: _anim.value),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double w, h, r, op;
  const _Shimmer({
    required this.w, required this.h,
    required this.r, required this.op,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color:        C.border.withValues(alpha: op),
      borderRadius: BorderRadius.circular(r),
    ),
  );
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