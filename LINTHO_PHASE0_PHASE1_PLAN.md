# LinTho — Phase 0 + Phase 1 Plan

Stabilization + Design System Enforcement — planning document only. No code has been
changed. This document is produced per the Master Prompt's Step 2 and the workflow
requires waiting for approval before any implementation begins.

Status: **awaiting approval**

---

## 1. Existing Architecture

- **Framework:** Flutter 3.44.1 / Dart 3.12, Material 3 (`useMaterial3: true`).
- **Backend:** Firebase — Auth, Cloud Firestore, Realtime Database (presence/chat),
  Storage, Cloud Messaging, Cloud Functions.
- **State management:** `flutter_riverpod` (`^2.5.1`) throughout — providers,
  notifiers, streams.
- **Navigation:** Plain `Navigator.push`/`MaterialPageRoute` everywhere audited.
  `go_router` (`^14.2.8`) is a declared dependency but no usage was found in any of
  the ~45 files read across this and the prior audit — appears vestigial. **Flagging
  as a verify-before-touching item**, not a Phase 0/1 concern.
- **Structure:** flat `lib/` (61 files, no feature folders), single app with role-based
  routing (`RoleRouter` in `lib/main.dart`) rather than separate customer/provider
  apps. `MainShell` (`lib/main.dart:956`) is the customer-facing tab shell
  (`IndexedStack` of `HomeScreen` / `BookingScreen` / `ProfileScreen`). Provider-facing
  shell is `lib/provider_dashboard.dart`.
- **Localization:** custom, not `intl`/ARB-based. `lib/app_locale.dart` — `enum AppLang
  { lo, en, th, zh }`, `class AppLocale extends ChangeNotifier`, global `String
  tr(String key) => AppLocale.instance.get(key)` (line 43). This **is** the existing
  localization architecture; Phase 1 localization work must route through `tr()` and
  add missing keys to all four locale maps in this same file — not introduce a second
  mechanism.
- **Tests:** 18 existing test files under `test/`, mostly named after prior audit fix
  batches (`critical_fixes_test.dart`, `high_severity_fixes_test.dart`,
  `medium_fixes_test.dart`, `release_audit_2026_07_27_fixes_test.dart`, etc.) — this
  project already has the habit of a test-per-fix-batch. Phase 0 should follow the
  same convention (e.g. `test/phase0_stabilization_test.dart`) rather than inventing a
  new testing structure.
- **Icons:** Material Icons only (`uses-material-design: true`, no icon-font/SVG-icon
  package beyond `flutter_svg` for illustrations). No custom LinTho icon set exists —
  "prefer the existing icon system" in Phase 1 §16 means `Icons.*`.

---

## 2. Existing Design System (source of truth)

All of the following already exist in `lib/theme/app_theme.dart` and
`lib/app_colors.dart`, are wired into a real `ThemeData`, and are confirmed **not**
regressed since the last audit:

| Layer | What exists |
|---|---|
| Color | `AppColors` — navy `#001B4B`, green `#14B87A` (primary), gold `#FBBF24`, ink `#1F2937`, background `#FFFFFF`, surface `#F8FAF8`, muted `#6B7280`, border `#E5E7EB`, success `#22C55E`, red `#EF4444`, orange `#F59E0B`, plus ~20 single-purpose tokens (category tints, promo banner colors, VIP gold/dark, splash gradient). Legacy alias class `C` in `app_colors.dart` mirrors every token under old names and is still the majority call pattern (40+ files) — **not a defect**, it's a compatibility shim over the same source of truth. |
| Status color | `AppStatus.colorOf(JobStatus)` / `.colorOfName(String)` / `.styleOf(...)` — single source of truth for booking/job status color. Confirmed still correctly centralized; the previously-fixed dual-status-system regression has not recurred. |
| Typography | `AppTypography` — 6 roles: `display`(32/700) `title`(22/600) `heading`(17/600) `body`(15/400) `label`(13/600) `caption`(12/500), plus `appBarTitle`(18/800). Wired into `ThemeData.textTheme`. `fontFamily` is deliberately `null` (system font). |
| Spacing | `AppSpacing` — 8pt grid: `xs`4 `sm`8 `md`12 `lg`16 `xl`24 `xxl`32 `xxxl`48. |
| Radius | `AppRadius` — `chip`8, `card`16, `sheet`24 (+ pre-built `chipShape`/`cardShape`/`sheetTop` `BorderRadius` objects). |
| ThemeData | `AppTheme.light` centrally styles AppBar, Card, ElevatedButton (green fill/white text/flat/card-radius), OutlinedButton (navy), TextField (filled surface, card-radius border, **sky** focus border), BottomSheet, Dialog, NavigationBar, Switch/Checkbox/Radio/FAB/ProgressIndicator (green), Chip, Divider. |
| Shared widgets | `lib/widgets/`: `app_text_field.dart` (`AppTextField` — wraps `TextField`, falls back to theme defaults, **no `errorText`/error-state param today** — gap noted below), `app_icon_button.dart` (`AppIconButton` — enforces 44dp minimum + mandatory `Semantics`/`Tooltip` label, already used correctly in several places), `empty_state_view.dart`, `error_state_view.dart` (supports `compact`+`onRetry`, inconsistently adopted), `pulsing_fade.dart`, `skeleton_box.dart`, `stat_card.dart` (two style variants incl. a "wallet/earnings" style per its own doc comment — not actually consumed by `earnings_tab.dart`), `status_stepper.dart` (correctly shared between provider job-workflow and customer tracking screens). |

**Conclusion, confirmed by fresh inspection:** the system is real, coherent, and does
not need replacement. The gap is adoption, not design. This plan does not propose new
colors, spacing values, or radius values anywhere.

---

## 3. Relevant Files (Phase 0 + Phase 1 scope)

**Phase 0 (bug fixes):**
- `lib/review_screen.dart` — Book Again / View History (lines 395-439)
- `lib/job_workflow_Screen.dart` — `customerName[0]` crash (lines 400-405)
- `lib/profile_tab.dart` — same unsafe-indexing pattern (line 1657)
- `lib/match_screen.dart` — fabricated live stats (lines 889-895), dead `estimatedMinutes` field (1272, 1750)
- `lib/app_locale.dart` — static stat strings (`info_chip_online_techs` etc., ~lines 668-670)
- `lib/provider_model.dart` — `estimatedMinutes` field does not exist; silently dropped by `fromMap()`
- `lib/provider_details_screen.dart` (line 757-771) and `lib/booking_form_screen.dart` (line 823) — no `isOnline` gate before booking
- `lib/technician_register_screen.dart` — GPS `deniedForever` has no manual-entry fallback (lines 938-977, `_finish()` 448-452)

**Phase 1 (design system enforcement, pilot screens):**
- `lib/main.dart` — `HomeScreen` + `_HomeSearchBar` + `SearchScreen` + `_SplashSkeleton` + `LoginPage` + `MainShell`
- `lib/quick_booking_screen.dart` + `lib/quick_booking_provider.dart`
- `lib/booking_form_screen.dart` (~4,036 lines — largest single file in the app)
- `lib/booking_detail_screen.dart`
- `lib/tracking_screen.dart` + `lib/match_screen.dart`
- Supporting: `lib/theme/app_theme.dart`, `lib/app_colors.dart`, `lib/widgets/*`, `lib/brand_mark_tile.dart`

---

## 4. P0 Bugs — Confirmed

Both re-verified against current source in this session (not just the prior audit
pass) — these are real, reachable code paths, not theoretical.

### P0-1 — "Book Again" / "View History" do nothing distinct
`lib/review_screen.dart:407-439`. Both buttons call the identical
`Navigator.popUntil(context, (r) => r.isFirst)`. Confirmed the screen already receives
everything needed to do this correctly: `ReviewScreen` takes `provider` (full
`ProviderModel`) and `serviceName` as constructor params (`review_screen.dart:32-45`),
and is reached via `Navigator.push` from exactly three call sites
(`booking_detail_screen.dart:349`, `tracking_screen.dart:488`, `main.dart:2473`) — in
every case pushed **on top of** `MainShell`, never replacing it. This means:
- **View History** fix: pop back to `MainShell` and select its `BookingScreen` tab
  (`main.dart:2251`, already the real "my bookings" screen, already has
  Ongoing/Completed/Cancelled tabs) — not a new screen, just correct navigation.
