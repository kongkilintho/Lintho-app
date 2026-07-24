// ============================================================
// batch_j_misc_test.dart — LinTho App
//
// Regression tests for the remaining small mechanical fixes in the
// followup batch:
//   FOLLOWUP-J1 — PaymentHistoryScreen uses the shared bookingTotalLabel()
//                 helper instead of its own pre-discount-preferring logic
//   FOLLOWUP-J2 — the home-screen notification bell (no onTap, dead
//                 affordance) has been removed
//   FOLLOWUP-J4 — codeAutoRetrievalTimeout clears the OTP-send spinner in
//                 both registration flows
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('FOLLOWUP-J1: PaymentHistoryScreen delegates to bookingTotalLabel()',
      () {
    test('_totalLabel calls the shared helper, not its own grandTotal-first '
        'logic', () {
      final source = _read('lib/main.dart');
      final start = source.indexOf('class PaymentHistoryScreen');
      final end = source.indexOf('_serviceNameOf', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('bookingTotalLabel(b)'));
      expect(block, isNot(contains("b['grandTotal'] ?? b['priceDisplay']")),
          reason: 'the old logic prioritized the pre-discount amount, '
              'showing customers a total that ignores their coupon');
    });
  });

  group('FOLLOWUP-J2: the dead notification bell affordance is removed', () {
    test('main.dart no longer has a bare, non-interactive notification bell '
        'icon next to the home-screen user name row', () {
      final source = _read('lib/main.dart');
      expect(source, isNot(contains('notifications_none_rounded')),
          reason: 'the bell had no onTap and no notification-center screen '
              'to navigate to — removed rather than left as a dead tap '
              'target, per the audit\'s own suggested alternative');
    });
  });

  group('FOLLOWUP-J4: OTP auto-retrieval timeout clears the loading spinner',
      () {
    for (final path in [
      'lib/customer_register_flow.dart',
      'lib/technician_register_screen.dart',
    ]) {
      test('$path: codeAutoRetrievalTimeout sets _loading = false', () {
        final source = _read(path);
        final start = source.indexOf('codeAutoRetrievalTimeout:');
        expect(start, greaterThan(-1), reason: 'callback not found in $path');
        final end = source.indexOf('},', start);
        final block = source.substring(start, end);
        expect(block, contains('_loading = false'),
            reason: 'without this, a slow network that fires this timeout '
                'before codeSent leaves the send-OTP button stuck spinning');
      });
    }
  });
}
