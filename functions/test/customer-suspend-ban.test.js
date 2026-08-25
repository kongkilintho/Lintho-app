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

// 🔒 [BATCH I — I-2, 2026-08-25] applyCustomerRestriction() is now the
// single implementation of the actual restrict/reactivate operations
// (extracted out of the trigger body so the backfill script can reuse it in
// principle — see that function's own comment for why the script currently
// carries its own mirrored copy instead). Extracted the same way
// functionBody() extracts the trigger, bounded by its own declaration and
// closing brace.
function helperBody() {
  const start = source.indexOf('async function applyCustomerRestriction');
  assert.ok(start > -1, 'applyCustomerRestriction must exist');
  const end = source.indexOf('\n}', start);
  assert.ok(end > start);
  return source.slice(start, end);
}

test('onCustomerStatusChange is a users/{uid} onUpdate trigger with '
    + 'failurePolicy retry enabled (Batch I — I-2.D)', () => {
  const body = functionBody();
  assert.match(body,
    /functions\s*\n\s*\.runWith\(\{ failurePolicy: true \}\)\s*\n\s*\.firestore\s*\n\s*\.document\('users\/\{uid\}'\)/);
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

test('treats suspended and banned identically via one restricted-status set '
    + '— RESTRICTED_CUSTOMER_STATUSES is hoisted to module scope (Batch I) '
    + 'so the trigger, applyCustomerRestriction(), and the backfill script '
    + 'all classify status identically', () => {
  assert.match(source,
    /const RESTRICTED_CUSTOMER_STATUSES = \[\s*'suspended',\s*'banned',?\s*\];/);
  const body = functionBody();
  assert.match(body, /RESTRICTED_CUSTOMER_STATUSES\.includes\(before\.status\)/);
  assert.match(body, /RESTRICTED_CUSTOMER_STATUSES\.includes\(after\.status\)/);
  const helper = helperBody();
  assert.match(helper, /RESTRICTED_CUSTOMER_STATUSES\.includes\(status\)/);
});

test('is a no-op when the restricted state does not change (covers '
    + 'suspended<->banned transitions and the unrelated legacy '
    + "provider 'pending' marker)", () => {
  const body = functionBody();
  assert.match(body, /if \(wasRestricted === isRestricted\) return null;/);
});

test('the trigger delegates to applyCustomerRestriction() rather than '
    + 'inlining Admin SDK calls itself (Batch I — single implementation, '
    + 'reused in principle by the backfill script)', () => {
  const body = functionBody();
  assert.match(body,
    /const result = await applyCustomerRestriction\(uid, \{ source: 'trigger' \}\);/);
  assert.doesNotMatch(body, /admin\.auth\(\)\.updateUser/,
    'Admin SDK mutation calls must live in applyCustomerRestriction(), not '
      + 'be duplicated inline in the trigger');
});

test('Batch I — I-2.C/D: a partial failure is re-thrown, not swallowed — '
    + 'observable in Cloud Functions logs and, with failurePolicy enabled, '
    + 'eligible for automatic retry', () => {
  const body = functionBody();
  assert.match(body, /if \(result\.errors\.length > 0\)/);
  assert.match(body, /throw new Error\(/);
});

test('Batch I — I-2.A live-state protection: applyCustomerRestriction() '
    + 're-reads the LIVE users/{uid} doc before deciding anything, instead '
    + 'of trusting the trigger event\'s before/after snapshot — this is '
    + 'what makes a stale/replayed event converge to current truth instead '
    + 'of reapplying an outdated decision', () => {
  const helper = helperBody();
  assert.match(helper, /const userRef = db\.collection\('users'\)\.doc\(uid\);/);
  assert.match(helper, /const userSnap = await userRef\.get\(\);/);
  // The restrict/no-restrict decision must be derived from userSnap (the
  // fresh read), never from the trigger's before/after parameters — those
  // are not even in scope inside this function.
  assert.doesNotMatch(helper, /\bbefore\.|after\./,
    'applyCustomerRestriction must not reference the trigger event\'s '
      + 'before/after snapshot — it only knows uid and re-reads live data');
});

test('Batch I — I-2.B idempotency: every operation applyCustomerRestriction '
    + 'performs is individually safe to repeat, and the decision itself is '
    + 're-derived from live data on every call, so repeated/duplicate '
    + 'invocations converge to the same final state', () => {
  const helper = helperBody();
  // Promise.allSettled (not Promise.all / sequential awaits) — one op
  // failing must not prevent the others from running (I-2.C).
  assert.match(helper, /Promise\.allSettled\(\[/);
  const restrictIdx = helper.indexOf('if (shouldRestrict) {');
  const elseIdx = helper.indexOf('} else {');
  assert.ok(restrictIdx > -1 && elseIdx > restrictIdx);
  const restrictBlock = helper.slice(restrictIdx, elseIdx);
  const reactivateBlock = helper.slice(elseIdx);

  assert.match(restrictBlock, /admin\.auth\(\)\.updateUser\(uid, \{ disabled: true \}\)/);
  assert.match(restrictBlock, /admin\.auth\(\)\.revokeRefreshTokens\(uid\)/);
  assert.match(restrictBlock, /restrictedRef\.set\(true\)/);

  assert.match(reactivateBlock, /admin\.auth\(\)\.updateUser\(uid, \{ disabled: false \}\)/);
  assert.match(reactivateBlock, /restrictedRef\.remove\(\)/);
  assert.doesNotMatch(reactivateBlock, /revokeRefreshTokens/,
    'reactivation must not re-grant refresh tokens revoked while '
      + 'restricted — forces a fresh login, unchanged from pre-Batch-I '
      + 'behavior');
});

test('the RTDB mirror path is restricted/{uid}, matching the '
    + "database.rules.json check", () => {
  const helper = helperBody();
  assert.match(helper,
    /admin\.database\(\)\.ref\(`restricted\/\$\{uid\}`\)/);
});

test('Batch I — I-2.C safe logging: structured, uid-scoped, and never '
    + 'includes tokens/credentials/PII beyond uid+status', () => {
  const helper = helperBody();
  assert.match(helper, /functions\.logger\.error\('applyCustomerRestriction: partial failure'/);
  assert.match(helper, /functions\.logger\.info\('applyCustomerRestriction: applied'/);

  // Scope the "no raw secret/token value" check to the actual log payload
  // object, not the whole function — revokeRefreshTokens/'revoke-refresh-
  // tokens' are legitimate Admin SDK method/op names elsewhere in this
  // function, not logged secret values, and would otherwise false-positive
  // against a naive whole-body regex.
  const payloadStart = helper.indexOf('const logPayload = {');
  const payloadEnd = helper.indexOf('};', payloadStart);
  assert.ok(payloadStart > -1 && payloadEnd > payloadStart);
  const payload = helper.slice(payloadStart, payloadEnd);
  assert.match(payload, /uid,/);
  assert.match(payload, /status:/);
  assert.match(payload, /targetRestricted: shouldRestrict,/);
  assert.doesNotMatch(payload, /idToken|password|secret|apiKey|token:/i,
    'log payload must never include a raw token/credential value — only '
      + 'uid, status, targetRestricted, and source');
});

test('applyCustomerRestriction() skips (does not throw, does not touch '
    + 'Auth/RTDB) when the users/{uid} doc does not exist or role is not '
    + "customer — Batch I — I-2.E: a missing doc or non-customer role must "
    + 'never be treated as an authorized restrict/reactivate transition',
  () => {
    const helper = helperBody();
    assert.match(helper, /if \(!userSnap\.exists\) \{/);
    assert.match(helper, /reason: 'user-doc-missing'/);
    assert.match(helper, /if \(role !== 'customer'\) \{/);
    assert.match(helper, /reason: 'not-a-customer'/);
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

test('applyCustomerRestriction() and RESTRICTED_CUSTOMER_STATUSES are '
    + 'exported (underscore-prefixed) for the backfill script to reuse, and '
    + 'a plain function export carries no firebase-functions trigger '
    + 'metadata — the Firebase CLI deploy step will not mistake it for a '
    + 'deployable Cloud Function', () => {
  assert.match(source, /exports\._applyCustomerRestriction = applyCustomerRestriction;/);
  assert.match(source, /exports\._RESTRICTED_CUSTOMER_STATUSES = RESTRICTED_CUSTOMER_STATUSES;/);
});

// ── Batch I — I-2.E: all 6 explicit state transitions + malformed/missing
// status classification, modeled in plain JS against the exact same
// RESTRICTED_CUSTOMER_STATUSES.includes(...) expression the real code uses
// (drift-guarded below, same pattern as EXPECTED_META_WRITE_RULE in
// initialize-booking-chat.test.js). This is still a structural/behavioral
// simulation, not a live Firestore/Auth/RTDB run (this repo has no
// emulator — see file header) — it proves the CLASSIFICATION logic is
// correct for every transition, not that the real Admin SDK calls actually
// land at runtime.

const RESTRICTED_CUSTOMER_STATUSES_MODEL = ['suspended', 'banned'];

function classifyRestricted(status) {
  return RESTRICTED_CUSTOMER_STATUSES_MODEL.includes(status);
}

test('behavioral-sim setup: the live RESTRICTED_CUSTOMER_STATUSES constant '
    + 'exactly matches what the simulation below models (fails loudly on '
    + 'drift)', () => {
  assert.match(source, /const RESTRICTED_CUSTOMER_STATUSES = \['suspended', 'banned'\];/);
});

const TRANSITIONS = [
  ['active', 'suspended', false, true],
  ['active', 'banned', false, true],
  ['suspended', 'active', true, false],
  ['banned', 'active', true, false],
  ['suspended', 'banned', true, true],
  ['banned', 'suspended', true, true],
];

for (const [before, after, expectedWas, expectedIs] of TRANSITIONS) {
  test(`transition ${before} -> ${after}: wasRestricted=${expectedWas}, `
      + `isRestricted=${expectedIs}, fires=${expectedWas !== expectedIs}`, () => {
    const wasRestricted = classifyRestricted(before);
    const isRestricted = classifyRestricted(after);
    assert.equal(wasRestricted, expectedWas);
    assert.equal(isRestricted, expectedIs);
    const fires = wasRestricted !== isRestricted;
    assert.equal(fires, expectedWas !== expectedIs);
  });
}

test('missing status (undefined) classifies as not-restricted — the '
    + 'existing, intended fallback (same as getRole()/isActiveCustomer() '
    + 'treating an absent field as the permissive default), preserved '
    + 'rather than changed to fail-closed', () => {
  assert.equal(classifyRestricted(undefined), false);
  assert.equal(classifyRestricted(null), false);
});

test('unknown/malformed status values never classify as restricted — no '
    + 'crash, no accidental match, regardless of type', () => {
  assert.equal(classifyRestricted('pending_review'), false);
  assert.equal(classifyRestricted(123), false);
  assert.equal(classifyRestricted({ weird: true }), false);
  assert.equal(classifyRestricted(['suspended']), false);
});

test('repeated event: applying the same transition twice converges to the '
    + 'same classification both times (idempotency at the classification '
    + 'level — the live-re-read in applyCustomerRestriction() extends this '
    + 'to the actual Admin SDK operations, see the I-2.B test above)', () => {
  const first = classifyRestricted('suspended');
  const second = classifyRestricted('suspended');
  assert.equal(first, second);
  assert.equal(first, true);
});

test('stale event simulation: a status classification is always derived '
    + 'from the CURRENT value passed in, never from a previously-observed '
    + 'one — modeling why a stale trigger event (old before/after) cannot '
    + 'corrupt the live-re-read decision in applyCustomerRestriction()', () => {
  // The event says "restrict" (stale, from when status was 'suspended')...
  const staleEventSaysRestrict = classifyRestricted('suspended');
  assert.equal(staleEventSaysRestrict, true);
  // ...but by the time applyCustomerRestriction() actually re-reads the
  // live doc, the customer has already been reactivated. The classification
  // is a pure function of whatever is passed in "now" — it has no memory of
  // the stale value, which is exactly the property that makes the live
  // re-read safe.
  const liveStatusNow = 'active';
  const actualDecision = classifyRestricted(liveStatusNow);
  assert.equal(actualDecision, false,
    'the live re-read must win over the stale event\'s implied decision');
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

// ── Batch I — I-3: firestore.rules chats/{chatId} restricted-write gap ────
//
// The audit that authorized this batch found chats/{chatId}'s Firestore-
// side update rule (lastMessage/lastMessageAt, the chat-list preview) had
// no restricted-status check at all — unlike the RTDB-side meta/messages
// .write rules above, which already do. isRestrictedUser(uid) closes that
// gap. It deliberately does NOT reuse isActiveCustomer() (which requires
// isCustomer(), i.e. getRole()=='customer' — false for a legitimate
// provider participant, which would wrongly block them too) — it checks
// the same users/{uid}.status field for whichever uid is passed in, with
// no role requirement, mirroring the RTDB rule's own uniform semantics.

test('firestore.rules defines isRestrictedUser(uid) as a live, role-agnostic '
    + 'status check (distinct from isActiveCustomer(), which is customer-'
    + 'role-specific)', () => {
  assert.match(rules, /function isRestrictedUser\(uid\) \{/);
  const start = rules.indexOf('function isRestrictedUser(uid) {');
  const end = rules.indexOf('\n    }', start);
  const block = rules.slice(start, end);
  assert.match(block, /exists\(path\)/,
    'must guard get() with exists() like isActiveCustomer()/getAdminRole() do');
  assert.match(block, /get\(path\)\.data\.status in \['suspended', 'banned'\]/);
  assert.doesNotMatch(block, /isCustomer\(\)|getRole\(\)/,
    'isRestrictedUser() must not require any particular role — it is used '
      + 'for both customer and provider chat participants');
});

test('isRestrictedUser() is referenced in exactly 1 place besides its own '
    + 'declaration — only chats/{chatId} update, matching the audit\'s '
    + 'minimal-fix scope (I-3)', () => {
  const codeLines = rules.split('\n').filter((rawLine) => {
    const line = rawLine.trim();
    if (!line.includes('isRestrictedUser(')) return false;
    if (line.startsWith('//')) return false;
    if (line.startsWith('function isRestrictedUser(')) return false;
    return true;
  });
  assert.equal(codeLines.length, 1,
    'expected exactly 1 code reference to isRestrictedUser() outside its '
      + 'own declaration (chats/{chatId} update) — a different count means '
      + 'either the call site is missing or it leaked into an unrelated rule');
  assert.match(codeLines[0], /!isRestrictedUser\(request\.auth\.uid\)/,
    'the sole reference must be the negated conjunct added to chats/'
      + '{chatId} update — the same call site checked precisely in the '
      + 'dedicated test below');
});

test('chats/{chatId} update requires !isRestrictedUser(request.auth.uid), '
    + 'added as an additional && conjunct — membership, identity '
    + '(members immutability), and the field allowlist are unchanged', () => {
  const start = rules.indexOf('match /chats/{chatId}');
  const end = rules.indexOf('allow delete: if false;', start);
  assert.ok(start > -1 && end > start);
  const block = rules.slice(start, end);

  // Unchanged from before Batch I.
  assert.match(block, /allow read: if isAuth\(\) && request\.auth\.uid in resource\.data\.members;/);
  assert.match(block, /allow create: if false;/);

  const updateStart = block.indexOf('allow update:');
  assert.ok(updateStart > -1);
  const updateRule = block.slice(updateStart);
  assert.match(updateRule, /isAuth\(\) && request\.auth\.uid in resource\.data\.members/,
    'membership check must remain intact');
  assert.match(updateRule, /!isRestrictedUser\(request\.auth\.uid\)/,
    'the new restricted-status check must be present');
  assert.match(updateRule, /request\.resource\.data\.members == resource\.data\.members/,
    'identity (members immutability) check must remain intact');
  assert.match(updateRule,
    /request\.resource\.data\.diff\(resource\.data\)\.affectedKeys\(\)\s*\n\s*\.hasOnly\(\['lastMessage', 'lastMessageAt'\]\);/,
    'field allowlist must remain exactly lastMessage/lastMessageAt');
});

test('chats/{chatId} read is NOT restricted-gated — data visibility is not '
    + 'revoked for a restricted participant, only new writes are, matching '
    + 'the same design decision already made for RTDB meta/messages .read', () => {
  const start = rules.indexOf('match /chats/{chatId}');
  const readEnd = rules.indexOf('allow create:', start);
  const readBlock = rules.slice(start, readEnd);
  assert.doesNotMatch(readBlock, /isRestrictedUser/);
});

// Behavioral simulation of the updated chats/{chatId} update rule, mirroring
// this file's own EXPECTED_META_WRITE_RULE / EXPECTED_MESSAGES_WRITE_RULE
// pattern from initialize-booking-chat.test.js. This models the RULE TEXT's
// boolean logic in plain JS, drift-guarded against the live rule string
// below — still not a live rules-emulator run (this repo has none — see
// file header), it proves the EXPRESSION is correct, not that Firestore's
// rule engine evaluates it identically at runtime.

const EXPECTED_CHAT_UPDATE_RULE_TAIL =
  "allow update: if isAuth() && request.auth.uid in resource.data.members &&\n" +
  "        !isRestrictedUser(request.auth.uid) &&\n" +
  "        request.resource.data.members == resource.data.members &&\n" +
  "        request.resource.data.diff(resource.data).affectedKeys()\n" +
  "          .hasOnly(['lastMessage', 'lastMessageAt']);";

test('behavioral-sim setup (chats/{chatId} update): the live rule string '
    + 'exactly matches what the simulation below models (fails loudly on '
    + 'drift)', () => {
  // Normalize CRLF -> LF for this exact-text comparison — firestore.rules is
  // checked in with CRLF line endings; the \s*\n\s*-style regexes elsewhere
  // in this file tolerate that naturally (\s matches \r), but a literal
  // indexOf() needs the same normalization applied to both sides.
  const normalizedRules = rules.replace(/\r\n/g, '\n');
  const idx = normalizedRules.indexOf(EXPECTED_CHAT_UPDATE_RULE_TAIL);
  assert.ok(idx > -1, 'chats/{chatId} allow update: text drifted from what '
    + 'this simulation models — update EXPECTED_CHAT_UPDATE_RULE_TAIL to match');
});

function simulateChatDocUpdate({ authUid, members, incomingMembers, affectedKeys, restrictedUids = new Set() }) {
  const authNotNull = authUid !== null && authUid !== undefined;
  const isMember = members.includes(authUid);
  const notRestricted = !restrictedUids.has(authUid);
  const membersUnchanged = JSON.stringify(incomingMembers) === JSON.stringify(members);
  const onlyAllowedFields = affectedKeys.every((k) => ['lastMessage', 'lastMessageAt'].includes(k));
  return authNotNull && isMember && notRestricted && membersUnchanged && onlyAllowedFields;
}

const CHAT_CUSTOMER_UID = 'customer-1';
const CHAT_PROVIDER_UID = 'provider-1';
const CHAT_OTHER_UID = 'unrelated-user';
const chatMembers = [CHAT_CUSTOMER_UID, CHAT_PROVIDER_UID];

test('an active customer CAN update lastMessage/lastMessageAt on the chat doc', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_CUSTOMER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage', 'lastMessageAt'],
  }), true);
});

test('an active provider CAN update lastMessage/lastMessageAt on the chat doc', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_PROVIDER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage'],
  }), true);
});

test('a restricted customer CANNOT update the chat doc directly — this is '
    + 'the exact gap I-3 closes (a modified client / direct SDK call could '
    + 'previously write lastMessage/lastMessageAt here even while '
    + 'suspended/banned)', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_CUSTOMER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage', 'lastMessageAt'],
    restrictedUids: new Set([CHAT_CUSTOMER_UID]),
  }), false);
});

test('a restricted provider CANNOT update the chat doc either — no '
    + 'customer-vs-provider special-casing, same as the RTDB-side check', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_PROVIDER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage'],
    restrictedUids: new Set([CHAT_PROVIDER_UID]),
  }), false);
});

test('the OTHER (non-restricted) participant is unaffected by their '
    + 'counterparty being restricted', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_PROVIDER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage'],
    restrictedUids: new Set([CHAT_CUSTOMER_UID]),
  }), true);
});

test('an unrelated (non-member) user is denied regardless of restricted '
    + 'status — membership check is unchanged and evaluated independently', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_OTHER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage'],
  }), false);
});

test('members cannot be changed in the same write, even by an active, '
    + 'non-restricted participant — identity immutability is unchanged', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_CUSTOMER_UID, members: chatMembers,
    incomingMembers: [CHAT_CUSTOMER_UID, CHAT_OTHER_UID],
    affectedKeys: ['lastMessage'],
  }), false);
});

test('fields outside the allowlist cannot be written, even by an active, '
    + 'non-restricted participant — field allowlist is unchanged', () => {
  assert.equal(simulateChatDocUpdate({
    authUid: CHAT_CUSTOMER_UID, members: chatMembers, incomingMembers: chatMembers,
    affectedKeys: ['lastMessage', 'customerId'],
  }), false);
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
