// ============================================================
// referral-signup-voucher.test.js — LinTho Cloud Functions
//
// Regression test for M-2 (2026-07-27 release-readiness audit): the
// referral signup-bonus idempotency guard used to live on the booking
// document (bookingRef.signupVoucherIssued), not the customer. Two
// bookings created back-to-back by a newly-referred customer could each
// independently pass the "is this the first booking" count check before
// either write was visible to the other, and since each invocation only
// checked its OWN booking's flag, both could grant a voucher — double
// paying out the 20,000 LAK signup bonus for one referral.
//
// Fix: the idempotency flag moved to users/{customerId}, the one document
// both concurrent invocations must read/write through the same
// transaction, so Firestore's transaction retry semantics guarantee only
// one grant succeeds.
//
// ໝາຍເຫດ: index.js ໂຫລດ Firebase Admin SDK ຕອນ import — ໃຊ້ source-text
// regression guard (ຄືກັນກັບ delete-own-account.test.js).
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'), 'utf8');

function grantSignupVoucherBody() {
  const start = source.indexOf('async function grantSignupVoucher(');
  assert.ok(start > -1, 'grantSignupVoucher must exist');
  const end = source.indexOf('\n}', start);
  return source.slice(start, end);
}

test('grantSignupVoucher exists', () => {
  assert.match(source, /async function grantSignupVoucher\(/);
});

test('the idempotency guard is scoped to users/{customerId}, not the '
  + 'booking document', () => {
  const block = grantSignupVoucherBody();
  assert.match(block, /db\.collection\('users'\)\.doc\(customerId\)/,
    'must read/write through a per-customer document, the one shared '
    + 'resource two concurrent bookings from the same referred customer '
    + 'both touch');
  assert.match(block, /customerSnap\.data\(\)\?\.signupVoucherIssued/,
    'the early-return guard must check the customer doc\'s flag');
});

test('the guard check and the voucher write happen inside the same '
  + 'runTransaction call (atomic check-then-act)', () => {
  const block = grantSignupVoucherBody();
  const txStart = block.indexOf('db.runTransaction(async (tx) => {');
  assert.ok(txStart > -1);
  const guardIdx = block.indexOf('customerSnap.data()?.signupVoucherIssued');
  const voucherSetIdx = block.indexOf("tx.set(voucherRef,");
  const flagSetIdx = block.indexOf("signupVoucherIssued: true", voucherSetIdx);
  assert.ok(guardIdx > txStart, 'the guard read must be inside the transaction');
  assert.ok(voucherSetIdx > guardIdx, 'the voucher write must come after the guard check');
  assert.ok(flagSetIdx > voucherSetIdx, 'the flag must be set in the same transaction as the voucher');
});

test('the booking is still stamped too, for traceability, but is no '
  + 'longer the sole gate', () => {
  const block = grantSignupVoucherBody();
  assert.match(block, /tx\.update\(bookingRef, \{ signupVoucherIssued: true \}\)/);
});

test('onNewBooking still passes bookingRef through unchanged (call-site '
  + 'contract preserved)', () => {
  const start = source.indexOf('exports.onNewBooking');
  const end = source.indexOf('const REFERRAL_SIGNUP_BONUS', start);
  const block = source.slice(start, end);
  assert.match(block, /grantSignupVoucher\(referralCode, customerId, bookingId, snap\.ref\)/);
});
