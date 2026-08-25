// ============================================================
// initialize-booking-chat.test.js — LinTho Cloud Functions
//
// Regression tests for H-1 (Batch H): chat-room squatting/impersonation.
// initializeBookingChat (index.js) is the server-trusted replacement for
// the client directly writing chats/{bookingId}_chat (Firestore) and
// chats/{bookingId}_chat/meta (Realtime Database) — see the fix's own
// header comment in index.js for the full exploit trace and rationale.
//
// ໝາຍເຫດ: index.js ໂຫລດ Firebase Admin SDK ຕອນ import (calls
// admin.initializeApp() at module scope) — ບໍ່ import ໂດຍກົງນອກ emulator
// (ຄືກັນກັບ delete-own-account.test.js/referral-signup-voucher.test.js),
// ໃຊ້ source-text regression guard ແທນ. THESE TESTS DO NOT PROVE RUNTIME
// SECURITY SEMANTICS — they verify the function's source contains the
// checks the threat model requires, in the right order, with no
// bypassable gaps in the *text* of the logic. They cannot catch a bug in
// how the Firestore/RTDB Admin SDK or the rules engine actually evaluates
// those checks at runtime. A rules-emulator + functions-emulator
// integration test (this repo has neither) would be required to prove the
// runtime behavior — flagged as a known gap, consistent with this
// project's existing test-coverage limitations (see rules_fixes_test.dart's
// own header note for the equivalent limitation on the Dart side).
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
  const start = source.indexOf('exports.initializeBookingChat');
  assert.ok(start > -1, 'initializeBookingChat must exist');
  const end = source.indexOf('\n});', start);
  assert.ok(end > start);
  return source.slice(start, end);
}

// ── AUTHORIZATION ──────────────────────────────────────────

test('1. rejects an unauthenticated caller', () => {
  const body = functionBody();
  assert.match(body, /if\s*\(!context\.auth\)/);
  assert.match(body, /unauthenticated/);
});

test('2/3/4. only the booking\'s real customerId or providerId may proceed '
  + '— anyone else is rejected', () => {
  const body = functionBody();
  assert.match(body, /callerUid\s*!==\s*customerId\s*&&\s*callerUid\s*!==\s*providerId/,
    'must reject unless caller matches customerId OR providerId from the booking');
  assert.match(body, /permission-denied/);
});

test('5. a booking with no assigned provider yet blocks initialization '
  + '(the core H-1 fix — a candidate provider cannot claim providerId '
  + 'before actually accepting the job)', () => {
  const body = functionBody();
  // The providerId emptiness check must appear before the
  // caller-is-customer-or-provider check, so an empty providerId can never
  // accidentally match an empty-string caller comparison.
  const providerCheckIdx = body.search(/typeof providerId !== 'string' \|\| !providerId/);
  const callerCheckIdx = body.indexOf('callerUid !== customerId');
  assert.ok(providerCheckIdx > -1, 'must check providerId is a non-empty string');
  assert.ok(callerCheckIdx > -1);
  assert.ok(providerCheckIdx < callerCheckIdx,
    'the empty-providerId rejection must happen before the caller-match check');
  assert.match(body, /failed-precondition/);
});

// ── BOOKING ─────────────────────────────────────────────────

test('6. rejects a nonexistent booking', () => {
  const body = functionBody();
  assert.match(body, /!bookingSnap\.exists/);
  assert.match(body, /not-found/);
});

test('7. rejects a booking with an empty providerId (duplicate of #5, '
  + 'checked from the "booking state" angle)', () => {
  const body = functionBody();
  assert.match(body, /providerId/);
  assert.match(body, /failed-precondition/);
});

// ── IDENTITY (server-derived, not client-supplied) ──────────

test('8/9. customerId and providerId are read from the booking document, '
  + 'never from the client payload', () => {
  const body = functionBody();
  assert.match(body, /const customerId = booking\.customerId/);
  assert.match(body, /const providerId = booking\.providerId/);
  // The only field ever read off `data` (the client payload) is bookingId.
  const dataReads = body.match(/data\.[a-zA-Z]+/g) || [];
  const nonBookingIdReads = dataReads.filter((m) => m !== 'data.bookingId');
  assert.deepEqual(nonBookingIdReads, [],
    `client payload fields must only ever include bookingId, found: ${nonBookingIdReads}`);
});

