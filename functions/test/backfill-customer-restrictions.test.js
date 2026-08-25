// ============================================================
// backfill-customer-restrictions.test.js — LinTho Cloud Functions
//
// Regression tests for Batch I — I-1 (customer restriction migration
// backfill, 2026-08-25). functions/scripts/backfill-customer-
// restrictions.js finds every customer whose users/{uid}.status was
// already 'suspended'/'banned' before onCustomerStatusChange (Batch H,
// commit 38e8ce17) was deployed, and applies the same Auth-disable/
// refresh-token-revoke/RTDB-restricted-mirror enforcement the trigger
// applies going forward.
//
// Unlike the other test files in this directory, this script does NOT
// require('../index.js') — see the script's own file-header comment for
// why: index.js currently cannot be require()'d at all with the installed/
// locked firebase-functions@7.2.5 (a pre-existing bug, unrelated to and
// out of scope for Batch I, reported separately). Because of that, this
// script is safely require()-able on its own, and classify()/fetchCandidates/
// summarize() are exercised directly below as real unit tests, not just
// source-text pattern matching — no Firebase credentials or emulator are
// needed for classify()/summarize() since they touch no Firebase API.
//
// fetchCandidates() DOES call live Firestore (db.collection('users')...) —
// it is not invoked here. Its query SHAPE is verified structurally instead
// (source text), same limitation as every other test file in this
// directory (no emulator in this repo — see initialize-booking-chat.test.js
// header for the full explanation). The dry-run/execute/verify MODE
// functions (runDryRun/runExecute/runVerify) are also not exported/invoked
// here for the same reason — their write-gating logic (which
// classifications get touched in which mode) is verified structurally.
//
// THESE TESTS DO NOT PROVE RUNTIME FIRESTORE/AUTH/RTDB BEHAVIOR beyond what
// classify()/summarize() actually execute in-process. A rules-emulator +
// functions-emulator + Auth-emulator integration test (this repo has none)
// would be required to prove the live query/write behavior.
// ============================================================

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const scriptPath = path.join(__dirname, '..', 'scripts', 'backfill-customer-restrictions.js');
const source = fs.readFileSync(scriptPath, 'utf8');
const script = require(scriptPath);

// ── classify(): real unit tests, no Firebase needed ─────────────────────

test('classify: an active customer (no status field) classifies as active', () => {
  assert.deepEqual(script.classify('u1', { role: 'customer' }),
    { uid: 'u1', classification: 'active' });
});

test('classify: an active customer with status="active" classifies as active', () => {
  assert.deepEqual(script.classify('u2', { role: 'customer', status: 'active' }),
    { uid: 'u2', classification: 'active' });
});

test('classify: a suspended customer classifies as suspended', () => {
  assert.deepEqual(script.classify('u3', { role: 'customer', status: 'suspended' }),
    { uid: 'u3', classification: 'suspended' });
});

test('classify: a banned customer classifies as banned', () => {
  assert.deepEqual(script.classify('u4', { role: 'customer', status: 'banned' }),
    { uid: 'u4', classification: 'banned' });
});

test('classify: a role-missing doc is still treated as a customer — same '
    + 'fallback as getRole() (firestore.rules) and the trigger '
    + '(functions/index.js)', () => {
  assert.deepEqual(script.classify('u5', { status: 'banned' }),
    { uid: 'u5', classification: 'banned' });
  assert.deepEqual(script.classify('u6', {}), { uid: 'u6', classification: 'active' });
});

test('classify: a provider (or any non-customer role) is always '
    + "'not-a-customer', regardless of its status field — never restricted "
    + 'through this script', () => {
  assert.deepEqual(script.classify('u7', { role: 'provider', status: 'suspended' }),
    { uid: 'u7', classification: 'not-a-customer' });
  assert.deepEqual(script.classify('u8', { role: 'admin', status: 'banned' }),
    { uid: 'u8', classification: 'not-a-customer' });
});

test('classify: a malformed (non-string) status is "invalid", never '
    + 'silently coerced into active or restricted', () => {
  const r1 = script.classify('u9', { role: 'customer', status: 123 });
  assert.equal(r1.classification, 'invalid');
  assert.equal(r1.rawStatus, 123);

  const r2 = script.classify('u10', { role: 'customer', status: { weird: true } });
  assert.equal(r2.classification, 'invalid');

  const r3 = script.classify('u11', { role: 'customer', status: ['suspended'] });
  assert.equal(r3.classification, 'invalid');
});

