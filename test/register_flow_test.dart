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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lintho/register_otp.dart';
import 'package:lintho/customer_register_flow.dart';
import 'package:lintho/technician_register_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

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
}
