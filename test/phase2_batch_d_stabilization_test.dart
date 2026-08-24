// ============================================================
// phase2_batch_d_stabilization_test.dart — LinTho App
//
// Regression guards for the real (non-cosmetic) behavior touched by Phase 2
// Batch D (Provider Core migration, LINTHO_PHASE2_BATCH_D_AUDIT.md): the new
// `invalid_amount` localization key added for earnings_tab.dart's two
// previously-hardcoded validation strings, the accessibility fixes (missing
// back-button tooltips), the confirmed navy→green CTA fixes, the pre-existing
// crash-safety guards on customer-name avatar fallbacks, and the intentional
// preservation of job_workflow_Screen.dart's per-step action-button colors.
// Follows the source-based assertion style already used by
// service_icon_remaining_spots_test.dart rather than widget-pumping, since
// none of this needs a rendered widget tree to verify.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('earnings_tab.dart: invalid-amount validation uses tr(), not '
      'hardcoded Lao', () {
    final source = _read('lib/earnings_tab.dart');

    test('the old hardcoded Lao string is gone', () {
      expect(source, isNot(contains('ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ')));
    });

    test('both validation call sites use tr(\'invalid_amount\')', () {
      expect('invalid_amount'.allMatches(source).length, greaterThanOrEqualTo(2));
      expect(source, contains("Text(tr('invalid_amount'))"));
    });
  });

  group('app_locale.dart: invalid_amount key exists in all 4 languages, '
      'Lao wording unchanged', () {
    final source = _read('lib/app_locale.dart');

    test('Lao value matches the exact string it replaced (no silent '
        'wording change)', () {
      expect(source, contains("'invalid_amount':      'ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ'"));
    });

    test('en/th/zh each define a non-empty invalid_amount value', () {
      final matches = RegExp(r"""'invalid_amount':\s*'([^']+)'""")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();
      // lo + en + th + zh = 4 entries, each non-empty.
      expect(matches.length, 4);
      for (final v in matches) {
        expect(v.trim(), isNotEmpty);
      }
    });
  });

  group('job_workflow_Screen.dart: accessibility + intentional exceptions', () {
    final source = _read('lib/job_workflow_Screen.dart');

    test('AppBar back button now has a tooltip', () {
      final start = source.indexOf('AppBar _buildAppBar(');
      final end = source.indexOf('\n}', start);
      final block = source.substring(start, end == -1 ? source.length : end);
      expect(block, contains("tooltip: tr('back_semantic')"));
    });

    test('_ActionButton step colors are preserved, not collapsed to green '
        '(documented intentional exception — see audit §3)', () {
      expect(source, contains('C.blue,  JobStatus.onTheWay'));
      expect(source, contains('C.orange, JobStatus.arrived'));
      expect(source, contains('C.navy,   JobStatus.inProgress'));
      expect(source, contains('C.green,  JobStatus.completed'));
    });

    test('unused booking_repository.dart import was removed', () {
      expect(source, isNot(contains("import 'booking_repository.dart';")));
    });

    test('customerName avatar fallback stays crash-guarded '
        '(no unguarded name[0])', () {
      expect(source, contains('b.customerName.isNotEmpty'));
      expect(source, contains('b.customerName[0].toUpperCase() : \'?\''));
    });
  });

  group('earnings_tab.dart / profile_tab.dart: confirmed navy→green CTA '
      'fixes landed', () {
    test('earnings_tab.dart withdrawal + bank-save buttons are primary '
        'green, not navy', () {
      final source = _read('lib/earnings_tab.dart');
      // ✅ [Batch D] both sole-primary-action sheet buttons fixed.
      final navyElevatedButtons = RegExp(
              r'ElevatedButton\.styleFrom\(\s*backgroundColor: C\.navy')
          .allMatches(source)
          .length;
      expect(navyElevatedButtons, 0);
    });

    test('profile_tab.dart save/reply buttons are primary green, not navy',
        () {
      final source = _read('lib/profile_tab.dart');
      final navyElevatedButtons = RegExp(
              r'backgroundColor: C\.navy, elevation: 0,')
          .allMatches(source)
          .length;
      // Only the logout dialog stays red/destructive (a different pattern,
      // not matched by this navy-specific regex) — no navy CTA should remain.
      expect(navyElevatedButtons, 0);
    });

    test('profile_tab.dart logout confirmation stays destructive (red), '
        'untouched by the CTA sweep', () {
      final source = _read('lib/profile_tab.dart');
      expect(source, contains('backgroundColor: C.red, elevation: 0,'));
    });
  });

  group('profile_tab.dart: back-button accessibility', () {
    test('all 6 profile-area back buttons now have a tooltip', () {
      final source = _read('lib/profile_tab.dart');
      final backButtons = 'Icons.arrow_back_ios,'.allMatches(source).length;
      final tooltips = "tooltip: tr('back_semantic')".allMatches(source).length;
      expect(backButtons, greaterThanOrEqualTo(6));
      expect(tooltips, backButtons);
    });

    test('review-card customer-name avatar fallback stays crash-guarded',
        () {
      final source = _read('lib/profile_tab.dart');
      expect(source, contains('r.customerName.isNotEmpty'));
      expect(source, contains("r.customerName[0].toUpperCase() : '?'"));
    });
  });

  group('home_tab.dart: emoji section headers replaced with Material icons',
      () {
    final source = _read('lib/home_tab.dart');

    test('no functional emoji remain in _SectionHeader titles', () {
      expect(source, isNot(contains('🔔')));
      expect(source, isNot(contains('📋')));
      expect(source, isNot(contains('⚡')));
    });

    test('_SectionHeader now accepts and renders an optional icon', () {
      expect(source, contains('final IconData? icon;'));
      expect(source, contains('Icons.notifications_outlined'));
      expect(source, contains('Icons.assignment_outlined'));
      expect(source, contains('Icons.bolt_outlined'));
    });
  });
}
