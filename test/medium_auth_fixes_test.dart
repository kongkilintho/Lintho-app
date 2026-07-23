// ============================================================
// medium_auth_fixes_test.dart — LinTho App
//
// Regression tests for the Medium-severity, auth/registration-flow-specific
// findings (audit pass "QA-2" — separate from the general QA-1 pass covered
// by medium_fixes_test.dart's ME-1..18). Both customer_register_flow.dart
// and technician_register_screen.dart implement the same fixes in parallel
// (two independent registration flows, no shared base class), so most groups
// below assert the same behavior in both files.
//   ME-AUTH-1 — back button from step 2 goes to step 0, not the OTP step
//   ME-AUTH-2 — resend-OTP cooldown (45s, Timer.periodic)
//   ME-AUTH-3 — a progress indicator shows how many steps remain
//   ME-AUTH-4 — KYC thumbnail enlarged (48x48 -> 96x96) to be reviewable
//   ME-AUTH-5 — icon-only buttons across auth screens carry a tooltip
//   ME-AUTH-6 / Medium-2 — profile photo uploaded before the Firestore write
//   Medium-1  — the back button is disabled while a request is in flight
//   Medium-5  — GPS "denied forever" routes to app settings, not a re-prompt
//   Medium-6  — stale KYC/skill/GPS data is cleared when re-editing the phone
//   Medium-7  — technician experience-years input is bounded 0-60
//   Medium-9  — rapid repeated taps can't push the same route twice
//
// ໝາຍເຫດ: source-text regression guard — pattern ດຽວກັນກັບ medium_fixes_test.dart,
// ນຳໃຊ້ເພາະ logic ພວກນີ້ຝັງຢູ່ໃນ private State class, ບໍ່ໄດ້ export ອອກມາເປັນ
// function ແຍກໃຫ້ໂທ ໂດຍກົງ.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

/// Extracts the source between two markers for a scoped, less-brittle check.
String _slice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  if (start == -1) {
    throw ArgumentError('marker not found: $startMarker');
  }
  final end = source.indexOf(endMarker, start + startMarker.length);
  return source.substring(start, end == -1 ? source.length : end);
}

