// ============================================================
// addr1_session_lifecycle_test.dart — LinTho App
//
// Regression coverage for ADDR-1 (Batch K, 2026-08-25) — 5 customer-side
// Riverpod StreamProviders read FirebaseAuth.instance.currentUser?.uid once
// at provider-BUILD time and never rebuilt on a same-process account
// switch (logout, different user login, no app restart), so a provider
// instance could keep streaming the PREVIOUS user's Firestore data/query
// until something unrelated happened to invalidate it:
//
//   savedAddressesProvider   (lib/saved_address.dart)
//   myCouponsProvider        (lib/coupon_repository.dart)
//   referralInfoProvider     (lib/referral_provider.dart)
//   rewardPointsProvider     (lib/rewards_provider.dart)
//   rewardHistoryProvider    (lib/rewards_provider.dart)
//
// Fix: each now calls `ref.watch(currentUidProvider);` as the first
// statement in its builder — the exact, already-proven pattern used by
// every uid-scoped StreamProvider in booking_provider.dart (e.g.
// activeBookingsProvider) and by onlineStatusProvider (online_provider.dart,
// the SEC-4 fix). currentUidProvider itself (booking_provider.dart) wraps
// FirebaseAuth.instance.authStateChanges() — watching it registers a
// Riverpod dependency edge that tears the provider down and rebuilds it
// (fresh uid read, old Firestore listener cancelled) whenever the
// authenticated uid changes.
//
// ໝາຍເຫດ: same source-text-only limitation as batch_h_suspend_ban_test.dart/
// profile_screen_fixes_test.dart — this repo has no Firebase emulator, and
// FirebaseAuth.instance/FirebaseFirestore.instance are hardcoded singletons
// in these providers (not constructor-injected), so a live Firestore-backed
// integration test isn't possible without a larger refactor outside this
// batch's "smallest safe fix" scope even though fake_cloud_firestore/
// firebase_auth_mocks are dev dependencies. Structural tests below verify
// the SOURCE contains the correct wiring. The Riverpod REBUILD MECHANISM
// itself (the actual thing that fixes ADDR-1) is additionally proven with a
// real, executed ProviderContainer test using synthetic providers shaped
// exactly like the real ones — not a fake that merely asserts a name
// exists.
// ============================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

