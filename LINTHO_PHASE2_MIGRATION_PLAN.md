# LinTho — Phase 2 Migration Plan

Full-App Design System Rollout — planning document only. No application code has
been changed to produce this plan. Companion to `LINTHO_PHASE1_AUDIT.md` (the
reference implementation), `LINTHO_PHASE0_PHASE1_PLAN.md`, and
`OUT_OF_SCOPE_FINDINGS.md` (issues logged, not touched).

Status: **awaiting approval — do not begin Batch A until this plan is reviewed**

Method: every file below was inspected directly (grep counts for
`Color(`/`Colors.`/`TextStyle(`/`EdgeInsets.*`/`BorderRadius.circular(N)`/
`.styleFrom(`/emoji/hardcoded strings, plus a manual read for state-coverage,
CTA hierarchy, touch targets, and UX defects) — none of the findings below are
guessed from file names.

---

## 0. Executive summary

The Phase 1 pilot (Home, Quick Booking, Booking Form, Booking Detail,
Tracking/Match — 5 screens) is the only part of the app currently on the
design system. The remaining **~30 screens/classes across 23 files** (out of
65 files in `lib/`) have **zero adoption** of `AppButton`, `AppCard`, or
`AppSection` — every button on every non-pilot screen is a raw
`ElevatedButton`/`OutlinedButton` with local `.styleFrom(...)`. This is the
single largest and most consistent finding, and it directly reproduces the
navy-vs-green CTA drift Phase 1 fixed on the pilot screens: **rewards
redemption, referral redemption, provider profile saves, earnings
withdraw/bank-info save, KYC resubmission, and the address-confirm button in
the booking-address picker all render their primary action in navy, not
LinTho green.**

Two items are more than styling debt and worth flagging up front:

- **`review_screen.dart` has an active localization regression** — inline
  comments in the file itself document `tr(...)` calls being *deliberately
  removed* and replaced with hardcoded Lao strings (labeled "FIX-2" in the
  code). This isn't unmigrated legacy code; it's a step backward that needs
  reverting, not just wrapping.
- **`Booking.dart`'s `JobStatusX.label`/`TxTypeX.label` extension getters are
  hardcoded Lao-only strings**, not routed through `tr()`, and are actively
  rendered in production UI at `home_tab.dart:536` and
  `tracking_screen.dart:819` — so non-Lao users see broken status badges in
  two screens that aren't even in this audit's direct scope. Fixing this one
  shared file fixes both call sites at once — good first target.

Two items are feature/data gaps, not styling, and are called out separately
so they aren't silently "fixed" as part of a color pass:

- **`FavoriteProvidersScreen`** (`main.dart`) always renders its empty state —
  no query/list path exists. This may be an intentionally deferred feature,
  not a bug; flagged for a product decision, not a UI migration fix.
- **`PaymentHistoryScreen`** (`main.dart`) has no error branch on its
  `StreamBuilder` — a stream failure leaves the screen silently stuck. This
  *is* a defect (silent failure, no retry), not a style issue, and should be
  fixed as part of that screen's migration rather than deferred.

