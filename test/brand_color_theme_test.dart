// ============================================================
// brand_color_theme_test.dart — LinTho App
//
// Locks in the 2026-07-27 brand-color audit (both passes: the initial
// primary-green pass, and the follow-up full 9-token Brand System audit —
// Primary/Background/Surface/Primary Text/Secondary Text/Border/Success/
// Warning/Error). This verifies the single-source-of-truth theme
// (theme/app_theme.dart's AppTheme.light) actually resolves every
// interactive widget category the audit covers — Switch/Checkbox/Radio/FAB/
// ProgressIndicator/Chip — to brand green when no screen overrides it, and
// that the shared EmptyStateView widget defaults to a neutral color instead
// of the old hardcoded sky-blue (empty states aren't a call-to-action, so
// they shouldn't compete visually with real brand-colored buttons).
//
// A CanvasKit-rendered Flutter web build can't be screenshotted in this
// environment's sandboxed browser preview, so this test is the verification
// path: it inspects the actual resolved ThemeData/WidgetStateProperty
// values rather than pixels, which is deterministic and catches regressions
// a screenshot wouldn't (e.g. a future screen re-introducing a hardcoded
// Colors.blue that happens to render similarly).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart' show JobStatus;
import 'package:lintho/theme/app_theme.dart';
import 'package:lintho/widgets/empty_state_view.dart';

void main() {
  group('AppColors.green is the official brand hex', () {
    test('#14B87A', () {
      expect(AppColors.green, const Color(0xFF14B87A));
    });
  });

  group('Brand System 9-token hex — 2026-07-27 v2 audit', () {
    test('Primary #14B87A',        () => expect(AppColors.green, const Color(0xFF14B87A)));
    test('Background #FFFFFF',     () => expect(AppColors.background, const Color(0xFFFFFFFF)));
    test('Surface #F8FAF8',        () => expect(AppColors.surface, const Color(0xFFF8FAF8)));
    test('Primary Text #1F2937',   () => expect(AppColors.ink, const Color(0xFF1F2937)));
    test('Secondary Text #6B7280', () => expect(AppColors.muted, const Color(0xFF6B7280)));
    test('Border #E5E7EB',         () => expect(AppColors.border, const Color(0xFFE5E7EB)));
    test('Success #22C55E',        () => expect(AppColors.success, const Color(0xFF22C55E)));
    test('Warning #F59E0B',        () => expect(AppColors.orange, const Color(0xFFF59E0B)));
    test('Error #EF4444',          () => expect(AppColors.red, const Color(0xFFEF4444)));

    test('Primary and Success are distinct tokens (not conflated)', () {
      expect(AppColors.green, isNot(AppColors.success));
    });
  });

  group('AppTheme.light — Background/Surface role swap', () {
    final theme = AppTheme.light;

    test('scaffoldBackgroundColor is Background (#FFFFFF)', () {
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });

    test('colorScheme.surface / cardTheme / appBarTheme / dialogTheme / '
        'bottomSheetTheme all use Surface (#F8FAF8), not plain white', () {
      expect(theme.colorScheme.surface, AppColors.surface);
      expect(theme.cardTheme.color, AppColors.surface);
      expect(theme.appBarTheme.backgroundColor, AppColors.surface);
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
      expect(theme.bottomSheetTheme.backgroundColor, AppColors.surface);
    });

    test('AppStatus.colorOf(completed) is Success, not Primary', () {
      expect(AppStatus.colorOf(JobStatus.completed), AppColors.success);
      expect(AppStatus.colorOf(JobStatus.completed), isNot(AppColors.green));
    });
  });

  group('AppTheme.light — single source of truth resolves to brand green', () {
    final theme = AppTheme.light;

    test('colorScheme.primary is brand green', () {
      expect(theme.colorScheme.primary, AppColors.green);
    });

    test('switchTheme: selected thumb/track resolve to brand green', () {
      final thumb = theme.switchTheme.thumbColor
          ?.resolve({WidgetState.selected});
      final track = theme.switchTheme.trackColor
          ?.resolve({WidgetState.selected});
      expect(thumb, AppColors.green);
      expect(track, AppColors.green);
    });

    test('switchTheme: unselected thumb/track are NOT brand green '
        '(so on/off remains visually distinguishable)', () {
      final thumb = theme.switchTheme.thumbColor?.resolve(<WidgetState>{});
      final track = theme.switchTheme.trackColor?.resolve(<WidgetState>{});
      expect(thumb, isNot(AppColors.green));
      expect(track, isNot(AppColors.green));
    });

    test('checkboxTheme: checked fill resolves to brand green', () {
      final fill = theme.checkboxTheme.fillColor
          ?.resolve({WidgetState.selected});
      expect(fill, AppColors.green);
    });

    test('radioTheme: selected fill resolves to brand green', () {
      final fill = theme.radioTheme.fillColor
          ?.resolve({WidgetState.selected});
      expect(fill, AppColors.green);
    });

    test('floatingActionButtonTheme uses brand green background', () {
      expect(theme.floatingActionButtonTheme.backgroundColor, AppColors.green);
    });

    test('progressIndicatorTheme defaults spinners to brand green', () {
      expect(theme.progressIndicatorTheme.color, AppColors.green);
    });

    test('chipTheme: selectedColor is brand green', () {
      expect(theme.chipTheme.selectedColor, AppColors.green);
    });

    test('elevatedButtonTheme (primary CTA) uses brand green', () {
      final bg = theme.elevatedButtonTheme.style?.backgroundColor
          ?.resolve(<WidgetState>{});
      expect(bg, AppColors.green);
    });
  });

  group('EmptyStateView — no longer defaults to blue', () {
    testWidgets('accent defaults to AppColors.muted, not sky-blue',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: EmptyStateView(
            icon: Icons.inbox_outlined,
            title: 'no items',
          ),
        ),
      ));

      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.color, AppColors.muted);
      expect(icon.color, isNot(AppColors.sky));
    });
  });
}