test('10. chatId is derived from bookingId server-side, never accepted '
  + 'from the client', () => {
  const body = functionBody();
  assert.match(body, /const chatId = `\$\{bookingId\}_chat`/);
  assert.doesNotMatch(body, /data\.chatId/);
});

test('11. client cannot override members either — derived from the '
  + 'booking-sourced customerId/providerId only', () => {
  const body = functionBody();
  assert.match(body, /const expectedMembers = \[customerId, providerId\]/);
  assert.doesNotMatch(body, /data\.members/);
});

// ── IDEMPOTENCY ─────────────────────────────────────────────

test('12. creates the Firestore doc when it does not yet exist', () => {
  const body = functionBody();
  assert.match(body, /if \(!chatDoc\.exists\)\s*\{\s*\n\s*await chatRef\.set\(/);
});

test('13/14. a second call with matching existing Firestore + RTDB '
  + 'identity is treated as idempotent success, not an error', () => {
  const body = functionBody();
  // The Firestore "else" branch only throws on mismatch — falling through
  // without throwing when membersMatch/customerId/providerId/bookingId all
  // agree is the idempotent-success path (no explicit "return success"
  // needed; the function simply continues to the RTDB section and finally
  // returns { chatId }).
  const firestoreElseIdx = body.indexOf('} else {', body.indexOf('chatRef.get()'));
  assert.ok(firestoreElseIdx > -1);
  const firestoreElseBlock = body.slice(firestoreElseIdx, body.indexOf("stage: 'firestore'", firestoreElseIdx) + 40);
  assert.match(firestoreElseBlock, /membersMatch/);
  assert.match(body, /return \{ chatId \};/);
});

test('15. a mismatched existing Firestore identity is rejected, not '
  + 'silently overwritten', () => {
  const body = functionBody();
  const firestoreSection = body.slice(body.indexOf('Firestore: chats'), body.indexOf('Realtime Database:'));
  assert.match(firestoreSection, /existing\.bookingId !== bookingId/);
  assert.match(firestoreSection, /existing\.customerId !== customerId/);
  assert.match(firestoreSection, /existing\.providerId !== providerId/);
  assert.match(firestoreSection, /!membersMatch/);
  assert.match(firestoreSection, /aborted/);
  assert.doesNotMatch(firestoreSection, /chatRef\.set\([^)]*\)\s*;\s*\}\s*else/,
    'the mismatch branch must not re-run chatRef.set(...) — no silent overwrite');
});

test('16. a mismatched existing RTDB identity is rejected, not silently '
  + 'overwritten', () => {
  const body = functionBody();
  const rtdbSection = body.slice(body.indexOf('Realtime Database: chats'));
  assert.match(rtdbSection, /meta\.bookingId !== bookingId/);
  assert.match(rtdbSection, /meta\.customerId !== customerId/);
  assert.match(rtdbSection, /meta\.providerId !== providerId/);
  assert.match(rtdbSection, /aborted/);
});

test('diagnostic logging on mismatch includes bookingId/chatId/callerUid/'
  + 'stage but never KYC or payment data', () => {
  const body = functionBody();
  const logCalls = body.match(/functions\.logger\.error\([^)]*\)[^;]*;/gs) || [];
  assert.equal(logCalls.length, 2, 'expected one log call per database mismatch branch');
  for (const call of logCalls) {
    assert.match(call, /bookingId/);
    assert.match(call, /chatId/);
    assert.match(call, /callerUid/);
    assert.match(call, /stage/);
    assert.doesNotMatch(call, /kyc|selfie|bankAccount|slipUrl/i);
  }
});

// ── SECURITY (rules-level enforcement) ──────────────────────

test('17. Firestore denies direct client creation of chats/{chatId}', () => {
  const start = rules.indexOf('match /chats/{chatId}');
  assert.ok(start > -1);
  const end = rules.indexOf('allow delete: if false;', start);
  const block = rules.slice(start, end);
  assert.match(block, /allow create: if false;/,
    'chats/{chatId} create must be fully client-denied now that '
    + 'initializeBookingChat is the only legitimate writer');
  // read/update must remain intact for the two real participants.
  assert.match(block, /allow read: if isAuth\(\) && request\.auth\.uid in resource\.data\.members;/);
  assert.match(block, /allow update: if isAuth\(\) && request\.auth\.uid in resource\.data\.members/);
});