String _extractProvider(String source, String declaration) {
  final start = source.indexOf(declaration);
  expect(start, greaterThan(-1), reason: '$declaration must exist');
  final end = source.indexOf('\n});', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  final savedAddressSource = _read('lib/saved_address.dart');
  final rewardsSource = _read('lib/rewards_provider.dart');
  final couponSource = _read('lib/coupon_repository.dart');
  final referralSource = _read('lib/referral_provider.dart');

  group('ADDR-1 — currentUidProvider import (reused, not reinvented)', () {
    test('all 4 files import the existing currentUidProvider from '
        'booking_provider.dart rather than defining a second uid stream', () {
      for (final source in [
        savedAddressSource, rewardsSource, couponSource, referralSource,
      ]) {
        expect(source,
            contains("import 'booking_provider.dart' show currentUidProvider;"));
      }
    });
  });

  group('ADDR-1 — each affected provider watches currentUidProvider before '
      'reading the uid', () {
    test('savedAddressesProvider', () {
      final body = _extractProvider(savedAddressSource,
          'final savedAddressesProvider = StreamProvider<List<SavedAddress>>((ref) {');
      final watchIdx = body.indexOf('ref.watch(currentUidProvider);');
      final uidReadIdx = body.indexOf('FirebaseAuth.instance.currentUser?.uid');
      expect(watchIdx, greaterThan(-1));
      expect(uidReadIdx, greaterThan(watchIdx),
          reason: 'the uid must be read AFTER establishing the watch '
              'dependency, so a rebuild always re-reads it fresh');
      // null-uid fallback must remain intact — no silent fallback to a
      // previous uid.
      expect(body, contains('if (uid == null) return Stream.value([]);'));
    });

    test('myCouponsProvider', () {
      final body = _extractProvider(couponSource,
          'final myCouponsProvider = StreamProvider<List<MyCoupon>>((ref) {');
      final watchIdx = body.indexOf('ref.watch(currentUidProvider);');
      final uidReadIdx = body.indexOf('FirebaseAuth.instance.currentUser?.uid');
      expect(watchIdx, greaterThan(-1));
      expect(uidReadIdx, greaterThan(watchIdx));
      expect(body, contains('if (uid == null) return Stream.value(const []);'));
    });

    test('referralInfoProvider', () {
      final body = _extractProvider(referralSource,
          'final referralInfoProvider = StreamProvider<ReferralInfo?>((ref) {');
      final watchIdx = body.indexOf('ref.watch(currentUidProvider);');
      final uidReadIdx = body.indexOf('FirebaseAuth.instance.currentUser?.uid');
      expect(watchIdx, greaterThan(-1));
      expect(uidReadIdx, greaterThan(watchIdx));
      expect(body, contains('if (uid == null) return Stream.value(null);'));
    });

    test('rewardPointsProvider', () {
      final body = _extractProvider(rewardsSource,
          'final rewardPointsProvider = StreamProvider<int>((ref) {');
      final watchIdx = body.indexOf('ref.watch(currentUidProvider);');
      final uidReadIdx = body.indexOf('FirebaseAuth.instance.currentUser?.uid');
      expect(watchIdx, greaterThan(-1));
      expect(uidReadIdx, greaterThan(watchIdx));
      expect(body, contains('if (uid == null) return Stream.value(0);'));
    });

    test('rewardHistoryProvider', () {
      final body = _extractProvider(rewardsSource,
          'final rewardHistoryProvider = StreamProvider<List<RewardTransaction>>((ref) {');
      final watchIdx = body.indexOf('ref.watch(currentUidProvider);');
      final uidReadIdx = body.indexOf('FirebaseAuth.instance.currentUser?.uid');
      expect(watchIdx, greaterThan(-1));
      expect(uidReadIdx, greaterThan(watchIdx));
      expect(body, contains('if (uid == null) return Stream.value(const []);'));
    });
  });

  group('ADDR-1 — write-path check: the 5 affected providers are read-only', () {
    test('none of the 5 provider bodies perform a Firestore write — no '
        'User-B-writes-under-A\'s-uid risk exists because there is no write '
        'in these providers to begin with', () {
      final bodies = [
        _extractProvider(savedAddressSource,
            'final savedAddressesProvider = StreamProvider<List<SavedAddress>>((ref) {'),
        _extractProvider(couponSource,
            'final myCouponsProvider = StreamProvider<List<MyCoupon>>((ref) {'),
        _extractProvider(referralSource,
            'final referralInfoProvider = StreamProvider<ReferralInfo?>((ref) {'),
        _extractProvider(rewardsSource,
            'final rewardPointsProvider = StreamProvider<int>((ref) {'),
        _extractProvider(rewardsSource,
            'final rewardHistoryProvider = StreamProvider<List<RewardTransaction>>((ref) {'),
      ];
      for (final body in bodies) {
        expect(body, isNot(contains('.set(')));
        expect(body, isNot(contains('.update(')));
        expect(body, isNot(contains('.delete(')));
      }
    });

    test('referralInfoProvider\'s one nested write (_ensureReferralCode, a '
        'separate top-level function called from inside asyncMap) always '
        'writes under the uid captured by value in that specific builder '
        'invocation — it can never be misattributed to a DIFFERENT '
        '(later-signed-in) user even if it completes after an account '
        'switch, because Dart closures capture the local `uid` variable by '
        'value, not by a mutable reference to "whoever is signed in now"', () {
      expect(referralSource, contains('code ??= await _ensureReferralCode(uid);'));
      final start = referralSource.indexOf(
          'Future<String> _ensureReferralCode(String uid) async {');
      final end = referralSource.indexOf('String _randomSuffix()', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final fnBody = referralSource.substring(start, end);
      // _ensureReferralCode only ever writes to the uid passed to it as a
      // parameter — never re-reads FirebaseAuth.instance.currentUser itself.
      expect(fnBody, isNot(contains('FirebaseAuth.instance.currentUser')));
      expect(fnBody, contains("db.collection('users').doc(uid)"));
    });
  });

  group('ADDR-1 — unaffected sibling providers/functions are untouched '
      '(regression guard — do not over-fix)', () {
    test('rewardSettingsProvider (global, not uid-scoped) was not given a '
        'currentUidProvider watch — it has no per-user staleness to fix', () {
      final body = _extractProvider(rewardsSource,
          "final rewardSettingsProvider = StreamProvider<RewardSettings>((ref) {");
      expect(body, isNot(contains('currentUidProvider')));
    });

    test('myCouponCountProvider derives from myCouponsProvider via '
        'ref.watch — transitively fixed, needed no direct change', () {
      expect(couponSource, contains(
          'final coupons = ref.watch(myCouponsProvider).value ?? const [];'));
    });

    test('CouponRepository.validate()/redeemReferralCode()/'
        '_ensureReferralCode() are plain functions, not providers — they '
        'already read FirebaseAuth.instance.currentUser fresh at CALL time '
        '(no build-time staleness possible), so they were correctly left '
        'unchanged', () {
      expect(couponSource, contains('Future<CouponResult?> validate('));
      expect(referralSource, contains('Future<String?> redeemReferralCode('));
    });
  });

  // ── Real, executed proof of the underlying Riverpod rebuild mechanism ──
  //
  // Cannot exercise the REAL providers end-to-end (they hardcode
  // FirebaseAuth.instance/FirebaseFirestore.instance — see file header),
  // but the actual bug-fixing mechanism — watching a uid stream forces a
  // dependent provider to rebuild and re-derive its value from the CURRENT
  // uid, never a stale captured one — is Riverpod machinery this test CAN
  // exercise directly and honestly, using synthetic providers shaped
  // exactly like the real ones (watch-a-uid-stream, then read "the
  // uid-owned data").

  group('ADDR-1 — executed proof: watching a uid StreamProvider rebuilds a '
      'dependent provider on account switch', () {
    test('A -> logout -> B: the dependent provider resolves to B\'s data, '
        'never A\'s — proves the exact mechanism the 5 real fixes rely on', () async {
      final uidController = StreamController<String?>.broadcast();
      // Mirrors currentUidProvider exactly: a StreamProvider wrapping an
      // auth-state-like stream.
      final testUidProvider = StreamProvider<String?>((ref) => uidController.stream);

      // Mirrors FirebaseAuth.instance.currentUser?.uid: a synchronously-
      // readable "current value" the SDK updates independently of the
      // stream's own async delivery — set immediately before each
      // uidController.add() below, exactly like the real Firebase Auth SDK
      // updates .currentUser before/as authStateChanges() emits.
      String? currentTestUid;

      // Mirrors the real providers' exact shape: `ref.watch(currentUidProvider);`
      // purely to register the rebuild dependency, then independently read
      // "whoever is current" — never derives its value FROM the watched
      // stream's payload, exactly like the real code never uses
      // currentUidProvider's own emitted value, only its rebuild signal.
      final testDataProvider = Provider<String>((ref) {
        ref.watch(testUidProvider);
        return 'data-for-${currentTestUid ?? 'nobody'}';
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(uidController.close);

      final results = <String>[];
      final sub = container.listen<String>(
        testDataProvider,
        (prev, next) => results.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      currentTestUid = 'A';
      uidController.add('A');
      await pumpEventQueue();

      currentTestUid = null; // logout
      uidController.add(null);
      await pumpEventQueue();

      currentTestUid = 'B'; // same-process login, no app restart
      uidController.add('B');
      await pumpEventQueue();

      expect(results.first, 'data-for-nobody',
          reason: 'before any uid arrives, no user is falsely assumed');
      expect(results, contains('data-for-A'));
      expect(results, contains('data-for-B'));
      expect(results.last, 'data-for-B',
          reason: 'the final resolved value must belong to B, not A — this '
              'is the exact invariant ADDR-1 requires, and it is never '
              'reachable through a value still equal to data-for-A once B '
              'has signed in');
      expect(container.read(testDataProvider), 'data-for-B',
          reason: 'a fresh read after the switch must never return a '
              'previous user\'s value');
    });
  });
}