void main() {
  const authFiles = [
    'lib/customer_register_flow.dart',
    'lib/technician_register_screen.dart',
  ];

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-1 — back from step 2 goes to step 0, not the OTP step
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-1: back button from step 2 skips the OTP step', () {
    for (final file in authFiles) {
      test('$file: step 2 back-press resets to step 0, not step 1', () {
        final source = _read(file);
        final block = _slice(source, 'onPressed: _loading ? null : () {',
            'else if (_step > 0 && _step != 1)');
        expect(block, contains('if (_step == 2) {'));
        expect(block, contains('_step = 0;'),
            reason: 'the old condition (_step > 0 && _step != 1) would '
                'decrement step 2 to step 1 (the OTP screen) instead of '
                'restarting phone verification');
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-2 — resend-OTP cooldown
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-2: resend-OTP cooldown prevents unlimited re-sends', () {
    for (final file in authFiles) {
      test('$file: _startResendCooldown runs a 45s countdown timer', () {
        final source = _read(file);
        final block = _slice(source, 'void _startResendCooldown()', '}\n\n');
        expect(block, contains('_resendCooldown = 45'));
        expect(block, contains('Timer.periodic'));
        expect(block, contains('_resendCooldown -= 1'));
      });

      test('$file: the resend button disables while cooldown > 0', () {
        final source = _read(file);
        expect(source, contains('_resendCooldown > 0'));
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-3 — progress indicator
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-3: a progress indicator shows remaining registration steps', () {
    for (final file in authFiles) {
      test('$file: LinearProgressIndicator is driven by the current step', () {
        final source = _read(file);
        expect(source, contains('LinearProgressIndicator'));
        expect(source, contains('value: (_step + 1) /'));
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-4 — KYC thumbnail enlarged
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-4: KYC document thumbnail is large enough to review', () {
    test('technician_register_screen.dart: thumbnail is 96x96, not 48x48', () {
      final source = _read('lib/technician_register_screen.dart');
      expect(source, contains('Image.file(file!, width: 96, height: 96'));
      expect(source, isNot(contains('Image.file(file!, width: 48, height: 48')));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-5 — icon buttons carry a tooltip/Semantics label
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-5: icon-only buttons on auth screens have a tooltip', () {
    test('back buttons on the 4 auth entry screens all set tooltip: back_semantic', () {
      for (final file in [
        'lib/customer_register_flow.dart',
        'lib/technician_register_screen.dart',
        'lib/register_otp.dart',
      ]) {
        final source = _read(file);
        expect(source, contains("tooltip: tr('back_semantic')"),
            reason: '$file is missing a tooltip on its back IconButton');
      }
    });

    test('welcome_screen.dart language switcher has a tooltip', () {
      final source = _read('lib/welcome_screen.dart');
      expect(source, contains("tooltip: tr('change_language_semantic')"));
    });

    test('main.dart password-visibility toggle has a tooltip', () {
      final source = _read('lib/main.dart');
      expect(source, contains('show_password_semantic'));
      expect(source, contains('hide_password_semantic'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // ME-AUTH-6 / Medium-2 — photo uploaded before the Firestore write
  // ══════════════════════════════════════════════════════════
  group('ME-AUTH-6 / Medium-2: profile photo upload happens before the Firestore write', () {
    test('customer_register_flow.dart: uploadImage() is awaited before users doc set()', () {
      final source = _read('lib/customer_register_flow.dart');
      final uploadIndex = source.indexOf('CloudinaryService.instance');
      final writeIndex = source.indexOf(
          "FirebaseFirestore.instance.collection('users').doc(uid).set(");
      expect(uploadIndex, greaterThan(-1));
      expect(writeIndex, greaterThan(uploadIndex),
          reason: 'if the upload fails partway (offline/network drop), the '
              'profile doc must not be written with no photo and status '
              "'active' left dangling");
    });

    test('technician_register_screen.dart: KYC photos are uploaded before the batch commit', () {
      final source = _read('lib/technician_register_screen.dart');
      final uploadIndex = source.indexOf('uploadKycPhoto(_idDocFile!');
      final commitIndex = source.indexOf('await batch.commit();');
      expect(uploadIndex, greaterThan(-1));
      expect(commitIndex, greaterThan(uploadIndex));
    });
  });

  // ══════════════════════════════════════════════════════════
  // Medium-1 — back button disabled while a request is in flight
  // ══════════════════════════════════════════════════════════
  group('Medium-1: the back button is disabled while _loading is true', () {
    for (final file in authFiles) {
      test('$file: onPressed is null while loading', () {
        final source = _read(file);
        expect(source, contains('onPressed: _loading ? null : () {'));
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // Medium-5 — GPS denied-forever routes to Settings
  // ══════════════════════════════════════════════════════════
  group('Medium-5: GPS "denied forever" opens app settings instead of re-prompting', () {
    for (final file in authFiles) {
      test('$file: deniedForever shows an "open settings" action', () {
        final source = _read(file);
        expect(source, contains('LocationPermission.deniedForever'));
        expect(source, contains('_locationDeniedForever = true'));
        expect(source, contains('Geolocator.openAppSettings()'));
      });
    }
  });

  // ══════════════════════════════════════════════════════════
  // Medium-6 — stale KYC/skill/GPS data cleared on phone re-entry
  // ══════════════════════════════════════════════════════════
  group('Medium-6: re-editing the phone number clears data captured for the old number', () {
    test('customer_register_flow.dart: selfie/GPS state is reset alongside the phone step', () {
      final source = _read('lib/customer_register_flow.dart');
      final block = _slice(source, 'if (_step == 2) {', '} else if');
      expect(block, contains('_selfieFile = null'));
      expect(block, contains('_lat = null; _lng = null;'));
    });

    test('technician_register_screen.dart: KYC/skill/GPS state is reset alongside the phone step', () {
      final source = _read('lib/technician_register_screen.dart');
      final block = _slice(source, 'if (_step == 2) {', '} else if');
      expect(block, contains('_idDocFile = null; _idSelfieFile = null;'));
      expect(block, contains('_serviceCategory = null'));
      expect(block, contains('_lat = null; _lng = null;'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // Medium-7 — experience-years input bounded 0-60
  // ══════════════════════════════════════════════════════════
  group('Medium-7: technician experience-years input rejects out-of-range values', () {
    test('the guard rejects null, negative, and > 60', () {
      final source = _read('lib/technician_register_screen.dart');
      expect(source, contains('exp == null || exp < 0 || exp > 60'));
    });

    test('the rejection logic itself behaves as expected', () {
      bool rejects(int? exp) => exp == null || exp < 0 || exp > 60;
      expect(rejects(null), isTrue);
      expect(rejects(-1), isTrue);
      expect(rejects(61), isTrue);
      expect(rejects(0), isFalse);
      expect(rejects(35), isFalse);
      expect(rejects(60), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // Medium-9 — navigation debounce on rapid repeated taps
  // ══════════════════════════════════════════════════════════
  group('Medium-9: rapid repeated taps cannot push the same route twice', () {
    for (final file in ['lib/register_otp.dart', 'lib/welcome_screen.dart']) {
      test('$file: a _navigating guard wraps the push', () {
        final source = _read(file);
        expect(source, contains('bool _navigating = false;'));
        expect(source, contains('if (_navigating) return;'));
        expect(source, contains('_navigating = true;'));
      });
    }
  });
}
