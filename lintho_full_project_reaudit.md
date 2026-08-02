# LinTho Full Project Re-Audit — Customer + Provider + Admin

**Audit date:** 2026-08-02
**Type:** Independent, fresh, from-scratch audit (prior audit conclusions were NOT assumed; every finding below was independently re-derived and evidenced against current source)
**Method:** 8 parallel specialized review passes (security, backend/Firestore, customer-app functional, provider-app functional, admin-panel functional/RBAC, edge-case/robustness, UI/UX, performance/release-readiness) + a cross-system end-to-end workflow trace performed directly against the collected evidence. No code was modified, no deployment was performed, no Firebase data was changed.

**Verification-label legend** (used throughout): `CODE VERIFIED` = traced directly in source with cited file/line. `PARTIALLY VERIFIED` = core defect confirmed, but full exploitability/reachability depends on something not independently confirmed (e.g., a system outside audit scope). `NOT TESTABLE` = requires live execution, device, or console access not available to a static review. `ASSUMPTION` = reasoned inference, flagged as such. Nothing in this report is labeled `LIVE TESTED` — no code was executed against a live Firebase project during this audit.

---

## 1. Executive Summary

LinTho is a two-repository system: a single Flutter app (`lintho-app`) that serves both customers and providers via runtime role-based routing, backed by Firebase (Auth, Firestore, Storage, Realtime Database, Cloud Functions, FCM), plus a separate Next.js admin panel (`lintho-admin`) deployed independently via Vercel. This audit found **4 Critical**, **11 High**, **26 Medium**, and **~24 Low/informational** issues across security, backend data integrity, both mobile-app surfaces, the admin panel, UI/UX consistency, and release readiness.

The most consequential findings:

- **Admin RBAC is real for exactly one collection (`bookings`) and effectively absent everywhere else.** The 5-tier `AdminRole` model that the admin panel's UI enforces client-side has no matching server-side (Firestore rules) enforcement for `users`, `wallets`, `withdrawalRequests`, `topupRequests`, `providers`, `settings`, `coupons`, or `reviews`. A blanket rule (`firestore.rules` lines 341-345) grants **any** authenticated account with `role=='admin'` — regardless of tier — full read/write to nearly everything. Combined with the admin panel's auth state living in tamperable `localStorage`, a low-privilege admin (e.g. `marketing_admin`) can self-promote to `super_admin`, approve their own withdrawal, or delete any customer account, entirely bypassing the UI gates. This is independently confirmed from two different code paths (security audit reading the rules directly; admin-panel audit reading the client + rules together) — two independent passes converging on the same root cause is a strong confidence signal, not duplicate noise.
- **New provider registration is functionally disconnected from real bookings.** The service-category picker at sign-up offers a vocabulary (`aircon`, `maid`, `electrician`, `plumber`) that shares zero overlap with the only two categories any booking is ever actually created with (`ac_clean`, `house_clean`). A newly registered, approved provider will receive **no jobs at all** until they separately discover an unrelated settings screen and manually pick a different, still-mismatched category list.
- **Cash-paid jobs are credited to the provider's withdrawable wallet at full price with no payment-method distinction**, meaning a provider can be paid in cash by the customer and *also* withdraw the same amount from the platform — a direct financial-integrity gap, not merely a UX nit.
- **The Android release build is signed with the debug keystore** and ships with no code shrinking/obfuscation — this is not production-shippable to the Play Store as configured.
- On the positive side, the **booking-lifecycle core (creation, acceptance race-safety, coupon redemption, wallet-credit idempotency, review integrity, and — notably — the previously-flagged "customer can self-complete a booking" issue) were independently re-verified and found genuinely fixed.** Booking-specific admin actions (edit/cancel/refund) are the one area where the tiered RBAC model is fully and correctly wired end-to-end (UI → Firestore rules), and should be used as the template to fix everywhere else.

**Overall verdict: NOT READY FOR PRODUCTION.** See §20–21 for score and full reasoning.

---

## 2. Architecture Map

```
CUSTOMER APP + PROVIDER APP  (single Flutter app, role-based routing at runtime)
  Repo: C:\Users\DELL\StudioProjects\lintho-app
  Stack: Flutter/Dart, Firebase (Auth, Firestore, Storage, Realtime DB, FCM, Cloud Functions)
  lib/ — 60 flat .dart files, no folder separation between customer/provider — role
         determined by users/{uid}.role at runtime (main.dart RoleRouter)
  lib/widgets/, lib/theme/ — shared UI kit (AppTheme, AppColors, AppTypography, AppRadius)

  Cloud Functions: functions/index.js (878 lines) + functions/test/*.test.js
  Firestore rules: firestore.rules (831 lines)
  Storage rules: storage.rules
  Realtime DB rules: database.rules.json
  Firestore indexes: firestore.indexes.json
  Firebase project: sabee-app-35d99 (.firebaserc)
  Hosting: firebase.json serves build/web (the Flutter web build — NOT the admin panel)

        ↓ Firebase SDK (client) + callable Cloud Functions ↓

ADMIN PANEL  (separate repository, separate stack, separate deploy target)
  Repo: C:\Users\DELL\StudioProjects\lintho-admin
  Stack: Next.js 14 (App Router) + TypeScript + Tailwind, client-only SPA (no API routes),
         deployed via Vercel. Talks to the SAME Firebase project directly via the client SDK.
  Auth: Firebase Auth (email/password) + a 5-tier AdminRole model (super_admin,
        operations_admin, finance_admin, support_admin, marketing_admin) resolved from
        users/{uid}.adminRole, matched against a ROLE_PERMISSIONS matrix in
        src/constants/index.ts.

BACKEND / FIREBASE (shared by both apps)
  Firebase Authentication, Cloud Firestore, Cloud Functions (functions/index.js),
  Firebase Storage, Realtime Database (chat), Cloud Messaging (FCM), Cloudinary
  (third-party, used for KYC + job photos via signed upload from a Cloud Function).

EXCLUDED FROM SCOPE
  C:\Users\DELL\StudioProjects\sabee — confirmed to be an empty leftover directory
  (only an empty build/ folder), not a real third app or repo.
```

No further repositories or missing source were identified once `lintho-admin` was located; both apps and the backend were fully in scope for this audit.

---

## 3. Customer App Audit

Scope: authentication, profile, services/pricing, booking (creation → cancellation → history), payments, notifications, reviews. Full detail: 8 findings below; see §15–17 for passed/not-implemented/not-testable inventories.

### CUST-1 — High — BCEL QR payment amount ignores coupon discount
**Affected system:** Customer App — Booking Form, Step 4 payment
**Feature:** BCEL bank-transfer QR code and displayed payment amount
**Evidence:**
```dart
String get bcelQrData => 'BCEL|LINTHO|LAK|$grandTotal|LinTho Service'; // pre-discount
// _BcelQrBox displays AppPricing.fmt(order.grandTotal) — but the Bill Card above it,
// and toFirestore()'s 'price' field, both correctly use order.discountedTotal
```
**Exact file path:** `lib/booking_form_screen.dart` (`bcelQrData` getter ~line 518; `_BcelQrBox` ~2586-2589; `_BillCard` ~2082-2087)
**Relevant function/class:** `BookingOrder.bcelQrData`, `_BcelQrBox`
**How to reproduce:** Apply a coupon in Step 4, select BCEL payment. Bill summary shows the discounted total; the QR box below it shows and encodes the pre-discount `grandTotal`.
**Expected behavior:** QR payload and displayed amount should be `discountedTotal`, matching the bill and the stored `price`.
**Actual behavior:** Customer is instructed to transfer the undiscounted amount.
**Root cause:** Wrong field referenced (`grandTotal` instead of `discountedTotal`) in `bcelQrData` and the QR box's amount text.
**Recommended fix:** Use `order.discountedTotal` in both places.
**Regression risk:** Low — isolated to a display/payload string.
**Verification label:** CODE VERIFIED

