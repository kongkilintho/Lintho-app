// ============================================================
// phase0_stabilization_test.dart — LinTho App
//
// Regression tests for the 5 P0/P1 findings from the LinTho Master Prompt
// "Phase 0 — Stabilization" pass (see LINTHO_PHASE0_PHASE1_PLAN.md):
//   P0-1: "Book Again" / "View History" both called the identical
//         Navigator.popUntil(isFirst) — neither did what it claimed.
//   P0-2: customerName[0] crashed with RangeError on an empty string
//         (Booking.customerName defaults to '' on legacy/corrupted docs).
//   P1:   No screen checked provider.isOnline before letting a customer
//         book — Provider Details' "Book Now" and BookingFormScreen's
//         submit both proceeded regardless of availability.
//   P1:   Technician onboarding had no fallback when GPS permission was
//         denied forever — registration could not be completed at all.
//   P1:   The matching screen showed fabricated "live" stats (12+ techs /
//         4.8★ / <30min) that were static locale strings, plus a dead
//         `estimatedMinutes` field that ProviderModel never actually reads.
//
// ໝາຍເຫດ: ຄືກັນກັບ critical_fixes_test.dart's CRIT-2/3/4/5 group — ບໍ່ມີ
// Firebase emulator / widget-rendering harness ໃນ repo ນີ້ສຳລັບ screen ທີ່
// ຕ້ອງການ Riverpod+Firebase+Navigator ຮ່ວມກັນ, ດັ່ງນັ້ນນີ້ແມ່ນ source-text
// regression guard — ຈັບໄດ້ຖ້າມີໃຜແກ້ໄຂ/ຖອນການແກ້ໄຂຄືນໂດຍບໍ່ຕັ້ງໃຈ.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('P0-1: Book Again / View History navigate correctly', () {
    final src = _read('lib/review_screen.dart');

    test('Book Again no longer just pops to root', () {
      // ✅ ຕ້ອງເປີດ ProviderDetailsScreen ຂອງ provider ຄົນເກົ່າ (ບໍ່ແມ່ນ
      // Navigator.popUntil ຢ່າງດຽວອີກຕໍ່ໄປ)
      expect(src.contains('ProviderDetailsScreen('), isTrue,
          reason: 'Book Again should push ProviderDetailsScreen for '
              'widget.provider so the customer can actually re-book, not '
              'just return to Home.');
      expect(src.contains('providerId: widget.provider.uid'), isTrue);
    });

    test('View History routes to the real booking history tab', () {
      expect(src.contains('goToBookingTab(context, ref)'), isTrue,
          reason: 'View History must open BookingScreen (MainShell tab 1), '
              'not just pop to Home.');
    });

    test('the two buttons no longer share one indistinguishable handler',
        () {
      // ▸ ຮູບແບບເກົ່າ: ທັງສອງປຸ່ມມີ `onPressed: () => Navigator.popUntil(
      //   context, (r) => r.isFirst)` ຄືກັນເປ໊ະ. ຮັບປະກັນວ່າ pattern ນັ້ນ
      //   ບໍ່ຢູ່ໃນໄຟລ໌ອີກຕໍ່ໄປ.
      final bareBothPop =
          RegExp(r'onPressed:\s*\(\)\s*=>\s*Navigator\.popUntil\(\s*context,\s*\(r\)\s*=>\s*r\.isFirst\)')
              .allMatches(src)
              .length;
      expect(bareBothPop, 0,
          reason: 'Book Again and View History previously both called the '
              'exact same bare popUntil — that handler should no longer '
              'exist on this screen.');
    });
  });

  group('P0-2: customerName indexing is guarded against empty strings', () {
    test('job_workflow_Screen.dart guards customerName[0]', () {
      final src = _read('lib/job_workflow_Screen.dart');
      expect(src.contains('b.customerName.isNotEmpty'), isTrue);
      expect(src.contains("? b.customerName[0].toUpperCase() : '?'"), isTrue);
    });

    test('profile_tab.dart guards customerName[0] on review avatars', () {
      final src = _read('lib/profile_tab.dart');
      expect(src.contains('r.customerName.isNotEmpty'), isTrue);
    });

    test('no other unguarded Name[0]/name[0] indexing exists in lib/', () {
      // ▸ ຄືກັນກັບ full-codebase sweep ທີ່ plan ຮຽກຮ້ອງ — ຢືນຢັນວ່າ pattern
      //   ນີ້ບໍ່ໄດ້ regress ຢູ່ໄຟລ໌ອື່ນທີ່ບໍ່ໄດ້ກວດຢູ່ນີ້. ໄຟລ໌ທີ່ຮູ້ແລ້ວວ່າມີ
      //   guard ທີ່ຖືກຕ້ອງ (avatarLetter getters, chat_screen.dart ternaries)
      //   ຖືກຍົກເວັ້ນ.
      final libDir = Directory('lib');
      final offenders = <String>[];
      for (final f in libDir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final content = f.readAsStringSync();
        for (final m
            in RegExp(r'[A-Za-z_]+Name\[0\]').allMatches(content)) {
          // ▸ ເບິ່ງ window 80 ຕົວອັກສອນກ່ອນໜ້າ (ບໍ່ແມ່ນແຕ່ບັນທັດດຽວ) —
          //   guard ບາງບ່ອນເປັນ multi-line ternary (isNotEmpty ຢູ່ຄົນລະບັນທັດ
          //   ກັບ [0] indexing ເອງ)
          final lineStart = content.lastIndexOf('\n', m.start) + 1;
          final lineEndIdx = content.indexOf('\n', m.start);
          final lineEnd = lineEndIdx == -1 ? content.length : lineEndIdx;
          final line = content.substring(lineStart, lineEnd).trim();
          if (line.startsWith('//')) continue; // comment, not real code

          final windowStart = (m.start - 80).clamp(0, content.length);
          final window = content.substring(windowStart, m.start);
          if (!window.contains('isNotEmpty')) {
            offenders.add('${f.path}: $line');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'Found unguarded *Name[0] indexing: $offenders');
    });
  });

  group('P1: booking is gated on provider.isOnline', () {
    test('BookingFormScreen._submit() checks isOnline before writing', () {
      final src = _read('lib/booking_form_screen.dart');
      expect(src.contains('provider.isOnline'), isTrue);
      expect(src.contains('provider_offline_choose_another'), isTrue);
    });

    test('ProviderDetailsScreen disables Book Now when offline', () {
      final src = _read('lib/provider_details_screen.dart');
      expect(src.contains('!provider.isOnline ? null :'), isTrue,
          reason: 'Book Now must be disabled (onPressed: null) when the '
              'provider is offline, not just silently allowed.');
    });
  });

  group('P1: technician onboarding has a GPS-denial fallback', () {
    test('technician_register_screen.dart offers manual map entry', () {
      final src = _read('lib/technician_register_screen.dart');
      expect(src.contains('_pickOnMap'), isTrue);
      expect(src.contains('MapPickerScreen'), isTrue);
      expect(src.contains("tr('pick_location_on_map')"), isTrue,
          reason: 'A manual "pick on map" fallback must exist so '
              'registration is not permanently blocked when GPS is denied '
              'forever or unavailable.');
    });
  });

  group('P1: match_screen.dart no longer shows fabricated live data', () {
    test('the searching-state info chips no longer use fake precision', () {
      // ▸ locale value ເກົ່າ ('12+', '4.8★', '< 30') ຕ້ອງບໍ່ຢູ່ໃນ app_locale.dart
      //   ອີກຕໍ່ໄປ ສຳລັບ 3 key ນີ້
      final src = _read('lib/app_locale.dart');
      final fakeStatPatterns = [
        "'info_chip_online_techs': '12+",
        "'info_chip_avg_rating':  '4.8",
        "'info_chip_fast_eta':    '< 30",
        "'info_chip_online_techs': '12+ Techs Online'",
      ];
      for (final p in fakeStatPatterns) {
        expect(src.contains(p), isFalse,
            reason: 'Fabricated stat string still present: $p');
      }
    });

    test('the fake fixed "20 min" ETA is gone from match_screen.dart', () {
      final src = _read('lib/match_screen.dart');
      expect(src.contains("20 \${tr('minutes_unit')}"), isFalse);
      expect(src.contains("'~20 \${tr('minutes_unit')}'"), isFalse);
      expect(src.contains('eta_on_the_way'), isTrue);
    });

    test('app_locale.dart defines eta_on_the_way for all 4 locales', () {
      final src = _read('lib/app_locale.dart');
      final count = 'eta_on_the_way'.allMatches(src).length;
      // 1 key ຄັ້ງ x 4 locale blocks == 4 (ບໍ່ນັບຄອมเมนต์ທີ່ອ້າງເຖິງມັນ)
      expect(count, greaterThanOrEqualTo(4));
    });
  });
}