test('classify: an unknown (but well-typed) status string is active, not '
    + 'invalid and not restricted', () => {
  assert.deepEqual(script.classify('u12', { role: 'customer', status: 'pending_review' }),
    { uid: 'u12', classification: 'active' });
});

test('classify: null status is treated the same as missing (active)', () => {
  assert.deepEqual(script.classify('u13', { role: 'customer', status: null }),
    { uid: 'u13', classification: 'active' });
});

// ── summarize(): real unit test ──────────────────────────────────────────

test('summarize counts each classification independently', () => {
  const candidates = [
    { uid: 'a', classification: 'suspended' },
    { uid: 'b', classification: 'suspended' },
    { uid: 'c', classification: 'banned' },
    { uid: 'd', classification: 'active' },
    { uid: 'e', classification: 'not-a-customer' },
    { uid: 'f', classification: 'invalid' },
  ];
  assert.deepEqual(script.summarize(candidates), {
    suspended: 2, banned: 1, active: 1, 'not-a-customer': 1, invalid: 1,
  });
});

test('summarize on an empty list returns an empty object', () => {
  assert.deepEqual(script.summarize([]), {});
});

// ── idempotency: the script's local applyCustomerRestriction mirrors the '
// canonical implementation's idempotent, live-re-reading design ──────────

function localHelperBody() {
  const start = source.indexOf('async function applyCustomerRestriction');
  assert.ok(start > -1, 'the script must carry its own applyCustomerRestriction');
  const end = source.indexOf('\n}', start);
  return source.slice(start, end);
}

test('the script\'s applyCustomerRestriction re-reads the live users/{uid} '
    + 'doc before deciding anything (same live-state protection as the '
    + 'canonical implementation in functions/index.js)', () => {
  const helper = localHelperBody();
  assert.match(helper, /const userSnap = await userRef\.get\(\);/);
});

