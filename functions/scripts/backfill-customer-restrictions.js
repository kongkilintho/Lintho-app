// ============================================================
// backfill-customer-restrictions.js — LinTho Cloud Functions (one-time,
// manually-run operational script — NOT a deployed Cloud Function)
//
// Batch I / I-1 — customer restriction migration backfill.
//
// onCustomerStatusChange (functions/index.js) only fires on a Firestore
// *update* to users/{uid} — any customer whose status was already
// 'suspended'/'banned' BEFORE that trigger was first deployed (commit
// 38e8ce17) has never had Firebase Auth disabled, refresh tokens revoked, or
// the RTDB restricted/{uid} mirror set. This script finds every such
// customer and applies the exact same enforcement the trigger would, via
// the shared applyCustomerRestriction() helper it exports — one enforcement
// implementation, reused here, not a second copy that could drift.
//
// This is a plain Node script, run manually by an operator with real
// credentials (Application Default Credentials, or GOOGLE_APPLICATION_
// CREDENTIALS pointing at a service-account key) — the same requirement as
// any other Admin SDK operation against this project. It is never deployed
// and has no HTTPS/callable surface of its own.
//
// Usage (run from the functions/ directory, or pass the full path):
//   node scripts/backfill-customer-restrictions.js --dry-run
//   node scripts/backfill-customer-restrictions.js
//   node scripts/backfill-customer-restrictions.js --verify
//
// --dry-run   Query + classify only. Writes NOTHING. Prints the affected
//             uid list and counts by classification. Always run this first
//             and review the output before running the default (execute)
//             mode.
// (default)   Executes: calls applyCustomerRestriction(uid) for every
//             customer classified 'suspended' or 'banned'. Safe to re-run
//             any number of times — every underlying operation
//             (Auth disable, revokeRefreshTokens, RTDB restricted/{uid}
//             set) is individually idempotent, and the decision is always
//             based on the live users/{uid} doc at the moment it runs, not
//             a cached snapshot. Writes a JSON report next to this script.
// --verify    Re-runs the same query/classification and, for every
//             suspended/banned customer found, reads back the LIVE Auth
//             disabled flag + RTDB restricted/{uid} value and reports any
//             mismatch. Writes NOTHING.
//
// This script is NEVER invoked automatically by anything else in this
// repository (not wired into any npm script, deploy step, or CI job) —
// production execution requires an operator to run it by hand.
//
// Classification (per users/{uid} doc, mirroring the trigger's own
// role/status fallback semantics exactly — see getRole()/isActiveCustomer()
// in firestore.rules and applyCustomerRestriction() in index.js):
//   'suspended' | 'banned' — role is 'customer' (or the field is missing —
//                            same fallback used everywhere else in this
//                            codebase) AND status is exactly that string.
//   'active'               — role is 'customer'-or-missing AND status is
//                            missing/null, or 'active', or any other
//                            non-restricted value.
//   'not-a-customer'       — role is present and is NOT 'customer' (e.g.
//                            'provider', 'admin') — always skipped, no
//                            matter what its status field says.
//   'invalid'              — status field is present but is not a string
//                            (a malformed record) — always skipped, NEVER
//                            silently coerced into 'active' or 'restricted'.
//
// Only 'suspended'/'banned' records are ever written to, and only in the
// default (execute) mode. 'active', 'not-a-customer', and 'invalid' records
// are classified and counted for the report but never touched in any mode —
// no unrelated customer field and no unrelated Auth account is ever
// modified, and this script never deletes anything.
// ============================================================

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// 🔒 [BATCH I — I-1, 2026-08-25] This does NOT require('../index.js') to
// reuse applyCustomerRestriction()/RESTRICTED_CUSTOMER_STATUSES, even though
// index.js exports both specifically for that purpose. Discovered while
// building this script: index.js cannot currently be require()'d at all —
// it throws immediately (`functions.firestore.document is not a function`)
// because the installed/locked firebase-functions@7.2.5 moved the v1
// builder API (.firestore.document(), .pubsub.schedule(), .runWith()) off
// the bare `require('firebase-functions')` import to the `firebase-
// functions/v1` subpath, and index.js still does the former. Verified this
// is 100% pre-existing (reproduces identically against the untouched
// `git show HEAD:functions/index.js`, before any Batch I edit) and affects
// every exported function in that file, not something specific to Batch I.
// Fixing it is a one-line, whole-file-impacting change outside this batch's
// locked scope (I-1/I-2/I-3 only) — flagged prominently in the Batch I
// report instead of fixed here. Once fixed, this script's two small pieces
// below (RESTRICTED_CUSTOMER_STATUSES and applyCustomerRestriction) can be
// replaced with a real require() of index.js's exports — until then they
// are DELIBERATELY duplicated here, mirroring index.js's implementation
// exactly (see the comment on each), the same way this codebase already
// duplicates the ['suspended','banned'] status list across firestore.rules'
// isActiveCustomer()/isRestrictedUser() rather than sharing one runtime
// constant across languages. backfill-customer-restrictions.test.js
// includes a drift guard comparing this script's operation list against
// index.js's, so a future edit to one that isn't mirrored in the other
// fails loudly.