### CUST-2 — High — "Book Now" on a specific provider does not guarantee that provider gets the job
**Affected system:** Customer App — Provider Details → Booking → Matching
**Feature:** Direct-provider booking vs. generic auto-match
**Evidence:** `booking_form_screen.dart._submit()` sets `data['providerId'] = widget.providerId` when booking from a provider's profile, but always routes to `MatchScreen` afterward. `match_screen.dart._findAndSendTop3()` never reads the pre-set `providerId` — it runs its normal geo/rating top-3 query and can send/assign the job to a different provider entirely; `firestore.rules`'s accept branch does not require the new `providerId` to equal the pre-existing one.
**Exact file path:** `lib/provider_details_screen.dart` (~757-761), `lib/booking_form_screen.dart` (`_submit`, ~773-793), `lib/match_screen.dart` (`_findAndSendTop3`, ~224-341), `firestore.rules` (~476-510)
**Relevant function/class:** `_BookingFormScreenState._submit`, `_MatchScreenState._findAndSendTop3`
**How to reproduce:** Tap "Book Now" from a specific provider's profile, complete the form. If that provider isn't in the algorithm's top-3 nearest/rated match, they never see the request; a different provider can accept and overwrite `providerId`.
**Expected behavior:** A direct provider booking should be routed to (or at least prioritize) that specific provider.
**Actual behavior:** Silently reassigned to whichever provider the generic algorithm surfaces.
**Root cause:** No branch in `MatchScreen`/booking submission respects a pre-set `providerId`.
**Recommended fix:** When `providerId` is pre-set, send the request to that provider first (with its own timeout/fallback) instead of running generic top-3 matching.
**Regression risk:** Medium — touches the core matching flow.
**Verification label:** CODE VERIFIED

### CUST-3 — Medium — Quick Booking allows scheduling a time already in the past
**Feature:** Quick Booking Flow, date/time picker
**Evidence:** `quick_booking_screen.dart._pickDateTime()` has no past-time guard, unlike the main booking flow's `booking_form_screen.dart`, which explicitly rejects `picked.isBefore(DateTime.now())` (a fix referenced by its own "AUDIT CUST-1/2026-07-30" comment) — the fix was never mirrored into Quick Booking's structurally identical picker.
**Exact file path:** `lib/quick_booking_screen.dart` (`_StepScheduleState._pickDateTime`, ~176-189)
**How to reproduce:** Quick Booking → pick today's date → pick a time earlier than now.
**Expected/Actual:** Should reject past times like the main flow; instead accepts and persists them.
**Recommended fix:** Add the same `isBefore(DateTime.now())` guard.
**Regression risk:** Low. **Verification label:** CODE VERIFIED

### CUST-4 — Medium — Notification preference toggles have no effect
**Feature:** Profile → Notifications settings
**Evidence:** `main.dart`'s notification bottom sheet writes `users/{uid}.notifPrefs` on toggle, but no Cloud Function in `functions/index.js` reads it before enqueueing `fcm_queue` writes (`onBookingStatusChange`/`onNewBooking`/`onReviewCreated`/`cleanupExpiredBookings` all send unconditionally).
**Exact file path:** `lib/main.dart` (`_notifPrefKeys` ~2997, `_showNotif` ~3004-3044)
**Expected/Actual:** Toggling "promo"/"news" off should stop those notifications; it does nothing.
**Recommended fix:** Read `notifPrefs` server-side before enqueueing, or remove the toggles until implemented.
**Regression risk:** Low (currently inert). **Verification label:** CODE VERIFIED

### CUST-5 — Medium — Chat messages never produce a push notification
**Feature:** Customer ↔ provider chat
**Evidence:** `chat_screen.dart._sendMessage()` writes only to RTDB/Firestore metadata; `NotificationSender.chatMessage()` exists in `fcm_service.dart` (lines 410-417) and is handled on the receiving end (`_navigate()`) but is never called from anywhere (confirmed by repo-wide grep), and no Cloud Function trigger exists for the RTDB chat path.
**Exact file path:** `lib/chat_screen.dart` (`_sendMessage`, 340-427), `lib/fcm_service.dart` (410-417)
**Expected/Actual:** Recipient should get a push when the app is backgrounded/closed; gets nothing beyond an in-app unread counter.
**Recommended fix:** Call `NotificationSender.chatMessage()` after a successful send, or add an RTDB-triggered Cloud Function.
**Regression risk:** Low. **Verification label:** CODE VERIFIED

### CUST-6 — Low — "Favorite Providers" is a non-functional placeholder
**Evidence:** `FavoriteProvidersScreen` always renders the empty state; no favorite/heart affordance or Firestore write path exists anywhere in the app.
**File path:** `lib/main.dart` (3395-3430). **Recommended fix:** Implement or remove the entry point. **Verification label:** CODE VERIFIED — classified Not Implemented.

### CUST-7 — Low — Cancellation fee amount computed but never shown to the customer
**Evidence:** `cancelFeeAmount` is computed/persisted by `CustomerBookingRepository.cancelBooking()` but never rendered in `booking_detail_screen.dart` or anywhere else.
**File path:** `lib/booking_repository.dart` (~504-517). **Recommended fix:** Surface the fee in the booking-detail cancellation card. **Verification label:** CODE VERIFIED

### CUST-8 — Low — Hardcoded fake ratings on Home screen "Popular" cards
**Evidence:** `HomeScreen._popular` hardcodes `'rating': 4.9/4.8` as static literals unrelated to any real aggregate.
**File path:** `lib/main.dart` (1186-1201). **Verification label:** CODE VERIFIED

**Passed (Customer App):** phone-OTP registration (role-conflict guard, debug-OTP gated to `kDebugMode`), phone re-verification/token refresh, login (phone + Google), RoleRouter's handling of an interrupted registration, booking creation (past-date validation, idempotent `clientRequestId` + transaction, coupon re-validation server-side), cancellation-fee grace-window logic, BCEL payment counter-signature (provider can't self-mark paid), duplicate payment-credit prevention, one-review-per-booking (client + rules), account deletion via real Cloud Function, reauthenticated password change, profile photo dual-write (Firestore + Auth), booking history (scoped, bounded, real error state).

---

## 4. Provider App Audit

Scope: provider auth, registration/approval gate, profile, KYC/verification, services & skills, availability, job discovery, job actions, cancellation/abandonment, earnings, client-side security posture.

### PROV-1 — Critical — Registration service-category picker never matches any bookable category
**Feature:** Technician registration vs. real booking categories
**Evidence:** `technician_register_screen.dart._serviceCategories` = `aircon/maid/electrician/plumber`, written to `providers/{uid}.serviceTypes`. Every real booking (main flow + Quick Booking) only ever uses `ServiceCategory` keys `ac_clean`/`house_clean` (`booking_form_screen.dart`). `isJobVisibleToProvider()` (`booking_provider.dart`) and the auto-match query (`match_screen.dart`, `arrayContains: category`) both filter on this field — zero overlap means zero visibility. A third, also-mismatched vocabulary (`ac_install`,`ac_repair`,`ac_clean`,`house_clean`,`maid`,`beauty`,`spa`,`massage`) exists in Profile → My Services (`profile_tab.dart ServicesScreen._all`), which is the *only* place `ac_clean`/`house_clean` can be selected — but it's not part of onboarding.
**Exact file path:** `lib/technician_register_screen.dart`, `lib/booking_form_screen.dart` (`ServiceCategory` enum), `lib/booking_provider.dart` (`isJobVisibleToProvider`), `lib/match_screen.dart` (`_findAndSendTop3`), `lib/profile_tab.dart` (`ServicesScreen._all`)
**How to reproduce:** Register a new technician through any of the 4 offered categories, get approved, go online. Have a customer create any booking. The provider never appears in open-jobs or the auto-match top-3 query.
**Expected behavior:** A provider's registered category should match real booking categories.
**Actual behavior:** New providers are structurally invisible to job matching until they manually find and reconfigure an unrelated settings screen.
**Root cause:** Three independent, unsynchronized category vocabularies across registration / profile-editor / actual bookings.
**Recommended fix:** Unify all three to the canonical `ServiceCategory.key` values; migrate already-registered providers' `serviceTypes`.
**Regression risk:** Low to fix in code; requires a data migration for existing providers.
**Verification label:** CODE VERIFIED