// 🔒 [FIX / post-H-1 correction] The original H-1 pass set chats/$chatId/
// meta's `.write` to the literal boolean `false`, on the theory that only
// initializeBookingChat (Admin SDK) should ever write there. That was too
// broad: `.write` at the `meta` node also gates legitimate, ongoing,
// non-identity writes that live under the same node — _markAsRead()'s
// `unread_${uid}` reset and _sendMessage()'s `lastMessage`/`lastMessageAt`
// update (both in lib/chat_screen.dart) — silently breaking the unread
// badge and, worse, making every message send throw a false
// "permission-denied" error immediately AFTER the message itself had
// already saved successfully (the message write and the meta write are
// separate RTDB calls; only the second one failed, but the client's error
// handling couldn't tell the difference).
//
// IMPORTANT — why this ISN'T simply "grant .write at meta, deny it at
// customerId/providerId": Realtime Database .write rules CASCADE
// DOWNWARD ONLY as grants — once a shallower node's .write evaluates
// true, it authorizes writes to every descendant regardless of what a
// deeper node's own .write says. A deeper `.write: false` on customerId/
// providerId can never "re-lock" what a permissive .write at meta already
// unlocked. So the real fix has to bake the "customerId/providerId must
// stay unchanged" condition directly into meta's own .write expression
// (newData.child('customerId').val() == data.child('customerId').val(),
// same for providerId) — that's what actually blocks identity mutation,
// for every possible caller, including an already-legitimate participant
// trying to alter it. The field-level `.write: false` on customerId/
// providerId below is kept anyway as explicit, defense-in-depth
// documentation of intent, not as the primary enforcement mechanism (per
// the cascade rule above, it's unreachable as long as meta's own
// condition never grants true for an identity-changing write — which is
// what the tests below verify).
test('18a. meta .write is no longer a bare `false` — it is a conditional '
  + 'expression (a literal `false` here would re-break unread_*/'
  + 'lastMessage, the exact bug this fix corrects)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(typeof meta['.write'], 'string',
    'meta .write must be a rule expression string, not the literal '
    + 'boolean false — see the comment above for why a bare false is '
    + 'the bug, not the fix');
});

test('18b. meta .write requires the node to already exist — the client '
  + 'can never CREATE it (only initializeBookingChat, via Admin SDK, can)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.match(meta['.write'], /data\.exists\(\)/);
});

test('18c. meta .write requires the caller to be an already-recognized '
  + 'participant (customerId or providerId already stored)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.match(meta['.write'],
    /auth\.uid == data\.child\('customerId'\)\.val\(\) \|\| auth\.uid == data\.child\('providerId'\)\.val\(\)/);
});

test('18d. meta .write requires customerId to remain byte-identical to '
  + 'its existing value — this is the load-bearing check that blocks '
  + 'identity mutation, including by an already-legitimate participant', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.match(meta['.write'],
    /newData\.child\('customerId'\)\.val\(\) == data\.child\('customerId'\)\.val\(\)/);
});

test('18e. meta .write requires providerId to remain byte-identical to '
  + 'its existing value (same guarantee as 18d, other field)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.match(meta['.write'],
    /newData\.child\('providerId'\)\.val\(\) == data\.child\('providerId'\)\.val\(\)/);
});

test('18f. meta .write does NOT restrict which OTHER fields may change '
  + '(no hasOnly()/hasChildren()-style allowlist that would also block '
  + 'unread_*/lastMessage/lastMessageAt/serviceName)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.doesNotMatch(meta['.write'], /hasOnly|hasChildren/,
    'the fix must not trade one over-broad restriction for another — '
    + 'only customerId/providerId are constrained, everything else under '
    + 'meta must remain freely writable by a recognized participant');
});

test('18g. customerId/providerId keep an explicit field-level .write: '
  + 'false as defense-in-depth documentation (not the primary enforcement '
  + '— see the comment block above on RTDB\'s downward-cascade-only-as-'
  + 'grants behavior)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(meta.customerId['.write'], false);
  assert.equal(meta.providerId['.write'], false);
});

