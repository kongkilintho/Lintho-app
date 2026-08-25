// ============================================================
// batch_h_suspend_ban_test.dart — LinTho App
//
// Regression coverage for Batch H — Customer suspend/ban enforcement
// (Critical, 2026-08-25). users/{uid}.status (admin-set via
// useSuspendCustomer/useBanCustomer, lintho-admin/src/lib/hooks/index.ts)
// was previously write-only: no Firestore rule, no RTDB rule, and the
// Firebase Auth account was never disabled, so a suspended/banned
// customer's existing session (and any future login) kept working
// indefinitely.
//
// The fix itself lives entirely in functions/index.js (new
// onCustomerStatusChange trigger), firestore.rules (new isActiveCustomer()
// helper + 3 call sites), and database.rules.json (one added conjunct) —
// no lib/*.dart file was touched by this batch (no Reactivate UI, no
// client-side status screen — both deliberately out of scope). This file
// exists purely as a second, independently-run regression guard over the
// same firestore.rules/database.rules.json text — the equivalent JS-side
// coverage lives in functions/test/customer-suspend-ban.test.js (which
// also covers the Cloud Function trigger's own logic, not readable from
// here). Two toolchains checking the same rule text means a future
// accidental revert is caught whether only `flutter test` or only
// `node --test` happens to run.
//
// ໝາຍເຫດ: same source-text-only limitation as rules_fixes_test.dart's own
// header note — no rules-emulator harness in this repo.
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Normalizes CRLF -> LF so multi-line literal-string matches below are not
// sensitive to the repo's line-ending convention (this repo's rule files
// are checked out with \r\n on Windows).
String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final rules = _read('firestore.rules');
  final dbRulesRaw = _read('database.rules.json');
  final functionsSource = _read('functions/index.js');

  group('isActiveCustomer() helper', () {
    test('is defined right after isCustomer(), layering a live status '
        're-check on top of it', () {
      final start = rules.indexOf('function isActiveCustomer() {');
      expect(start, greaterThan(-1));
      final end = rules.indexOf('\n    }', start);
      final block = rules.substring(start, end);
      expect(block, contains('isCustomer()'));
      expect(block, contains("get(path).data.status in ['suspended', 'banned']"));
    });

    test('guards the get() call with exists(), same pattern as '
        'getAdminRole() — avoids erroring on a users/{uid} doc that '
        'legitimately does not exist yet', () {
      final start = rules.indexOf('function isActiveCustomer() {');
      final end = rules.indexOf('\n    }', start);
      final block = rules.substring(start, end);
      expect(block, contains('exists(path)'));
    });

    test('isCustomer() itself is unmodified — this batch only adds a '
        'stricter helper, never edits the original', () {
      expect(
        rules,
        contains("function isCustomer() {\n"
            '      return isAuth() && getRole() == \'customer\';\n'
            '    }'),
      );
    });
  });

  group('isActiveCustomer() call sites — exactly 3, all create rules', () {
    test('bookings/{bookingId} create requires isActiveCustomer()', () {
      final start = rules.indexOf('match /bookings/{bookingId}');
      final end = rules.indexOf('lat/lng ບໍ່ຢູ່ໃນ list', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(
        block,
        contains('request.resource.data.customerId == request.auth.uid && '
            'isActiveCustomer()'),
        reason: 'previously isCustomer() — a suspended/banned customer '
            'could still create new bookings',
      );
    });

    test('reviews/{reviewId} create requires isActiveCustomer()', () {
      final start = rules.indexOf('match /reviews/{reviewId}');
      final end = rules.indexOf('match /wallets/{uid}');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(
        block,
        contains('allow create: if isActiveCustomer() &&'),
        reason: 'previously had no role/status check at all — only '
            'ownership + a real completed booking',
      );
    });

    test('rewardRedemptions/{reqId} create requires isActiveCustomer()', () {
      final start = rules.indexOf('match /rewardRedemptions/{reqId}');
      final end = rules.indexOf('\n    }', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = rules.substring(start, end);
      expect(
        block,
        contains('allow create: if isActiveCustomer() &&'),
        reason: 'previously had no role/status check at all — only '
            'ownership',
      );
    });

    test('no other rule block references isActiveCustomer() — the live '
        'status re-check is scoped to exactly these 3 writes, never a '
        'read/update/write rule', () {
      final codeLines = rules.split('\n').where((rawLine) {
        final line = rawLine.trim();
        if (!line.contains('isActiveCustomer()')) return false;
        if (line.startsWith('//')) return false;
        if (line.startsWith('function isActiveCustomer()')) return false;
        return true;
      }).toList();
      expect(codeLines, hasLength(3));
      for (final line in codeLines) {
        expect(line, isNot(matches(RegExp(r'allow (read|update|delete|write):'))));
      }
    });
  });

  group('database.rules.json — restricted/{uid} mirror on chat meta writes', () {
    test('meta .write includes the restricted check', () {
      expect(
        dbRulesRaw,
        contains("root.child('restricted').child(auth.uid).val() != true"),
      );
    });

    test('the restricted check sits inside chats/\$chatId/meta .write, not '
        'a new top-level rule', () {
      final metaStart = dbRulesRaw.indexOf('"meta": {');
      final metaEnd = dbRulesRaw.indexOf('"messages": {', metaStart);
      expect(metaStart, greaterThan(-1));
      expect(metaEnd, greaterThan(metaStart));
      final metaBlock = dbRulesRaw.substring(metaStart, metaEnd);
      expect(metaBlock, contains("root.child('restricted')"));
    });

    test('the pre-existing identity/participant checks in meta .write are '
        'untouched — the restricted check was appended, not substituted', () {
      final metaStart = dbRulesRaw.indexOf('"meta": {');
      final metaEnd = dbRulesRaw.indexOf('"messages": {', metaStart);
      final metaBlock = dbRulesRaw.substring(metaStart, metaEnd);
      expect(metaBlock, contains('data.exists()'));
      expect(
        metaBlock,
        contains("auth.uid == data.child('customerId').val() || "
            "auth.uid == data.child('providerId').val()"),
      );
      expect(
        metaBlock,
        contains("newData.child('customerId').val() == "
            "data.child('customerId').val()"),
      );
      expect(
        metaBlock,
        contains("newData.child('providerId').val() == "
            "data.child('providerId').val()"),
      );
      // Field-level identity locks (H-1) still present.
      expect(metaBlock, contains('"customerId"'));
      expect(metaBlock, contains('"providerId"'));
    });

    test('meta .read is NOT restricted-gated — a restricted user can still '
        'read their own chat history (data visibility is not revoked, '
        'only new writes are — matches firestore.rules never touching a '
        'read rule in this batch)', () {
      final metaStart = dbRulesRaw.indexOf('"meta": {');
      final readIdx = dbRulesRaw.indexOf('".read"', metaStart);
      final readLineEnd = dbRulesRaw.indexOf('\n', readIdx);
      final readLine = dbRulesRaw.substring(readIdx, readLineEnd);
      expect(readLine, isNot(contains('restricted')));
    });

  });

  group('database.rules.json — corrective fix: restricted/{uid} on '
      'chat MESSAGE writes (not just meta)', () {
    // Independent review found that gating only meta .write left the
    // actual message content (chats/$chatId/messages, written directly by
    // ChatService._sendMessage() via a call separate from the meta
    // update) fully sendable by a restricted user. This group proves the
    // corrective fix. Deeper behavioral proof (active/restricted
    // customer & provider, senderId spoofing, H-1 protections untouched)
    // lives in functions/test/initialize-booking-chat.test.js's
    // simulateMessagesWrite() scenarios P-W — not reproduced here in
    // JS-simulation form, since this file's role (per its header) is
    // structural text-matching, same division of labor already used
    // between rules_fixes_test.dart and its JS-side counterparts.
    test('messages .write includes the restricted check', () {
      final messagesStart = dbRulesRaw.indexOf('"messages": {');
      final messagesEnd = dbRulesRaw.indexOf('"\$messageId"', messagesStart);
      final messagesBlock = dbRulesRaw.substring(messagesStart, messagesEnd);
      expect(
        messagesBlock,
        contains("!root.child('restricted').child(auth.uid).val()"),
      );
    });

    test('the restricted check was appended to messages .write, not '
        'substituted — every pre-existing participant condition remains', () {
      final messagesStart = dbRulesRaw.indexOf('"messages": {');
      final writeIdx = dbRulesRaw.indexOf('".write"', messagesStart);
      final writeLineEnd = dbRulesRaw.indexOf('\n', writeIdx);
      final writeLine = dbRulesRaw.substring(writeIdx, writeLineEnd);
      expect(writeLine, contains('auth != null'));
      expect(
        writeLine,
        contains("auth.uid == root.child('chats').child(\$chatId).child('meta')"
            ".child('customerId').val()"),
      );
      expect(
        writeLine,
        contains("auth.uid == root.child('chats').child(\$chatId).child('meta')"
            ".child('providerId').val()"),
      );
    });

    test('messages .read is unchanged by the corrective fix — not '
        'restricted-gated, same design decision as meta .read', () {
      final messagesStart = dbRulesRaw.indexOf('"messages": {');
      final readIdx = dbRulesRaw.indexOf('".read"', messagesStart);
      final readLineEnd = dbRulesRaw.indexOf('\n', readIdx);
      final readLine = dbRulesRaw.substring(readIdx, readLineEnd);
      expect(readLine, isNot(contains('restricted')));
    });

    test('senderId field-level .validate is byte-for-byte unchanged', () {
      expect(dbRulesRaw, contains('"newData.val() == auth.uid"'));
    });

    test('meta .write (H-1 identity protection + its own restricted '
        'check from the first round of this batch) is untouched by this '
        'corrective round', () {
      final metaStart = dbRulesRaw.indexOf('"meta": {');
      final metaEnd = dbRulesRaw.indexOf('"messages": {', metaStart);
      final metaBlock = dbRulesRaw.substring(metaStart, metaEnd);
      expect(
        metaBlock,
        contains("newData.child('customerId').val() == "
            "data.child('customerId').val()"),
      );
      expect(
        metaBlock,
        contains("root.child('restricted').child(auth.uid).val() != true"),
      );
    });
  });

  group('functions/index.js — onCustomerStatusChange exists and is wired '
      'to a users/{uid} update trigger', () {
    test('the trigger is exported and targets users/{uid} onUpdate', () {
      expect(functionsSource, contains('exports.onCustomerStatusChange'));
      expect(functionsSource, contains("document('users/{uid}')"));
      expect(functionsSource, contains('.onUpdate(async (change, context)'));
    });

    test('writes and clears the same restricted/{uid} RTDB path '
        'database.rules.json checks', () {
      final start = functionsSource.indexOf('exports.onCustomerStatusChange');
      final end = functionsSource.indexOf('\n  });', start);
      final block = functionsSource.substring(start, end);
      expect(block, contains(r"admin.database().ref(`restricted/${uid}`)"));
      expect(block, contains('restrictedRef.set(true)'));
      expect(block, contains('restrictedRef.remove()'));
    });
  });

}
