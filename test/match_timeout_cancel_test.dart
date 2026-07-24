// ============================================================
// match_timeout_cancel_test.dart — LinTho App
//
// Regression test for FOLLOWUP-D: MatchScreen's 45s auto-timeout previously
// left the booking doc at status:'pending' instead of actually cancelling
// it — a provider that came online in that window could still accept a
// job the customer believed had already failed to find anyone.
//
// CustomerBookingRepository.cancelBooking() was already correct and
// transaction-guarded (see AUDIT H8 in match_screen.dart); the fix wires
// it into the timeout path via a new `_cancelSilently()` helper that does
// NOT pop the screen (the timeout needs to stay on the "no provider"
// screen), unlike the existing `_cancelBooking()` used by the manual
// cancel button (which does pop).
//
// ໝາຍເຫດ: ນີ້ແມ່ນ timer/widget-state logic, ບໍ່ມີ widget test harness ຢູ່ໃນ
// repo ນີ້ (ຄືກັນກັບ pattern ອື່ນໆ) — ໃຊ້ source-text regression guard.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  final source = _read('lib/match_screen.dart');

  group('FOLLOWUP-D: 45s search timeout actually cancels the booking', () {
    test('_startSearchTimer\'s timeout branch calls _cancelSilently before '
        'entering noProvider state', () {
      final start = source.indexOf('void _startSearchTimer()');
      final end = source.indexOf('void _startCountdown()');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('_cancelSilently('),
          reason: 'previously the timeout branch only set state to '
              'noProvider — the booking doc stayed status:\'pending\' for '
              'up to its full 10-minute expiry, so a provider coming '
              'online in that window could still accept a job the '
              'customer thinks already failed');
      // The cancel call must happen before the booking is left visually
      // "done" — i.e. it should appear before the setState(noProvider) line
      // within the same branch.
      final cancelIdx = block.indexOf('_cancelSilently(');
      final setStateIdx = block.indexOf("_state = _MatchState.noProvider");
      expect(cancelIdx, greaterThan(-1));
      expect(setStateIdx, greaterThan(cancelIdx));
    });

    test('_cancelSilently calls the repository\'s cancelBooking without '
        'popping the screen', () {
      final start = source.indexOf('Future<void> _cancelSilently(');
      expect(start, greaterThan(-1));
      final end = source.indexOf('\n  }', start);
      final block = source.substring(start, end);
      expect(block, contains('_customerBookingRepo.cancelBooking('));
      expect(block, isNot(contains('Navigator.pop')),
          reason: 'the timeout path must stay on the noProvider screen, '
              'unlike the manual-cancel _cancelBooking() which does pop');
    });

    test('the "go back" button on the no-provider screen does not call '
        'cancelBooking a second time (it would throw on an already-'
        'cancelled booking and show a confusing error toast)', () {
      final noProviderStart = source.indexOf('_buildNoProvider');
      final goBackIdx = source.indexOf("tr('go_back')", noProviderStart);
      expect(noProviderStart, greaterThan(-1));
      expect(goBackIdx, greaterThan(noProviderStart));
      // Look at the TextButton immediately preceding the go_back label.
      final buttonStart = source.lastIndexOf('TextButton(', goBackIdx);
      final onPressedBlock = source.substring(buttonStart, goBackIdx);
      expect(onPressedBlock, contains('Navigator.pop(context)'));
      expect(onPressedBlock, isNot(contains('_cancelBooking')));
    });
  });
}