test('18h. meta .read and messages read/write authorization are '
  + 'untouched by this correction', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(typeof meta['.read'], 'string',
    'meta .read must remain a real rule string (participants can still read)');
  assert.match(meta['.read'], /customerId|providerId/);

  const messages = dbRules.rules.chats.$chatId.messages;
  assert.match(messages['.read'], /meta.*customerId|meta.*providerId/s);
  assert.match(messages['.write'], /meta.*customerId|meta.*providerId/s);
});

// ── BEHAVIORAL SIMULATION ────────────────────────────────────
//
// Everything above is source-text/structural (see the file header). This
// block goes one step further for the specific rule this correction
// touches: it re-implements the meta .write expression's actual boolean
// logic in plain JS and exercises it against concrete before/after data,
// rather than just pattern-matching the rule string. To keep the
// simulation from silently drifting out of sync with the real rule, the
// FIRST test below asserts the live rule string character-for-character
// equals the exact expression this simulation is modeling — if anyone
// edits database.rules.json's meta .write without updating this test, that
// assertion fails loudly, rather than the simulation quietly testing
// something that no longer matches production.
//
// This still isn't a live RTDB emulator run (this repo has none — see
// file header) — it's a hand-verified model of the same expression,
// exercised against the exact scenarios A-M this fix was reviewed against.

const EXPECTED_META_WRITE_RULE =
  "auth != null && data.exists() && " +
  "(auth.uid == data.child('customerId').val() || auth.uid == data.child('providerId').val()) && " +
  "newData.child('customerId').val() == data.child('customerId').val() && " +
  "newData.child('providerId').val() == data.child('providerId').val() && " +
  "root.child('restricted').child(auth.uid).val() != true";

test('behavioral-sim setup: the live rule string exactly matches what '
  + 'the simulation below models (fails loudly on drift)', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(meta['.write'], EXPECTED_META_WRITE_RULE);
});

// Mirrors the rule's own semantics: `data` = existing node before the
// write, `newData` = full resulting node after the write is applied
// (RTDB rules always evaluate against the post-merge result, not just the
// delta) — exactly how a real .update({...}) call's rule evaluation works.
// `restrictedUids` (added for Batch H — Customer suspend/ban enforcement)
// mirrors root.child('restricted').child(auth.uid).val() != true — any uid
// present in this set stands in for a restricted/{uid}: true node written
// by onCustomerStatusChange (index.js). Defaults to an empty set so every
// pre-existing scenario (A-K, 18a-18h) below is unaffected and did not need
// to change when this conjunct was added.
function simulateMetaWrite({ authUid, existing, incomingUpdate, restrictedUids = new Set() }) {
  const data = existing; // may be null (node doesn't exist yet)
  const newData = { ...(existing || {}), ...incomingUpdate };
  const authNotNull = authUid !== null && authUid !== undefined;
  const dataExists = data !== null;
  const callerIsParticipant = dataExists &&
    (authUid === data.customerId || authUid === data.providerId);
  const customerIdUnchanged = dataExists &&
    newData.customerId === data.customerId;
  const providerIdUnchanged = dataExists &&
    newData.providerId === data.providerId;
  const callerNotRestricted = !restrictedUids.has(authUid);
  return authNotNull && dataExists && callerIsParticipant &&
    customerIdUnchanged && providerIdUnchanged && callerNotRestricted;
}

const CUSTOMER_UID = 'customer-1';
const PROVIDER_UID = 'provider-1';
const OTHER_UID     = 'unrelated-user';
const existingMeta = {
  bookingId: 'booking-1', customerId: CUSTOMER_UID, providerId: PROVIDER_UID,
  serviceName: 'AC repair', lastMessage: 'hi', lastMessageAt: 1000,
};

test('A. unauthenticated client cannot modify meta identity', () => {
  assert.equal(simulateMetaWrite({
    authUid: null, existing: existingMeta,
    incomingUpdate: { customerId: OTHER_UID },
  }), false);
});

test('B. the real customer cannot modify customerId/providerId', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { providerId: OTHER_UID },
  }), false);
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { customerId: OTHER_UID },
  }), false);
});

