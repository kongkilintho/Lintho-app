# LinTho — Out-of-Scope Findings

Issues discovered while working the Master Prompt's Phase 0 (Stabilization) that are
outside that phase's scope. Per the Master Prompt's rule ("If you discover something
outside scope: DO NOT silently modify it"), these are documented here rather than
fixed. None of the code changes made for Phase 0 touch any of the files/behavior
described below.

---

## OOS-1 — 12 pre-existing test failures unrelated to Phase 0

**File(s):** `test/critical_fixes_test.dart`, `test/high_severity_fixes_test.dart`,
`test/medium_auth_fixes_test.dart`, `test/release_audit_2026_07_27_fixes_test.dart`

**Issue:** Running the full existing test suite (`flutter test`) shows 12 failing
tests. To confirm these were not caused by the Phase 0 changes, the working tree was
stashed back to the pre-Phase-0 commit and the suite re-run: **the exact same 12
tests fail, in the same order, with identical failure messages, on the untouched
baseline.** These are pre-existing failures, not Phase 0 regressions.

The failures fall into two patterns:

1. **Stale hardcoded-offset assertions.** Several of these tests (e.g. `M-3:
   settings/legal is readable before sign-in`, most of the `RangeError (end): Invalid
   value` failures) call `content.substring(fixedStart, fixedEnd)` on
   `firestore.rules`/a `.dart` file using literal character offsets captured when the
   test was written, then assert a string is `contains`ed in that slice. As the
   underlying files have grown from unrelated feature work since, the offsets now
   point at the wrong region (or are out of range entirely), so the test fails even
   though the actual fix it's checking for may still be present elsewhere in the
   file. Spot-checked one case: `CRIT-5`'s failing assertion claims
   `match_screen.dart` lost its `.timeout(...)` calls — but `.timeout(const
   Duration(seconds: 15))` is still present at `match_screen.dart:458` and `:743`.
   This looks like test staleness, not a reverted fix.
2. **Possible real drift, not verified.** A few failures assert on a specific
   function *signature* rather than a behavior — e.g. `M-6` expects the literal text
   `'Future<bool> _sendRequestToTop3('` to exist in `match_screen.dart`; grepping the
   current file finds only comments referencing `_sendRequestToTop3()`, no matching
   declaration. This could mean the function was renamed/refactored and the test
   never updated, or it could mean the underlying fix (bool return + retry-once
   behavior) was lost in a later refactor. **Not verified either way** — doing so
   would mean auditing match_screen.dart's retry/error-reporting logic, which is
   outside Phase 0's scope (booking/matching architecture, not UI/UX or the specific
   P0/P1 bugs this phase targets).

**Severity:** Medium (test-suite health / possible silent regression risk) — not
blocking Phase 0, but the project loses regression protection on whatever these 12
tests were guarding for as long as they stay red.

**Recommendation:** A separate, explicitly-scoped pass to either (a) update the
stale offset-based assertions to be resilient to file growth (e.g. anchor on a
unique nearby string and search from there, the way `phase0_stabilization_test.dart`
added in this session does), or (b) for the signature-based ones, confirm by reading
the current implementation whether the original fix (H-2, H-4, M-1, M-3, M-6, M-8,
ME-AUTH-6, Medium-1, Medium-5, Medium-6, CRIT-5, H6/H9 — see full names in the test
output) is still behaviorally present, and fix forward if not.

---

## OOS-2 — `go_router` dependency appears unused

**File:** `pubspec.yaml` (declares `go_router: ^14.2.8`)

**Issue:** Across every screen read in this session and the prior UI/UX re-audit
(~45 files), navigation is done exclusively via `Navigator.push`/`MaterialPageRoute`.
No usage of `go_router`'s `GoRouter`/`context.go`/`context.push` API was found.

**Severity:** Low (dependency hygiene, not a bug).

**Recommendation:** Confirm it's genuinely unused (a repo-wide grep for `GoRouter`/
`context.go(` would settle it definitively) and either remove the dependency or
document why it's kept.

---

## OOS-3 — Two larger audits found issues outside the Master Prompt's scope entirely

Not re-verified in this session; carried forward from the prior UI/UX re-audit
(2026-08-23) and notification-system audit (2026-08-08) for visibility:

- Notification system: a Critical finding that `fcm_queue` writes have no admin/
  ownership check (any authenticated user can write a doc that gets treated as an
  admin broadcast), plus 3 High / 6 Medium / 3 Low findings — backend security, not
  UI/UX. Audit-only, not yet fixed.
- Broader UI/UX findings not selected as Phase 0/1 pilot scope (Rewards/Referral/
  Review localization gaps, brand-mark inconsistency at non-pilot screens, etc.) —
  tracked in the LinTho UI/UX Re-Audit report, to be picked up in a later, explicitly
  approved pass per that report's roadmap.

**Recommendation:** Handle as separate, explicitly-scoped engagements — not part of
this Master Prompt's Phase 0/1.

---

## OOS-4 — `FavoriteProvidersScreen` has no feature behind it (Phase 2 / Batch A)

**File:** `lib/main.dart` (`FavoriteProvidersScreen`, class only — unreachable)

**Issue:** Confirmed during the Phase 2 Batch A audit (2026-08-24): this screen's
nav entry point was already removed by a prior pass (🔒 AUDIT CUST-6 / 2026-08-02,
comment at `main.dart` ~line 2959) because no real favorites feature exists behind
it — no heart/favorite affordance anywhere in the app, no Firestore field or write
path for a favorites list. The screen class was deliberately kept (not deleted) in
case the feature gets built for real later, so it always renders its empty state.

**What Phase 2 did:** Per explicit instruction, Batch A gave this screen a
style-only migration — its existing empty state now renders through the shared
`EmptyStateView` component instead of a hand-rolled `Container`/`Column`. No
Firestore query, data model, or feature behavior was added or implied.

**Severity:** Low (dead code / deferred feature, not a bug).

**Recommendation:** A future, separately-scoped decision: either build the real
favorites feature (heart-toggle affordance on provider cards/details, a Firestore
field or subcollection, and restore the nav entry point) or delete
`FavoriteProvidersScreen` entirely if the feature is no longer planned.
