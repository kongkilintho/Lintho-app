// ============================================================
// medium_fixes_test.dart — LinTho App
//
// Regression tests for the Medium-severity findings (ME-1..ME-18, audit
// pass QA-1) that were already fixed in the working tree but — unlike the
// Critical/High findings — had no dedicated test coverage locking them in:
//   ME-1  — watchActiveBookings() is bounded (limit)
//   ME-2  — job-photo picker constrains image dimensions (maxWidth/maxHeight)
//   ME-3  — firestore.rules blocks customer-forged additionalCharges values
//   ME-4  — firestore.rules isVerifiedProvider() gates on KYC, not just role
//   ME-5  — Booking model carries landmark/specialInstructions/jobPhotoUrl
//   ME-6  — AC BTU size tiers have 3 distinct icons (no duplicate/wrong icon)
//   ME-7  — _QuickBookCard fully migrated to IconData (no emoji fallback)
//   ME-8  — "add to cart" button uses the tinted-fill ElevatedButton style
//   ME-9  — pest-control sqm dialog disables OK / shows error on invalid input
//   ME-10 — a manually-typed address must contain at least one digit
//   ME-11 — free-text fields have maxLength caps
//   ME-12 — booking submit is gated until live pricing has resolved
//   ME-13 — displayed room-price range reads from AppPricing.cleanRoomPrices
//   ME-14 — every GPS failure branch shows a SnackBar (no silent no-op)
//   ME-15 — bookingTotalLabel() prefers price (net of coupon) over grandTotal
//   ME-16 — a saved address's real GeoPoint is used when present
//   ME-17 — _submit() has a method-level in-flight guard
//   ME-18 — _submit() rejects a signed-out session before writing
//   FOLLOWUP-4 — CouponRepository.validate() rejects a coupon owned by
//                a different user (client-side half of the fix; the
//                server-side half is in test/rules_fixes_test.dart)
//
// ໝາຍເຫດ: pattern ດຽວກັນກັບ critical_fixes_test.dart / high_severity_fixes_test.dart
// — ບາງກຸ່ມທົດສອບພຶດຕິກຳຈິງ (fake_cloud_firestore / pure functions), ບາງກຸ່ມເປັນ
// source-text regression guard ສະເພາະ UI logic ທີ່ຝັງຢູ່ໃນ State class ບໍ່ໄດ້ export
// ອອກມາເປັນ function ແຍກ (ບໍ່ມີ test harness ໃຫ້ pump widget ໜັກແໜ້ນຢູ່ໃນ repo ນີ້).
// CouponRepository ໃຊ້ FirebaseFirestore.instance/FirebaseAuth.instance ໂດຍກົງ
// (ບໍ່ໄດ້ inject) ຄືກັນກັບ BookingRepository ໃນ critical_fixes_test.dart — ຈຶ່ງ
// reproduce ພຽງແຕ່ branch ownerId ຂຶ້ນມາທົດສອບແທນ (ຖ້າແກ້ logic ໃນ
// coupon_repository.dart, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ), ບວກກັບ source-text check ວ່າ
// check ຈິງຍັງຢູ່ໃນ source.
// ============================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/Booking.dart';
import 'package:lintho/booking_display_helpers.dart';
import 'package:lintho/booking_form_screen.dart' show AppPricing;

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════
  // ME-1 — watchActiveBookings() is bounded
  // ══════════════════════════════════════════════════════════
  group('ME-1: watchActiveBookings() is bounded (limit)', () {
    test('the active-jobs query has a .limit() like the other queries in the repo', () {
      final source = _read('lib/booking_repository.dart');
      final start = source.indexOf('Stream<List<Booking>> watchActiveBookings()');
      final end = source.indexOf('Stream<List<Booking>> watchJobHistory()');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);
      expect(method, contains('.limit('),
          reason: 'an unbounded active-jobs listener stays mounted for the '
              "whole app session and would re-download a provider's entire "
              'history on every open');
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-2 — job-photo picker constrains dimensions
  // ══════════════════════════════════════════════════════════
  group('ME-2: booking photo picker constrains image dimensions', () {
    test('pickImage() call passes maxWidth/maxHeight, not just imageQuality', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('maxWidth: 1600, maxHeight: 1600'),
          reason: 'imageQuality alone only controls JPEG compression, not '
              'pixel dimensions — modern phone cameras still upload '
              'multi-MB photos without an explicit size cap');
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-3 — firestore.rules blocks forged additionalCharges
  // ══════════════════════════════════════════════════════════
  group('ME-3: firestore.rules blocks customer-forged additionalCharges', () {
    test('isValidCustomerChargesResponse only allows the customer to null out the fields', () {
      final rules = _read('firestore.rules');
      final start = rules.indexOf('function isValidCustomerChargesResponse()');
      expect(start, greaterThan(-1));
      final end = rules.indexOf('}', rules.indexOf('}', start) + 1);
      final fn = rules.substring(start, end);
      expect(fn, contains("request.resource.data.additionalCharges == null"));
      expect(fn, contains("request.resource.data.additionalChargesNote == null"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-4 — isVerifiedProvider() gates on KYC status
  // ══════════════════════════════════════════════════════════
  group('ME-4: firestore.rules isVerifiedProvider() checks kycStatus', () {
    test('the function requires kycStatus == verified, not just role == provider', () {
      final rules = _read('firestore.rules');
      final start = rules.indexOf('function isVerifiedProvider()');
      final end = rules.indexOf('}', start);
      expect(start, greaterThan(-1));
      final fn = rules.substring(start, end);
      expect(fn, contains("kycStatus == 'verified'"),
          reason: 'role alone is self-declared at signup — without a KYC '
              'check, an unverified account could read customer PII off '
              'the open job board');
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-5 — Booking model carries landmark/specialInstructions/jobPhotoUrl
  // ══════════════════════════════════════════════════════════
  group('ME-5: Booking.fromFirestore parses landmark/specialInstructions/jobPhotoUrl', () {
    test('fields written at booking creation round-trip through the model', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('b1').set({
        'customerId': 'c1',
        'status': 'pending',
        'landmark': 'ຫຼັງຮ້ານກາເຟ',
        'specialInstructions': 'ມີໝາຢູ່ໃນເຮືອນ',
        'jobPhotoUrl': 'https://cloudinary.example/job.jpg',
        'scheduledAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.now(),
      });
      final doc = await db.collection('bookings').doc('b1').get();
      final booking = Booking.fromFirestore(doc);
      expect(booking.landmark, 'ຫຼັງຮ້ານກາເຟ');
      expect(booking.specialInstructions, 'ມີໝາຢູ່ໃນເຮືອນ');
      expect(booking.jobPhotoUrl, 'https://cloudinary.example/job.jpg');
    });

    test('job_workflow_Screen.dart actually displays these fields to the provider', () {
      final source = _read('lib/job_workflow_Screen.dart');
      expect(source, contains('.landmark'));
      expect(source, contains('.jobPhotoUrl'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-6 — AC BTU tiers have 3 distinct icons
  // ══════════════════════════════════════════════════════════
  group('ME-6: AC BTU size selector has 3 distinct icons', () {
    test('small/large/cabinet no longer share or misuse an icon', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('static const _items = [');
      final end = source.indexOf('];', start);
      expect(start, greaterThan(-1));
      final itemsList = source.substring(start, end);
      expect(itemsList, contains('Icons.ac_unit_outlined'));
      expect(itemsList, contains('Icons.ac_unit,'));
      expect(itemsList, contains('Icons.apartment_outlined'));
      expect(itemsList, isNot(contains('dns_outlined')),
          reason: 'a server-rack icon does not communicate "AC cabinet unit" '
              '— this checks only the actual _items literal, not the fix '
              "comment above it that references the old icon name by name");
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-7 — _QuickBookCard fully migrated off emoji
  // ══════════════════════════════════════════════════════════
  group('ME-7: _QuickBookCard uses IconData only, no emoji field', () {
    test('the widget has no emoji-typed field left to fall back to', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('class _QuickBookCard');
      final end = source.indexOf('class ', start + 20);
      final block = source.substring(start, end);
      expect(block, contains('final IconData icon;'));
      expect(block, isNot(contains('String emoji')));
    });

    test('_PaymentCard prefers the icon override over its emoji fallback', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('class _PaymentCard');
      final end = source.indexOf('class ', start + 20);
      final block = source.substring(start, end);
      expect(block, contains('if (icon != null)'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-8 — "add to cart" button style
  // ══════════════════════════════════════════════════════════
  group('ME-8: AC draft "add to cart" button uses the tinted-fill style', () {
    test('it is an ElevatedButton with a tinted primary background, not an outline', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('onPressed: () => _addAcDraftToCart(o)'));
      final start = source.indexOf('onPressed: () => _addAcDraftToCart(o)');
      final end = source.indexOf(';', start + 200);
      final block = source.substring(start, end);
      expect(block, contains('backgroundColor: C.primary.withValues(alpha: 0.1)'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-9 — pest-control sqm dialog validates input reactively
  // ══════════════════════════════════════════════════════════
  group('ME-9: pest-control sqm dialog disables OK on invalid input', () {
    test('canSubmit requires a strictly-positive parsed value', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('Future<void> _showPestSqmDialog');
      final end = source.indexOf('Future<void>', start + 50);
      final block = source.substring(start, end == -1 ? source.length : end);
      expect(block, contains('parsed != null && parsed > 0'));
      expect(block, contains('hasError'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-10 — manually-typed address requires a digit
  // ══════════════════════════════════════════════════════════
  group('ME-10: a hand-typed address must contain at least one digit', () {
    test('the guard is present and skipped for GPS-derived addresses', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('!_order!.isGpsAddress'));
      expect(source, contains(r"RegExp(r'\d').hasMatch(_order!.address)"));
    });

    test('the regex itself accepts "123 ຮ່ອມ 5" and rejects "aaaaa"', () {
      final withDigit = RegExp(r'\d').hasMatch('123 ຮ່ອມ 5');
      final noDigit = RegExp(r'\d').hasMatch('aaaaa');
      expect(withDigit, isTrue);
      expect(noDigit, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-11 — free-text fields have maxLength caps
  // ══════════════════════════════════════════════════════════
  group('ME-11: free-text fields are length-capped', () {
    test('maxLength appears at the notes/instructions fields', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('maxLength: 100'));
      expect(source, contains('maxLength: 200'));
      // 300 appears twice — maid notes and special-instructions fields
      final count = RegExp('maxLength: 300').allMatches(source).length;
      expect(count, greaterThanOrEqualTo(2));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-12 — submit gated until live pricing resolves
  // ══════════════════════════════════════════════════════════
  group('ME-12: booking submit is gated until live pricing resolves', () {
    test('_pricingLoaded starts false, is set after loadLive(), and gates step 4', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('bool          _pricingLoaded = false;'));
      expect(source, contains('await AppPricing.loadLive();'));
      expect(source, contains('setState(() => _pricingLoaded = true);'));
      expect(source, contains('case 4: return _pricingLoaded;'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-13 — displayed room price reads from the same source as pricing
  // ══════════════════════════════════════════════════════════
  group('ME-13: displayed room-price range matches AppPricing.cleanRoomPrices', () {
    test('cleanRoomPrices has min/max for both room tiers', () {
      final oneBed = AppPricing.cleanRoomPrices['1bed'];
      final twoBed = AppPricing.cleanRoomPrices['2bed'];
      expect(oneBed, isNotNull);
      expect(twoBed, isNotNull);
      expect(oneBed!['min'], lessThan(oneBed['max']!));
      expect(twoBed!['min'], lessThan(twoBed['max']!));
    });

    test('the room-tile builder reads minP/maxP from AppPricing.cleanRoomPrices, not a literal', () {
      final source = _read('lib/booking_form_screen.dart');
      expect(source, contains('AppPricing.cleanRoomPrices[r.\$1]'));
      expect(source, contains("minP: priceData?['min'] ?? 0"));
      expect(source, contains("maxP: priceData?['max'] ?? 0"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-14 — every GPS failure branch surfaces a SnackBar
  // ══════════════════════════════════════════════════════════
  group('ME-14: quick_booking_screen GPS failures always show a SnackBar', () {
    test('_useCurrentLocation has no silent early return', () {
      final source = _read('lib/quick_booking_screen.dart');
      final start = source.indexOf('Future<void> _useCurrentLocation()');
      final end = source.indexOf('void _useSavedAddress', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      // the 3 distinct failure branches (service disabled, permission denied
      // forever, unexpected exception) must each carry their own user-facing
      // message — a shared/missing message would silently look like a freeze
      expect(block, contains("tr('enable_gps_first')"));
      expect(block, contains("tr('gps_blocked')"));
      expect(block, contains('tr("gps_error")'));
      final snackbars = RegExp(r'showSnackBar').allMatches(block).length;
      expect(snackbars, greaterThanOrEqualTo(3));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-15 — bookingTotalLabel prefers price over grandTotal
  // ══════════════════════════════════════════════════════════
  group('ME-15: bookingTotalLabel() prefers price (net of coupon) over grandTotal', () {
    test('when both fields are present, the discounted price wins', () {
      final label = bookingTotalLabel({'price': 80000, 'grandTotal': 100000});
      expect(label, contains('80,000'));
      expect(label, isNot(contains('100,000')));
    });

    test('falls back to grandTotal when price is absent (older documents)', () {
      final label = bookingTotalLabel({'grandTotal': 100000});
      expect(label, contains('100,000'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-16 — saved address uses its real GeoPoint when present
  // ══════════════════════════════════════════════════════════
  group('ME-16: _useSavedAddress uses the saved GeoPoint when available', () {
    test('the call site reads saved.location instead of always geocoding', () {
      final source = _read('lib/quick_booking_screen.dart');
      final start = source.indexOf('void _useSavedAddress(SavedAddress saved)');
      final end = source.indexOf('void ', start + 20);
      final block = source.substring(start, end == -1 ? source.length : end);
      expect(block, contains('saved.location'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-17 — _submit() has a method-level in-flight guard
  // ══════════════════════════════════════════════════════════
  group('ME-17: booking_form_screen._submit() has a method-level guard', () {
    test('_submit returns immediately if already loading', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('Future<void> _submit()');
      final end = source.indexOf('setState(() => _loading = true);', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('if (_loading) return;'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-18 — _submit() rejects a signed-out session
  // ══════════════════════════════════════════════════════════
  group('ME-18: booking_form_screen._submit() checks currentUser before writing', () {
    test('a null currentUser shows a login prompt instead of hitting Firestore', () {
      final source = _read('lib/booking_form_screen.dart');
      final start = source.indexOf('Future<void> _submit()');
      final end = source.indexOf('setState(() => _loading = true);', start);
      final block = source.substring(start, end);
      expect(block, contains('FirebaseAuth.instance.currentUser'));
      expect(block, contains('if (user == null)'));
      expect(block, contains("tr('please_login_first')"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // FOLLOWUP-4 — coupon ownerId scoping
  // ══════════════════════════════════════════════════════════
  group('FOLLOWUP-4: CouponRepository.validate() rejects a mismatched owner', () {
    // ▸ ຄັດລອກ branch ownerId ຈາກ CouponRepository.validate()
    //   (coupon_repository.dart) — ຖ້າແກ້ logic ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<Map<String, dynamic>?> validateOwnerBranch(
        FakeFirebaseFirestore db, String code, String? currentUid) async {
      final doc = await db.collection('coupons').doc(code).get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;
      final ownerId = d['ownerId'] as String?;
      if (ownerId != null && ownerId != currentUid) return null;
      return d;
    }

    test('a coupon owned by a different user is rejected', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('coupons').doc('REWARD10').set({
        'ownerId': 'user-A',
        'status': 'active',
        'type': 'fixed',
        'value': 10000,
      });

      final result =
          await validateOwnerBranch(db, 'REWARD10', 'user-B');
      expect(result, isNull,
          reason: 'a personal reward-redeemed coupon must not be usable by '
              'anyone who merely obtained the code (e.g. a shared '
              'screenshot) before the real owner');
    });

    test('the true owner can still validate their own coupon', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('coupons').doc('REWARD10').set({
        'ownerId': 'user-A',
        'status': 'active',
        'type': 'fixed',
        'value': 10000,
      });

      final result =
          await validateOwnerBranch(db, 'REWARD10', 'user-A');
      expect(result, isNotNull);
    });

    test('a coupon with no ownerId (admin-issued) is usable by anyone', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('coupons').doc('PROMO2026').set({
        'status': 'active',
        'type': 'fixed',
        'value': 5000,
      });

      final result =
          await validateOwnerBranch(db, 'PROMO2026', 'anyone-at-all');
      expect(result, isNotNull);
    });

    test('coupon_repository.dart source still contains the ownerId check', () {
      final source = _read('lib/coupon_repository.dart');
      final start = source.indexOf('Future<CouponResult?> validate(');
      final end = source.indexOf('final minOrderAmount', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains("d['ownerId'] as String?"));
      expect(block, contains('ownerId != FirebaseAuth.instance.currentUser?.uid'));
    });
  });
}
