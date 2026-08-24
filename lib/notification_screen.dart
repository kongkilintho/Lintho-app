// ============================================================
// notification_screen.dart — LinTho Customer App
// ▸ ໜ້າ "ການແຈ້ງເຕືອນ" ເປີດຈາກໂຕກະດິ່ງ (bell) ຢູ່ Home header — 3 tabs:
//   Chat (ChatListBody, chat_screen.dart), News (CouponListBody — ຄູປອງ/
//   ສ່ວນຫຼຸດຈິງຂອງລູກຄ້າ, coupon_list_screen.dart), Customer Service (FAQ/
//   ໂທ/WhatsApp/ອີເມວ ຈິງຈາກ support_provider.dart — ໂຕດຽວກັນກັບທີ່ Profile
//   ໜ້າ "ຊ່ວຍເຫຼືອ" ໃຊ້ຢູ່ແລ້ວ).
// ▸ ບໍ່ມີ "ຂ່າວ/ໂປຣໂມຊັນ" collection ຈິງແຍກຕ່າງຫາກໃນແອັບນີ້ — tab "News" ຈຶ່ງ
//   ສະແດງ promotions/coupons ຈິງຂອງລູກຄ້າແທນທີ່ຈະສ້າງ feed ຂ່າວປອມຂຶ້ນມາ.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_colors.dart';
import 'app_locale.dart';
import 'chat_screen.dart' show ChatListBody;
import 'coupon_list_screen.dart' show CouponListBody;
import 'support_help.dart';
import 'support_provider.dart';
import 'theme/app_theme.dart' show AppTypography, AppRadius;

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: C.background,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          // ✅ [Phase 2 / Batch C] matches AppTypography.appBarTitle exactly.
          title: Text(tr('notifications'), style: AppTypography.appBarTitle),
          bottom: TabBar(
            labelColor: C.primary,
            unselectedLabelColor: C.muted,
            indicatorColor: C.primary,
            indicatorWeight: 3,
            // ✅ fontSize matches AppTypography.label; color comes from
            // labelColor/unselectedLabelColor above, same as before.
            labelStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w700),
            unselectedLabelStyle: AppTypography.label,
            tabs: [
              Tab(text: tr('notif_tab_chat')),
              Tab(text: tr('notif_tab_news')),
              Tab(text: tr('notif_tab_support')),
            ],
          ),
        ),
        body: const TabBarView(children: [
          ChatListBody(),
          CouponListBody(),
          _CustomerServiceTab(),
        ]),
      ),
    );
  }
}

// ── CUSTOMER SERVICE TAB ─────────────────────────────────────
class _CustomerServiceTab extends ConsumerWidget {
  const _CustomerServiceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(supportInfoProvider).valueOrNull ?? const SupportInfo();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (info.hours.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: C.mint,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: C.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(info.hours, style: const TextStyle(
                  fontSize: 12.5, color: C.text, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        _ServiceActionCard(
          icon: Icons.help_center_rounded,
          iconColor: C.primary,
          title: tr('help'),
          subtitle: 'FAQ',
          onTap: () => showFaqSheet(context),
        ),
        const SizedBox(height: 10),
        _ServiceActionCard(
          icon: Icons.phone_rounded,
          iconColor: C.sky,
          title: tr('call_support'),
          subtitle: info.phoneDisplay.isNotEmpty ? info.phoneDisplay : null,
          onTap: () => callSupport(context, info.phone),
        ),
        if (info.whatsapp.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ServiceActionCard(
            icon: Icons.chat_bubble_rounded,
            iconColor: C.primary,
            title: tr('live_chat_button'),
            subtitle: 'WhatsApp',
            onTap: () => whatsappSupport(context, info.whatsapp),
          ),
        ],
        if (info.email.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ServiceActionCard(
            icon: Icons.mail_outline_rounded,
            iconColor: C.gold,
            title: tr('chat_support'),
            subtitle: info.email,
            onTap: () => chatSupport(context, info.email),
          ),
        ],
      ],
    );
  }
}

class _ServiceActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ServiceActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 3),
            )],
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
                // ✅ [Phase 2 / Batch C] fontSize matches AppTypography.caption.
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTypography.caption),
                ],
              ],
            )),
            const Icon(Icons.chevron_right, color: C.muted, size: 20),
          ]),
        ),
      ),
    );
  }
}