test('C. the real provider cannot modify customerId/providerId', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { providerId: OTHER_UID },
  }), false);
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { customerId: OTHER_UID },
  }), false);
});

test('D. an unrelated user cannot modify meta at all, even non-identity '
  + 'fields', () => {
  assert.equal(simulateMetaWrite({
    authUid: OTHER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'hijack attempt' },
  }), false);
});

test('E. the authorized customer CAN update unread_<customerUid>', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { [`unread_${CUSTOMER_UID}`]: 0 },
  }), true);
});

test('F. the authorized provider CAN update unread_<providerUid>', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { [`unread_${PROVIDER_UID}`]: 3 },
  }), true);
});

test('G. an authorized participant CAN update lastMessage', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'On my way' },
  }), true);
});

test('H. an authorized participant CAN update lastMessageAt', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { lastMessageAt: 2000 },
  }), true);
});

test('I. sending a message\'s metadata update (lastMessage + '
  + 'lastMessageAt together, the exact _sendMessage() payload) succeeds — '
  + 'this is the specific write that previously threw permission-denied '
  + 'right after the message itself had already saved', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'On my way', lastMessageAt: 2500 },
  }), true);
});

test('J. _markAsRead()\'s reset-to-0 write succeeds for either '
  + 'participant', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { [`unread_${CUSTOMER_UID}`]: 0 },
  }), true);
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { [`unread_${PROVIDER_UID}`]: 0 },
  }), true);
});

test('K. the original H-1 attack — a fresh (nonexistent) meta node self-'
  + 'claimed by whoever writes first — remains blocked (data.exists() is '
  + 'false, so this fails before the participant check is even reached)', () => {
  assert.equal(simulateMetaWrite({
    authUid: OTHER_UID, existing: null,
    incomingUpdate: { customerId: 'real-customer', providerId: OTHER_UID },
  }), false);
});

// ── BATCH H — Customer suspend/ban: restricted/{uid} mirror ─────
//
// These model the conjunct onCustomerStatusChange (index.js) relies on:
// a restricted customer/provider is denied even though every other check
// (participant, identity-unchanged) would otherwise pass.

test('L. a restricted customer is denied even for an otherwise-legal '
  + 'non-identity write (e.g. sending a message updates lastMessage here)', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'still trying to chat while banned' },
    restrictedUids: new Set([CUSTOMER_UID]),
  }), false);
});

test('M. a restricted provider is denied the same way (enforcement is not '
  + "customer-specific in the rule itself — it's whichever uid is in "
  + 'restricted/{uid})', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'still trying to chat' },
    restrictedUids: new Set([PROVIDER_UID]),
  }), false);
});

test('N. the OTHER (non-restricted) participant is unaffected by their '
  + "counterparty being restricted — restricted/{uid} is keyed per-uid, "
  + 'not per-chat', () => {
  assert.equal(simulateMetaWrite({
    authUid: PROVIDER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'customer is banned but I can still write' },
    restrictedUids: new Set([CUSTOMER_UID]),
  }), true);
});

test('O. an active (non-restricted) customer is completely unaffected — '
  + 'restricted/{uid} absent (empty set) behaves exactly like before this '
  + 'batch', () => {
  assert.equal(simulateMetaWrite({
    authUid: CUSTOMER_UID, existing: existingMeta,
    incomingUpdate: { lastMessage: 'business as usual' },
  }), true);
});

// ── CORRECTIVE FIX — chats/$chatId/messages .write ──────────────
//
// Independent review found that scenarios A-O above (meta .write) do NOT
// prove a restricted user is blocked from actually sending a message.
// ChatService._sendMessage() (lib/chat_screen.dart) makes TWO separate
// RTDB calls, not one atomic multi-path write: _msgsRef.push().set({...})
// (the real message, governed by messages .write, modeled here) and a
// separate _chatMetaRef.update({lastMessage, lastMessageAt}) (governed by
// meta .write, modeled above). Gating only meta .write left message
// content fully sendable by a restricted user — this section proves the
// corrective fix (adding the same restricted/{uid} check directly to
// messages .write) actually closes that path, independent of meta.

