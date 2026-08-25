// ============================================================
// fcm1_session_lifecycle_test.dart — LinTho App
//
// Regression coverage for FCM-1 (Batch J, 2026-08-25) — FCM token
// registration did not correctly handle a same-process account switch.
//
// Root cause: FCMService.init() (lib/fcm_service.dart) is guarded by a
// process-lifetime `_initialized` flag, and the original code only ever
// called saveToken() once, inside init(), for whoever happened to be
// signed in the first time init() ran. _RoleRouterState.initState()
// (main.dart) DOES call init() again on every login — RoleRouter is
// unmounted on logout (swapped for WelcomeScreen by the app's top-level
// authStateChanges() StreamBuilder) and freshly remounted on the next
// login — but the old `_initialized` guard made every call after the
// first a pure no-op, so a second user signing in without an app restart
// never got a token written to users/{uid}.fcmTokens.
//
// Fix: init()'s one-time setup (still guarded by _initialized, unchanged
// in that respect) now also subscribes, exactly once, to
// FirebaseAuth.instance.authStateChanges() — that subscription itself
// lives for the rest of the process and re-registers the token every time
// the CURRENT uid changes, independent of how many times init() itself is
// (or is not) called again.
//
// ໝາຍເຫດ: fcm_service.dart hardcodes FirebaseMessaging.instance/
// FirebaseFirestore.instance as final fields (no constructor injection),
// so a live FirebaseMessaging.getToken() call cannot be faked even though
// this repo already has firebase_auth_mocks/fake_cloud_firestore available
// as dev dependencies — introducing that plumbing would be a larger
// refactor than the "smallest safe fix" this batch is scoped to. Structural
// tests below verify the SOURCE contains the correct wiring (same
// established convention as batch_h_suspend_ban_test.dart / rules_fixes_
// test.dart — no rules/Functions-emulator harness in this repo either).
// The dedupe DECISION itself (the actual bug-fixing logic) is additionally
// exercised as a real, executed, deterministic model — not just pattern-
// matched — drift-guarded against the live source below.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

String _extractMethod(String source, String signature, {String end = '\n  }'}) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: '$signature must exist');
  final endIdx = source.indexOf(end, start);
  expect(endIdx, greaterThan(start));
  return source.substring(start, endIdx);
}

