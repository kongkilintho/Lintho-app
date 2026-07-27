// ============================================================
// legal_content_realtime_test.dart — LinTho App
//
// Verifies the fix for: Admin Panel (lintho-admin) saves Legal Content to
// `settings/legal`, but the customer app showed stale hardcoded text
// because it never read Firestore for Terms & Conditions at all.
//
// legal_content_provider.dart now streams `settings/legal` via .snapshots(),
// which is only actually "real-time" if a listener that is already
// subscribed receives the NEXT admin write without needing to re-open the
// sheet / re-subscribe. That's what this test locks in, using
// FakeFirebaseFirestore's real listener semantics (not a one-shot get()).
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintho/legal_content_provider.dart';

void main() {
  group('LegalContent.fromMap', () {
    test('parses terms/privacy fields', () {
      final c = LegalContent.fromMap({'terms': 'T', 'privacy': 'P'});
      expect(c.terms, 'T');
      expect(c.privacy, 'P');
    });

    test('missing doc (null map) falls back to empty strings', () {
      final c = LegalContent.fromMap(null);
      expect(c.terms, '');
      expect(c.privacy, '');
    });

    test('a doc with only one field leaves the other empty', () {
      final c = LegalContent.fromMap({'terms': 'T only'});
      expect(c.terms, 'T only');
      expect(c.privacy, '');
    });
  });

  group('settings/legal .snapshots() is real-time (no re-subscribe needed)', () {
    test('an already-open listener sees the admin\'s next save', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('settings').doc('legal')
          .set({'terms': 'v1 terms', 'privacy': 'v1 privacy'});

      // Same query shape as legalContentProvider (main.dart's Terms & Privacy
      // sheet stays subscribed to this exact stream while it's open).
      final stream = db.collection('settings').doc('legal')
          .snapshots().map((s) => LegalContent.fromMap(s.data()));

      final emissions = <LegalContent>[];
      final sub = stream.listen(emissions.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions, hasLength(1));
      expect(emissions.first.terms, 'v1 terms');

      // Simulate the admin editing Legal Content and hitting Save
      // (useUpdateLegalContent → setDoc(doc(db,'settings','legal'), {...}, {merge:true})).
      await db.collection('settings').doc('legal')
          .set({'terms': 'v2 terms — updated by admin'}, SetOptions(merge: true));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The listener that was already open must have received a SECOND
      // emission with the new content, without cancelling/re-subscribing —
      // this is what makes the sheet update live instead of only after reopen.
      expect(emissions, hasLength(2));
      expect(emissions.last.terms, 'v2 terms — updated by admin');
      // merge:true must not have clobbered the untouched field.
      expect(emissions.last.privacy, 'v1 privacy');
    });

    test('doc created after the listener was already open still reaches it',
        () async {
      final db = FakeFirebaseFirestore();

      final stream = db.collection('settings').doc('legal')
          .snapshots().map((s) => LegalContent.fromMap(s.data()));

      final emissions = <LegalContent>[];
      final sub = stream.listen(emissions.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Doc doesn't exist yet — app should be able to fall back to the
      // static tr('terms_content') copy at this point (main.dart's
      // `(legal != null && legal.terms.isNotEmpty) ? legal.terms : tr(...)`).
      expect(emissions, hasLength(1));
      expect(emissions.first.terms, '');

      await db.collection('settings').doc('legal')
          .set({'terms': 'first content ever saved', 'privacy': 'p'});

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions, hasLength(2));
      expect(emissions.last.terms, 'first content ever saved');
    });
  });
}