Everything else is the expected shape of Phase 2 work: raw `TextStyle`/
`EdgeInsets`/`BorderRadius.circular(N)` literals, ad hoc empty/error/loading
UI where `EmptyStateView`/`ErrorStateView` already exist and are used
correctly elsewhere in the *same file* (so the gap is adoption, not
capability), missing `Semantics`/`Tooltip` on icon-only buttons, and a
handful of emoji-as-functional-icon holdouts (`review_screen.dart`'s rating
faces, `home_tab.dart`'s section-header bell/clipboard/lightning emoji).

**Not a violation, needs a design-system decision before migrating:**
`job_workflow_Screen.dart`'s primary action button intentionally changes
color per workflow step (blue=en route, orange=arrived, navy=start,
green=complete, teal=confirm payment). `AppButton.primary` cannot be
recolored by design (that's the whole point of the pilot's fix). This is a
legitimate use case the current component doesn't support — recommend either
a small `AppButton` step-status variant or leaving this file's buttons as a
documented, deliberate exception, rather than forcing it onto `AppButton` and
losing the step-color signal. Flagging as an open question in §8.

---

## 1. A — Screen inventory

65 files in `lib/`. 5 screens (in `main.dart`, `quick_booking_screen.dart`,
`booking_form_screen.dart`, `booking_detail_screen.dart`,
`tracking_screen.dart`, `match_screen.dart`) are Phase 1 pilot / done. 11 files
are pure data/service/model/logic (no UI, not in scope: `Booking.dart`*,
`app_navigation_state.dart`, `booking_provider.dart`, `booking_repository.dart`,
`cloudinary_service.dart`, `coupon_repository.dart`, `fcm_service.dart`,
`firestore_service.dart`, `geohash_util.dart`, `lao_phone.dart`,
`legal_content_provider.dart`, `online_provider.dart`, `payment_config_provider.dart`,
`pricing_repository.dart`, `provider_model.dart`, `quick_booking_provider.dart`,
`referral_provider.dart`, `rewards_provider.dart`, `saved_address.dart`,
`support_provider.dart`). 7 files are the shared component library itself
(`lib/widgets/*`, `lib/theme/app_theme.dart`, `lib/app_colors.dart`,
`lib/app_locale.dart`) — source of truth, not migration targets.
`brand_mark_tile.dart` is a shared widget, referenced below where relevant.

\* `Booking.dart` is a model file but is flagged separately in §2 because it
contains UI-facing hardcoded-string getters that leak into two screens.

| Category | Screen / class | File | Pilot status |
|---|---|---|---|
| **Authentication** | Splash, `RoleRouter`, incomplete-registration gate | `main.dart` (`_SplashSkeleton`/`RoleRouter`/`_IncompleteRegistrationScreen`/`_RoleRouterSkeleton`) | not migrated |
| **Authentication** | `LoginPage` | `main.dart` | not migrated |
| **Onboarding** | Welcome/landing | `welcome_screen.dart` | not migrated |
| **Onboarding** | Customer registration (phone→OTP→profile) | `customer_register_flow.dart` | not migrated |
| **Onboarding** | Account-type picker + T&C | `register_otp.dart` (misleading filename — no OTP logic here) | not migrated |
| **Onboarding** | Phone re-verification gate | `phone_verification.dart` | not migrated |
| **Onboarding** | Provider registration (multi-step + KYC) | `technician_register_screen.dart` | not migrated |
| **Onboarding** | Provider awaiting/rejected-KYC status | `pending_approval_screen.dart` | not migrated |
| **Customer / Home** | Home | `main.dart` (`HomeScreen`, `_HomeSearchBar`) | ✅ Phase 1 pilot |
| **Customer / Home** | App shell / bottom nav | `main.dart` (`MainShell`, `_FloatingNavBar`) | not migrated (wraps every customer screen) |
| **Search** | Global search | `main.dart` (`SearchScreen`) | not migrated |
| **Provider discovery** | Provider profile + booking entry | `provider_details_screen.dart` | not migrated |
| **Favorites** | Favorite providers | `main.dart` (`FavoriteProvidersScreen`) | not migrated — **appears stubbed/dead**, see §0 |
| **Addresses** | Address/GPS picker | `map_picker_screen.dart` | not migrated |
| **Booking** | Quick Booking | `quick_booking_screen.dart` | ✅ Phase 1 pilot |
| **Booking** | Booking form | `booking_form_screen.dart` | ⚠️ Phase 1 pilot, partial (radius 100%, spacing partial, ~73 raw `TextStyle` remain) |
| **Booking** | Booking detail | `booking_detail_screen.dart` | ✅ Phase 1 pilot |
| **Booking** | Tracking | `tracking_screen.dart` | ✅ Phase 1 pilot |
| **Booking** | Provider match | `match_screen.dart` | ✅ Phase 1 pilot |
| **Booking** | Booking history (Ongoing/Completed/Cancelled) | `main.dart` (`BookingScreen`, `_ActiveBookingCard`, `_BookingListSkeleton`) | not migrated |
| **Booking** | Coupons list | `coupon_list_screen.dart` | not migrated (closest to compliant already) |
| **Booking** | Status/label helpers | `booking_display_helpers.dart` | ✅ already clean — delegates to `AppStatus`/`tr()` correctly |
| **Booking** | Status label leak | `Booking.dart` (`JobStatusX.label`, `TxTypeX.label`) | **hardcoded strings, needs fixing** — see §0, §2 |
| **Profile / Settings** | Customer profile | `main.dart` (`ProfileScreen`) | not migrated |
| **Payments** | Payment history | `main.dart` (`PaymentHistoryScreen`) | not migrated — missing error handling, see §0 |
| **Notifications** | Notifications list | `notification_screen.dart` | not migrated (smallest gap) |
| **Review** | Post-job rating | `review_screen.dart` | not migrated — **localization regression**, see §0 |
| **Rewards** | Points balance/redeem | `rewards_screen.dart` | not migrated — money-adjacent |
| **Referral** | Referral code share/redeem | `referral_screen.dart` | not migrated — money-adjacent |
| **Chat** | In-app chat | `chat_screen.dart` | not migrated — heaviest hardcoding of the batch |
| **Support** | Help/contact | `support_help.dart` | not migrated (small) |
| **Provider Core** | Dashboard shell / bottom nav | `provider_dashboard.dart` | not migrated |
| **Provider Core** | Home tab (online toggle, job queue) | `home_tab.dart` (`ProviderHomeTab`) | not migrated — best-covered provider file |
| **Provider Core** | Job history/filters | `jobs_tab.dart` (`ProviderJobsTab`) | not migrated — **closest to fully compliant** |
| **Provider Core** | Job workflow (accept→complete) | `job_workflow_Screen.dart` | not migrated — see step-color exception, §0/§8 |
| **Provider Core** | Earnings/wallet | `earnings_tab.dart` (`ProviderEarningsTab`) | not migrated — money screen |
| **Provider Core** | Provider profile/availability/KYC | `profile_tab.dart` (`ProviderProfileTab`) | not migrated — largest provider file |
| **Utility** | Language selector | `language_selector.dart` | not migrated (small, mostly fine) |

---

## 2. B — Design-system violations (cross-cutting)

Systemic patterns found in 3+ files — fix the pattern once conceptually, then
apply per screen in each batch:

| Pattern | Where | Severity |
|---|---|---|
| Primary CTA rendered in navy instead of LinTho green | `map_picker_screen.dart` (confirm address), `rewards_screen.dart` (redeem), `referral_screen.dart` (redeem), `pending_approval_screen.dart` (resubmit KYC), `profile_tab.dart` (save profile/services/schedule/review-reply — all but logout), `earnings_tab.dart` (withdraw, save bank info) | **High** — directly reproduces the exact defect Phase 1 fixed on pilot screens |
| Zero `AppButton`/`AppCard`/`AppSection` adoption | All 23 non-pilot files | High (structural) |
| `EmptyStateView`/`ErrorStateView` exist and are used correctly *in the same file*, but a nearby class in that file still hand-rolls its own | `main.dart` `BookingScreen` (shared widgets used at line 271 elsewhere in the file, not here); `earnings_tab.dart` (empty transactions ad hoc) | Medium — adoption gap, not a capability gap |
| No error branch on a data stream at all (silent failure) | `PaymentHistoryScreen` (main.dart) | **High — real defect, not style** |
| Hardcoded (non-`tr()`) user-facing strings | `Booking.dart` `JobStatusX.label`/`TxTypeX.label` (leaks into `home_tab.dart`, `tracking_screen.dart`); `coupon_list_screen.dart` (5 Lao-only strings); `earnings_tab.dart` (2 invalid-amount error strings); `review_screen.dart` (actively regressed, see §0); `chat_screen.dart` (only 3 `tr()` calls in 1046 lines — most UI text hardcoded) | High where it's a regression (review_screen), Medium elsewhere |
| Emoji used as functional icon (not decorative copy) | `review_screen.dart` (rating faces 😞😐🙂😊🤩, confetti, hardcoded "📱 Book Again" label), `home_tab.dart` (🔔📋⚡ in section headers) | Medium |
| Icon-only button missing `Semantics`/`Tooltip` | Entire Customer Core batch (0 hits found — `SearchScreen`, `PaymentHistoryScreen`, `provider_details_screen.dart`, `map_picker_screen.dart`, `_FloatingNavBar`); `profile_tab.dart` (6 back buttons, inconsistent with the rest of the app which does set tooltips); `chat_screen.dart` back arrow | Medium (a11y) |
| Icon-only control under 44dp | `map_picker_screen.dart` GPS FAB (`mini: true` = 40×40) | Medium (a11y) |
| Raw `TextField` instead of `AppTextField` | `earnings_tab.dart` (amount/bank fields, SnackBar-only validation, no inline `errorText`); `technician_register_screen.dart` (8 of 9 fields); most account-type/registration screens | Medium |
| `StatCard`'s doc-comment claims a "wallet/earnings" variant is in use — **confirmed still false** | `earnings_tab.dart` hand-rolls an equivalent (`_WalletCards`/`_Card`) instead | Low (doc hygiene) — real fix is either extend `StatCard` to support action pills, or correct the doc comment |
| `BorderRadius.circular(N)` off the 3-token scale (8/16/24) | Present in every non-pilot file audited (values cluster around 10/12/14/18/20 — same pattern Phase 1's radius sweep fixed on the pilot set) | Medium, mechanical |
| Missing brand mark (`BrandMarkTile`) | `LoginPage` (none at all), Splash (`_SplashSkeleton`), `welcome_screen.dart` (both use a duplicated raw `Image.asset(...)` instead of the shared widget) | Low–Medium (brand consistency, confirmed still true from a prior audit) |

---

## 3. C — UX violations

| Issue | File | Notes |
|---|---|---|
| Silent stream failure, no retry | `PaymentHistoryScreen` (main.dart) | Real defect — fix during migration, not deferred |
| Feature appears stubbed (always-empty, no data path) | `FavoriteProvidersScreen` (main.dart) | Flag for a product decision (build it or remove the nav entry point) — **do not silently build the feature as part of a styling pass** |
| Active `tr()`-removal regression | `review_screen.dart` | Needs reverting to `tr()`, not "migrating" |
| Money-action CTA in navy, not green | `rewards_screen.dart`, `referral_screen.dart`, `earnings_tab.dart` (withdraw) | Trust/clarity concern on money screens specifically — §32 of the Master Prompt calls these out for extra scrutiny |
| Tab label reuses a verb string as a noun (`tr('cancel')` for the "Cancelled" tab) | `main.dart` `BookingScreen` | Minor, not blocking |
| Inconsistent tooltip coverage on back buttons across the app | `phone_verification.dart` (2 back buttons, no tooltip) vs. `customer_register_flow.dart`/`technician_register_screen.dart`/`register_otp.dart` (all correctly set `tooltip: tr('back_semantic')`) | Same app, same control, inconsistent — should converge on the pattern that already exists |
| `AppIconButton` used inconsistently within a single file | `job_workflow_Screen.dart` — card-level call/navigate icons use `AppIconButton`, AppBar icons (back/call/navigate) are raw `IconButton` with manual `tooltip` | Low risk (raw `IconButton` defaults to 48dp, likely fine) but worth converging |
| Previously-flagged "referral VIP-token misapplication" | `referral_screen.dart` / `referral_provider.dart` | **Re-checked fresh this session: no VIP/token logic found anywhere in either file.** Either already fixed, or the finding was misfiled. Recommend confirming with git history before assuming action is needed; not re-flagging as open. |

---

## 4. D — Risk / priority

Per the Master Prompt's ordering (core booking → customer core → provider
core → account → secondary), adjusted for what was actually found (a
silent-failure defect and a localization regression outrank pure styling
regardless of traffic):

| Priority | Screens | Why |
|---|---|---|
| **P0** | *(none found)* | No crashes, no destructive-action gaps, no broken core functionality discovered in this pass. `PaymentHistoryScreen`'s silent stream failure is real but degrades to a blank/stuck screen, not data loss or a crash — rated P1, not P0. |
| **P1** | `PaymentHistoryScreen`, `map_picker_screen.dart`, `review_screen.dart`, `rewards_screen.dart`, `referral_screen.dart`, `Booking.dart` label getters, `LoginPage`+`RoleRouter`+Splash, `welcome_screen.dart`, `customer_register_flow.dart`, `phone_verification.dart`, `pending_approval_screen.dart`, `home_tab.dart`, `earnings_tab.dart`, `profile_tab.dart` (provider), `technician_register_screen.dart`, `job_workflow_Screen.dart`, `main.dart` `BookingScreen` (booking history is core, not P2 — see note) | Core funnels (auth/onboarding conversion, booking history, provider workflow), money-adjacent screens (§32 special-attention list), or a confirmed defect/regression |
| **P2** | `SearchScreen`, `FavoriteProvidersScreen`, `provider_details_screen.dart`, `MainShell`/`_FloatingNavBar`, `main.dart` `ProfileScreen` (customer), `chat_screen.dart`, `provider_dashboard.dart`, `jobs_tab.dart`, `register_otp.dart`, `phone_verification.dart` (a11y-only gap) | High-traffic but no correctness/trust issue, or already close to compliant |
| **P3** | `coupon_list_screen.dart`, `notification_screen.dart`, `support_help.dart`, `language_selector.dart` | Small surface, mostly compliant already, or low-traffic |

Note: I moved `main.dart`'s `BookingScreen` (booking history) to P1 rather
than the P2 an agent's isolated read suggested — it's a core, high-frequency
customer screen (every completed/ongoing/cancelled booking funnels through
it), consistent with the Master Prompt's "core booking" batch coming before
"customer account."

---

## 5. Migration batches

Revised from the Master Prompt's suggested grouping to match the files that
actually exist. Each batch = one checkpoint (analyze → test → design scan →
manual UX review → commit) before the next, per §27.

**Batch A — Customer Core / Discovery** (P1/P2, 5 files)
`main.dart`: `MainShell`/`_FloatingNavBar` chrome, `SearchScreen`,
`FavoriteProvidersScreen` (flag-only, no feature build), `PaymentHistoryScreen`
(fix silent-failure defect + style) · `provider_details_screen.dart` ·
`map_picker_screen.dart` (CTA color + FAB touch target) · `coupon_list_screen.dart`
(i18n strings + touch target only — otherwise compliant)

**Batch B — Booking (remaining)** (P1, 4 files/classes)
`main.dart`: `BookingScreen`/`_ActiveBookingCard`/`_BookingListSkeleton` ·
`Booking.dart` (`JobStatusX.label`/`TxTypeX.label` → route through `tr()`,
fixes `home_tab.dart` + `tracking_screen.dart` call sites as a side effect —
do this **early**, before Batch D, since Batch D's `home_tab.dart` depends on
it) · `booking_form_screen.dart` remaining typography convergence (optional
continuation of the Phase 1 follow-up sweep, ~73 `TextStyle` literals,
concentrated and largest) — treat as its own sub-item, not blocking

**Batch C — Customer Account** (P1/P2/P3, 6 files)
`main.dart` `ProfileScreen` · `notification_screen.dart` ·
`review_screen.dart` (**revert localization regression first**, then style) ·
`rewards_screen.dart` (money-adjacent, CTA color) · `referral_screen.dart`
(money-adjacent, CTA color) · `chat_screen.dart` (heaviest localization gap) ·
`support_help.dart`

**Batch D — Provider Core** (P1/P2, 6 files)
`provider_dashboard.dart` · `home_tab.dart` (depends on Batch B's `Booking.dart`
fix) · `jobs_tab.dart` (near-compliant already, low effort) ·
`job_workflow_Screen.dart` (**resolve the step-color `AppButton` question in
§8 before touching this file's buttons**) · `earnings_tab.dart` (money
screen — CTA color, `StatCard` decision, 2 hardcoded strings, `AppTextField`
adoption) · `profile_tab.dart` (largest provider file — CTA color, 6 missing
tooltips)

**Batch E — Auth / Onboarding / Secondary** (P1/P2/P3, 8 files)
`main.dart`: `_SplashSkeleton`/`RoleRouter`/`_IncompleteRegistrationScreen`/
`_RoleRouterSkeleton`, `LoginPage` (highest-effort file in this batch — zero
shared-component usage, no brand mark) · `welcome_screen.dart` (brand mark
fix) · `customer_register_flow.dart` (best-covered already) ·
`phone_verification.dart` (2 missing tooltips) · `register_otp.dart` ·
`technician_register_screen.dart` (`AppTextField` adoption, 8 of 9 fields
still raw) · `pending_approval_screen.dart` (CTA color) ·
`language_selector.dart` (quick pass — flag emoji likely acceptable as
intentional locale iconography, confirm rather than assume)

**Estimated blast radius** (rough, based on line counts + violation density,
not a time estimate): Batch E and Batch D are the largest single-file efforts
(`LoginPage` ~536 lines with zero adoption; `profile_tab.dart` 1827 lines,
`technician_register_screen.dart` 1203 lines). Batch B's `Booking.dart` fix is
small in isolation (2 getters) but has ripple effects into 2 already-shipped
screens outside this plan's direct scope, so budget verification time there,
not just the edit. Batch A and Batch C are more numerous but smaller files.

---

## 6. Components — reuse vs. extend vs. create

Per §33/§13 of the Master Prompt (justify before creating), the audit found
**no new shared component is needed** for the bulk of Phase 2 — every screen's
gap is adoption of `AppButton`/`AppText`/`AppCard`/`AppSection`/`AppTextField`/
`AppIconButton`/`EmptyStateView`/`ErrorStateView`, all of which already exist.
Two narrow exceptions surfaced:

1. **`job_workflow_Screen.dart`'s step-status button colors** (§0, §8) — a
   real gap `AppButton` doesn't cover today. Needs an explicit decision, not
   a new bespoke component invented mid-migration.
2. **`StatCard`'s "wallet/earnings" variant** — its own doc comment claims
   this exists; confirmed (again, independently, in this session) that it
   doesn't. `earnings_tab.dart` hand-rolls an equivalent with action pills
   `StatCard` lacks. Either extend `StatCard` to accept an action-pill list
   (used once, by this exact screen — meets the "3+ uses" bar only if a
   second consumer is identified first) or correct the stale doc comment and
   leave `earnings_tab.dart`'s version as the legitimate exception. Recommend
   deciding this at the start of Batch D, not before.

No `AppSuperCard`/`AppGreenButton`/screen-specific variants are proposed
anywhere in this plan.

---

## 7. Explicitly out of scope (tracked elsewhere, not touched by Phase 2)

- `fcm_queue` admin/ownership-check Critical finding (notification-system
  security audit, 2026-08-08) — backend security, not design/UX. Untouched.
- 12 pre-existing failing tests, `go_router` unused-dependency question — both
  already logged in `OUT_OF_SCOPE_FINDINGS.md` (OOS-1, OOS-2). Untouched.
- `FavoriteProvidersScreen`'s missing data path — flagged in this plan (§0,
  §3) as a product decision, not fixed as part of the styling pass.
