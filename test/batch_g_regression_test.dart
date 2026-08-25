// ============================================================
// batch_g_regression_test.dart — LinTho App
//
// Focused regression coverage for the fixes implemented in Phase 2 Batch G
// (the post-Batch-F full-system audit): KYC-2, LC-1, AUTH-2, LC-2/F1.
// firestore.rules has no rules-emulator harness wired into this repo (see
// test/rules_fixes_test.dart's header note) so KYC-2/LC-1/AUTH-2 use the
// same source-text regression-guard pattern already established there and
// in test/register_flow_test.dart. ProviderTransaction/ProviderProfile's
// fromFirestore() are plain Dart factories with no Firebase I/O of their
// own, so LC-2/F1 use fake_cloud_firestore to build a real DocumentSnapshot
// and exercise the actual parsing code — genuine behavioral coverage, not
// just a string check.
//
// Does NOT touch or rewrite any of the 12 pre-existing OOS-1 failing tests.
// ============================================================

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lintho/Booking.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════
  // KYC-2 — rejected/none→pending self-resubmit allowed, everything else
  // still denied
  // ══════════════════════════════════════════════════════════
  group('KYC-2: providers/{providerId} owner-update rule allows only the '
      'rejected|none -> pending kycStatus self-transition', () {
    final rules = _read('firestore.rules');
    final start = rules.indexOf('match /providers/{providerId}');
    final end = rules.indexOf('match /reviews/{reviewId}');
    late final String block;

    setUpAll(() {
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      block = rules.substring(start, end);
    });

    test('kycStatus is no longer in the owner-update blanket-blocked list', () {
      // Before the fix, 'kycStatus' sat in the same hasAny([...]) list as
      // isVerified/rejectReason/rating/etc — that also blocked the one
      // legitimate self-service write: a rejected provider resubmitting.
      expect(block, isNot(contains(
          "hasAny(['kycStatus', 'isVerified', 'rejectReason'")));
    });

    test('the owner-update rule still blocks isVerified/rejectReason/'
        'suspendReason/rating/totalJobs/completionRate/KYC doc URLs/phone', () {
      expect(block, contains(
          "hasAny(['isVerified', 'rejectReason', 'suspendReason',"));
      expect(block, contains('rating'));
      expect(block, contains('totalJobs'));
      expect(block, contains('completionRate'));
      expect(block, contains('kycDocUrl'));
      expect(block, contains('kycIdUrl'));
      expect(block, contains('kycSelfieUrl'));
      expect(block, contains('phone'));
    });

    test('kycStatus writes are gated to exactly the rejected|none -> pending '
        'transition', () {
      expect(block, contains(
          "resource.data.get('kycStatus', 'none') in ['none', 'rejected']"));
      expect(block, contains("request.resource.data.kycStatus == 'pending'"));
    });

    test('the admin-tier update branch is untouched and still permits '
        'kycStatus (verified/rejected/suspended come from here only)', () {
      expect(block, contains(
          "allow update: if getAdminRole() in ['super_admin', 'operations_admin']"));
      final adminStart = block.indexOf(
          "allow update: if getAdminRole() in ['super_admin', 'operations_admin']");
      final adminBlock = block.substring(adminStart);
      expect(adminBlock, isNot(contains('kycStatus')),
          reason: 'admin branch never explicitly excluded kycStatus — it '
              'was already free to set verified/rejected/suspended, and '
              'must remain so');
    });

    test('KYC document fields (kycDocUrl/kycIdUrl/kycSelfieUrl) are still '
        'never owner-writable on providers/{uid} — KYC-2 only relaxed '
        'kycStatus, not document access', () {
      expect(block, contains("!('kycDocUrl' in request.resource.data)"));
      expect(block, contains("!('kycIdUrl' in request.resource.data)"));
      expect(block, contains("!('kycSelfieUrl' in request.resource.data)"));
    });
  });

  // ══════════════════════════════════════════════════════════
  // LC-1 — RoleRouter's providers/{uid} stream has hasError handling
  // ══════════════════════════════════════════════════════════
  group('LC-1: RoleRouter provider-stream StreamBuilder handles hasError', () {
    final source = _read('lib/main.dart');
    final start = source.indexOf('class _RoleRouterState extends State<RoleRouter> {');
    final end = source.indexOf('return resolveRoleDestination(role: role, kycStatus: null);');

    test('the provider StreamBuilder checks provSnapshot.hasError before '
        'reading kycStatus', () {
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);
      expect(block, contains('provSnapshot.hasError'));
      expect(block, contains('ErrorStateView('));
      // Retry must actually resubscribe (same _retryTick mechanism as the
      // sibling users/{uid} stream a few lines above it), not be a dead button.
      expect(block, contains('onRetry: () => setState(() => _retryTick++)'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // AUTH-2 — _loginWithGoogle() checks admin@sabee.la before any Firestore
  // role read/write
  // ══════════════════════════════════════════════════════════
  group('AUTH-2: _loginWithGoogle() short-circuits admin@sabee.la before '
      'role/kycStatus provisioning', () {
    final source = _read('lib/main.dart');
    final start = source.indexOf('Future<void> _loginWithGoogle()');
    final end = source.indexOf('Future<void> _forgotPassword()');
    late final String block;

    setUpAll(() {
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      block = source.substring(start, end);
    });

    test('the admin check appears before the role/Firestore-write block', () {
      final adminCheckIndex = block.indexOf("user?.email == 'admin@sabee.la'");
      final roleWriteIndex = block.indexOf("'role':        'customer',");
      expect(adminCheckIndex, greaterThan(-1),
          reason: 'admin@sabee.la must never fall through to normal '
              'role/kycStatus provisioning below');
      expect(roleWriteIndex, greaterThan(-1));
      expect(adminCheckIndex, lessThan(roleWriteIndex),
          reason: 'the admin short-circuit must run before the users/{uid} '
              "doc.set({'role': 'customer', ...}) write — otherwise the "
              'admin account gets a permanent role:customer doc (role is '
              'immutable in firestore.rules)');
    });

    test('the admin branch navigates to _AdminRedirectScreen and returns '
        'without falling through', () {
      final adminCheckIndex = block.indexOf("user?.email == 'admin@sabee.la'");
      final nearby = block.substring(adminCheckIndex, adminCheckIndex + 400);
      expect(nearby, contains('_AdminRedirectScreen()'));
      expect(nearby, contains('if (!mounted) return;'));
    });
  });

  // ══════════════════════════════════════════════════════════
  // LC-2 / F1 — ProviderTransaction.fromFirestore is malformed-data safe
  // (behavioral, via fake_cloud_firestore — not source-text)
  // ══════════════════════════════════════════════════════════
  group('LC-2/F1: ProviderTransaction.fromFirestore survives malformed docs', () {
    test('a doc missing type/amount/description/createdAt does not throw '
        'and uses safe defaults', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('transactions').doc('tx-missing').set({
        'providerId': 'p1',
      });
      final doc = await db.collection('transactions').doc('tx-missing').get();

      expect(() => ProviderTransaction.fromFirestore(doc), returnsNormally);
      final tx = ProviderTransaction.fromFirestore(doc);
      expect(tx.type, TxType.adjustment);
      expect(tx.amount, 0);
      expect(tx.description, '');
      expect(tx.providerId, 'p1');
    });

    test('a non-null but invalid "type" string falls back to adjustment '
        'instead of throwing (Batch F only null-hardened this, Batch G '
        'F1 hardened the invalid-value case)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('transactions').doc('tx-bad-type').set({
        'providerId': 'p1',
        'type': 'not_a_real_tx_type',
        'amount': 5000,
        'description': 'legacy doc',
      });
      final doc =
          await db.collection('transactions').doc('tx-bad-type').get();

      expect(() => ProviderTransaction.fromFirestore(doc), returnsNormally);
      final tx = ProviderTransaction.fromFirestore(doc);
      expect(tx.type, TxType.adjustment);
      expect(tx.amount, 5000);
    });

    test('a valid "type" string still parses to the correct enum value '
        '(the fix must not change valid-data behavior)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('transactions').doc('tx-good').set({
        'providerId': 'p1',
        'type': 'earning',
        'amount': 20000,
      });
      final doc = await db.collection('transactions').doc('tx-good').get();
      final tx = ProviderTransaction.fromFirestore(doc);
      expect(tx.type, TxType.earning);
    });
  });

  group('F1: ProviderProfile.kycStatus survives an invalid enum string', () {
    test('a non-null but invalid kycStatus string falls back to none '
        'instead of throwing', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('providers').doc('p1').set({
        'displayName': 'Test Provider',
        'email': 't@example.com',
        'kycStatus': 'bogus_legacy_status',
      });
      final doc = await db.collection('providers').doc('p1').get();

      expect(() => ProviderProfile.fromFirestore(doc), returnsNormally);
      expect(ProviderProfile.fromFirestore(doc).kycStatus, KycStatus.none);
    });

    test('a valid kycStatus string still parses correctly', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('providers').doc('p2').set({
        'displayName': 'Test Provider 2',
        'email': 't2@example.com',
        'kycStatus': 'verified',
      });
      final doc = await db.collection('providers').doc('p2').get();
      expect(ProviderProfile.fromFirestore(doc).kycStatus, KycStatus.verified);
    });
  });
}
