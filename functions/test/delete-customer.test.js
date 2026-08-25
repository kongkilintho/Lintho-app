// ============================================================
// delete-customer.test.js — LinTho Cloud Functions
//
// Regression test for Batch L: lintho-admin's useDeleteCustomer previously
// called deleteDoc(doc(db,'users',id)) directly from the client — Firebase
// Auth was never touched, so a "deleted" customer's session stayed fully
// usable indefinitely (confirmed HIGH severity — isActiveCustomer() in
// firestore.rules treats a missing users/{uid} doc as an active,
// unrestricted customer). deleteCustomer (index.js) is the new
// _assertSuperAdmin()-gated callable the admin panel now calls instead,
// combining deleteAdminUser's admin-only authorization with
// deleteOwnAccount's addresses-subcollection cleanup.
//
// ໝາຍເຫດ: index.js ໂຫລດ Firebase Admin SDK ຕອນ import — ບໍ່ import ໂດຍກົງ
// ນອກ emulator (ຄືກັນກັບ delete-own-account.test.js), ໃຊ້ source-text
// regression guard ແທນ.
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'), 'utf8');

function functionBody() {
  const start = source.indexOf('exports.deleteCustomer');
  assert.ok(start > -1, 'deleteCustomer must exist');
  const end = source.indexOf('\n});', start);
  assert.ok(end > start);
  return source.slice(start, end);
}

test('exports.deleteCustomer exists as a callable function', () => {
  assert.match(source, /exports\.deleteCustomer\s*=\s*functions\.https\.onCall/);
});

test('requires the caller to be super_admin via the existing '
  + '_assertSuperAdmin() helper — not a new/duplicated authorization check', () => {
  const body = functionBody();
  assert.match(body, /const callerUid = await _assertSuperAdmin\(context\);/);
});

test('validates uid is a non-empty string', () => {
  const body = functionBody();
  assert.match(body, /const \{ uid \} = data \|\| \{\};/);
  assert.match(body, /if \(typeof uid !== 'string' \|\| !uid\) \{/);
  assert.match(body, /invalid-argument/);
});

test('rejects deleting the caller\'s own account through this endpoint '
  + '(same self-delete guard as deleteAdminUser)', () => {
  const body = functionBody();
  assert.match(body, /if \(uid === callerUid\) \{/);
  assert.match(body, /failed-precondition/);
});

test('deletes the target Firebase Auth account', () => {
  const body = functionBody();
  assert.match(body, /admin\.auth\(\)\.deleteUser\(uid\)/);
});

test('tolerates auth\\/user-not-found (idempotent retry) but rethrows any '
  + 'other Auth deletion error instead of silently continuing', () => {
  const body = functionBody();
  assert.match(body, /if \(err\.code !== 'auth\/user-not-found'\) \{/);
  assert.match(body, /throw new functions\.https\.HttpsError\('internal', /);
});

test('Auth deletion happens BEFORE the Firestore cleanup — the safer '
  + 'partial-failure order (matches deleteAdminUser, not deleteOwnAccount) '
  + 'so a mid-flight failure still leaves the account locked out', () => {
  const body = functionBody();
  const authIdx = body.indexOf('admin.auth().deleteUser(uid)');
  const batchCommitIdx = body.indexOf('await batch.commit();');
  assert.ok(authIdx > -1 && batchCommitIdx > -1);
  assert.ok(authIdx < batchCommitIdx,
    'Auth deletion must run before the Firestore batch commit');
});

test('deletes the target users/{uid} doc and its addresses subcollection '
  + '(same cleanup scope as deleteOwnAccount)', () => {
  const body = functionBody();
  assert.match(body, /collection\('addresses'\)/);
  assert.match(body, /batch\.delete\(doc\.ref\)/);
  assert.match(body, /batch\.delete\(db\.collection\('users'\)\.doc\(uid\)\)/);
});

test('does not touch any collection beyond users/{uid} and its addresses '
  + 'subcollection — no silently broadened deletion scope (bookings/'
  + 'wallets/reviews/rewardTransactions are explicitly out of scope, same '
  + 'as deleteOwnAccount)', () => {
  const body = functionBody();
  for (const unrelated of ['bookings', 'wallets', 'providers', 'reviews',
    'rewardTransactions', 'transactions']) {
    assert.doesNotMatch(body, new RegExp(`collection\\('${unrelated}'\\)`),
      `must not touch collection('${unrelated}')`);
  }
});

test('returns the uid on success', () => {
  const body = functionBody();
  assert.match(body, /return \{ uid \};/);
});