const EXPECTED_MESSAGES_WRITE_RULE =
  "auth != null && (auth.uid == root.child('chats').child($chatId).child('meta').child('customerId').val() || " +
  "auth.uid == root.child('chats').child($chatId).child('meta').child('providerId').val()) && " +
  "!root.child('restricted').child(auth.uid).val()";

test('behavioral-sim setup (messages): the live rule string exactly '
  + 'matches what the simulation below models (fails loudly on drift)', () => {
  const messages = dbRules.rules.chats.$chatId.messages;
  assert.equal(messages['.write'], EXPECTED_MESSAGES_WRITE_RULE);
});

// Mirrors messages .write's own semantics: authorization is derived from
// meta's customerId/providerId (not from a `data`/`newData` diff on the
// messages node itself — the real rule reads root.child('chats')...meta,
// which is why this takes metaCustomerId/metaProviderId directly rather
// than an `existing` messages-node argument).
function simulateMessagesWrite({ authUid, metaCustomerId, metaProviderId, restrictedUids = new Set() }) {
  const authNotNull = authUid !== null && authUid !== undefined;
  const callerIsParticipant = authUid === metaCustomerId || authUid === metaProviderId;
  const callerNotRestricted = !restrictedUids.has(authUid);
  return authNotNull && callerIsParticipant && callerNotRestricted;
}

// Field-level guard on the message itself (chats/$chatId/messages/
// $messageId/senderId .validate) — independent of, and evaluated in
// addition to, messages .write. A write only actually succeeds if BOTH
// pass, exactly like real RTDB rule evaluation (a passing .write does not
// exempt a node's own .validate).
function simulateSenderIdValidate({ newSenderId, authUid }) {
  return newSenderId === authUid;
}

test('P. an active customer CAN send a message (write-rule requirement 1)', () => {
  assert.equal(simulateMessagesWrite({
    authUid: CUSTOMER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
  }), true);
});

test('Q. an active provider CAN send a message (write-rule requirement 2)', () => {
  assert.equal(simulateMessagesWrite({
    authUid: PROVIDER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
  }), true);
});

test('R. a restricted customer CANNOT send a message — this is the exact '
  + 'gap the corrective fix closes: the block now applies to the actual '
  + 'message write directly, not only to meta (write-rule requirement 3, '
  + 'and requirement 9 — there is no other path to create a message doc, '
  + 'so this IS the "cannot bypass by writing directly to messages" proof)', () => {
  assert.equal(simulateMessagesWrite({
    authUid: CUSTOMER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
    restrictedUids: new Set([CUSTOMER_UID]),
  }), false);
});

test('S. a restricted provider CANNOT send a message either — the rule '
  + 'checks whichever uid is in restricted/{uid}, with no customer-vs-'
  + 'provider distinction, so provider behavior is unchanged *in kind* '
  + 'from the customer case (write-rule requirement 4: this codebase does '
  + 'not currently have a provider-suspend concept that writes '
  + "restricted/{uid} — providers are suspended via providers/{uid}."
  + "kycStatus instead, see isVerifiedProvider() in firestore.rules — but "
  + 'IF a provider uid were ever present in restricted/{uid}, this rule '
  + 'would block them exactly like a customer, with no special-casing '
  + 'either way)', () => {
  assert.equal(simulateMessagesWrite({
    authUid: PROVIDER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
    restrictedUids: new Set([PROVIDER_UID]),
  }), false);
});

test('T. an unrelated (non-participant) user remains denied (write-rule '
  + 'requirement 5 — unaffected by this corrective fix, still blocked by '
  + 'the pre-existing participant check)', () => {
  assert.equal(simulateMessagesWrite({
    authUid: OTHER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
  }), false);
});

test('U. senderId spoofing remains denied — an authorized, non-restricted '
  + "participant still cannot write a message claiming to be sent by the "
  + 'OTHER participant (write-rule requirement 6, unrelated to and '
  + 'unweakened by this corrective fix — messages .write authorizes WHO '
  + 'may write, the field .validate independently enforces WHAT identity '
  + 'the message claims)', () => {
  const writeAuthorized = simulateMessagesWrite({
    authUid: CUSTOMER_UID, metaCustomerId: CUSTOMER_UID, metaProviderId: PROVIDER_UID,
  });
  assert.equal(writeAuthorized, true, 'sanity check: the customer IS an authorized writer here');
  const senderIdValid = simulateSenderIdValidate({
    newSenderId: PROVIDER_UID, // customer claiming to be the provider
    authUid: CUSTOMER_UID,
  });
  assert.equal(senderIdValid, false,
    'a write CAN be authorized and still be rejected by the field .validate');
});

