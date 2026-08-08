// ============================================================
// provider_dashboard.dart — LinTho Provider App
// Main Scaffold + Bottom Navigation
//
// Fixes:
//   ✅ withOpacity → withValues(alpha:)
//   ✅ GestureDetector nav item → InkWell
//   ✅ badge cap ສູງສຸດ 99+ (ຖ້າ pending > 99)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'app_locale.dart';
import 'booking_provider.dart';
import 'home_tab.dart';
import 'jobs_tab.dart';
import 'earnings_tab.dart';
import 'online_provider.dart';
import 'profile_tab.dart';

// ── NAV INDEX ────────────────────────────────────────────────

final navIndexProvider = StateProvider<int>((_) => 0);

// ── DASHBOARD ────────────────────────────────────────────────

class ProviderDashboard extends ConsumerWidget {
  const ProviderDashboard({super.key});

  static const List<Widget> _tabs = [
    ProviderHomeTab(),
    ProviderJobsTab(),
    ProviderEarningsTab(),
    ProviderProfileTab(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx          = ref.watch(navIndexProvider);
    // 🔒 [AUDIT PROV-5 / 2026-07-30] pendingJobsProvider ນັບສະເພາະວຽກທີ່ຖືກ
    // ມອບໝາຍໃຫ້ provider ນີ້ໂດຍກົງ — ບໍ່ນັບ unassignedOpenJobsProvider (ວຽກເປີດ/
    // broadcast ທີ່ຍັງບໍ່ຖືກມອບໝາຍໃຫ້ໃຜ) ເລີຍ, ເຮັດໃຫ້ badge ບໍ່ຂຶ້ນທັງໆທີ່ມີວຽກ
    // ລໍຖ້າຢູ່ໜ້າ home tab. ນັບລວມທັງສອງ.
    final pendingCount = ref.watch(pendingJobsProvider).length +
        ref.watch(unassignedOpenJobsProvider).length;

    // 🔒 [Availability persistence fix] seed the local online/offline toggle
    // from the persisted providers/{uid}.isOnline value once profile data
    // loads — otherwise both Home tab's and Profile's availability switches
    // always show "offline" after app restart/login regardless of the real
    // Firestore state (see online_provider.dart's syncFromRemote).
    ref.listen(profileStreamProvider, (prev, next) {
      next.whenData((p) =>
          ref.read(onlineStatusProvider.notifier).syncFromRemote(p.isOnline));
    });
    // listen() only fires on *future* changes — if the stream already had
    // data cached before this widget attached the listener, catch up here
    // too (syncFromRemote is idempotent/one-shot, safe to call every build).
    ref.read(profileStreamProvider).whenData(
        (p) => ref.read(onlineStatusProvider.notifier).syncFromRemote(p.isOnline));

    return Scaffold(
      body: IndexedStack(index: idx, children: _tabs),
      bottomNavigationBar: _BottomNav(
        currentIndex: idx,
        pendingCount: pendingCount,
        onTap: (i) => ref.read(navIndexProvider.notifier).state = i,
      ),
    );
  }
}

// ── BOTTOM NAV ───────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int                currentIndex;
  final int                pendingCount;
  final void Function(int) onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.dashboard_outlined,              Icons.dashboard,              tr('home')),
      (Icons.work_outline,                    Icons.work,                   tr('all_jobs')),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, tr('earnings')),
      (Icons.person_outline,                  Icons.person,                 tr('profile')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color:      Colors.black.withValues(alpha: 0.08), // ✅ fix
          blurRadius: 20,
          offset:     const Offset(0, -4),
        )],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(items.length, (i) {
              final (outlineIcon, filledIcon, label) = items[i];
              final selected  = currentIndex == i;
              final showBadge = i == 1 && pendingCount > 0;
              // ✅ badge cap 99+
              final badgeLabel = pendingCount > 99 ? '99+' : '$pendingCount';

              return Expanded(
                child: AnimatedContainer(
                  duration:     const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color:        selected
                        ? C.navy.withValues(alpha: 0.07) // ✅ fix
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  // ✅ InkWell ripple
                  child: Material(
                    color:        Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap:       () => onTap(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(clipBehavior: Clip.none, children: [
                              Icon(
                                selected ? filledIcon : outlineIcon,
                                color: selected ? C.navy : C.muted,
                                size:  24,
                              ),
                              if (showBadge)
                                Positioned(
                                  top: -4, right: -8,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 17, minHeight: 17,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: C.red,
                                      // ຖ້າເປັນເລກຫຼັກດຽວໃຫ້ເປັນວົງມົນ, ຖ້າເປັນ 99+ ໃຫ້ເປັນຊົງແຄັບຊູນ (Pill Shape) Auto
                                      borderRadius: BorderRadius.circular(pendingCount > 9 ? 8 : 10),
                                    ),
                                    child: Center(
                                      child: Text(badgeLabel,
                                        style: const TextStyle(
                                          color:      Colors.white,
                                          fontSize:   9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 4),
                            Text(label, style: TextStyle(
                              fontSize:   10,
                              fontWeight: FontWeight.w600,
                              color:      selected ? C.navy : C.muted,
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}