// Mirrors functions/index.js's RESTRICTED_CUSTOMER_STATUSES exactly.
const RESTRICTED_CUSTOMER_STATUSES = ['suspended', 'banned'];

if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

// Mirrors functions/index.js's applyCustomerRestriction() exactly (live
// re-read before deciding, Promise.allSettled for error isolation, same
// idempotent Auth/RTDB operations, same structured logging shape) — see
// that function's own comment for the full rationale, which applies
// identically here. Kept as a distinct local copy for the reason explained
// in the file header above.
async function applyCustomerRestriction(uid, { source } = {}) {
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    return { uid, skipped: true, reason: 'user-doc-missing', errors: [] };
  }
  const data = userSnap.data() || {};
  const role = data.role || 'customer';
  if (role !== 'customer') {
    return { uid, skipped: true, reason: 'not-a-customer', errors: [] };
  }

  const status = data.status;
  const shouldRestrict = RESTRICTED_CUSTOMER_STATUSES.includes(status);
  const restrictedRef = admin.database().ref(`restricted/${uid}`);
  const errors = [];

  if (shouldRestrict) {
    const ops = ['auth-disable', 'revoke-refresh-tokens', 'rtdb-restrict'];
    const results = await Promise.allSettled([
      admin.auth().updateUser(uid, { disabled: true }),
      admin.auth().revokeRefreshTokens(uid),
      restrictedRef.set(true),
    ]);
    results.forEach((r, i) => {
      if (r.status === 'rejected') {
        errors.push({ op: ops[i], code: r.reason && r.reason.code, message: r.reason && r.reason.message });
      }
    });
  } else {
    const ops = ['auth-enable', 'rtdb-unrestrict'];
    const results = await Promise.allSettled([
      admin.auth().updateUser(uid, { disabled: false }),
      restrictedRef.remove(),
    ]);
    results.forEach((r, i) => {
      if (r.status === 'rejected') {
        errors.push({ op: ops[i], code: r.reason && r.reason.code, message: r.reason && r.reason.message });
      }
    });
  }

  const logPayload = {
    uid, status: status === undefined ? null : status, targetRestricted: shouldRestrict, source: source || 'backfill',
  };
  if (errors.length > 0) {
    console.error('applyCustomerRestriction: partial failure', JSON.stringify({ ...logPayload, errors }));
  }

  return { uid, skipped: false, targetRestricted: shouldRestrict, errors };
}

const PAGE_SIZE = 200;

function classify(uid, data) {
  const role = data.role || 'customer';
  if (role !== 'customer') {
    return { uid, classification: 'not-a-customer' };
  }
  const status = data.status;
  if (status === undefined || status === null) {
    return { uid, classification: 'active' };
  }
  if (typeof status !== 'string') {
    return { uid, classification: 'invalid', rawStatus: status };
  }
  if (RESTRICTED_CUSTOMER_STATUSES.includes(status)) {
    return { uid, classification: status }; // 'suspended' | 'banned'
  }
  return { uid, classification: 'active' };
}

// Firestore's `in` filter is an equality-class filter — it merges with the
// automatic single-field indexes Firestore already maintains (verified
// during the audit that authorized this batch: no composite index is
// required as long as no orderBy is added on a THIRD field beyond the
// cursor field used for pagination below). Deliberately queried WITHOUT a
// `role` filter — a role-missing document is still a customer per the same
// fallback classify() applies above, and an equality filter on `role` would
// silently exclude it from this query entirely.
async function fetchCandidates() {
  const results = [];
  let lastDoc = null;
  for (;;) {
    let q = db.collection('users')
      .where('status', 'in', RESTRICTED_CUSTOMER_STATUSES)
      .orderBy('__name__')
      .limit(PAGE_SIZE);
    if (lastDoc) q = q.startAfter(lastDoc);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      results.push(classify(doc.id, doc.data() || {}));
    }
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < PAGE_SIZE) break;
  }
  return results;
}

function summarize(candidates) {
  const byClass = {};
  for (const c of candidates) {
    byClass[c.classification] = (byClass[c.classification] || 0) + 1;
  }
  return byClass;
}

