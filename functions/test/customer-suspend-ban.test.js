// ============================================================
// customer-suspend-ban.test.js — LinTho Cloud Functions
//
// Regression tests for Batch H — Customer suspend/ban enforcement
// (Critical, 2026-08-25). users/{uid}.status was previously write-only:
// lintho-admin's useSuspendCustomer/useBanCustomer set the field but
// nothing ever enforced it — no Firestore rule, no RTDB rule, and the
// Firebase Auth account itself was never disabled. onCustomerStatusChange
// (index.js) is the single authoritative sync point: on a transition into
// 'suspended'/'banned' it disables Firebase Auth, revokes refresh tokens,
// and mirrors a restricted/{uid} flag into RTDB (since RTDB rules cannot
// reference Firestore data — see database.rules.json's chats/$chatId/meta
// AND chats/$chatId/messages .write rules, both covered separately below).
// On a transition back to 'active' it reverses all three.
//
// CORRECTIVE FIX (same day): the first round of this batch only gated
// meta .write. Independent review found ChatService._sendMessage()
// (lib/chat_screen.dart) writes the real message via a separate RTDB call
// from the meta update, so a restricted customer could still send message
// content. messages .write now carries the same restricted/{uid} check —
// see the dedicated section below.
//
// ໝາຍເຫດ: index.js ໂຫລດ Firebase Admin SDK ຕອນ import — ບໍ່ import ໂດຍກົງ
// ນອກ emulator, ໃຊ້ source-text regression guard ແທນ (ຄືກັນກັບ
// initialize-booking-chat.test.js). THESE TESTS DO NOT PROVE RUNTIME
// SECURITY SEMANTICS — they verify the function's source contains the
// checks the threat model requires. A rules-emulator + functions-emulator
// integration test (this repo has neither, confirmed during the design
// pass — no @firebase/rules-unit-testing, no emulators block in
// firebase.json, no Java runtime) would be required to prove runtime
// behavior — flagged as a known, pre-existing gap, not introduced by this
// change.
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'), 'utf8');

const rulesPath = path.join(__dirname, '..', '..', 'firestore.rules');
const rules = fs.readFileSync(rulesPath, 'utf8');

const dbRulesPath = path.join(__dirname, '..', '..', 'database.rules.json');
const dbRulesSource = fs.readFileSync(dbRulesPath, 'utf8');
const dbRules = JSON.parse(dbRulesSource);

function functionBody() {
  const start = source.indexOf('exports.onCustomerStatusChange');
  assert.ok(start > -1, 'onCustomerStatusChange must exist');
  const end = source.indexOf('\n  });', start);
  assert.ok(end > start);
  return source.slice(start, end);
}