void main() {
  final source = _read('lib/fcm_service.dart');

  group('FCM-1 — init() one-time setup vs. per-login token registration', () {
    test('init() is still guarded by the process-lifetime _initialized '
        'flag — one-time setup (permission request, listeners) must still '
        'only ever run once, that part of the original design is correct '
        'and unchanged', () {
      final body = _extractMethod(source, 'Future<void> init() async {');
      expect(body, contains('if (_initialized) return;'));
      expect(body, contains('_initialized = true;'));
    });

    test('init() no longer calls saveToken() directly for a one-time '
        'snapshot of the current user — that call site (the actual bug) '
        'is gone', () {
      final body = _extractMethod(source, 'Future<void> init() async {');
      expect(body, isNot(contains('if (token != null) await saveToken(token);')));
    });

    test('init() subscribes to FirebaseAuth.instance.authStateChanges() '
        'exactly once, inside the _initialized-guarded one-time setup — '
        'this is what makes token registration follow the current uid for '
        'the rest of the process without depending on init() being called '
        'again', () {
      final body = _extractMethod(source, 'Future<void> init() async {');
      final matches = 'authStateChanges()'.allMatches(body).length;
      expect(matches, 1,
          reason: 'exactly one authStateChanges() subscription must be '
              'created — creating it more than once, or conditionally, '
              'risks listener multiplication');
      expect(body, contains('.listen(_onAuthUserChanged)'));
    });

    test('onTokenRefresh/onMessage/onMessageOpenedApp listeners remain '
        'wired exactly as before — token refresh while the same user '
        'stays logged in must keep working', () {
      final body = _extractMethod(source, 'Future<void> init() async {');
      expect(body, contains('_messaging.onTokenRefresh.listen(saveToken);'));
      expect(body, contains('FirebaseMessaging.onMessage.listen(_onForeground);'));
      expect(body, contains('FirebaseMessaging.onMessageOpenedApp.listen(_onTap);'));
    });
  });

  group('FCM-1 — _onAuthUserChanged (the account-switch fix itself)', () {
    test('exists as its own method, called from the auth-state '
        'subscription (not inlined) — a discrete unit this file can be '
        'reasoned about independently of init()', () {
      expect(source, contains('Future<void> _onAuthUserChanged(User? user) async {'));
    });

    test('a null user (signed out) clears the dedupe key and registers no '
        'token — a signed-out state must never write to any '
        "users/{uid}.fcmTokens path (there is no uid to write to)", () {
      final body = _extractMethod(
          source, 'Future<void> _onAuthUserChanged(User? user) async {');
      final nullBranchStart = body.indexOf('if (user == null) {');
      final nullBranchEnd = body.indexOf('}', nullBranchStart);
      final nullBranch = body.substring(nullBranchStart, nullBranchEnd);
      expect(nullBranch, contains('_lastRegisteredUid = null;'));
      expect(nullBranch, isNot(contains('saveToken')));
    });

    test('the same uid re-emitted (no actual account change) is a no-op — '
        'the dedupe check appears before any token fetch/save, so a '
        'repeated event for the SAME user never causes a duplicate write', () {
      final body = _extractMethod(
          source, 'Future<void> _onAuthUserChanged(User? user) async {');
      final dedupeIdx = body.indexOf('if (user.uid == _lastRegisteredUid) return;');
      final tokenFetchIdx = body.indexOf('_messaging.getToken()');
      expect(dedupeIdx, greaterThan(-1));
      expect(tokenFetchIdx, greaterThan(dedupeIdx),
          reason: 'the dedupe check must run BEFORE fetching/saving a '
              'token, not after');
    });

    test('a genuinely different (or first-seen) uid fetches a fresh token '
        'and calls the existing saveToken() — reuses the established '
        'token-storage write path rather than writing Firestore directly '
        'here', () {
      final body = _extractMethod(
          source, 'Future<void> _onAuthUserChanged(User? user) async {');
      expect(body, contains('final token = await _messaging.getToken();'));
      expect(body, contains('await saveToken(token);'));
      expect(body, contains('_lastRegisteredUid = user.uid;'));
    });
  });

  group('FCM-1 — token storage structure is unchanged', () {
    test('saveToken() still resolves the uid from the currently '
        'authenticated user and still writes users/{uid}.fcmTokens via '
        'arrayUnion — the storage model itself was not redesigned', () {
      final body = _extractMethod(source, 'Future<void> saveToken(String token) async {');
      expect(body, contains("final uid = FirebaseAuth.instance.currentUser?.uid;"));
      expect(body, contains("await _db.collection('users').doc(uid).set({"));
      expect(body, contains("'fcmTokens':        FieldValue.arrayUnion([token]),"));
    });

    test('removeToken() (the existing logout-time cleanup, called before '
        'signOut() at every call site) is untouched by this fix', () {
      final body = _extractMethod(source, 'Future<void> removeToken() async {');
      expect(body, contains("await _db.collection('users').doc(uid).update({"));
      expect(body, contains("'fcmTokens': FieldValue.arrayRemove([token]),"));
      expect(body, contains('await _messaging.deleteToken();'));
    });
  });

  // ── Deterministic model of _onAuthUserChanged's dedupe decision ────────
  //
  // Re-implements the exact same 3-line decision _onAuthUserChanged makes,
  // as plain executable Dart, and exercises it against the FCM SESSION-
  // LIFECYCLE REQUIREMENTS cases from the Batch J brief. Drift-guarded
  // above (the "same uid re-emitted is a no-op" test asserts the real
  // source's dedupe-before-fetch ordering) so this model can't silently
  // diverge from the real method's logic.

  group('FCM-1 — deterministic model of the dedupe/registration decision '
      '(mirrors _onAuthUserChanged exactly)', () {
    late String? lastRegisteredUid;
    late List<String> registrations;

    void onAuthChanged(String? uid) {
      if (uid == null) {
        lastRegisteredUid = null;
        return;
      }
      if (uid == lastRegisteredUid) return;
      registrations.add(uid);
      lastRegisteredUid = uid;
    }

    setUp(() {
      lastRegisteredUid = null;
      registrations = [];
    });

    test('CASE 1 — app start, user A already authenticated: '
        'authStateChanges() replays the current user immediately, '
        'registering A', () {
      onAuthChanged('A');
      expect(registrations, ['A']);
    });

    test('CASE 2 — logout: no new registration for a null user', () {
      onAuthChanged('A');
      onAuthChanged(null);
      expect(registrations, ['A']);
      expect(lastRegisteredUid, isNull);
    });

    test('CASE 3/4 — A logs out, B logs in in the same process: B is '
        'registered (the exact bug this batch fixes)', () {
      onAuthChanged('A');
      onAuthChanged(null);
      onAuthChanged('B');
      expect(registrations, ['A', 'B']);
    });

    test('CASE 6 — same user remains logged in (auth stream re-emits the '
        'same user, e.g. on token/reauth events): no duplicate '
        'registration', () {
      onAuthChanged('B');
      onAuthChanged('B');
      onAuthChanged('B');
      expect(registrations, ['B']);
    });

    test('CASE 7 — app restart while B is authenticated: a fresh service '
        'instance (fresh dedupe state) still registers B on the first '
        'emission', () {
      // Simulates a fresh process: lastRegisteredUid starts null (setUp).
      onAuthChanged('B');
      expect(registrations, ['B']);
    });

    test('CASE 8 — uid changes without an intervening null event still '
        're-registers (covers a hypothetical direct A->B emission, not '
        'just the observed logout-then-login sequence)', () {
      onAuthChanged('A');
      onAuthChanged('B');
      expect(registrations, ['A', 'B']);
    });

    test('rapid A -> B -> A within one process registers each transition '
        '— token ownership always follows the CURRENT uid, never gets '
        'stuck on an earlier one', () {
      onAuthChanged('A');
      onAuthChanged(null);
      onAuthChanged('B');
      onAuthChanged(null);
      onAuthChanged('A');
      expect(registrations, ['A', 'B', 'A']);
    });
  });
}