- **Book Again** fix: pop back to `MainShell`, then open the booking flow pre-filled
  with `widget.provider` + `widget.serviceName` — but only if `widget.provider.isOnline`
  is still true (needs a fresh read, not the stale snapshot from when the job was
  booked). If offline, fall back to `provider_details_screen.dart` or search, not a
  dead end.

### P0-2 — Crash on empty `customerName`
`lib/job_workflow_Screen.dart:400-405` calls `b.customerName[0]`. `Booking.customerName`
defaults to `''` via `_str(d['customerName'])` on malformed/legacy docs
(`Booking.dart:215`), so this is a live `RangeError` path, not hypothetical. The same
pattern exists at `lib/profile_tab.dart:1657` (`r.customerName[0]` on a review). A
correct fallback pattern already exists in the same codebase at
`lib/home_tab.dart:136` and should be reused/extracted rather than re-invented per
call site. **A full-codebase grep for `[0]` indexing on user-controlled strings is
required in Phase 0 execution** — this plan does not claim these are the only two
instances, only the two confirmed.

---

## 5. P1 Bugs — Confirmed vs. Requires Verification

### Confirmed (re-checked against current source this session)

- **Fake live data, `match_screen.dart:889-895`** — `tr('info_chip_online_techs')` /
  `_avg_rating` / `_fast_eta` resolve to static strings hardcoded in `app_locale.dart`
  (all 4 locales), not query results. Traced the ETA specifically: `_onMatched()`
  passes `data['estimatedMinutes'] ?? 20` into `ProviderModel.fromMap()`, but
  `ProviderModel` (confirmed via full-field read) **has no `estimatedMinutes` field at
  all** — the value is silently discarded, so the "20 min" literal at
  `match_screen.dart:1272,1750` can never be anything else. This is broken plumbing,
  not just misleading copy — fixing the copy alone doesn't fix the underlying dead
  field.
- **Offline-provider booking, confirmed no gate exists** — grepped both call sites;
  neither `provider_details_screen.dart`'s "Book Now" nor `booking_form_screen.dart`
  reads `provider.isOnline` anywhere before submit.
- **GPS fallback, confirmed missing** — `technician_register_screen.dart`'s location
  step (938-977) only offers "Use current location" or, if permission is
  `deniedForever`, "Open Settings." There is no manual address/pin-drop entry anywhere
  in this file. Note: the **customer** side of the app already has exactly this
  capability (`lib/map_picker_screen.dart`) — Phase 0 should reuse that screen/pattern
  for the provider flow rather than build a second one.

### Requires verification before implementation (flagging per Master Prompt §26.4 — do not assume)

- **What should "Currently Offline" actually allow?** The master prompt gives two
  options (`Schedule Later` / `Currently Offline`, non-bookable). The existing booking
  architecture (`booking_form_screen.dart`) has no concept of a "scheduled for later
  when provider comes online" state today — Firestore booking docs don't carry a
  provider-availability-pending status. Implementing "Schedule Later" as a real state
  is a larger change than swapping a button label. **Recommend Phase 0 scope = disable
  direct booking + honest messaging (`Currently Offline`) only; defer a real "schedule
  for later" queue to a separate, explicitly-approved change**, since building it
  would touch the booking document schema — a Stop Condition per §26.1.