test('onCustomerStatusChange is a users/{uid} onUpdate trigger', () => {
  const body = functionBody();
  assert.match(body, /functions\.firestore\s*\n\s*\.document\('users\/\{uid\}'\)/);
  assert.match(body, /\.onUpdate\(async \(change, context\)/);
});

test('resolves role with the same customer fallback as getRole()/'
    + 'resolveRoleDestination()', () => {
  const body = functionBody();
  assert.match(body, /const role = after\.role \|\| 'customer';/);
});

test('is a no-op for any role other than customer', () => {
  const body = functionBody();
  assert.match(body, /if \(role !== 'customer'\) return null;/);
});

test('treats suspended and banned identically via one restricted-status set',
  () => {
    const body = functionBody();
    assert.match(body,
      /const RESTRICTED_STATUSES = \[\s*'suspended',\s*'banned',?\s*\];/);
    assert.match(body, /RESTRICTED_STATUSES\.includes\(before\.status\)/);
    assert.match(body, /RESTRICTED_STATUSES\.includes\(after\.status\)/);
  });

test('is a no-op when the restricted state does not change (covers '
    + 'suspended<->banned transitions and the unrelated legacy '
    + "provider 'pending' marker)", () => {
  const body = functionBody();
  assert.match(body, /if \(wasRestricted === isRestricted\) return null;/);
});

test('on transition into suspended/banned: disables Auth, revokes refresh '
    + 'tokens, and sets the RTDB restricted mirror', () => {
  const body = functionBody();
  const ifIdx = body.indexOf('if (isRestricted) {');
  const elseIdx = body.indexOf('} else {');
  assert.ok(ifIdx > -1, 'must branch on isRestricted');
  assert.ok(elseIdx > ifIdx);
  const restrictBlock = body.slice(ifIdx, elseIdx);

  assert.match(restrictBlock,
    /admin\.auth\(\)\.updateUser\(uid, \{ disabled: true \}\);/);
  assert.match(restrictBlock, /admin\.auth\(\)\.revokeRefreshTokens\(uid\);/);
  assert.match(restrictBlock, /restrictedRef\.set\(true\);/);
});

test('on transition back to active: re-enables Auth and removes the RTDB '
    + 'restricted mirror (does not re-grant refresh tokens revoked while '
    + 'restricted — forces a fresh login)', () => {
  const body = functionBody();
  const elseIdx = body.indexOf('} else {');
  assert.ok(elseIdx > -1);
  const reactivateBlock = body.slice(elseIdx);

  assert.match(reactivateBlock,
    /admin\.auth\(\)\.updateUser\(uid, \{ disabled: false \}\);/);
  assert.match(reactivateBlock, /restrictedRef\.remove\(\);/);
  assert.doesNotMatch(reactivateBlock, /revokeRefreshTokens/);
});

test('the RTDB mirror path is restricted/{uid}, matching the '
    + "database.rules.json check", () => {
  const body = functionBody();
  assert.match(body,
    /admin\.database\(\)\.ref\(`restricted\/\$\{uid\}`\)/);
});

test('does not duplicate the admin-tier write-authorization check — the '
    + 'write to users/{uid}.status this trigger reacts to is already '
    + 'tier-gated by firestore.rules (super_admin/operations_admin), so '
    + 'this trigger must not re-implement a caller-role check of its own',
  () => {
    const body = functionBody();
    assert.doesNotMatch(body, /getAdminRole|_assertSuperAdmin|context\.auth/,
      'onCustomerStatusChange is a background trigger, not a callable — '
        + 'it has no context.auth to check; authorization is enforced by '
        + 'firestore.rules on the write that triggers it');
  });

// ── firestore.rules: isActiveCustomer() and its 3 call sites ──────────────

test('firestore.rules defines isActiveCustomer() as a live status re-check '
    + 'layered on isCustomer()', () => {
  assert.match(rules, /function isActiveCustomer\(\) \{/);
  const start = rules.indexOf('function isActiveCustomer() {');
  const end = rules.indexOf('\n    }', start);
  const block = rules.slice(start, end);
  assert.match(block, /isCustomer\(\)/);
  assert.match(block, /get\(path\)\.data\.status in \['suspended', 'banned'\]/);
  assert.match(block, /exists\(path\)/,
    'must guard get() with exists() like getAdminRole() does, to avoid '
      + 'erroring on a users/{uid} doc that legitimately does not exist yet');
});

test('isActiveCustomer() is referenced in exactly 3 places besides its own '
    + 'declaration — no read/update/write rule anywhere uses it', () => {
  const codeLines = rules.split('\n').filter((rawLine) => {
    const line = rawLine.trim();
    if (!line.includes('isActiveCustomer()')) return false;
    if (line.startsWith('//')) return false;
    if (line.startsWith('function isActiveCustomer()')) return false;
    return true;
  });
  assert.equal(codeLines.length, 3,
    'expected exactly 3 code references to isActiveCustomer() outside its '
      + 'own declaration (bookings/reviews/rewardRedemptions create) — a '
      + 'different count means either a call site is missing or it leaked '
      + 'into an unrelated rule');
  for (const line of codeLines) {
    assert.doesNotMatch(line, /allow (read|update|delete|write):/,
      'isActiveCustomer() must only ever gate a create rule, never read/'
        + 'update/write — this batch does not change data visibility');
  }
});

test('bookings/{bookingId} create uses isActiveCustomer(), not the bare '
    + 'isCustomer()', () => {
  const start = rules.indexOf('match /bookings/{bookingId}');
  const end = rules.indexOf('lat/lng ບໍ່ຢູ່ໃນ list', start);
  assert.ok(start > -1 && end > start);
  const block = rules.slice(start, end);
  assert.match(block, /request\.resource\.data\.customerId == request\.auth\.uid && isActiveCustomer\(\)/);
});

test('reviews/{reviewId} create uses isActiveCustomer()', () => {
  const start = rules.indexOf('match /reviews/{reviewId}');
  const end = rules.indexOf('match /wallets/{uid}');
  assert.ok(start > -1 && end > start);
  const block = rules.slice(start, end);
  assert.match(block, /allow create: if isActiveCustomer\(\) &&/);
});

test('rewardRedemptions/{reqId} create uses isActiveCustomer()', () => {
  const start = rules.indexOf('match /rewardRedemptions/{reqId}');
  const end = rules.indexOf('\n    }', start);
  assert.ok(start > -1 && end > start);
  const block = rules.slice(start, end);
  assert.match(block, /allow create: if isActiveCustomer\(\) &&/);
});

test('no unrelated rule was touched: bookings/reviews/rewardRedemptions '
    + 'read rules and every other isCustomer()/isProvider() call site are '
    + 'unchanged', () => {
  // isCustomer() itself must still exist, unmodified, for callers that
  // intentionally do NOT need the extra live-status re-check (this batch
  // only ever ADDS a stricter helper, it never edits isCustomer()'s body).
  assert.match(rules, /function isCustomer\(\) \{\s*\n\s*return isAuth\(\) && getRole\(\) == 'customer';\s*\n\s*\}/);
  // Booking/review read rules were explicitly out of scope.
  assert.match(rules, /allow read: if isAuth\(\) && \(\s*\n\s*resource == null \|\|/,
    'bookings read rule must be byte-for-byte unchanged');
  assert.match(rules, /match \/reviews\/\{reviewId\} \{\s*\n\s*allow read: if isAuth\(\);/,
    'reviews read rule must be unchanged');
});

// ── database.rules.json: restricted/{uid} mirror enforcement ──────────────

test('chats/$chatId/meta .write denies a restricted user', () => {
  const metaWrite = dbRules.rules.chats.$chatId.meta['.write'];
  assert.match(metaWrite, /root\.child\('restricted'\)\.child\(auth\.uid\)\.val\(\) != true/);
});

test('the restricted check was added without weakening the existing '
    + 'identity/participant checks already in meta .write', () => {
  const metaWrite = dbRules.rules.chats.$chatId.meta['.write'];
  assert.match(metaWrite, /data\.exists\(\)/);
  assert.match(metaWrite,
    /auth\.uid == data\.child\('customerId'\)\.val\(\) \|\| auth\.uid == data\.child\('providerId'\)\.val\(\)/);
  assert.match(metaWrite,
    /newData\.child\('customerId'\)\.val\(\) == data\.child\('customerId'\)\.val\(\)/);
  assert.match(metaWrite,
    /newData\.child\('providerId'\)\.val\(\) == data\.child\('providerId'\)\.val\(\)/);
});

test('meta .read and the customerId/providerId field-level .write:false '
    + 'immutability locks are untouched', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(meta.customerId['.write'], false);
  assert.equal(meta.providerId['.write'], false);
  assert.doesNotMatch(meta['.read'], /restricted/,
    'restricted enforcement is scoped to write only in this batch — a '
      + 'restricted customer/provider can still read their own chat '
      + 'history, which was an explicit design decision (data visibility '
      + 'is not revoked, only new writes are)');
});

// ── CORRECTIVE FIX: chats/$chatId/messages .write ──────────────────────────
//
// The initial round of this batch only gated chats/$chatId/meta .write —
// independent review found that ChatService._sendMessage()
// (lib/chat_screen.dart) writes the actual message via a SEPARATE RTDB
// call (_msgsRef.push().set(...)) from the meta update
// (_chatMetaRef.update({lastMessage, lastMessageAt})), so a restricted
// customer could still send real message content even though their meta
// write was denied. This section proves the corrective fix: the exact
// same restricted/{uid} conjunct is now also present on messages .write.
// Deeper behavioral proof (active/restricted customer & provider, senderId
// spoofing, H-1 identity protection untouched) lives in
// initialize-booking-chat.test.js's simulateMessagesWrite() scenarios
// P-W, which share the same CUSTOMER_UID/PROVIDER_UID/OTHER_UID fixtures
// and rule-drift guard pattern already established there for meta .write.

test('chats/$chatId/messages .write requires the exact restricted '
    + 'conjunct specified for this corrective fix', () => {
  const messagesWrite = dbRules.rules.chats.$chatId.messages['.write'];
  assert.match(messagesWrite,
    /!root\.child\('restricted'\)\.child\(auth\.uid\)\.val\(\)/);
});

test('messages .write preserves every pre-existing participant condition '
    + '— the restricted check was appended with &&, not substituted for '
    + 'the customerId/providerId check', () => {
  const messagesWrite = dbRules.rules.chats.$chatId.messages['.write'];
  assert.match(messagesWrite, /auth != null/);
  assert.match(messagesWrite,
    /auth\.uid == root\.child\('chats'\)\.child\(\$chatId\)\.child\('meta'\)\.child\('customerId'\)\.val\(\)/);
  assert.match(messagesWrite,
    /auth\.uid == root\.child\('chats'\)\.child\(\$chatId\)\.child\('meta'\)\.child\('providerId'\)\.val\(\)/);
});

test('messages .read is unchanged — not restricted-gated (data visibility '
    + 'is not revoked, only new writes are, same design decision as '
    + 'meta .read)', () => {
  const messagesRead = dbRules.rules.chats.$chatId.messages['.read'];
  assert.doesNotMatch(messagesRead, /restricted/);
  assert.match(messagesRead,
    /auth\.uid == root\.child\('chats'\)\.child\(\$chatId\)\.child\('meta'\)\.child\('customerId'\)\.val\(\)/);
});

test('senderId field-level .validate is byte-for-byte unchanged — the '
    + 'corrective fix only touches .write authorization, never the '
    + 'identity-claim validation', () => {
  const validate = dbRules.rules.chats.$chatId.messages.$messageId.senderId['.validate'];
  assert.equal(validate, "newData.val() == auth.uid");
});

test('meta .write (H-1 identity protection) is untouched by this '
    + 'corrective round — still includes the identity-unchanged checks '
    + 'and its own (earlier) restricted conjunct', () => {
  const metaWrite = dbRules.rules.chats.$chatId.meta['.write'];
  assert.match(metaWrite,
    /newData\.child\('customerId'\)\.val\(\) == data\.child\('customerId'\)\.val\(\)/);
  assert.match(metaWrite,
    /newData\.child\('providerId'\)\.val\(\) == data\.child\('providerId'\)\.val\(\)/);
  assert.match(metaWrite,
    /root\.child\('restricted'\)\.child\(auth\.uid\)\.val\(\) != true/);
});