async function collectAndReport() {
  const candidates = await fetchCandidates();
  const toRestrict = candidates.filter(
    (c) => c.classification === 'suspended' || c.classification === 'banned');

  console.log('classification counts:', summarize(candidates));
  console.log(`${toRestrict.length} customer(s) matched suspended/banned and a customer role:`);
  for (const c of toRestrict) console.log(`  - ${c.uid} (${c.classification})`);

  const notCustomer = candidates.filter((c) => c.classification === 'not-a-customer');
  if (notCustomer.length > 0) {
    console.log(`${notCustomer.length} record(s) matched the status filter but skipped (not a customer):`);
    for (const c of notCustomer) console.log(`  - ${c.uid}`);
  }

  const invalid = candidates.filter((c) => c.classification === 'invalid');
  if (invalid.length > 0) {
    console.log(`${invalid.length} record(s) matched the status filter but skipped (invalid/malformed status field):`);
    for (const c of invalid) console.log(`  - ${c.uid} (rawStatus=${JSON.stringify(c.rawStatus)})`);
  }

  return { candidates, toRestrict };
}

async function runDryRun() {
  console.log('=== backfill-customer-restrictions: DRY RUN (no writes) ===\n');
  const { toRestrict } = await collectAndReport();
  console.log(`\n[dry-run] would restrict ${toRestrict.length} customer(s). No writes were made.`);
  return { toRestrict };
}

async function runExecute() {
  console.log('=== backfill-customer-restrictions: EXECUTE ===\n');
  const { toRestrict } = await collectAndReport();

  console.log(`\napplying restriction to ${toRestrict.length} customer(s)...`);
  const report = { runAt: new Date().toISOString(), mode: 'execute', results: [] };
  for (const c of toRestrict) {
    try {
      const result = await applyCustomerRestriction(c.uid, { source: 'backfill' });
      report.results.push({ uid: c.uid, classification: c.classification, ...result });
      if (result.errors && result.errors.length > 0) {
        console.error(`  x ${c.uid}: ${result.errors.map((e) => `${e.op}=${e.code || e.message}`).join(', ')}`);
      } else {
        console.log(`  ok ${c.uid}`);
      }
    } catch (err) {
      console.error(`  x ${c.uid}: unexpected error: ${err.message}`);
      report.results.push({
        uid: c.uid, classification: c.classification, skipped: false,
        errors: [{ op: 'unexpected', message: err.message }],
      });
    }
  }

  const failed = report.results.filter((r) => r.errors && r.errors.length > 0);
  const reportPath = path.join(__dirname, `backfill-report-${Date.now()}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`\nreport written to ${reportPath}`);
  console.log(`done: ${report.results.length - failed.length} succeeded, ${failed.length} had errors.`);
  if (failed.length > 0) {
    console.log('Re-run this script (execute mode) to retry the failed uid(s) — every operation is idempotent.');
  }
  return report;
}

async function runVerify() {
  console.log('=== backfill-customer-restrictions: VERIFY (no writes) ===\n');
  const candidates = await fetchCandidates();
  const toCheck = candidates.filter(
    (c) => c.classification === 'suspended' || c.classification === 'banned');
  console.log(`checking live Auth + RTDB state for ${toCheck.length} customer(s)...`);

  let mismatches = 0;
  for (const c of toCheck) {
    const problems = [];
    try {
      const userRecord = await admin.auth().getUser(c.uid);
      if (!userRecord.disabled) problems.push('auth-not-disabled');
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        problems.push('auth-user-missing');
      } else {
        problems.push(`auth-check-error:${err.message}`);
      }
    }
    try {
      const restrictedSnap = await admin.database().ref(`restricted/${c.uid}`).get();
      if (restrictedSnap.val() !== true) problems.push('rtdb-not-restricted');
    } catch (err) {
      problems.push(`rtdb-check-error:${err.message}`);
    }

    if (problems.length > 0) {
      mismatches++;
      console.error(`  x ${c.uid} (${c.classification}): ${problems.join(', ')}`);
    } else {
      console.log(`  ok ${c.uid} (${c.classification}): consistent`);
    }
  }

  console.log(`\n${toCheck.length - mismatches}/${toCheck.length} consistent, ${mismatches} mismatch(es).`);
  if (mismatches > 0) {
    console.log('Run this script in default (execute) mode to reconcile the mismatched uid(s).');
  }
  return { checked: toCheck.length, mismatches };
}

async function main() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const isVerify = args.includes('--verify');
  if (isDryRun && isVerify) {
    console.error('Pass only one of --dry-run or --verify, not both.');
    process.exitCode = 1;
    return;
  }
  if (isDryRun) {
    await runDryRun();
  } else if (isVerify) {
    await runVerify();
  } else {
    await runExecute();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('backfill-customer-restrictions: fatal error:', err);
    process.exitCode = 1;
  });
}

module.exports = { classify, fetchCandidates, summarize };