### PROV-2 — Critical — Wallet credited full job price regardless of payment method
**Feature:** Earnings/wallet crediting on booking completion
**Evidence:** `functions/index.js`'s `grantWalletCredit()` (called from `onBookingStatusChange`) credits `total = price + approvedAdditionalCharges` to `wallets/{providerId}.balance` unconditionally — no `paymentMethod` branch anywhere in the file (0 grep matches). Cash payment is self-attested by the provider with no counter-signature requirement (unlike BCEL, which requires `customerConfirmedPayment`). No commission/platform-fee concept exists anywhere in the codebase.
**Exact file path:** `functions/index.js` (`onBookingStatusChange`, `grantWalletCredit`), `lib/booking_repository.dart` (`confirmPaymentReceived`)
**How to reproduce:** Customer books with "Cash" payment method, pays the provider in person, provider confirms payment received (self-attested), job completes → Cloud Function credits the full price to the withdrawable wallet balance.
**Expected behavior:** Wallet credit should reflect only money LinTho actually collected (BCEL), or a commission-only model for cash jobs.
**Actual behavior:** Cash and BCEL jobs credit an identical, full, withdrawable amount — LinTho never received the cash, but the provider can withdraw it as if it had.
**Root cause:** No payment-method-aware branch in payout logic; no commission model exists.
**Recommended fix:** Exclude/limit cash-job wallet credit, or introduce an explicit commission calculation.
**Regression risk:** Medium — core payout logic; needs product/finance sign-off.
**Verification label:** CODE VERIFIED

### PROV-3 — High — No safety net for a silently abandoned accepted job
**Feature:** Cancellation / abandon prevention
**Evidence:** `cleanupExpiredBookings` (`functions/index.js`) only sweeps `status=='pending'` bookings past `expiresAt`; nothing checks `providers.isOnline` or stale `accepted`/`onTheWay`/`arrived`/`inProgress` bookings (0 grep matches for `isOnline` in `functions/index.js`).
**How to reproduce:** Provider accepts a job, then force-quits/goes offline permanently. Booking stays `accepted` forever with no auto-cancel, reassignment, or admin alert.
**Expected behavior:** An SLA-based backstop that flags/reassigns/cancels stuck active bookings.
**Recommended fix:** Extend `cleanupExpiredBookings` (or add a new scheduled function) to cover post-acceptance staleness.
**Regression risk:** Low to add. **Verification label:** CODE VERIFIED

### PROV-4 — High — Active job is hidden from the provider whenever they go offline
**Feature:** Home tab / availability toggle interaction
**Evidence:** `home_tab.dart`'s `ProviderHomeTab.build()` replaces the *entire* job-list body with a static `_OfflineView` whenever `isOnline==false`, including an active/in-progress job. The "All Jobs" tab (`watchJobHistory`) only ever shows terminal statuses (`completed/cancelled/rejected`). A purpose-built `ongoingJobProvider` exists in `booking_provider.dart` but is never consumed anywhere (dead code).
**How to reproduce:** Accept a job, then toggle offline. The active job disappears from the UI entirely; only re-visible by toggling back online.
**Recommended fix:** Render the ongoing job (via the existing `ongoingJobProvider`) independent of the online/offline toggle; only gate *new*-job sections by online state.
**Regression risk:** Low, additive. **Verification label:** CODE VERIFIED

### PROV-5 — Medium — Job-history filter chips return empty results in any non-Lao locale
**Evidence:** `jobFilterProvider`/`filteredHistoryProvider` compare against hardcoded Lao literals (`'ທັງໝົດ'`) and `JobStatus.label` (also hardcoded Lao), while the UI chips are built from locale-aware `tr()` strings — in English/Thai/Chinese, the comparison never matches.
**File path:** `lib/booking_provider.dart`, `lib/jobs_tab.dart`, `lib/Booking.dart`
**Recommended fix:** Compare against a stable enum/sentinel instead of display text. **Regression risk:** Low. **Verification label:** CODE VERIFIED

### PROV-6 — Medium — KYC/verification status never re-checked before matching/acceptance
**Evidence:** Neither the auto-match query (`match_screen.dart`) nor `acceptBooking()`/`setOnlineStatus()` check `providers.kycStatus`. If an approved provider's KYC is later `rejected`, nothing client-side stops them from staying online and accepting jobs.
**Recommended fix:** Add `kycStatus=='verified'` as an explicit precondition. **Regression risk:** Low.
**Verification label:** PARTIALLY VERIFIED (client-side gap confirmed; server-rule enforcement of this specific field not independently confirmed by this pass)

