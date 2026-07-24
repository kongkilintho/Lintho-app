// ============================================================
// service_icon_remaining_spots_test.dart — LinTho App
//
// Regression test for FOLLOWUP-J3: review_screen.dart and tracking_screen.dart
// were the last two screens still rendering the raw serviceEmoji string
// instead of the resolved Material icon (serviceIconForCategory /
// Booking.serviceIcon) already adopted everywhere else (home_tab.dart,
// jobs_tab.dart, job_workflow_Screen.dart, match_screen.dart).
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('FOLLOWUP-J3: review_screen.dart uses serviceIcon, not raw emoji', () {
    final source = _read('lib/review_screen.dart');

    test('the header no longer interpolates a serviceEmoji string', () {
      expect(source, isNot(contains('widget.serviceEmoji')));
    });

    test('the widget accepts and renders an IconData serviceIcon', () {
      expect(source, contains('final IconData       serviceIcon;'));
      expect(source, contains('Icon(widget.serviceIcon'));
    });
  });

  group('FOLLOWUP-J3: tracking_screen.dart\'s provider info row uses '
      'serviceIcon, not raw emoji', () {
    final source = _read('lib/tracking_screen.dart');

    test('_ProviderInfoRow no longer interpolates a serviceEmoji string', () {
      final start = source.indexOf('class _ProviderInfoRow');
      final end = source.indexOf('class ', start + 10);
      final block = source.substring(start, end == -1 ? source.length : end);
      expect(block, isNot(contains(r'$serviceEmoji')));
      expect(block, contains('Icon(serviceIcon'));
    });

    test('TrackingScreen threads serviceIcon through to both '
        '_ProviderInfoRow and ReviewScreen', () {
      expect(source, contains('final IconData       serviceIcon;'));
      expect(source, contains('serviceIcon:  widget.serviceIcon,'),
          reason: 'must be passed to both _ProviderInfoRow and, in '
              '_goReview(), to ReviewScreen');
    });
  });

  group('FOLLOWUP-J3: all real construction sites pass serviceIcon', () {
    test('every TrackingScreen(...) / ReviewScreen(...) call site sets '
        'serviceIcon', () {
      for (final path in [
        'lib/main.dart',
        'lib/booking_detail_screen.dart',
        'lib/match_screen.dart',
      ]) {
        final source = _read(path);
        if (source.contains('TrackingScreen(') ||
            (path != 'lib/main.dart' && source.contains('ReviewScreen('))) {
          expect(source, contains('serviceIcon:'),
              reason: '$path constructs TrackingScreen/ReviewScreen but '
                  'does not pass serviceIcon');
        }
      }
    });
  });
}