test('V. the senderId .validate expression itself is unchanged by this '
  + 'corrective fix', () => {
  const validate = dbRules.rules.chats.$chatId.messages.$messageId.senderId['.validate'];
  assert.equal(validate, "newData.val() == auth.uid");
});

test('W. meta .write (H-1 identity protection + suspend/ban restricted '
  + 'check) is untouched by this corrective round — still exactly what '
  + 'the earlier drift-guard (EXPECTED_META_WRITE_RULE, above) asserts', () => {
  const meta = dbRules.rules.chats.$chatId.meta;
  assert.equal(meta['.write'], EXPECTED_META_WRITE_RULE);
  assert.equal(meta.customerId['.write'], false);
  assert.equal(meta.providerId['.write'], false);
});

// ── CLIENT WIRING ────────────────────────────────────────────

test('the callable exists and is exported', () => {
  assert.match(source, /exports\.initializeBookingChat\s*=\s*functions\.https\.onCall/);
});

// ── THE ORIGINAL EXPLOIT SEQUENCE, EXPLICITLY ───────────────
//
// This narrates the exact attack path from the H-1 threat model end to
// end, as a single test, rather than relying on the reader to mentally
// compose tests #2-#5 into the story. Still a source-text guard, not a
// runtime emulator run (see file header) — it verifies the code CONTAINS
// the decision points that produce this sequence, in the right order and
// with no gap between them, not that a live Cloud Functions emulator
// actually returns these exact results end to end.
test('the original exploit sequence is fully closed by source, step by step', () => {
  const body = functionBody();

  // Step 1-3: booking is pending, Provider A is a candidate (not yet the
  // accepted provider), Provider A calls initializeBookingChat before
  // accepting → booking.providerId is still '' at this point → rejected.
  // (Same assertion as test #5 — restated here as part of the narrative.)
  assert.match(body, /typeof providerId !== 'string' \|\| !providerId/,
    'Provider A pre-acceptance: booking.providerId=="" must be rejected '
    + 'before the caller-identity check ever runs');

  // Step 4: Provider A accepts the booking (acceptBooking(), outside this
  // function's scope — booking_repository.dart/firestore.rules already
  // enforce this is a real, single-winner transaction). booking.providerId
  // is now Provider A's uid.
  // Step 5: Provider A opens chat again → callerUid == providerId → passes
  // the permission check → proceeds to Firestore/RTDB initialization.
  assert.match(body, /callerUid !== customerId && callerUid !== providerId/,
    'accepted Provider A: callerUid matching the now-populated '
    + 'booking.providerId must pass this check, not be rejected');

  // Step 6: Provider B (a different candidate, never accepted this job)
  // attempts the same booking's chat. booking.providerId is Provider A's
  // uid, not Provider B's — callerUid (Provider B) matches neither
  // customerId nor providerId → rejected by the same check as Step 5,
  // now on the other side of the boolean.
  assert.match(body, /permission-denied/,
    'Provider B (uninvolved candidate): must be rejected via the same '
    + 'callerUid check, now failing since callerUid is neither identity');

  // Step 7: the real customer opens the same chat. By this point Step 5
  // has already created the Firestore doc + RTDB meta with Provider A's
  // (correct) identity. The customer's call finds chatDoc.exists==true
  // and metaSnap.exists()==true, both matching the booking exactly →
  // idempotent success, not a second write and not an error.
  const firestoreElseIdx = body.indexOf('} else {', body.indexOf('chatRef.get()'));
  const rtdbElseIdx = body.indexOf('} else {', body.indexOf('metaRef.get()'));
  assert.ok(firestoreElseIdx > -1 && rtdbElseIdx > -1,
    'both Firestore and RTDB must have an "already exists" branch, not '
    + 'just an "if not exists, create" with no else — a second (correct) '
    + 'caller must be able to complete successfully without re-writing');
});