### PROV-7 — Medium — Repository layer doesn't independently enforce status-transition sequencing
**Evidence:** `BookingRepository.updateStatus()` only checks `paymentStatus` for the `completed` transition, not that the requested status is the immediate next state — sequencing is enforced purely by which button the UI renders (`_ActionButton` in `job_workflow_Screen.dart`). Not reachable through the shipped UI today, but a client-layer defense-in-depth gap. (Note: the Security audit independently confirmed `firestore.rules`'s `isValidBookingStatusTransition()` *does* enforce this server-side — see §7 — so this is residual client-layer risk only, not an end-to-end hole.)
**Recommended fix:** Add explicit transition validation inside `updateStatus()` as defense-in-depth. **Regression risk:** Low. **Verification label:** CODE VERIFIED (client-side gap only)

### PROV-8 — Low — `GeohashUtil.neighborsOf()` uses an approximate heuristic, not canonical geohash bit math
**File path:** `lib/geohash_util.dart`. Bounded impact — a query-less fallback path exists if the primary geo query returns zero results. **Verification label:** NOT TESTABLE (would need geohash test vectors).

**Passed (Provider App):** approval-gate bypass-proof (`RoleRouter` is the sole entry point, no alternate route reaches the dashboard while `status=='pending'`), job-action sequencing at the UI layer, wallet-credit and withdrawal idempotency (transaction-scoped guards), accept-job race-safety, reject-job open-vs-targeted distinction, provider self-cancel with correct customer notification, KYC document isolation from the public provider profile, FCM notification tap-routing, profile edit round-trip field parity.

---

## 5. Admin Panel Audit

Scope: `lintho-admin` (Next.js/TypeScript), cross-referenced against `firestore.rules` and `functions/index.js` in `lintho-app`.

**Re-verification of the prior claim "admin panel has no booking RBAC":** **REFUTED for booking-specific actions as of current code.** `firestore.rules` (420-563) has three explicit `getAdminRole()`-gated branches for `bookings/{bookingId}` writes (refund: `super_admin`/`finance_admin`; cancel: `super_admin`/`operations_admin`; non-critical edit: `super_admin`/`operations_admin`/`support_admin`), each with a `hasOnly()` field allow-list, and the UI (`bookings/page.tsx`) gates each button with `hasPermission()`. This is real, tamper-resistant, defense-in-depth RBAC — confirmed by two independent audit passes. **However, the same class of gap the prior audit found for bookings is still present, unfixed, almost everywhere else** — this is this audit's headline admin-panel finding (ADM-1).

### ADM-1 — Critical — Client-side RBAC fully bypassable by editing localStorage; not backed by Firestore rules for anything except bookings and admin-user management
**Evidence:** `useAuthStore` persists `{user, isAuthenticated}` to `localStorage` (`src/lib/store/index.ts`) and is never re-verified against Firestore after login. `RequireRole`/`hasPermission()` read only from this store. `firestore.rules`'s blanket bypass (`341-345`) grants **any** `role=='admin'` tier full write to every collection except `bookings` — so rules that look restrictive per-collection (e.g. `withdrawalRequests: allow update, delete: if false`) are OR'd with, and therefore overridden by, the blanket rule.
**Exact file path:** `lintho-admin/src/lib/store/index.ts`, `src/components/shared/RequireRole.tsx`, `src/lib/utils/index.ts:131`, `lintho-app/firestore.rules:341-345,691-715`
**How to reproduce:** Log in as `support_admin`/`marketing_admin` (lacking `withdrawals:approve`/`wallet:adjust`/`providers:approve`/`settings:write`). In devtools, edit the `lintho-admin-auth` localStorage entry to `role:'super_admin'` with full permissions, reload. Every UI gate passes; the underlying Firestore write (still under the attacker's real, valid session) succeeds for real because the collection-level rule doesn't check tier.
**Expected/Actual:** Only the intended tier should be able to perform these writes, enforced somewhere the user can't edit; instead enforcement lives only in client state the user fully controls.
**Root cause:** The 2026-07-30 remediation added `getAdminRole()` branches for `bookings/**` only; no equivalent was added for `users`, `wallets`, `withdrawalRequests`, `topupRequests`, `providers`, `settings`, `coupons`, `reviews`.
**Recommended fix:** Add `getAdminRole() in [...]` branches to `firestore.rules` per tier-restricted collection/action (mirroring the `bookings` pattern), or move these mutations behind Cloud Functions that re-verify tier server-side (as already done for `createAdminUser`/`setAdminUserActive`/`deleteAdminUser`).
**Regression risk:** Medium — tightening the blanket rule requires re-testing every legitimate admin write path.
**Verification label:** CODE VERIFIED (also independently confirmed from the rules side as SEC-1/SEC-2, §7).

### ADM-2 — High — Provider approval never releases the app's pending-approval gate (cross-repo field mismatch)
**Evidence:** Admin's approve action (`useApproveProvider`, `src/lib/hooks/index.ts:507-514`) writes only `providers/{id}.kycStatus`. The Flutter app's gate (`main.dart:231-236`, `RoleRouter`) reads `users/{uid}.status`, which is set to `'pending'` exactly once at registration (`technician_register_screen.dart:490`) and **never written anywhere else in either repo** (confirmed by cross-repo grep).
**How to reproduce:** Register a provider (→ `users.status='pending'`). Admin clicks Approve (→ `providers.kycStatus='verified'`). Reopen the provider app.
**Expected:** Approved provider reaches `ProviderDashboard`.
**Actual:** `PendingApprovalScreen` shown forever — the live listener on `users/{uid}` never sees `status` change.
**Root cause:** Two independent, never-unified "approval" concepts.
**Recommended fix:** Have `useApproveProvider`/`useRejectProvider`/`useSuspendProvider` also write `users/{uid}.status`, or change the app's gate to read `providers.kycStatus` instead.
**Regression risk:** Medium — this is the entire provider-onboarding critical path.
**Verification label:** CODE VERIFIED

### ADM-3 — High — Ten admin pages have zero RBAC gating at any layer
**Evidence:** `ROLE_PERMISSIONS` scopes `providers:approve`, `reviews:delete`, `transactions:read`, `audit_logs:read`, etc. to specific tiers, but `customers/page.tsx`, `providers/page.tsx`, `live-orders/page.tsx`, `notifications/page.tsx`, `promotions/page.tsx`, `reviews/page.tsx`, `reports/page.tsx`, `rewards/page.tsx`, `services/page.tsx`, `transactions/page.tsx`, `audit-logs/page.tsx` have zero `RequireRole`/`hasPermission` references. `Sidebar.tsx` renders every nav item unfiltered regardless of the viewer's permissions.
**How to reproduce:** Log in as `marketing_admin`, navigate directly to `/providers`, `/reviews`, `/transactions`, `/audit-logs` — full unrestricted access.
**Recommended fix:** Add `RequireRole`/`hasPermission` matching `ROLE_PERMISSIONS` to all ten pages; filter `Sidebar` nav items by permission.
**Regression risk:** Low, additive. **Verification label:** CODE VERIFIED

### ADM-4 — Medium — `middleware.ts` performs no real authentication check
**Evidence:** Only checks that *some* cookie value is present (not a valid, decoded Firebase ID token). Not a real data-access hole (Firestore rules are the actual boundary and would reject an unauthenticated visitor's reads), but the failure mode for a truly unauthenticated visitor is a broken/loading page rather than a clean redirect.
**Recommended fix:** Low priority; optionally verify the token in middleware or catch permission-denied globally. **Verification label:** CODE VERIFIED

### ADM-5 — Medium — Settings page write access not distinguished by tier the way the permission matrix implies
**Evidence:** `ROLE_PERMISSIONS.finance_admin` has `settings:read` only, but `settings/page.tsx` gates the whole page (including Save buttons) with `RequireRole(['super_admin','finance_admin'])` — no read/write split. `firestore.rules`'s `settings` write rule (`isAdmin()`) doesn't check tier either, so if the UI gate were bypassed (ADM-1), *any* admin tier could write settings, not just `finance_admin`.
**Recommended fix:** Split read vs. write UI, and tighten the Firestore rule to `getAdminRole()=='super_admin'` for writes. **Verification label:** CODE VERIFIED

**Section I (Booking Management) detailed conclusion:** List/detail visibility, edit, cancel, and refund are all genuinely tier-gated both in the UI and in `firestore.rules`, with `hasOnly()` field restrictions that a hand-crafted write cannot escape. Provider reassignment has **no** UI, hook, or rule support anywhere — correctly and consistently absent end-to-end (a **Not Implemented** feature, not a broken one). **PASSED, CODE VERIFIED** — this is the one part of the admin panel that should be the template for fixing ADM-1/ADM-3.

**Passed (Admin Panel):** Bookings (full RBAC chain), Admin-user provisioning (`_assertSuperAdmin()` re-verified server-side in Cloud Functions, immune to client tampering), Roles page (read-only, correctly gated), page-level gates on Withdrawals/Top-ups/Wallet-adjustment (though the underlying *write* is not tier-enforced — ADM-1 caveat applies), KYC document exposure (moved off the public provider doc, fetched lazily), mock-auth fails closed in production builds.

**Not Implemented:** Provider reassignment, SMS/Email notification delivery (explicitly throws "not connected to a delivery provider yet" — honestly surfaced in code), scheduled notifications, admin-edited service pricing actually affecting real bookings (apps still use hardcoded pricing).

---

## 6. Backend and Firebase Audit

### Firestore Collection Catalog

| Collection | Purpose | Written by | Read by |
|---|---|---|---|
| `bookings` | Core job lifecycle | Customer/provider repos (txn), Cloud Functions, Admin | Both apps, Cloud Functions, Admin |
| `providers` | Profile, online status, geohash, aggregate rating | Profile repo, LocationService, Cloud Functions | Both apps, Admin, rules |
| `providers/{id}/reviews` | Per-booking review | Customer (create), provider (`providerReply`) | Provider repo |
| `users` | Account profile, role, rewardPoints, referral | Client (owner), Cloud Functions, Admin | rules, rewards/referral providers |
| `wallets/{providerId}` | Balance/earnings/bank info | Cloud Functions (txn), client (bank fields only) | Earnings repo, Admin |
| `transactions` | Earning/withdrawal/topup ledger | Cloud Functions, Admin | Earnings repo, Admin |
| `withdrawalRequests` / `topupRequests` | Provider payout/topup requests | Client (create), Cloud Functions, Admin (approve/reject) | Admin |
| `coupons` | Discount codes | Admin, Cloud Functions, client (`usedCount` only) | Coupon repo, booking creation txn |
| `rewardRedemptions` / `rewardTransactions` | Points ledger | Client / Cloud Functions | Rewards provider |
| `referralCodes` | code→owner map | Client txn | Cloud Functions |
| `schedules` | Provider weekly availability | Profile repo | Profile repo |
| `services`, `settings/*`, `faqs` | Admin-managed config | Admin only | Various providers |
| `kyc/{uid}` | ID/selfie doc URLs (PII) | Profile repo | Owner/admin only |
| `fcm_queue` | Push outbox | Cloud Functions | `processFCMQueue` trigger |
| `chats` (Firestore) + RTDB `chats/{id}` | Chat metadata / messages | Chat screen | Chat screen |

Status enum (`pending/accepted/onTheWay/arrived/inProgress/completed/cancelled/rejected`) confirmed **identical** across `lib/Booking.dart`, `functions/index.js`, `firestore.rules`, and `lintho-admin/src/types/index.ts` — no drift found.

### BE-1 — High (latent) — Second round of approved "additional charges" on the same booking is silently never paid out
**Evidence:** `grantAdditionalChargesWalletCredit()` guards on a single boolean `additionalChargesWalletCredited` per booking; a second approved charges-round after the first sets `chargesJustApproved` true again but the guard blocks the credit with no error/log. Not reachable via the *current shipped UI* (which hides the "request charges" button once `additionalCharges != null`) — flagged as a real latent defect one client change away from firing, with silent, unobservable financial impact if it does.
**File path:** `functions/index.js` (83-102, 432-458), `lib/booking_repository.dart` (343-369)
**Recommended fix:** Track credited amount/delta instead of a boolean, or reset the flag atomically when a new charges round is requested.
**Regression risk:** Low. **Verification label:** CODE VERIFIED (logic defect); UI-reachability NOT VERIFIED as currently exploitable.

### BE-2 — Medium — Cloud Functions retries can produce duplicate push notifications
**Evidence:** Every `notify()`/`fcm_queue.add()` call lacks the idempotency guard the file's own financial `grant*()` functions use elsewhere; `processFCMQueue`'s `data.sent` check reads the immutable trigger snapshot, which is always `false` on a retried invocation of the same event.
**File path:** `functions/index.js`. **Recommended fix:** Deterministic doc IDs for `fcm_queue` writes tied to the event. **Verification label:** CODE VERIFIED (gap); real-world frequency is ASSUMPTION.

### BE-3 — Low — `withdrawalRequests.status:'failed'` is invisible in the admin panel and provider app
**Evidence:** Cloud Function writes `status:'failed'` on several conditions; `lintho-admin`'s `WithdrawalStatus` type and filter list have no `'failed'` member; no code in `lib/` reads `withdrawalRequests` after creation.
**Recommended fix:** Add `'failed'` to the type/filter; consider surfacing it to the provider. **Verification label:** CODE VERIFIED

### BE-4 — Low — No cleanup/TTL for `fcm_queue` or cancelled-booking chat records
**Recommended fix:** Firestore TTL policy or scheduled cleanup for `sent:true` docs. **Verification label:** CODE VERIFIED (absence confirmed)

### BE-5 — Low — Coupon `usedCount` not reverted on cancellation before acceptance
**Evidence:** Ambiguous by design (could be intentional anti-farming) — no code comment records intent, unlike nearly every other financial decision point in this codebase. Flagged so it becomes an explicit product decision. **Verification label:** CODE VERIFIED (behavior); intent is ASSUMPTION.

### BE-6 — Low — Provider can write `additionalCharges` fields on a cancelled/rejected booking they still own
**Evidence:** `isValidProviderChargesRequest()` isn't conditioned on `resource.data.status`, unlike the sibling admin-edit rule branch a few lines below it. Not financially exploitable (the only payout path additionally requires `status=='completed'`) — a data-hygiene gap, not a security hole. **Verification label:** CODE VERIFIED (rule text); NOT TESTABLE live.

### BE-7 — Low — Referral code generation has no uniqueness pre-check or retry-on-collision
**File path:** `lib/referral_provider.dart`. A genuine collision is safely rejected by rules (no silent overwrite) but surfaces as a raw transaction error to the affected user with no retry loop. **Verification label:** CODE VERIFIED

**Passed (Backend):** Booking creation idempotency (txn + `clientRequestId`), coupon redemption race-safety (client + rules), provider job-acceptance race-safety, wallet-credit idempotency (main payout path), signup/referral voucher idempotency (test-covered — `functions/test/referral-signup-voucher.test.js` passes), reward-redemption and withdrawal-reservation idempotency, admin approve/reject withdrawal/topup race-safety, review-aggregate computation (server-recomputed, not trusting rules alone), malformed-document resilience (`Booking.fromFirestore`, `_safeMapBookings`), field-name parity between main and Quick Booking flows, composite-index coverage for the current query set (except §9 PERF-1), payment-confirmation counter-signature.

---

## 7. Security Audit

### SEC-1 — Critical — Admin privilege escalation via blanket Firestore bypass rule
**Evidence:**
```
match /{document=**} {
  allow write: if request.auth != null &&
    get(...).data.role == 'admin' && request.path[3] != 'bookings';
}
```
This grants **any** admin tier full write to `users/{otherUid}`, including `role`/`adminRole` fields — the tier restriction (`role`/`adminRole` locked) only exists in the *owner-scoped* `users/{uid}` rule, a separate `match` block that doesn't apply here. Firestore OR-combines matching blocks, so the blanket rule's absence of a field restriction wins.
**How to reproduce (traced, not executed):** Any account with `role=='admin'` (any tier) can call `updateDoc(doc(db,'users',anyUid), {role:'admin', adminRole:'super_admin'})` directly from a Firestore client, bypassing the hardened `createAdminUser` Cloud Function entirely.
**Recommended fix:** Carve `users` out of the blanket bypass (at minimum for `role`/`adminRole`/`isActive`), or replace the bypass with per-collection `getAdminRole()` branches.
**Regression risk:** Medium. **Verification label:** CODE VERIFIED (also independently found from the admin-panel side as ADM-1).

### SEC-2 — High — Financial operations RBAC not enforced server-side
**Evidence:** `withdrawalRequests`/`topupRequests`/`wallets` balance mutations have no tier check in `firestore.rules` beyond the same untiered blanket bypass; `ROLE_PERMISSIONS` restricts approval to `super_admin`/`finance_admin` only in the UI.
**Recommended fix:** Same pattern as SEC-1/ADM-1. **Verification label:** CODE VERIFIED.

### SEC-3 — High — Provider live location and phone number readable by any authenticated user
**Evidence:** `firestore.rules` line 566: `match /providers/{providerId} { allow read: if isAuth(); }` — no scoping to an active booking relationship. `online_provider.dart` writes `lat`/`lng`/`geohash` every ≤5s while online; `technician_register_screen.dart` stores `phone` on the same doc.
**How to reproduce:** Any signed-in account (including a brand-new customer with no bookings) can poll any provider's live GPS coordinates and phone number continuously.
**Recommended fix:** Split live location into a booking-scoped-readable subcollection, or coarsen the publicly-readable location to city/district level.
**Regression risk:** Medium-High (several screens read `lat`/`lng` off this doc directly). **Verification label:** CODE VERIFIED.

### SEC-4 — Medium — Realtime DB chat rules don't validate message authorship
**Evidence:** `database.rules.json`'s `messages` rule only checks the writer is a chat participant, never that `senderId == auth.uid` — either party can write a message with the other's `senderId`.
**Recommended fix:** Add `"senderId": {".validate": "newData.val() == auth.uid"}`. **Verification label:** CODE VERIFIED.

### SEC-5 — Low — Password-reset flow allows account-existence enumeration
**Evidence:** `main.dart`'s forgot-password dialog shows a distinct `reset_password_not_found` message for unregistered emails instead of a generic "if this email exists..." message.
**Recommended fix:** Treat `user-not-found` the same as success in the UI. **Verification label:** CODE VERIFIED.

### SEC-6 — Low / Not fully testable — Cloudinary delivery for KYC documents may be publicly fetchable by URL
**Evidence:** Upload-signature requests are correctly owner/participant-scoped server-side, but standard Cloudinary delivery is public-by-URL unless the account has signed/authenticated delivery configured — not visible from this repo. **Recommended fix:** Confirm/enable signed delivery for `kyc/**` assets, or proxy reads through an auth-checking Cloud Function. **Verification label:** NOT TESTABLE (requires Cloudinary console access).

**Passed / correctly implemented (Security):**
1. **Customer cannot self-complete a booking** — re-verified independently; **this was fixed since the prior (2026-07-30) audit**, which had flagged it as broken. The prior finding should be considered stale.
2. Provider cannot accept a job not assigned/broadcast to them (`isValidSentToTargeting`/`isOpenOrTargeted`/KYC gate).
3. Payout requires real, server-independently-re-checked `paymentStatus=='paid'`.
4. BCEL payment cannot be self-marked "paid" by the provider (counter-signature required).
5. Wallet balance cannot be edited directly by the owning provider (bank fields only; balance via idempotent Cloud Function transactions).
6. Reviews cannot be forged (booking-linked, ownership/status/duplicate-checked server-side; rating fields locked from client writes).
7. KYC documents isolated from the publicly-readable provider profile.
8. Admin-user provisioning is properly server-enforced end-to-end (`_assertSuperAdmin()`), immune to client tampering — the one place the tiered model works correctly everywhere it's applied.
9. Cloudinary upload signing requires auth and scopes the folder to caller/booking.
10. New booking creation cannot fabricate a pre-completed/pre-paid/zero-price booking.
11. `contactPhone` on a booking must match the caller's verified phone claim.
12. Coupon redemption and reward/withdrawal handling are race-safe and server-enforced, not merely client-trusted.
13. Storage and Realtime DB both have explicit default-deny at the root.
14. No secrets hardcoded client-side in either repo; Cloudinary API secret lives in a Cloud Functions secret, not in Dart source.

---

## 8. End-to-End Workflow Audit

Traced directly against the evidence gathered in §3–7 (no separate re-reading was needed — every workflow below cites findings already fully evidenced above).

**1. Registration → booking → match → accept → work → payment → earnings → review.**
Registration, booking creation, acceptance race-safety, status-gated job actions, wallet-credit idempotency, and review integrity are all `CODE VERIFIED` working correctly in isolation. However the **workflow as a whole is broken for a large share of realistic paths**: a brand-new provider will never be matched at all (PROV-1, Critical); a customer using "Book Now" on a specific provider isn't guaranteed that provider receives the job (CUST-2, High); and once work is done, cash-paid jobs over-credit the wallet (PROV-2, Critical) while a second round of approved additional charges can silently go unpaid (BE-1, High-latent). **Conclusion: functionally completes only for the narrow happy path of an already-correctly-configured provider matched via the generic algorithm with a single BCEL payment and no repeat charge requests — CODE VERIFIED broken for the other paths named above.**

**2. Customer cancels before acceptance.** Works correctly (`CODE VERIFIED`) — rules permit customer cancel while `pending`. Coupon `usedCount` is not reverted (BE-5) — an explicit product-decision gap, not a functional break.

**3. Customer cancels after provider acceptance.** Works correctly with a 2-minute grace window / fee logic consistently applied client-side and server-computed (`CODE VERIFIED`). The assessed fee is never shown back to the customer afterward (CUST-7, Low — transparency gap, not a functional break).

**4. Provider rejects booking.** Works correctly (`CODE VERIFIED`) — open-board reject keeps the booking available to others; a directly-targeted reject is terminal.

**5. Provider cancels accepted booking.** The formal cancel path itself works correctly with proper customer notification (`CODE VERIFIED`). But the workflow assumes good-faith formal cancellation — a provider who instead silently abandons (goes offline, never opens the app again) triggers no automatic reassignment, timeout, or admin alert (PROV-3, High). **Conclusion: the explicit-cancel path is sound; the implicit-abandonment path has no backstop.**

**6. Admin cancels booking.** Genuinely, tamper-resistantly enforced end-to-end (UI `hasPermission` + Firestore `getAdminRole()` branch with a `hasOnly()` field allow-list) — `CODE VERIFIED PASS`, and the one part of the system that should be the template for fixing ADM-1/ADM-3.

**7. Admin reassigns provider.** **Not Implemented** anywhere (no UI, hook, or rule support in either repo) — confirmed consistent end-to-end, i.e. correctly and safely absent rather than half-built.

**8. Payment fails.** There's no automated third-party payment gateway in this system — BCEL "payment" is a manual bank-transfer QR that the customer self-confirms and the provider counter-confirms; there is no automated "payment failed" state as such. The closest analogue, "customer approves/rejects additional charges," lacks a timeout and fails silently offline with no user-visible error (EDGE-3, Medium). Separately, the BCEL QR itself can display/request the wrong (undiscounted) amount when a coupon is active (CUST-1, High).

**9. Refund is issued.** The Firestore-rules layer correctly restricts this to `super_admin`/`finance_admin`, requires `status=='completed' && paymentStatus=='paid'`, and locks the writable field set — `CODE VERIFIED PASS` at the rules layer. There is no automated payment-gateway refund call (consistent with the cash/manual-transfer economy of the app) — this is a logged status change, not a money-movement API call, which appears to be an intentional architecture given there's no payment processor integration anywhere in the codebase (`ASSUMPTION`, consistent with all other evidence).

**10. Customer submits review.** Works correctly and is duplicate/spoof-resistant both client-side (deterministic doc ID + existence check inside a transaction) and server-side (rules independently verify booking ownership/status/`reviewed` flag) — `CODE VERIFIED PASS`.

---

## 9. UI/UX Audit

16 findings, all Medium/Low, no Critical/High — the design system (`AppTheme`/`AppColors`/`AppTypography`/`AppRadius`, shared widgets) is well-built and consistently *available*, but adoption across individual screens is inconsistent, and an emoji→Icon migration that's clearly underway (per the codebase's own `[FIX ...]` comments) is incomplete in several places.

| ID | Sev. | Summary |
|---|---|---|
| UI-1 | Medium | Add-on/specialist service rows still render raw emoji instead of `Icon()` (`booking_form_screen.dart`) |
| UI-2 | Medium | Provider "My Services" screen still uses raw emoji per-row (`profile_tab.dart`) |
| UI-3 | Low | Avatar fallback is a 🔧 emoji glyph in 3+ places instead of initials/icon |
| UI-4 | Medium | ~40 localization keys hard-bake emoji into functional button/status copy across all 4 locales, sometimes duplicating an adjacent real `Icon()` |
| UI-5 | Medium | 3 independently hand-rolled "skeleton" loading widgets + a 4th plain-spinner pattern for the same UX moment, never consolidated into shared `PulsingFade`/`SkeletonBox` |
| UI-6 | Medium | `booking_form_screen.dart` uses raw `CircularProgressIndicator` in 3 spots despite a changelog comment claiming skeleton loading was applied |
| UI-7 | Medium | Schedule/Reviews screens (Profile tab) use bare `Text` for error/empty states instead of the shared `ErrorStateView`/`EmptyStateView` |
| UI-8 | Medium | `C.gold` used as *text* color for rating badges — computed contrast ≈1.7:1 vs. white, well under WCAG AA (4.5:1) |
| UI-9 | Low | One subtitle uses raw `Colors.grey[600]` instead of the `C.muted` token |
| UI-10 | Low | 4 snackbar strings hardcoded in Lao regardless of selected app language |
| UI-11 | Low | Corner-radius literals (9–28px) scattered across screens instead of the declared `AppRadius` 3-value scale |
| UI-12 | Low | No screen in the reviewed set actually consumes the declared `AppTypography` scale; font sizes chosen ad hoc per widget |
| UI-13 | Low | Provider "Go Online" toggle pill has an effective ~30-32px tap height, under the app's own 44dp minimum-target rule |
| UI-14 | Low | Job Workflow AppBar's call/navigate `IconButton`s lack tooltip/Semantics labels, unlike the identical, accessible actions duplicated lower on the same screen |
| UI-15 | Low | Admin panel icon-only buttons rely on `title` only, no `aria-label`; mobile hamburger ≈30×30px touch target |
| UI-16 | Low (informational) | Admin panel has full dark-mode theming; the Flutter app has none — likely an intentional scope decision, not a defect |

**Passed (UI/UX):** `app_theme.dart` is a well-documented single source of truth correctly wired into every relevant `ThemeData` sub-theme; `AppIconButton` is an exemplary accessible component (44dp minimum, Tooltip + Semantics); `EmptyStateView`/`ErrorStateView`/`SkeletonBox`/`PulsingFade` are clean and correctly disposed where adopted; `StatusStepper`/`AppStatus` genuinely unified two previously-drifting implementations; no raw color literals found in the two largest screens reviewed; consistent overflow-safe text wrapping in provider-side cards; consistent controller/subscription disposal; admin panel's shared component library (`Badge`/`Skeleton`/`EmptyState`/`ErrorState`/`DataTableContainer`/`Pagination`/`ConfirmDialog`) is coherent and well-adopted, with no ad hoc hex colors found.

---

## 10. Performance Audit

### PERF-1 — High — Likely-missing Firestore composite index for the chat list query
**Evidence:** `chat_screen.dart`'s `ChatListScreen` query combines `where('members', arrayContains: uid)` + `orderBy('lastMessageAt', descending: true)` — `firestore.indexes.json` has no `chats` collection entry at all.
**Impact:** If this currently works, the index exists only ad hoc in the live console and isn't reproducible from source — a fresh project or an indexes-only redeploy would break chat entirely with `FAILED_PRECONDITION`.
**Recommended fix:** Add the composite index to `firestore.indexes.json` and redeploy/verify. **Verification label:** CODE VERIFIED (file absence confirmed; live console state not checked).

### PERF-2 — Medium — Chat list and rewards-history listeners have no `.limit()`
Unlike every other query in the codebase, which is disciplined about bounding result sets. **File path:** `lib/chat_screen.dart`, `lib/rewards_provider.dart`. **Verification label:** CODE VERIFIED.

### PERF-3 — Medium — Rewards history renders all rows eagerly via `Column`+`for` instead of a lazy `ListView.builder`
**File path:** `lib/rewards_screen.dart`. Compounds PERF-2. **Verification label:** CODE VERIFIED.

### PERF-4 — Medium — KYC photo picker is the one call site missing `maxWidth`/`maxHeight` downsampling
Every other `pickImage()` call site in the app sets both `imageQuality` and `maxWidth`/`maxHeight`; the KYC (ID/selfie) picker in `profile_tab.dart` only sets `imageQuality`, uploading at full camera resolution. **Verification label:** CODE VERIFIED.

### PERF-5 — Medium — `cached_network_image` is a declared dependency but never used; `cacheWidth`/`cacheHeight` applied inconsistently
About half of `Image.network` call sites bound decode size, half don't; no disk caching anywhere despite the dependency being present. **Verification label:** CODE VERIFIED.

### PERF-6 — Critical — Android release build signed with the debug keystore, no shrinking/obfuscation
**Evidence:** `android/app/build.gradle.kts`: `release { signingConfig = signingConfigs.getByName("debug") }`, no `signingConfigs.release` block anywhere, no `minifyEnabled`/`shrinkResources`.
**Impact:** As configured, a release build **cannot be legitimately uploaded to the Play Store** (or is uploaded improperly signed), and ships unobfuscated, unshrunk.
**Recommended fix:** Add a real release signing config (keystore kept out of VCS) and enable R8 shrinking with appropriately tuned keep-rules for Firebase/Flutter plugin reflection.
**Regression risk:** Medium — R8 shrinking needs a full release-build test pass to avoid breaking reflection-dependent plugin code.
**Verification label:** CODE VERIFIED.

### PERF-7 — Medium — No global crash/error reporting hook
No `FlutterError.onError`/`runZonedGuarded`/Crashlytics/Sentry anywhere in the app — production crashes and uncaught async errors are invisible to the team. **Verification label:** CODE VERIFIED.

### PERF-7b — Low — One `StreamBuilder` (the top-level `RoleRouter`) doesn't branch on `snapshot.hasError`
A transient stream error on a fully-registered user's `users/{uid}` listener would misleadingly show "incomplete registration" instead of a retryable error. **Verification label:** CODE VERIFIED.

### PERF-8 — Medium — Admin panel's API client falls back to a `localhost` URL if `NEXT_PUBLIC_API_URL` is unset in production
Would fail 100% of production traffic with no clear error pointing at the cause, if the env var were ever missing from a build. **Verification label:** PARTIALLY VERIFIED (code confirmed; live Vercel env-var configuration not checked — latent risk only if currently set correctly).

### PERF-9 — Low — Admin panel's `next.config.js` ignores TypeScript/ESLint errors during build; no security response headers set
`ignoreBuildErrors`/`ignoreDuringBuilds: true` remove a safety net for an admin tool handling PII/financial data; no CSP/`X-Frame-Options`/etc. (`productionBrowserSourceMaps` is correctly left disabled, which is good). **Verification label:** CODE VERIFIED.

**Passed (Performance):** Lean startup path (no blocking Firestore fetch before first frame); all "hot" booking/earnings/review queries are bounded and correctly indexed; provider geo-matching is properly indexed with widening-radius fallbacks; no N+1 query patterns found anywhere; no writes-in-a-loop (batches/transactions used correctly); aggregate `.count()` query used for booking counts instead of downloading full lists; parallel (`Future.wait`) fetching used correctly for pricing; chat messages (high-frequency) correctly bounded via RTDB `limitToLast`; image compression is the norm at 8 of 9 picker call sites; controllers/subscriptions consistently disposed across ~20 files checked; Riverpod screens handle stream errors correctly via `AsyncValue.when` (the gap is isolated to PERF-7b); admin panel doesn't expose source maps and whitelists image domains explicitly.

---

## 11. Critical Issues

| ID | Summary |
|---|---|
| SEC-1 / ADM-1 | Admin privilege escalation: any admin tier can self-promote to super_admin and bypass financial/RBAC restrictions server-side (blanket Firestore rule + tamperable client auth state) |
| PROV-1 | New provider registration category mismatch → zero job visibility for new providers |
| PROV-2 | Wallet credited full price on cash jobs regardless of payment method → real double-payment exposure |
| PERF-6 | Android release build signed with debug keystore, no shrinking/obfuscation → not legitimately shippable as configured |

## 12. High Issues

SEC-2 (financial-ops RBAC not server-enforced), SEC-3 (provider live location/phone exposed to any authenticated user), ADM-2 (provider approval field mismatch — approved providers stuck on pending screen forever), ADM-3 (10 admin pages with zero RBAC gating), EDGE-1 (session-expiry false-success on all provider job actions), CUST-1 (BCEL QR ignores coupon discount), CUST-2 ("Book Now" doesn't guarantee the selected provider gets the job), PROV-3 (no backstop for a silently abandoned accepted job), PROV-4 (active job hidden from provider while offline), PERF-1 (likely-missing Firestore index for chat — could break chat outright), BE-1 (second round of approved additional charges silently unpaid, latent).

## 13. Medium Issues

SEC-4 (RTDB chat message-authorship spoofing), ADM-4 (admin middleware not a real auth check — low practical impact), ADM-5 (settings write-tier ambiguity), EDGE-2 (coupon check can hang indefinitely offline), EDGE-3 (additional-charges response has no timeout, fails silently), CUST-3 (Quick Booking allows past-time scheduling), CUST-4 (notification preference toggles are inert), CUST-5 (chat has no push notifications), PROV-5 (job-history filters break in non-Lao locales), PROV-6 (KYC status not re-checked before matching), PROV-7 (repository layer lacks its own status-transition check), BE-2 (duplicate push notifications under Cloud Functions retry), BE-3 (failed withdrawal requests invisible), PERF-2/3 (unbounded chat/rewards listeners + non-lazy list rendering), PERF-4 (KYC photo not downsampled), PERF-5 (inconsistent image caching/decode-size limiting), PERF-8 (admin API client localhost fallback in production), UI-1/2/4/5/6/7/8 (emoji migration incomplete, inconsistent loading-state widgets, missing shared error/empty states in two Profile sub-screens, low-contrast gold-on-white rating text).

## 14. Low Issues

SEC-5 (password-reset account enumeration), SEC-6 (Cloudinary KYC delivery — not testable), BE-4 (no fcm_queue/chat cleanup), BE-5 (coupon usedCount not reverted on early cancel), BE-6 (charges request allowed on terminal bookings — not exploitable), BE-7 (referral code collision has no retry), CUST-6/7/8 (dead Favorites screen, cancellation fee not shown, fake home-screen ratings), PROV-8 (geohash neighbor approximation — not testable), EDGE-4/5/6 (chat error state indistinguishable from empty, chat-open has no timeout/loading state, permission-denied mislabeled as "upload failed"), UI-3/9/10/11/12/13/14/15/16 (avatar emoji fallback, one stray color literal, 4 unlocalized snackbars, radius/typography scale not adopted, one undersized tap target, two accessibility-label gaps, dark-mode scope difference — informational), PERF-7/7b/9 (no crash reporting, one missing stream-error branch, admin build ignores type/lint errors + no security headers).

## 15. Passed Features

See the "Passed" subsection at the end of each of §3–10 above for the full, evidenced list per system. Headline items: booking creation is idempotent and atomic; the previously-flagged "customer can self-complete a booking" defect is genuinely fixed; job-acceptance and wallet-credit race conditions are correctly handled; reviews are duplicate/spoof-resistant both client- and server-side; admin booking management (edit/cancel/refund) has real, tamper-resistant, tiered RBAC end-to-end; admin-user provisioning is properly server-enforced; the Flutter app's design system and shared widget library are well-built where adopted; startup performance and query-indexing discipline are strong across the board.

## 16. Not Implemented Features

Favorite Providers (customer), notification preference enforcement (customer — toggle exists, has no effect), chat push notifications, provider reassignment (admin), SMS/Email notification delivery (admin — honestly self-documented as unimplemented), scheduled notifications (admin), admin-edited service pricing actually affecting live bookings, post-acceptance job-abandonment safety net (provider), any commission/platform-fee model.

## 17. Not Testable Features

Live exploitation of any Firestore-rules finding (no emulator/live project execution performed, by audit constraint); Cloudinary account-level delivery/access configuration (SEC-6); real FCM push delivery/timing on-device; actual Vercel production environment-variable values (PERF-8); actual on-device rendering, contrast under gradients/blur, screen-reader announcement behavior, and large-font-scale overflow risk (UI section); real query latency, memory profile, and APK/IPA size (Performance section); GeohashUtil correctness at precision boundaries (PROV-8); real-world Cloud-Functions event-redelivery frequency (BE-2).

## 18. Regression Risks

- **Fixing SEC-1/SEC-2/ADM-1** (tightening the blanket admin bypass) requires re-testing every legitimate admin write path across all 8+ affected collections — the highest-regression-risk fix in this report, but also the highest priority.
- **Fixing PROV-1** (category vocabulary unification) requires a data migration for already-registered providers' `serviceTypes`, or they remain invisible even after the code fix ships.
- **Enabling R8 shrinking** (PERF-6) can break reflection-dependent Firebase/plugin code paths if keep-rules aren't tuned correctly — must be tested with a full release build before shipping, not just a code change.
- **Splitting/coarsening provider location exposure** (SEC-3) touches every screen that currently reads `lat`/`lng` directly off the `providers/{uid}` document (search, match, tracking) and needs a coordinated rework, not a one-line rule change.
- Most other fixes (BE-2/3/4, CUST-3/4/5, PROV-5/6/7, UI-*, PERF-1/2/3/4/5/7/7b/9) are additive or narrowly scoped and carry low regression risk individually.

## 19. Recommended Fix Order

1. **SEC-1 / SEC-2 / ADM-1 / ADM-3** — close the admin RBAC gap (Critical, affects money movement and account takeover). Use the already-correct `bookings` pattern as the template.
2. **PROV-1** — fix provider-registration category vocabulary + migrate existing providers (Critical, breaks the core marketplace function for every new provider).
3. **PROV-2** — add payment-method awareness to wallet crediting (Critical, real financial exposure, needs a product decision on the cash-job model first).
4. **PERF-6** — real release signing + R8 shrinking (Critical for any store submission; do this on its own release-testing cycle given the regression risk noted in §18).
5. **ADM-2** — unify the provider-approval field so approved providers actually unlock (High, breaks onboarding).
6. **SEC-3** — scope down provider live-location/phone exposure (High, privacy).
7. **PERF-1** — add the missing chat composite index (High, could take down chat entirely on a fresh deploy).
8. **EDGE-1, CUST-1, CUST-2, PROV-3, PROV-4, BE-1** — remaining High items, roughly in this order given user-facing frequency (session-expiry false-success and payment-amount mismatch affect every user; abandonment/offline-hiding and the latent charges bug are lower-frequency but real).
9. Medium items, grouped by system, as a normal sprint's worth of hardening work.
10. Low/informational items opportunistically alongside other work in the same files.

## 20. Production Readiness Score: 48 / 100

Rationale: core booking-lifecycle logic (creation, race-safety, idempotency, reviews) is genuinely solid and several previously-flagged issues are confirmed fixed — this is not a codebase in disarray. But four **independently-confirmed Critical issues** span exactly the categories that matter most for a launch decision: **security** (admin account takeover), **core product function** (new providers can't get jobs at all), **financial integrity** (cash-job double-payment), and **release mechanics** (the Android build can't legitimately ship as configured) — plus a cluster of High-severity issues immediately behind them (broken provider onboarding, PII/location exposure, a possible chat outage, and a payment-display bug affecting every discounted booking). A score in the high-40s reflects a codebase that is closer to ready than not, but has hard blockers in every one of the categories a pre-launch review exists to catch.

## 21. Final Decision

# NOT READY FOR PRODUCTION

Do not ship until at minimum the 4 Critical issues (§11) and the ADM-2/PERF-1 High items are resolved and re-verified; the remaining High issues (§12) should be resolved or explicitly risk-accepted with a documented owner before launch.
