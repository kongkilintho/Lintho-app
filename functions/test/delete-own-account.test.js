// ============================================================
// delete-own-account.test.js — LinTho Cloud Functions
//
// Regression test for FOLLOWUP-I4: the Profile "Delete Account" button
// previously only called Navigator.pop — no Auth deletion, no Firestore
// cleanup. deleteOwnAccount (index.js) is the new self-service callable
// the client now calls instead.
//
// ໝາຍເຫດ: index.js ໂຫລດ Firebase Admin SDK ຕອນ import — ບໍ່ import ໂດຍກົງ
// ນອກ emulator (ຄືກັນກັບ cloudinary-folder.test.js), ໃຊ້ source-text
// regression guard ແທນ.
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'), 'utf8');

test('exports.deleteOwnAccount exists', () => {
  assert.match(source, /exports\.deleteOwnAccount\s*=/);
});

test('deleteOwnAccount is scoped to the caller\'s own uid, no uid param '
  + 'accepted (unlike admin-only deleteAdminUser)', () => {
  const start = source.indexOf('exports.deleteOwnAccount');
  const end = source.indexOf('\n});', start);
  const block = source.slice(start, end);
  assert.match(block, /context\.auth\.uid/);
  assert.doesNotMatch(block, /const \{ uid \} = data/,
    'must not accept a uid argument from the client — self-service only');
});

test('deleteOwnAccount requires authentication', () => {
  const start = source.indexOf('exports.deleteOwnAccount');
  const end = source.indexOf('\n});', start);
  const block = source.slice(start, end);
  assert.match(block, /unauthenticated/);
});

test('deleteOwnAccount deletes the Auth user and the users/{uid} doc and '
  + 'its addresses subcollection', () => {
  const start = source.indexOf('exports.deleteOwnAccount');
  const end = source.indexOf('\n});', start);
  const block = source.slice(start, end);
  assert.match(block, /admin\.auth\(\)\.deleteUser\(/);
  assert.match(block, /collection\('users'\)/);
  assert.match(block, /collection\('addresses'\)/);
});