- Firestore schema, Cloud Functions, authentication architecture, navigation
  architecture (`Navigator`/`MaterialPageRoute`), localization architecture
  (`tr()`) — none of these are touched anywhere in this plan, consistent with
  §3/§21/§22 of the Master Prompt.

---

## 8. Open questions requiring approval before implementation

1. **`job_workflow_Screen.dart` step-color buttons** — extend `AppButton`
   with a step-status variant, or document this file's buttons as a
   deliberate, permanent exception to "primary CTA is always green"? Affects
   Batch D scope.
2. **`StatCard` wallet/earnings variant** — extend the component or correct
   its doc comment? Affects Batch D scope and whether `earnings_tab.dart`'s
   card styling changes at all.
3. **`FavoriteProvidersScreen`** — is this a deferred feature (leave empty
   state as-is, just style it) or should the missing query path be raised as
   a separate, explicitly-scoped bug-fix task? Recommend the former for
   Phase 2 (style only, no new data-fetching logic) unless told otherwise.
4. **Batch order** — this plan sequences Booking (B) before Customer Account
   (C) and Provider Core (D), matching the Master Prompt's "core booking →
   customer core → provider core → account → secondary" guidance, with
   Batch A (Customer Core/Discovery) first since Home is already done and
   Search/Provider-Details/Address-Picker are immediate booking
   prerequisites. Confirm this ordering, or reprioritize.
5. **`booking_form_screen.dart`'s remaining ~73 raw `TextStyle` literals** —
   include as a Batch B sub-item (continuing the Phase 1 follow-up sweep), or
   leave as tracked debt and focus Phase 2 entirely on the 23 un-migrated
   files? Recommend including it in Batch B since it's the same
   already-open sweep, not new scope — but flagging since it wasn't
   explicitly re-approved.

No code will be modified until this plan (and the five questions above) are
approved. Once approved, execution follows §6/§27 of the Master Prompt:
Audit → Batch → Implement → `flutter analyze` → `flutter test` → design scan
→ manual UX review → commit → next batch, one batch at a time.
