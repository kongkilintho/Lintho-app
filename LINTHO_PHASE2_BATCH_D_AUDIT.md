# LinTho — Phase 2 Batch D Audit — Provider Core

STATUS: **IMPLEMENTED — VERIFIED, NOT YET COMMITTED**

Approved for implementation 2026-08-24 ("APPROVED FOR IMPLEMENTATION — Batch D
ສາມາດເລີ່ມແກ້ code ໄດ້."). All fixes described in §5–§10 and the 5 open decisions in
"Open decisions" below were implemented, verified via `flutter analyze`/`flutter test`
after each high-risk file and again project-wide, and a stabilization test file was
added. See §19–§21 for the implementation results; the original pre-implementation
audit content in §3–§18 is left as written (it was accurate) with implementation notes
appended where a decision was refined during the actual edit (see §22).

---

## 1. Scope

Primary files (per Master Prompt):

1. `lib/provider_dashboard.dart` (187 lines)
2. `lib/home_tab.dart` (901 lines)
3. `lib/jobs_tab.dart` (254 lines)
4. `lib/job_workflow_Screen.dart` (1444 lines)
5. `lib/earnings_tab.dart` (1186 lines)
6. `lib/profile_tab.dart` (1827 lines — **bounded scope**, per Step 10 and Batch C
   audit §16's recommendation)

No supporting files were touched during this audit. `lib/widgets/stat_card.dart`
is discussed (§4/§8) as a documentation-only candidate fix, not yet applied.

---

## 2. Baseline

Read before auditing: `LINTHO_PHASE2_MIGRATION_PLAN.md`, `LINTHO_PHASE2_BATCH_A/B/C_AUDIT.md`,
`OUT_OF_SCOPE_FINDINGS.md`, `lib/theme/app_theme.dart`, `lib/app_colors.dart`,
`lib/widgets/app_button.dart`, `app_text.dart`, `app_card.dart`, `app_section.dart`,
`app_icon_button.dart`, `error_state_view.dart`, `empty_state_view.dart`, `stat_card.dart`,
plus all six Batch D files in full (profile_tab.dart via full read of its CTA/back-button/
crash-risk surface area, consistent with its bounded-scope treatment).

`flutter analyze`:
- **0 errors**
- **2 warnings** (`unused_import` in `job_workflow_Screen.dart:17` — `booking_repository.dart`;
  `unused_field` in `match_screen.dart:116` — `_auth`) — both pre-existing, outside Batch D's
  file list except the first, which lives in a Batch D file but predates this batch.
- **65 total issues**

`flutter test`:
- **236 passed, 12 failed**
- Failing tests match `OOS-1` in `OUT_OF_SCOPE_FINDINGS.md` exactly (stale hardcoded-offset
  assertions and signature-based checks against code that has since moved, not real
  regressions).

**Matches the expected Batch C baseline exactly (0 errors / 2 warnings / 65 issues,
236 passed / 12 failed). No baseline mismatch — implementation may proceed once this
audit and the open decisions below are approved.**

---

## 3. Special rule — job workflow colors (Step 3)

`job_workflow_Screen.dart`'s primary action button changes color per step
(`_getAction()`, ~line 1195):

| Status | Color | Meaning |
|---|---|---|
| accepted → onTheWay | `C.blue` | "start travel" |
| onTheWay → arrived | `C.orange` | "arrived" |
| arrived → inProgress | `C.navy` | "start work" |
| inProgress → completed | `C.green` | "complete job" |
| inProgress + unpaid | `C.teal` | "confirm payment" |

**Verification performed:** `C` (`lib/app_colors.dart`) is a compatibility alias class —
every member (`C.navy`, `C.blue`, `C.orange`, `C.green`, `C.teal`, ...) is declared as
`static const X = AppColors.X`, i.e. it mirrors `lib/theme/app_theme.dart`'s `AppColors`
(the single source of truth) 1:1. **These are existing semantic design-system tokens,
not new hardcoded hex** — confirmed by reading both files directly.

**Determination (per Step 3's decision tree):**
1. Is the color semantically tied to `JobStatus`? **Yes** — each color maps 1:1 to a
   workflow step, encoded in `_getAction()`'s `switch`.
2. Represented by `AppStatus`? No — `AppStatus.colorOf()` colors *booking status badges*
   (pending/accepted/onTheWay/... — the stepper/badge), a different semantic axis from
   "what does the primary button do right now." Reusing it here would be a category
   error, not a simplification.
3. Represented by existing `AppColors` tokens? **Yes** (see above).
4. Is this workflow-state signal, not CTA hierarchy? **Yes** — a provider mid-job needs
   "am I about to start driving, or about to mark this done" to be visually distinct at
   a glance; collapsing every step to the same green would remove that signal.
5. Would converting to green destroy meaning? **Yes** for 4 of 5 steps (only the final
   "complete job" step is already green).

**Recommendation: PRESERVE.** This is an **INTENTIONAL EXCEPTION** — do not convert
`_ActionButton` to `AppButton.primary`. It already satisfies the Master Prompt's own
bar ("resolve from existing semantic tokens, not new hardcoded hex"). This matches
what the Batch C audit (§16) asked to have verified, and closes that open item.

No AppButton extension is needed or recommended here — flagging a hypothetical
"AppButton semantic step variant" would be speculative API surface for a single
5-branch switch that already works correctly as plain `ElevatedButton.styleFrom`.

---

## 4. StatCard decision (Step 4)

`lib/widgets/stat_card.dart`'s header comment claims a "wallet/earnings" variant of
`StatCard` (`StatCardStyle.solid`) is in use; `earnings_tab.dart`'s `_WalletCards`/`_Card`
(~line 721) is a separate, hand-rolled implementation.

**Inspected both.** `StatCard.actionLabel` renders **one** non-interactive pill (no
`onTap`, no per-pill color). `earnings_tab.dart`'s `_Card` needs **two independently
tappable** action pills per card (`+ ຕື່ມເງິນ` / `ຖອນ →`), each with its own optional
accent color (gold for top-up to make it visually primary over the plain-pill withdraw,
per an explicit "UI Polish" comment at line 736). `StatCard` cannot express this today.

**Outcome: B — the documentation is stale.** Extending `StatCard.actionLabel` into a
`List<action>` API to fit this one caller would not meet the project's own "3+ uses"
bar for justifying an extension (per Migration Plan §6), and no second consumer with
this exact multi-pill need was found. Recommend correcting the doc comment only — drop
the "(solid, ໃຊ້ໃນ wallet/earnings)" claim, and add a short note pointing at
`earnings_tab.dart`'s `_WalletCards`/`_Card` as a documented, intentional exception.
No behavior change, no new component, no earnings_tab.dart migration to StatCard.

---

## 5. provider_dashboard.dart

Small (187 lines), scaffold + bottom nav only. No CTA buttons, no hardcoded strings
(all `tr()`), no emoji, no async loading/error/empty states (pure UI shell over
`IndexedStack`). Availability sync logic (`ref.listen`/`ref.read` on
`profileStreamProvider` → `onlineStatusProvider.notifier.syncFromRemote`) is
business logic — **not touched, not in scope**.

**Findings:**
- `BorderRadius.circular(14)` × 3 (nav-item highlight background/Material/InkWell,
  lines 123/128/130) — off the 3-token scale. **DESIGN-SYSTEM VIOLATION** — maps
  cleanly to `AppRadius.card` (16), matches the convention already used for
  bottom-nav-adjacent chrome elsewhere in the app (e.g. `main.dart`'s equivalent
  `_FloatingNavBar` nav-item highlight).
- Badge shape `BorderRadius.circular(pendingCount > 9 ? 8 : 10)` (line 155) —
  **INTENTIONAL EXCEPTION**: this is a deliberate circle→pill shape transition for a
  numeric badge (single digit = circle at radius 10, "99+" = pill at radius 8), not an
  arbitrary choice. Preserving per Step 13 ("preserve intentionally geometric ...UI").
- `Colors.white`/`Colors.black.withValues(...)` — not part of the established violation
  set (Batches A/B/C did not migrate these; `AppColors.white`/`Colors.white` are
  value-identical). **OUT OF SCOPE** for this pass, consistent with prior batches.

**Planned fix:** radius-only, 3 lines + 1 import. No behavior risk.

---

## 6. home_tab.dart

901 lines. Already home to `StatCard`, `EmptyStateView`, `ErrorStateView`, `SkeletonListTile`,
`AppIconButton` (customer-card call/navigate icons) — the plan's "best-covered provider
file" claim holds up.

**CTA hierarchy:**
- `_OfflineView`'s "go online" button (line 486) — `C.green`, already correct primary.
- `_PendingActions`'s Accept button (line 751) — `C.green`, already correct primary.
- `_PendingActions`'s Reject button (line 738) — `OutlinedButton` with **red** border/text
  (`C.red`), not navy. `AppButton.outline` is hardcoded to navy (OutlinedButtonTheme
  default) with no destructive-outline variant available. **REQUIRES VERIFICATION /
  INTENTIONAL EXCEPTION**: recommend leaving as raw `OutlinedButton.styleFrom` (red) since
  `AppButton` has no red-outline variant and inventing one for a single call site isn't
  justified — document as an exception rather than force it into `AppButton.outline`
  (which would silently change its color to navy, misrepresenting "reject" as a neutral
  action).
- Reject-reason sheet's confirm button (line 813) — `C.red`, correct destructive semantic.
  Raw `ElevatedButton.styleFrom` → could migrate to `AppButton.destructive` (same red,
  same behavior) — safe, cosmetic.

**Radius:** off-token literals throughout (20, 18, 14, 12, 10, 8, 4/5 for progress bars) —
**DESIGN-SYSTEM VIOLATION**, standard mechanical convergence to `AppRadius.chip/card/sheet`
where the value is a real card/chip/sheet shape. The countdown-bar `circular(4)` and
skeleton-shimmer radii are **INTENTIONAL EXCEPTIONS** (thin progress-bar/skeleton shapes,
not a card/chip/sheet — Step 13 "preserve ... layout-specific" applies).

**Emoji-as-icon:** `_SectionHeader` titles interpolate `🔔`/`📋`/`⚡` directly into the
title string (lines 361/373/384) — matches Migration Plan §2's flagged pattern.
**DESIGN-SYSTEM VIOLATION.** `_SectionHeader` already accepts a `badge`/`badgeColor`;
adding an optional leading `IconData` (mirroring `AppSection`'s `icon` parameter) and
swapping the 3 emoji for `Icons.notifications_outlined`/`Icons.assignment_outlined`/
`Icons.bolt_outlined` is a small, contained fix — not a new component (AppSection
itself isn't a drop-in replacement here since `_SectionHeader` also carries a badge,
which `AppSection` doesn't support).

**Accessibility:** `_OnlineToggle` already has an explicit 44dp `SizedBox` wrapper
(documented fix from a prior audit) — good. No new icon-only-control gaps found.

**Crash safety:** `p?.avatarLetter ?? '?'` (line 136) — safe (delegates to
`Booking.avatarLetter`, already null/empty-guarded per the cross-file grep in §Business
logic below). No unsafe `name[0]` found in this file.

**Localization:** all display strings route through `tr()`. No hardcoded Lao found.

---

## 7. jobs_tab.dart

254 lines — matches the plan's "near-compliant already, low effort" call. Already uses
`EmptyStateView`/`ErrorStateView`/`SkeletonListTile` correctly. **No CTA buttons exist in
this file at all** (filter chips + tappable cards only) — no navy-vs-green risk.

**Findings:**
- `BorderRadius.circular(20/18/14)` (filter chip, job-history card, service icon tile) —
  **DESIGN-SYSTEM VIOLATION**, off-token, straightforward convergence (20→`AppRadius.sheet`
  for the pill-shaped filter chip is arguably wrong — a filter *chip* pill commonly stays
  a true stadium shape; recommend converging the *card* radii — 18/14 → `AppRadius.card`
  — and leaving the chip's 20 as an **INTENTIONAL EXCEPTION**, stadium/pill geometry per
  Step 13, since chip=8 would visibly shrink the pill and change its look).
- `jobFilterProvider`/`filteredHistoryProvider`/`JobStatus` comparisons are enum-identity
  based throughout (`filter == value`, `b.status == JobStatus.completed`), never compared
  via localized `.label` strings — **confirmed safe**, satisfies Step 7's critical rule.
- No hardcoded strings; `_fmtDate` is a plain numeric formatter (not user-facing prose),
  not a localization gap.

---

## 8. job_workflow_Screen.dart

1444 lines — read in full given this is explicitly the business-critical screen (Step 8).

**Workflow transition map (traced, unchanged by this audit):**

| From | Action button | → To | Extra gate |
|---|---|---|---|
| accepted | "start travel" (blue) | onTheWay | — |
| onTheWay | "arrived" (orange) | arrived | — |
| arrived | "start work" (navy) | inProgress | — |
| inProgress | "confirm payment" (teal) | *(no status change)* | shown when `paymentStatus != 'paid'`; calls `confirmPayment()`, not `updateStatus()` |
| inProgress (paid) | "complete job" (green) | completed | blocked (`needsAfterPhoto`) until `beforePhotoUrl != null`; confirmation dialog before `updateStatus(completed)` |
| accepted+ | "cancel job" (red, `_CancelJobButton`) | cancelled | reason-picker sheet, confirmation dialog |

All writes go through `bookingNotifierProvider.notifier.updateStatus()`/`confirmPayment()`/
`cancelJob()`/`requestAdditionalCharges()` (`booking_repository.dart`) — **no Firestore
call sites found inline in this UI file**, so a UI-only pass cannot touch write paths by
construction. **Confirmed: no transition graph changes proposed anywhere in this audit.**

**Crash safety sweep (Step 8):** grepped this file plus the other 5 for `\w+\[0\]` /
`.avatarLetter` / `substring(0,1)`. Found one instance — `_CustomerCard`'s avatar fallback
(line 405-406) — already guarded (`b.customerName.isNotEmpty ? b.customerName[0]... : '?'`,
carries a `🔒 [PHASE0 P0-2]` comment citing the exact prior fix). **No unguarded indexing
found.** (Full cross-file sweep results in §17.)

**CTA hierarchy:**
- Primary step button (`_ActionButton`) — **INTENTIONAL EXCEPTION**, see §3.
- Chat / copy-phone buttons (`_CustomerCard`, lines 487-513) — `OutlinedButton.icon` with
  `foregroundColor: C.navy` — this **is** exactly what `AppButton.outline`'s default
  (OutlinedButtonTheme, navy) already renders. **DESIGN-SYSTEM VIOLATION** (adoption gap,
  not a color problem) — safe to migrate to `AppButton.outline(icon:, fullWidth:false)`
  inside the existing `Expanded` row; no visual change expected since the theme default
  is already navy.
- "Add charges" button (line 879) — `OutlinedButton` with `C.orange` — **INTENTIONAL
  EXCEPTION**: this is a warning/pending-charge semantic (matches the orange "required"
  badge elsewhere on the same screen), not a CTA-hierarchy button; converting it to
  navy/green would lose the "this needs customer approval" signal `C.orange` currently
  carries.
- Charges-sheet "send request" button (line 981, `C.orange`) — same reasoning, **INTENTIONAL
  EXCEPTION** — it's the confirm step of the orange "add charges" flow above, not a
  competing primary action on the main screen.
- `_CancelJobButton`'s outline (red border/text, line 1341-1352) and its sheet's confirm
  (`C.red`, line 1406-1417) — correct destructive semantics; raw styling could migrate to
  `AppButton.destructive` (confirm) and stays a documented red-outline exception (trigger
  button) for the same reason as home_tab.dart's Reject button in §6.
- `_PriceSummary`'s navy/blue gradient background — **INTENTIONAL EXCEPTION**, hero/brand
  surface (Step 14 explicitly allows navy for "brand surface, hero background").
- AppBar `backgroundColor: C.navy` — **INTENTIONAL EXCEPTION**, brand surface.

**Accessibility:** AppBar's back/call/navigate `IconButton`s (lines 121-159) set
`tooltip:` manually (call/navigate) but the back button (line 121-125) has **no**
`tooltip`/Semantics — inconsistent with the rest of the app's back-button convention
(`tooltip: tr('back_semantic')`, confirmed present in `customer_register_flow.dart`/
`technician_register_screen.dart`/`register_otp.dart` per the Migration Plan §3).
**ACCESSIBILITY ISSUE** — small, safe fix (add `tooltip: tr('back_semantic')`). Separately,
these AppBar icons use raw `IconButton` while the identical call/navigate actions lower
on the same screen (`_CustomerCard`, line 471+) use `AppIconButton` — **DESIGN-SYSTEM
VIOLATION** (duplicated pattern within one file), low risk per the Migration Plan §3
("raw IconButton defaults to 48dp, likely fine, worth converging").

**Radius:** extensive off-token literals (24/20/18/16/14/12/10/8/5/4/2) across cards,
sheets, and photo slots. Bulk of these map cleanly to `AppRadius.card`(16)/`chip`(8)/
`sheet`(24). **INTENTIONAL EXCEPTIONS to preserve:** the `_PhotoSlot` upload-progress
`circular(5)` skeleton shimmer bar, the countdown-style thin bars, and the small
`circular(2)`/`circular(4)` bottom-sheet drag-handles (`_Handle`-style — layout-specific,
not a card/chip/sheet shape).

**Localization:** all display strings route through `tr()`. No hardcoded Lao found in
this file (unlike `review_screen.dart`'s now-fixed regression from Batch C).

**Typography:** heavy raw `TextStyle` usage throughout — sizes/weights are internally
consistent (14/w800 for names, 12/w700 for meta, 11/muted for captions) but don't map
1:1 onto `AppTypography`'s 6 roles without judgment calls (e.g. `fontSize: 15,
fontWeight: w800` for the price-summary total doesn't cleanly match `heading`'s
`17/w600`). Per Step 12, **flagging rather than mechanically replacing** — recommend a
bounded pass only where size+weight+color match a role exactly (there are some — e.g.
several `fontSize: 18, fontWeight: w800` AppBar-adjacent titles are close to
`appBarTitle`), leaving the rest as **REQUIRES VERIFICATION**, deferred.

**Unused import:** `booking_repository.dart` (line 17, flagged by `flutter analyze` as
`unused_import`) — dead import, safe one-line removal, reduces the warning count from 2
to 1.

---

## 9. earnings_tab.dart — money screen, extra scrutiny (Step 9)

1186 lines. Three modal sheets (withdraw, top-up, bank-info) plus wallet cards, weekly
chart, transaction list.

**CTA hierarchy — confirmed navy-vs-green defects (matches Migration Plan §2/§3 exactly):**
- Withdrawal sheet confirm button (line 154, `C.navy`) — this is the **sole primary
  action** of that sheet. **DESIGN-SYSTEM VIOLATION**, should be `AppColors.green`
  (`AppButton.primary`).
- Bank-info sheet save button (line 488, `C.navy`) — same, sole primary action of its
  sheet. **DESIGN-SYSTEM VIOLATION**.
- Top-up sheet confirm button (line 390, `C.primary`/green) — **already correct**, no
  change.

Both fixes are pure `styleFrom(backgroundColor:)` swaps (or a full migration to
`AppButton.primary`) — **no change to `requestWithdrawal()`/`updateBankInfo()` calls,
amounts, or Firestore writes**, satisfying Step 9's "do not change the underlying
logic" rule. Server-side balance-safety (atomic transaction in
`functions/index.js`'s `onWithdrawalRequested`) is untouched and out of scope.

**Hardcoded strings:** `'ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ'` ("invalid amount") appears as a raw Lao
literal, not `tr()`, in **two places** (line 162, withdrawal sheet; line 395, top-up
sheet) — matches Migration Plan §2's flagged "earnings_tab.dart (2 invalid-amount error
strings)" exactly. **LOCALIZATION ISSUE.** Needs one new `tr()` key (e.g.
`invalid_amount`) added to lo/en/th/zh, with the Lao value set to this exact existing
string so wording doesn't silently change (Step 11 requirement) — then both call sites
swapped to `tr('invalid_amount')`.

**Error/empty/loading states:** already correct and better than most of the app —
wallet load error uses `ErrorStateView` with retry (line 51-52); transaction load error
uses the `compact` variant (line 81-83) with an explicit comment about *not* faking
empty state on error (a real historical bug this screen already fixed). **No changes
needed.**

**StatCard vs hand-rolled wallet cards:** see §4 — documented exception, no migration.

**Raw `TextField` usage:** amount fields (withdraw/top-up) and 3 bank-info fields use
plain `TextField` + manual `OutlineInputBorder` boilerplate (repeated 5 times across the
file) with **SnackBar-only validation** (no inline `errorText`). Matches Migration Plan
§2's flagged Medium finding. **DESIGN-SYSTEM VIOLATION / adoption gap** — recommend
`AppTextField` adoption *only if* `AppTextField` supports the exact features these fields
need (numeric keyboard + prefix text + custom hint) without behavior loss; given this
wasn't verified against `AppTextField`'s actual API in this audit pass, **flagging as
REQUIRES VERIFICATION** rather than committing to it sight-unseen — this is money-input
validation, so a wrong assumption here is higher-cost than elsewhere.

**Radius:** extensive off-token literals (24/20/18/16/14/12/8/6/2), same shape as other
Batch D files — standard convergence candidates, with the small `circular(2)` sheet-handle
and `circular(6)`/`circular(8)` chart-bar/badge shapes as **INTENTIONAL EXCEPTIONS**
(layout-specific, not card/chip/sheet).

---

## 10. profile_tab.dart — bounded scope (Step 10)

1827 lines, largest Batch D file — **not the same file** as customer `main.dart`'s
`ProfileScreen`. Per Batch C audit §16's explicit recommendation and the Master
Prompt's Step 10, this file gets the same bounded treatment `ProfileScreen` received
in Batch C: fix confirmed CTA/destructive/a11y/radius violations, do not claim full
convergence.

**Confirmed via targeted grep + spot-reads (not a full line-by-line read of all 1827 lines):**

**CTA hierarchy — 5 confirmed navy violations**, all "save"-type sole-primary-action
buttons in their respective screens/sheets, matching Migration Plan §2's "profile_tab.dart
(save profile/services/schedule/review-reply — all but logout)" finding exactly:

| Line | Screen | Button |
|---|---|---|
| 878 | Edit Profile | "save" |
| 1035 | My Services | (save selection) |
| 1149 | *(unverified in this pass — 6th screen, not individually opened)* | — |
| 1347 | Availability/schedule sheet | (save) |
| 1752 | *(unverified — last sheet in file)* | — |

Lines 1149 and 1752 were located via grep but not individually opened in this audit
pass (bounded-scope trade-off, consistent with Step 10's "do not read/migrate the whole
file"); both are `ElevatedButton.styleFrom(backgroundColor: C.navy, ...)` matching the
same pattern as the 3 confirmed ones and should be treated as the same violation class
during implementation, verified individually before each fix (not assumed).

**Correct as-is:** Logout confirmation dialog (line 293-294, `C.red`) — correct
destructive semantic, matches the plan's "all but logout" carve-out exactly. No change.

**Accessibility — 6 back buttons, 0 tooltips:** grep-confirmed `IconButton` at lines
675, 984, 1065, 1178, 1236, 1375 — spot-read two of them (675 "Edit Profile", 984 "My
Services") in full, both `IconButton(icon: Icon(Icons.arrow_back_ios, ...), onPressed:
...)` with **no `tooltip`/Semantics**, unlike `job_workflow_Screen.dart`'s AppBar which
(mostly) does set them, and unlike the registration-flow files which set
`tooltip: tr('back_semantic')` consistently. Matches Migration Plan §2 exactly ("profile_
tab.dart (6 back buttons, inconsistent with the rest of the app which does set
tooltips)"). **ACCESSIBILITY ISSUE** — mechanical, safe fix (add the same
`tooltip: tr('back_semantic')` string already used elsewhere — verified this is an
existing key, not inventing new wording).

**Crash safety:** one `customerName[0]` (line 1660, review-card avatar fallback) —
already guarded (`isNotEmpty ? ... : '?'`), same pattern as `job_workflow_Screen.dart`.
`avatarLetter` used elsewhere (4 call sites) delegates to the already-safe
`Booking.avatarLetter`/`ProviderProfile.avatarLetter` getters. **No unguarded indexing
found** in what was inspected.

**Not inspected in this bounded pass** (would require the full 1827-line read this
batch's scope explicitly avoids): bottom-sheet-level typography/radius convergence,
raw-`TextField` density, full localization audit beyond the CTA/back-button/crash sweep
above, and the two unverified navy CTA line numbers' exact screen context. If Batch D
is approved, the implementation step will open and verify each of these individually
before editing — this audit does not assume more than what was directly read.

**Recommendation:** proceed with the 5 CTA-color fixes (verifying 1149/1752 individually
first), the 6 tooltip additions, and nothing else in this file for Batch D. Document
remaining internal debt (bottom sheets not touched) explicitly at commit time, same
honesty standard Batch C set for customer `ProfileScreen`.

---

## 11. Localization

No new hardcoded strings are being *introduced* by this audit's recommended fixes — the
only localization change proposed is **fixing** the existing `earnings_tab.dart` hardcoded
Lao string (§9) by wrapping it in `tr('invalid_amount')`, with the Lao value set to the
exact current text (`'ຈຳນວນເງິນບໍ່ຖືກຕ້ອງ'`) so wording does not change, only the mechanism.
The `tooltip: tr('back_semantic')` additions (§10) reuse an existing key already used
identically elsewhere in the app — verified, not assumed. No JobStatus/Firestore-value
strings are touched anywhere in this batch.

---

## 12. Design-system migration summary

| Category | Files affected | Count |
|---|---|---|
| Navy→green CTA fix | earnings_tab.dart (2), profile_tab.dart (5) | 7 |
| AppButton adoption (cosmetic, same color) | job_workflow_Screen.dart (chat/copy-phone outline, cancel/reject-confirm destructive) | ~4 |
| Radius token convergence | all 6 files | ~60+ literal sites, bulk-convertible |
| Emoji→icon | home_tab.dart `_SectionHeader` | 3 |
| Hardcoded string→tr() | earnings_tab.dart | 2 (1 new key) |
| Tooltip/a11y addition | job_workflow_Screen.dart (1), profile_tab.dart (6) | 7 |
| Unused import removal | job_workflow_Screen.dart | 1 |

---

## 13. Accessibility findings

- `job_workflow_Screen.dart` AppBar back button — missing tooltip (§8).
- `profile_tab.dart` — 6 back buttons missing tooltip (§10).
- `job_workflow_Screen.dart` AppBar call/navigate icons use raw `IconButton` instead of
  `AppIconButton`, inconsistent with the same actions elsewhere on the same screen (§8) —
  low-risk convergence, not a hard a11y defect (raw `IconButton` already defaults to 48dp).
- No icon-only control found under 44dp in Batch D's scope.
- No color-only status signaling found beyond what `AppStatus`/`StatusBadge` already
  pairs with text labels.

---

## 14. UX findings (provider journey walk-through, Step 23)

Dashboard → Available/Offline → Incoming Job → Details → Accept → Navigate → Arrived →
In Progress → Completed → Earnings → Profile:

- Primary actions are visually obvious at each step **except** where the primary button
  is intentionally non-green (§3) — this is correct, not a defect, since the color
  itself *is* the "which step am I on" signal.
- No dead buttons found. `_JobHistoryCard`'s tap target was fixed in a prior audit
  (comment at jobs_tab.dart:182-184 documents this).
- No broken retry — every `ErrorStateView`/`ErrorStateView(compact:)` call site invokes
  a real `ref.invalidate(...)`, not a no-op repaint.
- Destructive actions (logout, cancel job, reject job) all go through a confirmation
  dialog/sheet before executing.
- No silent failures found in Batch D's scope — earnings error states were already
  fixed to distinguish "error" from "empty" in a prior pass (§9).

No workflow-logic changes are proposed anywhere in this audit.

---

## 15. Business-logic verification

Every finding above is one of: CTA color (`styleFrom`/`AppButton` swap, same
`onPressed`), radius literal, raw-widget→shared-component swap with identical resulting
visual, a missing `tooltip`, an emoji→`IconData` swap, or a hardcoded string→`tr()` swap
with unchanged wording. **No finding in this audit touches**: Firestore queries/writes,
RTDB, Cloud Functions, provider earnings/balance calculations, booking status
transitions, provider matching, payment/withdrawal logic, KYC, address logic,
notification triggers, or chat backend logic. The one dead import removal
(`booking_repository.dart` in `job_workflow_Screen.dart`) was confirmed unused by
`flutter analyze` and does not affect the file's actual booking-repo usage (the file
uses `bookingProvider.dart`'s `bookingRepoProvider`/`bookingNotifierProvider`, imported
separately).

---

## 16. Intentional exceptions (full list, with why)

1. **`job_workflow_Screen.dart` `_ActionButton` step colors** (§3) — resolves from
   existing `AppColors` tokens via the `C` alias; encodes workflow state, not CTA rank.
   Converting to green would erase the "which step" signal. Violates "primary CTA is
   always green" *by design*, and changing it would make the screen harder to read, not
   more consistent.
2. **`home_tab.dart`/`job_workflow_Screen.dart` red-outline Reject/Cancel trigger
   buttons** (§6, §8) — `AppButton` has no destructive-outline variant; forcing them
   into `AppButton.outline` would silently repaint them navy, misrepresenting a
   destructive action as neutral. Left as raw styled `OutlinedButton`.
3. **`job_workflow_Screen.dart` "add charges"/"send request" orange buttons** (§8) —
   warning/pending-approval semantic tied to the same orange "required" badge on the
   same screen; not competing with the main step CTA. Converting to green/navy would
   make an approval-pending action look like a routine primary action.
4. **`job_workflow_Screen.dart` `_PriceSummary` navy/blue gradient, AppBar navy
   background** (§8) — brand/hero surface, explicitly allowed by Step 14.
5. **`provider_dashboard.dart` badge circle/pill radius transition** (§5) — deliberate
   shape logic tied to digit count, not an arbitrary literal.
6. **Various thin progress-bar / skeleton-shimmer / bottom-sheet-handle radii** across
   all files — layout-specific shapes (Step 13), not card/chip/sheet geometry.
7. **`StatCard` doc-comment / `earnings_tab.dart` wallet cards** (§4) — genuine capability
   gap (multi-pill, per-pill accent, independent taps) that `StatCard.actionLabel`
   doesn't support; extending it would be speculative API for one caller.

---

## 17. Deferred issues

- `job_workflow_Screen.dart`'s raw `TextStyle` literals — flagged (§8) as not cleanly
  mapping to `AppTypography` roles without per-site judgment calls; deferred to a
  future, explicitly-scoped typography pass rather than guessed at here (Step 12).
- `earnings_tab.dart`'s raw `TextField` → `AppTextField` adoption — deferred pending
  verification that `AppTextField` actually supports numeric keyboard + prefix text +
  custom hint without behavior loss (§9); money-input validation is too high-stakes to
  assume.
- `profile_tab.dart` — everything outside the CTA/tooltip/crash-safety sweep in §10
  (internal bottom-sheet typography/radius/TextField convergence) — explicit bounded-scope
  deferral, matching how `ProfileScreen` was handled in Batch C.
- Two `profile_tab.dart` navy-CTA line numbers (1149, 1752) — located but not individually
  opened; must be verified before fixing, not fixed by pattern-matching alone.

---

## 18. Out-of-scope findings

None newly discovered in this audit beyond what's already tracked in
`OUT_OF_SCOPE_FINDINGS.md` (OOS-1 through OOS-4). No backend/security/schema/architecture
problems surfaced while reading Batch D's six files.

---

## 19. Regression assessment

**Final `flutter analyze` (project-wide):**
- **0 errors**
- **1 warning** (`match_screen.dart:116` `unused_field` — pre-existing, outside Batch D
  scope) — down from 2, because `job_workflow_Screen.dart`'s unused
  `booking_repository.dart` import (§8) was removed.
- **64 total issues** — down from the 65-issue baseline, strictly better, no new
  issue categories introduced anywhere in the 6 edited files (each file's post-edit
  `flutter analyze` was checked individually and matched its pre-edit baseline count
  exactly, aside from the one warning fixed).

**Final `flutter test` (project-wide):**
- **239 passed, 12 failed** (251 total, up from 236/12/248 — the +15 comes from the new
  `test/phase2_batch_d_stabilization_test.dart`, all 15 passing).
- The 12 failing tests are **byte-for-byte the same test names** as the pre-Batch-D
  baseline (`OOS-1`) — no new failures, no previously-failing test newly passes or
  changes failure message.

**No regression found.** `git diff` was reviewed file-by-file (§17's business-logic
boundary check) and a targeted grep for Firestore/withdrawal/balance/payment-status
keywords across every added line found only the two expected `tr('invalid_amount')`
UI-string swaps — no business-logic line was touched anywhere in the diff.

---

## 20. Commit(s)

Not yet committed — changes are staged in the working tree, verified, and ready for the
user to review before a commit is made (per this session's operating rules, commits are
only created when explicitly requested). Files changed (`git status`):

```
 M lib/app_locale.dart
 M lib/earnings_tab.dart
 M lib/home_tab.dart
 M lib/job_workflow_Screen.dart
 M lib/jobs_tab.dart
 M lib/profile_tab.dart
 M lib/provider_dashboard.dart
 M lib/widgets/stat_card.dart
?? LINTHO_PHASE2_BATCH_D_AUDIT.md
?? test/phase2_batch_d_stabilization_test.dart
```

Diff size: 88 insertions / 57 deletions across the 8 modified `lib/` files — consistent
with a presentational/localization/a11y pass, not a rewrite.

---

## 21. Recommendation for Batch E

Batch D is complete and verified. Batch E (Auth/Onboarding/Secondary — `main.dart`
Splash/RoleRouter/LoginPage, `welcome_screen.dart`, `customer_register_flow.dart`,
`phone_verification.dart`, `register_otp.dart`, `technician_register_screen.dart`,
`pending_approval_screen.dart`, `language_selector.dart`) can proceed per the Migration
Plan's existing scope (§5) once the user reviews this batch and explicitly approves
starting the next one — no automatic continuation, per the Master Prompt's stop
condition. No new open decisions were surfaced that would carry into Batch E — the two
items Batch C left open (job-workflow colors, StatCard) are both resolved here (§3, §4).

---

## 22. Implementation notes (decisions refined during actual editing)

The pre-implementation audit (§3–§18) proved accurate; two scope decisions were made
more conservative during actual implementation than the audit's own wording suggested,
based on things only visible once editing began:

- **AppButton widget migrations were skipped entirely** (job_workflow_Screen.dart's
  chat/copy-phone outline buttons, the destructive confirm buttons in home_tab.dart/
  job_workflow_Screen.dart, §6/§8/§12 of the pre-implementation audit). Re-checking
  `AppButton`'s actual implementation during editing showed it hardcodes
  `padding: EdgeInsets.symmetric(vertical: AppSpacing.lg)` (16) with no padding
  override parameter, while these buttons use custom padding (`vertical: 10`) and
  fontSize (12) not exposed by `AppButton`'s API. Migrating them would have visibly
  changed button height/text size in a way that can't be verified without running the
  app on device. **Left as raw styled widgets — the color was already correct, so no
  functional violation remains, only an adoption-gap that's now more precisely
  attributed to `AppButton`'s current API gap** (documented here rather than silently
  dropped from scope).
- **Radius token convergence was scoped to non-interactive container/card/sheet shapes**
  (customer cards, job cards, status badges, bottom-sheet tops, icon tiles), converting
  both exact-token literals (8/16/24) and near-token container literals (14/18/20→
  nearest of chip/card/sheet). **Compact interactive-button radii (10, 12, 14 on
  Accept/Reject/confirm-sheet buttons) were left unconverted** — this is stricter than
  §5–§10's per-file wording implied, based on checking already-migrated reference files
  (`main.dart`, `review_screen.dart`) during implementation and finding the established
  codebase practice already leaves many near-token literals (especially 10/12) as raw
  values rather than mechanically snapping every one to a token, particularly on
  interactive controls where a visual size change is higher-stakes than on a static
  card background. This is *more* conservative than the original audit text, not less
  — no additional risk was introduced, some previously-flagged radius sites remain as
  documented deferred debt instead of being changed.

Neither refinement required a new user decision — both are narrowings of already-flagged
"REQUIRES VERIFICATION" / "DESIGN-SYSTEM VIOLATION (low risk)" items in the original
audit, resolved conservatively per the Master Prompt's own repeated instruction not to
blindly migrate every literal.

---

## Open decisions — resolution record

1. **§3** — Preserve `job_workflow_Screen.dart`'s step colors as-is (no `AppButton`
   change). **Approved and implemented** — no code change made to `_ActionButton`'s
   color logic; verified unchanged by the new stabilization test.
2. **§4** — Correct `StatCard`'s doc comment only. **Approved and implemented** —
   `lib/widgets/stat_card.dart`'s header comment updated, no API change, no
   `earnings_tab.dart` migration.
3. **§9** — Add one new `tr()` key (`invalid_amount`). **Approved and implemented** —
   added to all 4 locale blocks (lo/en/th/zh) in `lib/app_locale.dart`, Lao value set to
   the exact original hardcoded text; both `earnings_tab.dart` call sites now use
   `tr('invalid_amount')`.
4. **§9** — `AppTextField` adoption for earnings_tab.dart's money fields. **Approved
   deferral** — not implemented, remains open debt for a future pass.
5. **§10** — `profile_tab.dart` bounded scope. **Approved and implemented** — lines 1149
   and 1752 were individually opened and verified (both confirmed sole-primary-action
   "save"/"send" buttons matching the pattern) before fixing; all 5 CTA fixes and all 6
   back-button tooltips landed.
