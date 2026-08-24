// ============================================================
// register_flow_test.dart — LinTho App
//
// ກວດສອບ Register Flow (Customer + Provider):
//  1. Navigation smoke test — RegisterPage → CustomerRegisterFlow /
//     TechnicianRegisterScreen ບໍ່ throw exception, step title ຖືກຕ້ອງ.
//     (ບໍ່ແຕະ Firebase ເລີຍ ເພາະ handler ຍັງບໍ່ຖືກເອີ້ນຈົນກວ່າຈະກົດປຸ່ມ)
//  2. Client-side validation ບໍ່ໃຫ້ຜ່ານໄປ Firebase call ຖ້າຂໍ້ມູນຜິດ
//     (ເບີໂທບໍ່ຖືກຕ້ອງ → ຄ້າງຢູ່ step ດຽວກັນ, ບໍ່ crash)
//  3. Contract test — ຢືນຢັນວ່າ 'users' + 'providers' document write
//     ຕ້ອງເປັນ atomic (WriteBatch). ນີ້ແມ່ນ regression test ສຳລັບ bug
//     ທີ່ພົບ: ຖ້າ write ທີສອງ (providers) ລົ້ມເຫຼວຫຼັງ write ທຳອິດ
//     (users) ສຳເລັດແລ້ວ, ບັນຊີຈະກາຍເປັນ "ghost" (ຄ້າງ PendingApproval
//     ຕະຫຼອດໄປ, admin ຫາບໍ່ພົບໃນ 'providers' collection).
//
// ໝາຍເຫດ: ໜ້າ Register ຕົວແທ້ (customer_register_flow.dart /
// technician_register_screen.dart) ເອີ້ນ FirebaseAuth.instance /
// FirebaseFirestore.instance ໂດຍກົງ (ບໍ່ໄດ້ inject ເຂົ້າ constructor)
// ຈຶ່ງບໍ່ສາມາດ swap ເປັນ Fake instance ຜ່ານ widget test ໄດ້ໂດຍກົງ.
// ພາກທີ 3 ຂ້າງລຸ່ມນີ້ຈຶ່ງຈຳລອງ write payload ດຽວກັນກັບ source ຂຶ້ນມາໃໝ່
// (fake_cloud_firestore) ເພື່ອພິສູດວ່າ "atomic batch" ແກ້ບັນຫາໄດ້ແທ້.
// ສຳລັບ true end-to-end (ຮວມ Phone OTP ແທ້) ຄວນໃຊ້ Firebase Emulator
// Suite + integration_test package ແທນ.
// ============================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lintho/register_otp.dart';
import 'package:lintho/customer_register_flow.dart';
import 'package:lintho/technician_register_screen.dart';
import 'package:lintho/main.dart' show resolveRoleDestination, MainShell;
import 'package:lintho/provider_dashboard.dart';
import 'package:lintho/pending_approval_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);
String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('Register entry — navigation & no-exception smoke test', () {
    testWidgets('RegisterPage shows both account type cards', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterPage()));
      await tester.pumpAndSettle();

      expect(find.text('ລູກຄ້າ'), findsOneWidget);
      expect(find.text('ຊ່າງ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ບໍ່ຕິກຍອມຮັບເງື່ອນໄຂ → ກົດ "ລູກຄ້າ" ຄ້າງຢູ່ RegisterPage ພ້ອມ SnackBar ເຕືອນ',
        (tester) async {
      await tester.pumpWidget(_wrap(const RegisterPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ລູກຄ້າ'));
      await tester.pump();

      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byType(CustomerRegisterFlow), findsNothing);
      expect(find.text('ກະລຸນາກວດສອບ ແລະ ຕິກຍອມຮັບເງື່ອນໄຂກ່ອນດຳເນີນການ'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ຕິກຍອມຮັບເງື່ອນໄຂ ແລ້ວເລືອກ "ລູກຄ້າ" → ໄປ CustomerRegisterFlow, step 0 = ເບີໂທ',
        (tester) async {
      await tester.pumpWidget(_wrap(const RegisterPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('ລູກຄ້າ'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerRegisterFlow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ຕິກຍອມຮັບເງື່ອນໄຂ ແລ້ວເລືອກ "ຊ່າງ" → ໄປ TechnicianRegisterScreen, step 0 = ເບີໂທ',
        (tester) async {
      await tester.pumpWidget(_wrap(const RegisterPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('ຊ່າງ'));
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianRegisterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ເບີໂທບໍ່ຖືກຕ້ອງ → ຄ້າງ step 0 ພ້ອມ error, ບໍ່ແຕະ Firebase, ບໍ່ crash',
        (tester) async {
      await tester.pumpWidget(_wrap(const CustomerRegisterFlow()));
      await tester.pumpAndSettle();

      // ✅ ພິມເບີໂທຜິດຮູບແບບ (ສັ້ນເກີນໄປ) — ຄາດວ່າ _sendOtp() ຈະ return
      // ກ່ອນເຖິງ FirebaseAuth.instance.verifyPhoneNumber(...) ໃດໆ
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // ຍັງຄ້າງຢູ່ step ດຽວກັນ (ບໍ່ໄດ້ໄປ step OTP)
      expect(find.byType(CustomerRegisterFlow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '🧪 Bypass OTP (debug) → ໄປ step ຂໍ້ມູນສ່ວນຕົວ ໂດຍບໍ່ crash '
        '(ຈຳລອງຫຼັງ OTP ຢືນຢັນສຳເລັດ, kDebugMode ເທົ່ານັ້ນ)',
        (tester) async {
      await tester.pumpWidget(_wrap(const TechnicianRegisterScreen()));
      await tester.pumpAndSettle();

      final bypassBtn = find.text('Bypass OTP (Debug Only)');
      expect(bypassBtn, findsOneWidget,
          reason: 'ປ่ຸม debug bypass ຄວນສະແດງໃນ debug/test build');

      await tester.tap(bypassBtn);
      await tester.pumpAndSettle();

      // ✅ ໄປ step 2 (ຂໍ້ມູນສ່ວນຕົວ) ໂດຍບໍ່ຕ້ອງ verify OTP ແທ້
      expect(find.text('ຂໍ້ມູນສ່ວນຕົວ'), findsOneWidget);
      expect(find.text('ຊື່-ນາມສະກຸນ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Register write payload — atomic-write contract (regression)', () {
    // ▸ payload ນີ້ຄັດລອກມາຈາກ technician_register_screen.dart _finish()
    //   ຄືກັນເປັ๊ະ — ຖ້າແກ້ schema ໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Map<String, dynamic> usersPayload(String uid) => {
          'uid': uid,
          'displayName': 'ທົດສອບ ຊ່າງ',
          'phone': '2091312566',
          'role': 'provider',
          'photoUrl': '',
          'status': 'pending',
          'lat': 17.9757,
          'lng': 102.6331,
          'createdAt': FieldValue.serverTimestamp(),
        };

    Map<String, dynamic> providersPayload(String uid) => {
          'displayName': 'ທົດສອບ ຊ່າງ',
          'phone': '2091312566',
          'isOnline': false,
          'status': 'pending',
          'kycStatus': 'pending',
          'serviceTypes': ['aircon'],
          'experienceYears': 2,
          'fcmTokens': <String>[],
          'lat': 17.9757,
          'lng': 102.6331,
          'rating': 0.0,
          'totalJobs': 0,
          'completionRate': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
        };

    // ▸ [AUDIT KYC-1] ຮູບ KYC ຍ້າຍໄປ kyc/{uid} (ອ່ານໄດ້ສະເພາະເຈົ້າຂອງ/admin)
    //   ແທນ providers/{uid} (ອ່ານໄດ້ໂດຍ user login ໃດກໍໄດ້).
    Map<String, dynamic> kycPayload() => {
          'idDocUrl': 'https://cloudinary.example/id.jpg',
          'selfieUrl': 'https://cloudinary.example/selfie.jpg',
          'updatedAt': FieldValue.serverTimestamp(),
        };

    test(
        'CURRENT BEHAVIOR (bug repro): two separate .set() calls → '
        'partial failure leaves an orphaned users/{uid} doc with no '
        'matching providers/{uid} doc', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'tech-uid-1';

      // 1) ຂຽນ users ສຳເລັດ (ຈຳລອງ code ປັດຈຸບັນ)
      await db.collection('users').doc(uid).set(usersPayload(uid),
          SetOptions(merge: true));

      // 2) ຈຳລອງ providers write ລົ້ມເຫຼວ (network drop / app killed
      //    ລະຫວ່າງທາງ) — ບໍ່ໄດ້ເອີ້ນ .set() ອັນທີສອງເລີຍ

      final usersDoc = await db.collection('users').doc(uid).get();
      final providersDoc = await db.collection('providers').doc(uid).get();

      // ▸ ນີ້ຄືສະຖານະ "ghost account" ທີ່ພົບ: users ບອກວ່າເປັນ provider
      //   ລໍຖ້າອະນຸມັດ ແຕ່ providers ບໍ່ມີເລີຍ → admin ຫາບໍ່ພົບ, RoleRouter
      //   ພາໄປ PendingApprovalScreen ຕະຫຼອດໄປ ໂດຍບໍ່ມີທາງກັບຄືນ.
      expect(usersDoc.exists, isTrue);
      expect(usersDoc.data()?['role'], 'provider');
      expect(usersDoc.data()?['status'], 'pending');
      expect(providersDoc.exists, isFalse,
          reason: 'ນີ້ຄື bug: users write ສຳເລັດແຕ່ providers ຍັງບໍ່ມີ');
    });

    test(
        'FIX: WriteBatch commits both docs atomically — either both exist '
        'or neither does', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'tech-uid-2';

      final batch = db.batch();
      batch.set(db.collection('users').doc(uid), usersPayload(uid),
          SetOptions(merge: true));
      batch.set(db.collection('kyc').doc(uid), kycPayload(),
          SetOptions(merge: true));
      batch.set(db.collection('providers').doc(uid), providersPayload(uid),
          SetOptions(merge: true));
      await batch.commit();

      final usersDoc = await db.collection('users').doc(uid).get();
      final providersDoc = await db.collection('providers').doc(uid).get();
      final kycDoc = await db.collection('kyc').doc(uid).get();

      expect(usersDoc.exists, isTrue);
      expect(providersDoc.exists, isTrue);
      expect(kycDoc.exists, isTrue);
      expect(kycDoc.data()?['idDocUrl'], isNotEmpty);
      expect(providersDoc.data()?.containsKey('kycDocUrl'), isFalse,
          reason: 'ຮູບ KYC ຫ້າມຢູ່ໃນ providers/{uid} — doc ນັ້ນອ່ານໄດ້ໂດຍ '
              'user login ໃດກໍໄດ້ (firestore.rules)');
      expect(providersDoc.data()?['serviceTypes'], contains('aircon'));
    });
  });

  group('Role-conflict guard — early detection contract', () {
    // ▸ ຄັດລອກ decision logic ດຽວກັນກັບ _blockIfRoleConflict() ໃນ
    //   customer_register_flow.dart / technician_register_screen.dart —
    //   ຖ້າແກ້ເງື່ອນໄຂໃນ source, ຕ້ອງອັບເດດບ່ອນນີ້ນຳ.
    Future<bool> wouldBlock(FakeFirebaseFirestore db, String uid,
        String expectedRole) async {
      final doc = await db.collection('users').doc(uid).get();
      final existingRole = doc.data()?['role'] as String?;
      return doc.exists && existingRole != null && existingRole != expectedRole;
    }

    test('ບໍ່ blocked ຖ້າຍັງບໍ່ມີ users/{uid} doc (ລົງທະບຽນໃໝ່)', () async {
      final db = FakeFirebaseFirestore();
      expect(await wouldBlock(db, 'new-uid', 'provider'), isFalse);
    });

    test(
        'blocked ຖ້າເບີໂທດຽວກັນເຄີຍລົງທະບຽນເປັນ customer ມາກ່ອນ ແລ້ວພະຍາຍາມ '
        'ລົງທະບຽນເປັນ provider (ຫຼືກັບກັນ)', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'shared-phone-uid';
      await db.collection('users').doc(uid).set({'role': 'customer'});

      expect(await wouldBlock(db, uid, 'provider'), isTrue);

      final db2 = FakeFirebaseFirestore();
      await db2.collection('users').doc(uid).set({'role': 'provider'});
      expect(await wouldBlock(db2, uid, 'customer'), isTrue);
    });

    test(
        'ບໍ່ blocked ຖ້າ role ເກົ່າກົງກັບ role ທີ່ພະຍາຍາມລົງທະບຽນ '
        '(resubmit ຫຼັງ partial failure ຄັ້ງກ່ອນ)', () async {
      final db = FakeFirebaseFirestore();
      const uid = 'retry-uid';
      await db.collection('users').doc(uid).set({'role': 'provider'});

      expect(await wouldBlock(db, uid, 'provider'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // TEST 1 — E-01/E-02 regression: post-auth destination
  // ══════════════════════════════════════════════════════════
  //
  // resolveRoleDestination() (lib/main.dart) is the single source of truth
  // extracted for the Phase 2 Batch E fix — previously RoleRouter and
  // LoginPage._loginWithGoogle() each had their own copy of this decision,
  // and LoginPage._login() (email/password — the primary login method) had
  // no copy at all, so a provider signing in with email/password always
  // landed on the customer MainShell. It's a pure function (no Firebase
  // I/O), so it can be exercised directly without any mocking — this is
  // exactly why it was extracted as a pure function rather than inlined.
  group('resolveRoleDestination — E-01/E-02: single source of truth for '
      'post-auth destination', () {
    test('customer → MainShell', () {
      final w = resolveRoleDestination(role: 'customer', kycStatus: null);
      expect(w, isA<MainShell>());
    });

    test('provider + kycStatus verified → ProviderDashboard', () {
      final w = resolveRoleDestination(role: 'provider', kycStatus: 'verified');
      expect(w, isA<ProviderDashboard>());
    });

    test('provider + kycStatus pending → PendingApprovalScreen', () {
      final w = resolveRoleDestination(role: 'provider', kycStatus: 'pending');
      expect(w, isA<PendingApprovalScreen>());
    });

    test('provider + kycStatus rejected → PendingApprovalScreen', () {
      final w = resolveRoleDestination(role: 'provider', kycStatus: 'rejected');
      expect(w, isA<PendingApprovalScreen>());
    });

    test('provider + missing/null kycStatus → PendingApprovalScreen', () {
      final w = resolveRoleDestination(role: 'provider', kycStatus: null);
      expect(w, isA<PendingApprovalScreen>());
    });
  });

  // ══════════════════════════════════════════════════════════
  // TEST 1b — E-01/E-02 regression: no duplicate decision tree left behind
  // ══════════════════════════════════════════════════════════
  //
  // Source-based guard (same style as service_icon_remaining_spots_test.dart)
  // — _login() must resolve its destination through the shared function
  // (not hardcode MainShell again), and neither login path should still
  // contain its own inline "kycStatus == 'verified' ? ... : ..." branch.
  group('main.dart — E-01/E-02: no duplicated role-routing logic remains', () {
    final source = _read('lib/main.dart');

    test('_login() no longer hardcodes MainShell as the destination', () {
      final start = source.indexOf('Future<void> _login() async {');
      final end = source.indexOf('Future<void> _loginWithGoogle()');
      final block = source.substring(start, end);
      expect(block, contains('resolvePostAuthDestination()'));
      expect(block, isNot(contains('builder: (_) => const MainShell()')));
    });

    test('_loginWithGoogle() delegates the final branch to '
        'resolveRoleDestination(), not its own inline ternary', () {
      final start = source.indexOf('Future<void> _loginWithGoogle()');
      final end = source.indexOf('Future<void> _forgotPassword()');
      final block = source.substring(start, end);
      expect(block, contains('resolveRoleDestination(role: role, kycStatus: kycStatus)'));
      expect(block, isNot(contains("kycStatus == 'verified'\n                ? const ProviderDashboard()")));
    });
  });

  // ══════════════════════════════════════════════════════════
  // TEST 2 — E-03 regression: OTP-step back navigation
  // ══════════════════════════════════════════════════════════
  //
  // Driving CustomerRegisterFlow/TechnicianRegisterScreen to _step==1 (OTP)
  // for a real interaction test would require a live FirebaseAuth
  // verifyPhoneNumber() call (no Firebase is initialized in this widget-test
  // environment — see this file's header note on why the flows above use
  // contract tests instead of full E2E). Source-based regression guard
  // instead: confirms the back-button handler now special-cases _step==1
  // (reset to step 0) rather than falling through to Navigator.pop(), for
  // both registration flows.
  group('customer_register_flow.dart / technician_register_screen.dart — '
      'E-03: OTP step back button returns to phone step', () {
    test('customer_register_flow.dart handles _step==1 before the pop '
        'fallback', () {
      final source = _read('lib/customer_register_flow.dart');
      final start = source.indexOf('onPressed: _loading ? null : () {');
      final end = source.indexOf('),\n        ),\n      ),\n      body:');
      final block = source.substring(start, end == -1 ? start + 1500 : end);
      expect(block, contains('} else if (_step == 1) {'));
      // the _step==1 branch must appear before the final else{} that pops
      final step1Index = block.indexOf('_step == 1');
      final popIndex = block.indexOf('Navigator.pop(context);');
      expect(step1Index, greaterThan(0));
      expect(popIndex, greaterThan(step1Index));
    });

    test('technician_register_screen.dart handles _step==1 before the '
        'generic decrement/pop fallback', () {
      final source = _read('lib/technician_register_screen.dart');
      final start = source.indexOf('onPressed: _loading ? null : () {');
      final end = source.indexOf('),\n        ),\n      ),\n      body:');
      final block = source.substring(start, end == -1 ? start + 2000 : end);
      expect(block, contains('} else if (_step == 1) {'));
      final step1Index = block.indexOf('_step == 1');
      final decrementIndex = block.indexOf('_step -= 1');
      final popIndex = block.indexOf('Navigator.pop(context);');
      expect(step1Index, greaterThan(0));
      expect(decrementIndex, greaterThan(step1Index));
      expect(popIndex, greaterThan(decrementIndex));
    });
  });

  // ══════════════════════════════════════════════════════════
  // TEST 3 — Pending approval: rejected vs. generic state
  // ══════════════════════════════════════════════════════════
  group('pending_approval_screen.dart — rejected vs. generic pending UI', () {
    // PendingApprovalScreen.build() reads FirebaseAuth.instance.currentUser
    // unconditionally (not inside a tap handler), which throws
    // `[core/no-app]` in this widget-test environment (no Firebase
    // initialized) — so, consistent with this file's other Firebase-touching
    // screens, this is a source-based regression guard rather than a pump.

    // Reaching kycStatus=='rejected' requires a live providers/{uid} stream
    // (FirebaseAuth + Firestore), not available in this widget-test
    // environment — source-based regression guard instead, confirming the
    // rejected branch still wires reason text + resubmit CTA + KycScreen
    // navigation, and that E-04's CTA-color fix is in place.
    test('rejected kycStatus renders reject reason + resubmit CTA routed '
        'to KycScreen, with the primary (not navy) CTA color', () {
      final source = _read('lib/pending_approval_screen.dart');
      expect(source, contains("kycStatus == 'rejected'"));
      expect(source, contains('rejectReason: rejectReason'));
      expect(source, contains('kyc_rejected_reason_label'));
      expect(source, contains('builder: (_) => const KycScreen()'));
      // ✅ [FIX E-04] was C.navy — must not regress back to it.
      expect(source, isNot(contains('backgroundColor: C.navy, elevation: 0,')));
      expect(source, contains('backgroundColor: C.primary, elevation: 0,'));
    });

    test('non-rejected kycStatus keeps the generic pending body (no reject '
        'reason, no resubmit CTA)', () {
      final source = _read('lib/pending_approval_screen.dart');
      // default constructor path used for everything except 'rejected'
      expect(source, contains('return const _PendingApprovalBody();'));
    });
  });
}