test('the script\'s applyCustomerRestriction uses Promise.allSettled so one '
    + 'failed uid\'s operation does not abort the others (error isolation, '
    + 'matching the canonical implementation)', () => {
  const helper = localHelperBody();
  assert.match(helper, /Promise\.allSettled\(\[/);
});

test('drift guard: the script\'s local applyCustomerRestriction performs '
    + 'the exact same 3 restrict / 2 reactivate Admin SDK + RTDB operations '
    + 'as the canonical functions/index.js implementation — if either is '
    + 'edited without the other, this fails', () => {
  const indexSource = fs.readFileSync(
    path.join(__dirname, '..', 'index.js'), 'utf8');
  const canonicalStart = indexSource.indexOf('async function applyCustomerRestriction');
  const canonicalEnd = indexSource.indexOf('\n}', canonicalStart);
  const canonical = indexSource.slice(canonicalStart, canonicalEnd);
  const local = localHelperBody();

  const opPatterns = [
    /admin\.auth\(\)\.updateUser\(uid, \{ disabled: true \}\)/,
    /admin\.auth\(\)\.revokeRefreshTokens\(uid\)/,
    /restrictedRef\.set\(true\)/,
    /admin\.auth\(\)\.updateUser\(uid, \{ disabled: false \}\)/,
    /restrictedRef\.remove\(\)/,
  ];
  for (const p of opPatterns) {
    assert.match(canonical, p, `canonical implementation missing ${p}`);
    assert.match(local, p, `script's local copy missing ${p} — drifted from index.js`);
  }
});

// ── query shape (structural — fetchCandidates is not invoked, no live '
// Firestore in this test environment) ────────────────────────────────────

test('fetchCandidates queries by status "in" [suspended, banned] without a '
    + 'role filter — a role-missing doc must still be found (classify() '
    + 'resolves role afterwards, in-memory)', () => {
  assert.match(source, /\.where\('status', 'in', RESTRICTED_CUSTOMER_STATUSES\)/);
  assert.doesNotMatch(source, /\.where\('role'/,
    'must not filter by role in the query itself — role-missing customer '
      + 'docs would be silently excluded');
});

test('fetchCandidates is pagination-safe: cursors on __name__ with a '
    + 'bounded page size, looping until a short page is returned', () => {
  assert.match(source, /const PAGE_SIZE = \d+;/);
  assert.match(source, /\.orderBy\('__name__'\)/);
  assert.match(source, /\.limit\(PAGE_SIZE\)/);
  assert.match(source, /q = q\.startAfter\(lastDoc\)/);
  assert.match(source, /if \(snap\.docs\.length < PAGE_SIZE\) break;/);
});

// ── mode separation: dry-run and verify write nothing; execute only ever '
// touches suspended/banned classifications ───────────────────────────────

test('--dry-run and --verify are mutually exclusive and both refuse to run '
    + 'together', () => {
  assert.match(source, /const isDryRun = args\.includes\('--dry-run'\);/);
  assert.match(source, /const isVerify = args\.includes\('--verify'\);/);
  assert.match(source, /if \(isDryRun && isVerify\) \{/);
});

test('runDryRun only classifies/logs — contains no Admin SDK or RTDB '
    + 'mutation call', () => {
  const start = source.indexOf('async function runDryRun');
  const end = source.indexOf('\nasync function runExecute');
  assert.ok(start > -1 && end > start);
  const body = source.slice(start, end);
  assert.doesNotMatch(body, /updateUser|revokeRefreshTokens|\.set\(|\.remove\(/,
    'dry-run mode must never call an Admin SDK or RTDB write');
});

test('runVerify only reads (getUser / restricted ref .get()) — contains no '
    + 'Admin SDK or RTDB mutation call', () => {
  const start = source.indexOf('async function runVerify');
  const end = source.indexOf('\nasync function main');
  assert.ok(start > -1 && end > start);
  const body = source.slice(start, end);
  assert.match(body, /admin\.auth\(\)\.getUser\(/);
  assert.match(body, /admin\.database\(\)\.ref\(`restricted\/\$\{c\.uid\}`\)\.get\(\)/);
  assert.doesNotMatch(body, /updateUser\(.*disabled|revokeRefreshTokens|\.set\(true\)|\.remove\(\)/,
    'verify mode must never call an Admin SDK or RTDB write');
});

test('runExecute only calls applyCustomerRestriction for uids classified '
    + "'suspended' or 'banned' — active/not-a-customer/invalid records are "
    + 'never passed to it (no unrelated Auth account or customer field is '
    + 'ever touched)', () => {
  const start = source.indexOf('async function runExecute');
  const end = source.indexOf('\nasync function runVerify');
  assert.ok(start > -1 && end > start);
  const body = source.slice(start, end);
  assert.match(body, /const \{ toRestrict \} = await collectAndReport\(\);/);
  assert.match(body, /for \(const c of toRestrict\) \{/);
  assert.match(body, /applyCustomerRestriction\(c\.uid, \{ source: 'backfill' \}\);/);
});

test('collectAndReport (shared by dry-run and execute) filters toRestrict '
    + "to exactly the 'suspended'\\/'banned' classifications", () => {
  assert.match(source,
    /const toRestrict = candidates\.filter\(\s*\n\s*\(c\) => c\.classification === 'suspended' \|\| c\.classification === 'banned'\);/);
});

test('the script never calls a Firestore/Auth delete operation — it must '
    + 'not delete customer data', () => {
  assert.doesNotMatch(source, /\.delete\(\)|deleteUser\(/,
    'backfill script must never delete anything — only disable/enable Auth '
      + 'and set/remove the RTDB restricted mirror, same as the trigger');
});

test('the script never writes any users/{uid} field other than through '
    + 'applyCustomerRestriction (no unrelated field writes) — the only '
    + 'db.collection(\'users\') use is the read-only query/get path', () => {
  const writesToUsers = source.match(/db\.collection\('users'\)[^;]*\.(update|set)\(/g) || [];
  assert.deepEqual(writesToUsers, [],
    'found a direct write to the users collection outside '
      + 'applyCustomerRestriction — the script must only ever read '
      + "users/{uid} to classify, never write it directly");
});

test('production execution requires an explicit manual invocation — this '
    + 'script is not referenced from any npm script, deploy step, or other '
    + 'automated entry point in this repository', () => {
  const packageJson = fs.readFileSync(
    path.join(__dirname, '..', 'package.json'), 'utf8');
  assert.doesNotMatch(packageJson, /backfill-customer-restrictions/,
    'this script must not be wired into any npm script (predeploy, test, '
      + 'etc.) — it is a manually-run, one-time operational tool only');
});