- **Book Again's pre-fill scope** — should it jump straight to a payment-ready
  re-booking, or just pre-select provider+service and land the user on step 1 of the
  existing form for them to confirm address/schedule? Recommend the latter (safer,
  no schema/logic change, matches "do not blindly copy expired/unavailable provider
  state") but confirming this interpretation before building it.

---

## 6. Shared Components — Reuse vs. Create

### Already exist, reuse as-is
- `AppIconButton` — solid, enforces 44dp + `Semantics`. Use directly in Phase 1 pilot
  screens wherever a hand-rolled icon button was found (Tracking's map FAB/call
  button, Quick Booking's GPS/coupon-clear buttons, Match's cancel button).
- `status_stepper.dart` — already correctly shared between provider and customer
  screens. No change needed.
- `AppStatus` — no change needed.

### Already exist, need a small extension before Phase 1 can lean on them
- `AppTextField` — good base (falls back to theme defaults, override params for
  legacy exact-match styling) but **has no `errorText`/error-state parameter**, which
  the Master Prompt's `AppInput` requirement explicitly calls for (label/hint/error/
  focus). Needs one additive param, not a rewrite.
- `stat_card.dart` — doc comment already claims a "wallet/earnings" style variant, but
  `earnings_tab.dart` doesn't consume it (it hand-rolls an equivalent with a two-pill
  action row `StatCard` doesn't support). Needs either a small API extension (accept a
  list of action pills) or an honest doc-comment correction — decide during Phase 1,
  not in scope for the 5 pilot screens directly but noted since Earnings is adjacent.

### Do not exist, genuinely need creating (Master Prompt §15)
- **`AppButton`** — no shared button widget exists; every screen calls
  `ElevatedButton`/`OutlinedButton` directly, sometimes through the theme default,
  sometimes with local overrides (the navy-vs-green drift). Creating a thin `AppButton`
  with `primary`/`secondary`/`outline`/`ghost`/`destructive` variants **that simply
  delegate to the existing themed Material buttons with no new colors** is the
  single highest-leverage new component — it's also the direct fix vehicle for the
  P1 navy/green CTA inconsistency, since a shared widget removes the *ability* to
  casually override the color per call site.
- **`AppText`** — no semantic typography wrapper exists; this is the direct adoption
  vehicle for `AppTypography`, which today sits unused specifically because reaching
  for it requires remembering the role name rather than just typing `TextStyle(...)`.
  A thin `AppText.title(...)`, `AppText.body(...)` etc. makes the token the path of
  least resistance instead of the exception.
- **`AppCard`** — no generic card wrapper exists (only the theme's default `Card` and
  several bespoke hand-rolled containers, e.g. `booking_detail_screen.dart`'s `_card()`
  helper with its own radius/shadow). A thin wrapper standardizing padding/radius/
  border on top of the existing `CardTheme` closes this gap.
- **`AppSection`** — no shared section-header widget exists; every screen hand-writes
  its own header row. Low-risk, high-repetition win across all 5 pilot screens.
- **`AppIcon`** — lowest priority. `AppIconButton` already covers the *interactive*
  icon case (which is where the real bugs — sub-44dp targets, missing `Semantics` —
  live). A plain non-interactive icon-sizing wrapper is a nice-to-have, not a
  bug-fix vehicle. **Recommend deferring this one past the pilot** unless it falls out
  naturally while building the other four.

---

## 7. Pilot Screens

Per Master Prompt §19, the five pilot screens are pre-specified: **Home, Quick
Booking, Booking Form, Booking Detail, Tracking/Match**. Inspection confirms this is a
sound choice independent of the mandate — this exact group is where this audit found
the *highest concentration* of the primary cross-cutting defects:

