// ============================================================
// quick_booking_false_failure_test.dart — LinTho App
//
// Regression test for FOLLOWUP-F: QuickBookingNotifier.confirmBooking()
// (quick_booking_provider.dart) wrapped both repo.createBooking(...) and an
// unrelated "save as default address" write in one try/catch — a failure
// in the latter reported total booking failure even though a live,
// unattended booking already existed in Firestore.
//
// ໝາຍເຫດ: confirmBooking() ໃຊ້ CustomerBookingRepository (ບໍ່ໄດ້ inject) ຄືກັນ
// ກັບ pattern ອື່ນໆ — ບໍ່ສາມາດ simulate write ລົ້ມເຫລວກາງທາງດ້ວຍ
// fake_cloud_firestore ໄດ້ຢ່າງແທ້ຈິງ (mock ບໍ່ throw ແບບ network partial
// failure) — ໃຊ້ source-text regression guard ຢືນຢັນວ່າ try/catch ຖືກແຍກແລ້ວ.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('FOLLOWUP-F: confirmBooking() separates createBooking from the '
      'best-effort address save', () {
    final source = _read('lib/quick_booking_provider.dart');
    final start = source.indexOf('Future<String?> confirmBooking(');
    final end = source.indexOf('final quickBookingProvider =');

    test('the address-save block has its own try/catch, not shared with '
        'createBooking()', () {
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);

      final createIdx = block.indexOf('repo.createBooking(');
      final addressTryIdx = block.indexOf('if (state.saveAsDefaultAddress)');
      expect(createIdx, greaterThan(-1));
      expect(addressTryIdx, greaterThan(createIdx),
          reason: 'the address save must come after booking creation');

      // The address-save section must contain its own try/catch.
      final addressSection = block.substring(addressTryIdx);
      final addressSectionEnd = addressSection.indexOf('state = const QuickBookingDraft();');
      final scoped = addressSection.substring(0, addressSectionEnd);
      expect(scoped, contains('try {'));
      expect(scoped, contains('} catch (e) {'));
      expect(scoped, contains('debugPrint('),
          reason: 'an address-save failure must not rethrow into the '
              'outer catch — it should be logged and ignored since the '
              'booking already succeeded');
    });

    test('return id happens unconditionally after the address-save '
        'try/catch, not inside it', () {
      final block = source.substring(start, end);
      final returnIdx = block.indexOf('return id;');
      final addressCatchIdx = block.lastIndexOf('debugPrint(', returnIdx);
      expect(returnIdx, greaterThan(-1));
      expect(addressCatchIdx, greaterThan(-1));
      expect(returnIdx, greaterThan(addressCatchIdx));
    });
  });
}