- All 3 confirmed navy-vs-green CTA overrides live inside this group (Quick Booking,
  Booking Detail; Map Picker is adjacent/reused from Booking Form's flow).
- The only screen with zero emoji-migration progress (Quick Booking) is in this group.
- The fabricated-live-data P1 (Match) is in this group.
- The offline-provider-booking gap spans two files in this group (Booking Form +
  Provider Details, reachable from Booking Detail).
- Booking Form, at ~4,036 lines, is the largest single file in the app and the
  clearest case of the "self-documented internal drift from incremental growth" the
  original audit flagged (a code comment in the file itself describes reverting a
  button style because it matched neither existing convention).

No change to the pilot selection is recommended.

---

## 8. Risks

- **`booking_form_screen.dart` size/blast-radius.** At ~4,000 lines with 5 sequential
  steps, a full token migration touches a very large surface in one file. Recommend
  migrating it in step-sized sub-passes (one commit per form step) rather than one
  pass, per the Master Prompt's own "never modify the entire application in one
  uncontrolled pass" rule.
- **`AppButton` risks masking real semantic differences.** Some navy usage may be
  intentional (e.g. navy-as-secondary-action is a legitimate role per the Master
  Prompt's own color-hierarchy section) rather than accidental. Before blanket-
  converting every navy CTA to green, each site needs a one-line judgment call:
  *is this actually a primary action, or a legitimate secondary/navigation action
  that happens to sit on a CTA-shaped button?* Flagging this so migration isn't
  mechanical.
- **`estimatedMinutes` fix has two valid shapes.** Either add the field to
  `ProviderModel` and compute a real ETA (larger, needs a distance/time source — may
  not exist yet), or remove the fabricated-precision copy entirely in favor of honest
  language ("technician is on the way", no minute count). The Master Prompt prefers
  real data if it exists, honest language if it doesn't. **Requires a quick check of
  whether any ETA-capable data (distance + average speed, or a Cloud Function) already
  exists before deciding** — flagging as a Phase 0 sub-task, not a design decision I
  should make unilaterally.
- **`go_router` dependency is unused wherever checked.** Not touching it, but noting
  it so nobody mistakes it for the actual navigation architecture (it's
  `Navigator`/`MaterialPageRoute` throughout).
- **Two prior, larger audits found issues outside this Master Prompt's scope**
  (notification-system backend security findings, 2026-08-08; admin-panel items).
  These are **not** part of Phase 0/1 and will be logged to
  `OUT_OF_SCOPE_FINDINGS.md` rather than touched, per §3.
- **Test coverage for the two P0 fixes.** No existing test currently exercises
  `ReviewScreen`'s Book Again/View History buttons or the `customerName[0]` path —
  Phase 0 should add a `test/phase0_stabilization_test.dart`, matching this project's
  existing per-batch test-file convention, rather than assuming manual verification is
  sufficient.

---

## 9. Proposed Order of Work

1. **Phase 0 fixes**, one commit per fix per Master Prompt §24:
   `fix: prevent empty customerName crash` → `fix: Book Again / View History
   navigation` → `fix: gate booking on provider online status` → `fix: GPS fallback in
   provider onboarding` → `fix: remove fabricated match-screen stats`.
2. `flutter analyze` + `flutter test` (baseline not yet captured — will run at the
   start of Phase 0 execution per workflow Step 1/4).
3. Re-audit Phase 0 (workflow Step 5) — confirm no P0 remains before touching UI.
4. Build the 4 new shared components (`AppButton`, `AppText`, `AppCard`,
   `AppSection`) + the small `AppTextField` error-state extension — one commit:
   `refactor: create shared UI components`.
5. Migrate the 5 pilot screens, `booking_form_screen.dart` split into per-step
   sub-commits, one commit per screen otherwise:
   `refactor: migrate Home to design tokens`, etc.
6. Design-system acceptance test (§20) + automated violation scan (§21) against the
   pilot screens only.
7. Produce `LINTHO_PHASE1_AUDIT.md`.
8. **Stop.** Remaining ~40 screens are explicitly out of scope for this pass per §19
   ("Only after these five screens pass audit should you migrate the remaining
   screens") — that migration is a separate, future-approved pass.

---

## Open questions requiring your approval before implementation (Master Prompt §26)

1. **"Schedule Later" vs. simple "Currently Offline" messaging** for the
   offline-provider gate — building a real scheduling queue touches the booking
   schema; recommend the simpler, non-schema-changing option for Phase 0 (see §5
   above) unless you want the larger change.
2. **Book Again's exact landing point** — pre-fill provider+service and land on step 1
   of the booking form for confirmation, vs. attempting a fuller pre-fill. Recommend
   the safer, minimal option (see §5 above).
3. **ETA fix shape** — remove the fabricated minute-count vs. wire up a real
   computation. Needs a quick check of whether ETA-capable data already exists
   anywhere in the backend before this can even be decided with evidence.

No code will be modified until you confirm the plan above (and these three
open questions) are approved.
