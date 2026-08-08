# LinTho Full Project Re-Audit (ກວດສອບອີກຄັ້ງ)
**Date:** 2026-08-06
**Scope:** Customer App, Provider App (both in `lintho-app`, Flutter), Admin Panel (`lintho-admin`, Next.js), Firebase Authentication, Cloud Firestore, Firestore/Storage/RTDB Security Rules, Cloud Functions, Notifications, Payments, Storage/media.
**Method:** Independent fresh audit. Did not trust or copy conclusions from the prior 2026-08-02 audit (same filename, overwritten by this report). 8 specialist sub-audits ran in parallel, each reading current source directly, each labeling every conclusion CODE VERIFIED / LIVE TESTED / PARTIALLY VERIFIED / NOT TESTABLE / ASSUMPTION. No code was modified, refactored, or deployed during this audit.

**Important — working-tree state at audit time:** `lintho-app` had 8 files with **uncommitted changes** (`lib/Booking.dart`, `lib/app_locale.dart`, `lib/booking_form_screen.dart`, `lib/main.dart`, `lib/online_provider.dart`, `lib/profile_tab.dart`, `lib/provider_dashboard.dart`, `lib/quick_booking_screen.dart` — ~810 lines, an in-progress Home/Booking/Profile UI redesign on top of commit `a35ae816`). All sub-audits examined the actual working-tree file contents, not just the last commit. Findings below apply to that state.

---

## 1. Executive Summary

This is a mature codebase — nine-plus prior audit rounds are visible directly in code comments (`🔒 [AUDIT ...]`), and the large majority of previously-known issue classes (unbounded queries, missing timeouts, non-idempotent writes, missing `mounted` checks, non-atomic wallet credits) are demonstrably still fixed. This fresh, independent pass found **1 new Critical, 10 High, 14 Medium, and 17 Low** issues that were not previously flagged (or reflect either new work or gaps earlier passes missed because they didn't cover the admin panel as thoroughly).

The headline finding is **CUST-1**: a real financial exploit reachable through completely ordinary customer UI actions (apply a coupon, then edit the order) that can push a booking's price to ₭0 while the provider is still dispatched to perform the full job — with no server-side backstop in `firestore.rules` or the booking-creation transaction to catch it. This alone is a shipping blocker.

Independently, the **Admin Panel** (a separate repo, `lintho-admin`) has three High-severity functional breaks that would hit staff on their first day of real use: editing a provider is broken for any account created after a schema migration (ADM-2), the Customer "View details" button 404s (ADM-3), and bookings created via the Quick Booking flow silently vanish from the Service filter (ADM-1). The admin panel's list pages also read entire collections client-side with no pagination and no search debounce (PERF-1/PERF-2) — fine today, but will degrade sharply and rack up Firestore billing as real usage grows.

On the positive side: the booking lifecycle state machine, wallet-crediting idempotency, review-uniqueness, RBAC enforcement in Firestore rules, and Cloud Functions authorization were all independently re-verified as solid by multiple agents working from different angles. Security rules are broadly strong, with one real gap (SEC-1: an incomplete exclusion list lets any admin bypass intentionally Cloud-Function-only collections).

**Verdict: NOT READY FOR PRODUCTION.** See §20–21.

---

## 2. Architecture Map

```
Customer App ─┐
              ├─► lintho-app  (Flutter, single codebase, role-based routing via RoleRouter)
Provider App ─┘        │
                        ├─ lib/                       UI + Riverpod state
                        ├─ functions/index.js          Cloud Functions backend (1101 lines)
                        ├─ firestore.rules (950 lines), storage.rules, database.rules.json
                        │
                        ▼
                   Firebase project: sabee-app-35d99
                   ├─ Authentication (phone OTP + email/password + Google)
                   ├─ Firestore: bookings, users, providers (+reviews subcoll.), wallets,
                   │   transactions, withdrawalRequests, topupRequests, coupons,
                   │   rewardRedemptions, rewardTransactions, referralCodes, fcm_queue,
                   │   kyc, schedules, chats, settings, services, faqs, addresses (subcoll.)
                   ├─ Realtime Database (chat messages + presence)
                   ├─ Cloud Storage / Cloudinary (KYC docs, job photos, avatars, slips)
                   └─ Cloud Functions (source present and tested; deploy status not
                        re-verified this session — prior sessions noted Blaze-plan-blocked)
                        ▲
                        │
              lintho-admin (Next.js App Router, separate repo, client-SDK-only —
              confirmed zero server API routes; firestore.rules is the actual
              enforcement boundary for every admin action)
              routes: dashboard, customers, providers, bookings, live-orders,
              transactions, topups, withdrawals, promotions, rewards, reviews,
              services, roles, admin-users, audit-logs, reports, settings, auth
```

No missing repositories — both `lintho-app` and `lintho-admin` are present locally as siblings under `C:\Users\DELL\StudioProjects\`. `sabee` (a third sibling directory) was previously confirmed empty/irrelevant.

---

## 3. Customer App Audit

Covered: registration/OTP, login (phone/email/Google), password reset, profile/address management, service catalog, both booking-creation flows (main form + Quick Booking), coupon redemption, notifications, reviews, and client-observed security boundaries.

**Solid:** idempotent booking creation (`clientRequestId` as transaction-scoped doc ID) in both flows; phone-verification gating enforced at both UI and write-call-site layers; one-review-per-booking enforced via `bookingId`-as-doc-ID transaction; cancellation-fee logic correctly re-checked server-side inside a transaction; password reset has no account-enumeration oracle; defensive `Booking.fromFirestore` parsing so one malformed doc can't crash a whole list stream; FCM notification tap-routing correctly role-scoped.

**Broken:** **CUST-1 / CUST-1b (Critical)** — coupon discount is captured as a fixed Kip amount and never invalidated when the customer edits the order afterward (both booking flows have a same-screen "Edit" shortcut back to the item-selection step); nothing server-side re-derives `discountAmount` against the live order total, so price can be forced to ₭0. **CUST-2 (Low)** — customer-tab logout doesn't defensively clear the nav stack the way the (uncommitted) provider-tab logout fix and delete-account flow do.

Full detail: §11 (Critical), §14 (Low).

---

## 4. Provider App Audit

Covered: registration, KYC/verification gating, profile, availability toggle, job discovery/visibility, full job-action lifecycle (accept → travel → arrive → start → photos → charges → complete), cancellation, earnings/wallet, and client-observed security boundaries.

**Solid:** registration writes a single atomic batch (no ghost accounts); role-conflict guard prevents a customer phone from silently becoming a provider; KYC gating is real-time (`kycStatus` stream) and independently re-checked server-side at accept-time; job-visibility filtering correctly excludes other providers' assigned/rejected/expired/category-mismatched jobs; full status state machine agrees across UI, client validation, and rules; payment-before-completion gate correctly wired end-to-end; wallet crediting has no client write path at all (Cloud-Function-only, idempotency-flagged).

**Broken:** **PROV-NEW-1 (High)** — a provider whose KYC is rejected is routed to the identical "under review, 24 hours" screen as a still-pending provider, with no in-app way to see the rejection reason or resubmit documents (the resubmit UI exists elsewhere in the app but is unreachable from this screen) — the account is permanently stuck without out-of-band support contact. **PROV-NEW-2 (Medium)** — the after-photo slot stays tappable after job completion, but the security rule unconditionally rejects any write on a `completed` booking, so a retake upload succeeds to Cloudinary and then fails with a raw `permission-denied` on the Firestore write. Three Low-severity polish items (generic error messages hiding specific reasons, missing `canLaunchUrl` guard on one of two "call" implementations, duplicate reject/cancel mechanisms for the same pending-job case).

Full detail: §12 (High), §13 (Medium), §14 (Low).

---

## 5. Admin Panel Audit

Covered (separate Next.js repo, `lintho-admin`): auth, RBAC, dashboard, customer/provider management, booking management, payments/withdrawals/topups, promotions, reviews, reports, settings, audit logs.

**Solid:** RBAC is genuinely enforced server-side via `firestore.rules` tier checks (not just hidden UI), cross-checked against `ROLE_PERMISSIONS`; `createAdminUser`/`setAdminUserActive`/`deleteAdminUser` independently re-verify `super_admin` server-side; withdrawal/top-up approve/reject use transactions with correct double-processing guards and correct reservation-reversal semantics; audit logging is real (Firestore-backed, written from every sensitive mutation checked); `npx tsc --noEmit` returned zero errors.

**Broken:** **ADM-1 (High)** — Quick Booking writes a localized display string into `serviceType` while the main booking flow writes a machine key into the same field; the admin Service filter compares against the machine key, so every Quick-Booking-created booking is invisible to that filter. **ADM-2 (High)** — the Edit Provider form still treats `phone` as a `providers/{uid}` field and requires it non-empty to enable Save, but `phone` was migrated to `users/{uid}` and `firestore.rules` now flatly denies writing it on the provider doc — Save is either permanently disabled (post-migration providers, no `phone` field at all) or silently fails via an uncaught `permission-denied` (legacy providers), taking the rest of the edit (name/city/bio) down with it. **ADM-3 (High)** — Customers' "View details" links to `/customers/{id}`, a route that doesn't exist (`useCustomer(id)` hook is fully implemented but no page ever calls it) — dead-end 404. Plus Medium (dead search box on Reviews, permanently-hardcoded `'completed'` transaction status makes 3 of 4 status filters unreachable) and Low (coupon status display never reflects real expiry; no provider-reassignment feature exists anywhere in the panel).

Full detail: §12 (High), §13 (Medium), §14 (Low).

---

## 6. Backend and Firebase Audit

Collection inventory (cross-referenced against every reader/writer found): `bookings`, `providers` (+`reviews` subcoll.), `users` (+`addresses` subcoll.), `wallets` (+`vouchers` subcoll.), `transactions`, `withdrawalRequests`, `topupRequests`, `coupons`, `rewardRedemptions`, `rewardTransactions`, `referralCodes`, `fcm_queue`, `kyc`, `schedules`, `chats`, `settings`, `services`, `faqs`. No unexplained orphan collections found.

**Live-tested:** Cloud Functions test suite — `node --test test/*.test.js` → **16/16 passing** (Cloudinary folder-regex validation, `deleteOwnAccount` scoping, `grantSignupVoucher` idempotency).

**Solid:** every financially-adjacent Cloud Function (`grantWalletCredit`, `grantAdditionalChargesWalletCredit`, `grantReferralReward`, `grantRewardPoints`, `grantSignupVoucher`, `onWithdrawalRequested`, `onRewardRedemptionRequested`) uses a transaction with an idempotency flag read-and-written inside the same transaction, correctly defending against Cloud Functions' at-least-once redelivery; `acceptBooking()` is genuinely atomic (re-reads booking/provider/user state before writing); coupon usage-count incrementing is transaction-scoped both client- and rule-side; `firestore.indexes.json` has a matching composite index for every query found; booking-status enum values are used identically as raw strings across client, functions, and rules.

**Broken:** **BE-1 (High)** — the 2026-07-30 fix that correctly moved refund state from an invalid `status:'refunded'` value to `paymentStatus:'refunded'` was never propagated to the admin panel's financial-reporting reads (`useDashboardStats`, `useRevenueTrend`, `useBookingTrend`, `useTransactionsSummary` all still check the now-permanently-false `status === 'refunded'`), so refunded revenue is never excluded from totals and the "Refunds" stat is permanently 0. **BE-2 (Medium)** — `match_screen.dart`'s candidate-notify write is a bare `.update()` (not a transaction) that unconditionally forces `status: 'pending'`, unlike every other status-changing write path in the app; under a specific retry/timeout race this could theoretically overwrite an already-`accepted` booking back to `pending`.

Full detail: §12 (High), §13 (Medium).

---

## 7. Security Audit

Covered: authentication across all 3 surfaces, Firestore/Storage/RTDB rules for every major collection, admin RBAC enforcement layer, Cloud Functions authorization, sensitive-data exposure.

**Solid (extensive — this is the strongest area of the codebase):** the full booking-lifecycle state machine, price/payment bounds, and phone-ownership checks are enforced in `firestore.rules` independently of client logic; a customer cannot read/write another customer's data; a provider cannot self-approve their own KYC/rating/stats (explicitly denied fields on the owner-write path); reviews are defense-in-depth validated both in rules and again server-side in the Cloud Function; wallet/earnings collections are owner-scoped both client- and rule-side; `getCloudinarySignature` requires auth and validates the target folder is genuinely owned by the caller (no unsigned-upload path); no hardcoded secrets found (Cloudinary secret is a Cloud Functions `defineSecret`); `lintho-admin` has zero server API routes, so `firestore.rules` — not any Next.js middleware — is honestly the real and only enforcement boundary, and the code's own comments correctly disclaim `middleware.ts` as non-authoritative.

**Broken:** **SEC-1 (High)** — the top-level admin blanket-bypass rule excludes only 8 collections from full admin write access via a hand-maintained array; 6 collections whose own dedicated rules are supposed to be Cloud-Function-only or field-restricted (`rewardTransactions`, `rewardRedemptions`, `kyc`, `chats`, `fcm_queue`, `referralCodes`) were never added to that list, so any signed-in admin of any tier can bypass their intended restrictions (forge reward ledger entries, reassign a chat's members, tamper with the KYC pointer doc, etc.) directly via the client SDK. This exclusion-list pattern has already been extended twice across prior audit rounds and is still incomplete — a structural fix (invert to an allow-list) is recommended over another patch. **SEC-2 (Medium)** — KYC ID/selfie photos and bank-transfer top-up slips are persisted as `getDownloadURL()` bearer-token URLs, which grant indefinite unauthenticated access to anyone who obtains the URL, independent of `storage.rules`. **SEC-3 (Low)** — service pricing/FAQ content is editable by any admin tier because no `services:write` permission exists yet in the RBAC model (rules correctly mirror this absence — a product-design gap, not a rules bug). **SEC-4 (Low, informational)** — an RTDB presence write appears to be dead code (no matching rule exists to permit it).

Full detail: §12 (High), §13 (Medium), §14 (Low).

---

## 8. End-to-End Workflow Audit

10 workflows traced through actual code (client write → rules/Cloud Function → other clients reading the result):

| # | Workflow | Verdict |
|---|---|---|
| 1 | Full happy-path lifecycle (register → book → match → accept → work → pay → earn → review) | **PASS** (idempotent throughout) — but see CUST-1: the *price* feeding this whole chain can be manipulated before booking creation |
| 2 | Customer cancels before acceptance | PASS |
| 3 | Customer cancels after acceptance | PASS (fee calc mirrored correctly client/server) |
| 4 | Provider rejects | PASS (open-board vs direct-assignment correctly distinguished) |
| 5 | Provider cancels accepted job | PASS (transaction re-checks `isFinished`) |
| 6 | Admin cancels booking | PARTIAL — writes go through real, tier-gated Firestore paths (confirmed by the admin functional pass), but no dedicated cross-repo trace was completed connecting the admin write back through to customer/provider-side state in this session |
| 7 | Admin reassigns provider | **NOT IMPLEMENTED** — no reassignment feature exists anywhere in `lintho-admin` (see ADM-7) |
| 8 | Payment fails | PARTIAL — no real payment gateway exists yet (BCEL flow is counter-confirmation-based, cash is self-attested); no true gateway-failure path to test |
| 9 | Refund issued | PASS functionally (write path is correctly tier-gated and atomic) but financial *reporting* of it is broken (BE-1) |
| 10 | Customer submits review | PASS (idempotent, double-submit-safe) |

Edge-case/robustness findings layered on top of this trace: **EDGE-1 (Low)** — past-date `scheduledAt` not validated server-side. **EDGE-2 (Medium)** — the provider's "additional charges" request sheet has no double-tap guard (inconsistent with the pop-before-await pattern used elsewhere in the same file), risking duplicate charge requests and duplicate customer notifications. **EDGE-3 (Medium)** — provider online/offline presence has two signals (Firestore `isOnline`, RTDB `presence/{uid}`) that aren't kept in sync server-side; a force-killed app can leave a provider matchable-but-unreachable until a 24h stale-booking cleanup cron eventually intervenes. **EDGE-4 (Low)** — deep-clean sqm input has no upper bound, surfacing a raw technical exception at submit time for unrealistic values instead of inline validation. **EDGE-5 (Low)** — one write method (`respondToAdditionalCharges`) was missed when the session-expiry guard pattern was rolled out everywhere else.

Full detail: §12–14.

---

## 9. UI/UX Audit

Covered all 3 surfaces, with extra scrutiny on the uncommitted redesign files since they're new/unreviewed work.

**Solid:** timers/controllers in the new carousel/search-hint widgets are correctly disposed; bottom-nav occlusion padding correctly updated across all 3 tabs to match the new floating nav bar; localization sync for the redesign's 24 new keys is clean (verified 4/4 language blocks present for every key, no fallback risk); image loading has placeholder/error fallbacks and preloading; a genuine overflow-guard improvement was added to the profile name/email fields in this same diff.

**Broken:** **UI-1 (High)** — the shared `StatCard` component (now reused for currency values) has no `maxLines`/overflow handling and no equal-height guard on its parent row — a large monthly-earnings figure or a longer-language label will visually overflow or break row alignment. **UI-2 (High)** — the new notification-bell button is 36×36dp, below the app's own documented 44dp minimum-tap-target rule (already correctly enforced elsewhere in the very same file), and has no Semantics label. Six Medium items, all concentrated in the new redesign work: a contrast-risk color swap on the Quick Book banner (dark→bright background, unchanged translucent-white text), two brand-new raw hex colors bypassing the `AppColors` token system, the new widgets not adopting the app's own `AppTypography`/`AppSpacing`/`AppRadius` system at all, remaining emoji-as-icon usage in touched files, and emoji baked directly into localized KYC-status strings (4 languages × 3 statuses). Several Low items: two structurally different visual treatments for the same online/offline feature between Home and Profile tabs, a dropped category-filter shortcut with no replacement, one dead widget class, one orphaned locale key.

Full detail: §12 (High), §13 (Medium), §14 (Low).

---

## 10. Performance Audit

**Live-tested:** `flutter analyze` — **64 issues, 0 errors** (2 warnings: unused import/field; 62 info-level lints, mostly `prefer_const_constructors` cosmetic items and pre-existing `deprecated_member_use`/`file_names` items; several `use_build_context_synchronously` infos in `profile_tab.dart` are already guarded by a `mounted` check immediately before use — low real risk, flagged as a known analyzer false-positive pattern).

**Solid (Flutter app side):** app startup does no blocking Firestore reads before first frame; nearly every list-backing query across the app is `.limit()`-bounded; every `ImagePicker` call site already constrains quality/dimensions; Android release build has minification, resource shrinking, and real signing config; dev-only packages are correctly scoped to `dev_dependencies`.

**Broken — concentrated entirely in the admin panel, and architectural rather than one-off:** **PERF-1 (High)** — essentially every admin list page (Customers, Providers, Bookings, Withdrawals, Transactions, Reviews) and the Dashboard call `getDocs()`/`onSnapshot()` on the **entire** collection with zero `where`/`limit`, then filter/sort/paginate client-side in JS; the Bookings page in particular holds an unbounded live listener open on the whole collection for the page's lifetime. **PERF-2 (High)** — the search box has no debounce, and search text is part of the data-fetching cache key, so combined with PERF-1, every keystroke re-triggers a full-collection read. **PERF-3 (Medium)** — the Providers list issues one `getDoc()` per provider in the *entire* collection (N+1) just to show wallet balances, before pagination even happens. **PERF-4 (Medium)** — 4 independent Dashboard widgets each separately re-fetch the full `bookings`/`providers` collections with no sharing between them. Two Low items on the Flutter side: a provider's "This Month's Earnings" stat silently undercounts once a provider passes 30 transactions in a month (reusing a capped history-list query for an aggregation it wasn't designed for); 6 `TextEditingController`s in profile bottom sheets aren't disposed (currently harmless since they're locally scoped, but deviates from the app's own established pattern).

**Impact assessment:** none of the Flutter-app-side items are urgent, but PERF-1/PERF-2 will degrade sharply — and increase Firestore billing meaningfully — as soon as `users`/`bookings`/`transactions` grow past roughly a few thousand documents each, which is realistic within the first months of real marketplace usage.

Full detail: §12 (High), §13 (Medium), §14 (Low).

---

## 11. Critical Issues

```
Issue ID: CUST-1 (+ CUST-1b, same root cause, second independent code path)
Severity: Critical
Affected system: Customer App (both booking-creation flows) / Firestore Rules / Cloud Functions (downstream wallet credit)
Feature: Booking — discount coupon application, price integrity
Evidence:
  - lib/booking_form_screen.dart:432-442 — BookingOrder.discountedTotal = (grandTotal - (couponDiscount ?? 0)).clamp(0, double.infinity)
  - lib/booking_form_screen.dart:2172-2189 — _CouponBox._check sets order.couponDiscount as an absolute number computed against grandTotal AT CHECK TIME only
  - lib/booking_form_screen.dart:1809 — _BookingReviewCard "Edit" jumps back to step 1 (service/cart selection) from the same review screen the coupon box lives on
  - lib/booking_form_screen.dart:2193-2194 — couponCode/couponDiscount are cleared ONLY by explicit user action (_CouponBox._clear()); nothing clears them when the order total changes underneath
  - lib/quick_booking_provider.dart:172-185 (selectService, no clearCoupon on re-selection), :125-126 (finalPrice, same clamp pattern), lib/quick_booking_screen.dart:35-43 (2-tap path back to service step)
  - lib/booking_repository.dart:543-588 (createBooking transaction) — re-validates only the coupon doc's own status/dates/usageLimit; never recomputes or bounds discountAmount against the booking's own serviceTotal/grandTotal
  - firestore.rules:167-171 — only checks price is a number in [0, 50000000]; no cross-field consistency check against serviceTotal/discountAmount
  - functions/index.js:188 — provider wallet credit on completion is computed directly from the same client-supplied price field
Relevant function/class: BookingOrder.discountedTotal / _CouponBox (booking_form_screen.dart); QuickBookingDraft.finalPrice / QuickBookingNotifier.selectService (quick_booking_provider.dart); CustomerBookingRepository.createBooking (booking_repository.dart)
How to reproduce: Start a booking, add items totaling e.g. 900,000₭, proceed to the review/payment step, apply a coupon worth 100,000₭. Tap "Edit" on the service row (or back arrow), remove/reduce items until the new total is below the already-applied discount (e.g. 80,000₭), return to the review step, submit. price = (80,000 − 100,000).clamp(0,∞) = 0. Independently reproducible in Quick Booking via its own 2-tap back path and re-selecting a cheaper package after applying a coupon.
Expected behavior: Coupon discount is recalculated (or the coupon re-validated and discountAmount re-derived) against the current order total immediately before submission; server independently bounds price against serviceTotal/discountAmount and rejects an inconsistent booking.
Actual behavior: A fully valid booking write is created with price as low as ₭0 for real, uncapped service value. The provider is dispatched to perform the full job and (if Cloud Functions are live) is paid based on the same manipulated price field — i.e. the provider can be underpaid for completed work, and the platform loses the full service value.
Root cause: couponDiscount is a stale, absolute Kip amount that's never invalidated when order-affecting fields change; no layer (client transaction, Cloud Function, Firestore rule) independently re-derives or bounds the discount against the live total.
Recommended fix: Clear couponCode/couponDiscount whenever any order-affecting field changes after a coupon has been applied, AND/OR recompute discountAmount server-side inside the createBooking() transaction from the coupon's own type/value/maxDiscount rather than trusting the client's discountAmount verbatim. Add a Firestore rule bounding price >= (serviceTotal + travelFee) - discountAmount with discountAmount itself re-derived, not trusted.
Regression risk: Low — additive validation/invalidation; does not change the correct happy path (coupon applied last, right before submit).
Label: CODE VERIFIED
```

---

## 12. High Issues

```
Issue ID: SEC-1
Severity: High
Affected system: Firestore Rules
Feature: Admin blanket-bypass rule — incomplete exclusion list
Evidence: firestore.rules:378-383 — top-level match /{document=**} grants any admin (any tier) write access unless request.path[3] is in an 8-entry exclusion array ['bookings','users','wallets','withdrawalRequests','topupRequests','providers','settings','coupons','transactions']. Six collections with their own dedicated Cloud-Function-only/field-restricted rules were never added: rewardTransactions (line 884-887, allow write: if false), rewardRedemptions (873-880, status transitions meant to be Cloud-Function-only), kyc (903-905), chats (934-948, members meant to be immutable post-creation), fcm_queue (918-923, if false), referralCodes (768-772, update/delete: if false).
Relevant function/class: top-level match /{document=**} block; getRole()/isAdmin()
How to reproduce: Any signed-in admin account (any adminRole tier, including low-privilege ones like marketing_admin) can, via the client Firebase SDK directly, forge/delete rewardTransactions ledger entries, force-complete or delete rewardRedemptions bypassing the atomic points-deduction transaction, overwrite a chat's members array to re-point a conversation, or tamper with queued fcm_queue push payloads.
Expected behavior: These 6 collections should be as unreachable through the blanket bypass as the existing 8 already are.
Actual behavior: They are not — the exclusion-list pattern has already been extended twice across prior audit rounds and is still incomplete.
Root cause: Deny-list pattern requires remembering to add every new restrictive collection to an unrelated array; this has been missed repeatedly.
Recommended fix: Add the 6 missing collection names to the exclusion array (quick fix); structurally better: invert to an allow-list of collections with no dedicated tier-sensitive rule, so new restrictive collections are secure by default.
Regression risk: Low — none of the 6 collections has a legitimate admin-write use case currently relying on the blanket rule.
Label: CODE VERIFIED
```

```
Issue ID: BE-1
Severity: High
Affected system: Admin Panel backend / Firestore data model (cross-repo field consistency)
Feature: Refund financial reporting (dashboard revenue, revenue trend, booking trend, transactions summary)
Evidence: lintho-admin/src/lib/hooks/index.ts — useRefundBooking (731-748) writes paymentStatus:'refunded' while status stays 'completed' (intentional, per a 2026-07-30 fix that stopped writing an invalid status enum value). Readers never updated to match: useDashboardStats (71-72) sums price+additionalCharges for every status==='completed' booking with no refund subtraction; useRevenueTrend (150-154) same; useBookingTrend (188) checks status==='refunded', which can now never be true; useTransactionsSummary (1481-1518) refunds accumulator checks the same permanently-false condition while total still includes the full refunded price.
Relevant function/class: useRefundBooking, useDashboardStats, useRevenueTrend, useBookingTrend, useTransactionsSummary (lintho-admin/src/lib/hooks/index.ts)
How to reproduce: Refund a completed booking via the Bookings page; open Dashboard or the Transactions summary for the same period.
Expected behavior: Refunded amount excluded from revenue totals; "Refunds" stat reflects actual refund count/amount.
Actual behavior: Revenue totals still include the refunded booking's full price; "Refunds" always reads 0; booking-trend chart buckets the refund as a normal completed booking.
Root cause: The writer-side fix (paymentStatus instead of status) was never propagated to these four reader hooks, which still check the old, now-dead status==='refunded' condition.
Recommended fix: Switch all four hooks to check paymentStatus==='refunded' (keep status==='completed' as the base filter) and subtract refundAmount from revenue/trend figures wherever paymentStatus==='refunded'.
Regression risk: Low — read-side only, no schema/write-path change.
Label: CODE VERIFIED
```

```
Issue ID: PROV-NEW-1
Severity: High
Affected system: Provider App
Feature: KYC verification / pending-approval gating
Evidence: lib/main.dart:302-305 — RoleRouter: kycStatus == 'verified' ? ProviderDashboard() : PendingApprovalScreen() — binary check, no branch for 'rejected'. lib/pending_approval_screen.dart:12-53 — static screen, only a Logout button, no kycStatus-aware content. A working "rejected" UI state (label/color) and KycScreen resubmit form already exist elsewhere but are only reachable from inside ProviderDashboard → Profile → KYC, which RoleRouter never permits for a rejected account.
Relevant function/class: RoleRouter (_RoleRouterState.build), PendingApprovalScreen, KycScreen
How to reproduce: Admin sets providers/{uid}.kycStatus = 'rejected'. Provider relaunches app → routed to the identical "reviewing your documents, 24 hours" screen shown to a still-pending account, with no link to see the rejection reason or resubmit.
Expected behavior: Distinct message with rejection reason and a path to resubmit KYC photos (KycScreen already implements this correctly, resetting kycStatus back to 'pending' on resubmit).
Actual behavior: Account is permanently stuck — the only available action is Logout — unless the provider contacts support out-of-band.
Root cause: RoleRouter/PendingApprovalScreen were never updated to branch on the 'rejected' value even though the rest of the app already supports it.
Recommended fix: Stream kycStatus in PendingApprovalScreen; on 'rejected', show the reason (if stored) plus a button pushing KycScreen directly.
Regression risk: Low — additive, isolated screen; approved-provider path untouched.
Label: CODE VERIFIED
```

```
Issue ID: UI-1
Severity: High
Affected system: Provider App
Feature: Profile tab — earnings stat card (StatCard component)
Evidence: lib/profile_tab.dart:127-129 — _profileStat(monthlyEarnings formatted as '₭12,345,000', ...) inside a 3-column Row. lib/widgets/stat_card.dart:100-106 — value/label Text widgets have no maxLines, no TextOverflow, no FittedBox.
Relevant function/class: _profileStat(), StatCard.build()
How to reproduce: View Provider Profile with a large monthly-earnings total (e.g. ₭12,345,000+) — an unbroken numeric string in a ~90-100dp-wide column.
Expected behavior: Value truncates/ellipsizes or shrinks to fit; all 3 stat cards stay equal height.
Actual behavior: No overflow protection at all; a long value or a 2-line label (locale-dependent) will visually overflow or break row alignment — StatCard was written for short/bounded text (rating, percentage) and reused here for unbounded currency text without adding safety.
Root cause: Shared component reused for new content type without overflow handling.
Recommended fix: Add maxLines:1 + TextOverflow.ellipsis (or FittedBox) to StatCard's text widgets; wrap the stat Row in IntrinsicHeight + CrossAxisAlignment.stretch.
Regression risk: Low — additive layout safety only.
Label: CODE VERIFIED
```

```
Issue ID: UI-2
Severity: High
Affected system: Customer App
Feature: Home screen header — notification bell button
Evidence: lib/main.dart:1781-1794 — Material/InkWell with Padding.all(8) around a 20dp icon = 36×36dp effective tap target, no Semantics label. App's own documented minimum is 44dp, already correctly enforced elsewhere in the same file (home_tab.dart:234-239, explicit "AUDIT UI-13" comment).
Relevant function/class: HomeScreen build() (header Row)
How to reproduce: Inspect the new notification bell icon-button.
Expected behavior: ≥44dp tap target, per the app's own established rule; Semantics label for screen readers.
Actual behavior: 36×36dp, below the documented minimum; icon-only with no text-equivalent for accessibility.
Root cause: New icon-only button added without reusing the app's existing 44dp-enforcing pattern.
Recommended fix: Wrap in a 44×44 (or 48×48) minimum container matching the existing _OnlineToggle pattern; add Semantics(label: tr('notifications'), button: true).
Regression risk: Low.
Label: CODE VERIFIED
```

```
Issue ID: ADM-1
Severity: High
Affected system: Admin Panel
Feature: Booking Management — Service filter
Evidence: lintho-admin/src/lib/hooks/index.ts:671 — filters on b.serviceType === params.service against machine-key options (SERVICE_CATEGORIES). lintho-app/lib/booking_form_screen.dart:549-554 writes serviceType as the machine key (e.g. 'ac_clean'). lintho-app/lib/quick_booking_provider.dart:251-253 writes serviceType as a localized display string instead, keeping the real machine key in a separate category field (confirmed present on both flows at lintho-app/lib/Booking.dart:281).
Relevant function/class: useBookings() (lintho-admin), QuickBookingNotifier.selectService()/submit() (lintho-app)
How to reproduce: Create a booking via Quick Booking; in the admin Bookings page, filter by the matching service category.
Expected behavior: Booking appears under its category filter.
Actual behavior: Never matches any Service filter option — only visible under "All Services". Bookings table's Service column is also visually inconsistent between the two flows.
Root cause: Two booking-creation code paths write semantically different values into the same field; the filter assumes only one of the two conventions.
Recommended fix: Filter/group on booking.category instead of booking.serviceType, since category is written consistently as the machine key by both flows.
Regression risk: Low.
Label: CODE VERIFIED
```

```
Issue ID: ADM-2
Severity: High
Affected system: Admin Panel
Feature: Provider Management — Edit Provider
Evidence: lintho-admin/src/app/providers/page.tsx:129-135 (form seeded from provider.phone), :213 (Save disabled if !form.phone), :516-529 (payload always includes phone if non-null). lintho-admin/src/lib/hooks/index.ts:608-615 — useUpdateProvider calls updateDoc with no onError handler anywhere. lintho-app/firestore.rules:683-686 — admin update rule on providers/{id} explicitly denies any write touching phone. lintho-app/lib/technician_register_screen.dart:521 confirms phone was deliberately moved off providers/{uid} to users/{uid} only.
Relevant function/class: EditProviderModal (providers/page.tsx), useUpdateProvider
How to reproduce: Open Edit on any provider registered after the phone-field migration (no phone field on their providers/{uid} doc at all) — Save button stays permanently disabled. For a legacy provider that still has a phone value, changing it and saving triggers a whole-payload permission-denied that silently discards the name/city/bio edits too, with no error surfaced.
Expected behavior: Admin can edit name/service types/city/bio; phone either isn't modeled here at all, or is written to the correct document.
Actual behavior: Editing is broken for post-migration providers (Save disabled) and silently fails for legacy providers (whole update rejected, no feedback).
Root cause: Admin UI schema wasn't updated when phone was migrated off the provider doc and blocked by rules.
Recommended fix: Remove phone from the Edit Provider form/payload (or redirect it to users/{uid}); add onError handling to every mutation on this page.
Regression risk: Low.
Label: CODE VERIFIED
```

```
Issue ID: ADM-3
Severity: High
Affected system: Admin Panel
Feature: Customer Management — "View details" navigation
Evidence: lintho-admin/src/app/customers/page.tsx:242 — router.push(`/customers/${c.id}`). Filesystem check confirms lintho-admin/src/app/customers/ contains only page.tsx — no [id]/page.tsx route exists (unlike bookings/[id] and providers/[id], which both do).
Relevant function/class: CustomersPage / "View details" button
How to reproduce: Click the eye/"View details" icon on any customer row.
Expected behavior: Navigate to a customer detail page.
Actual behavior: 404 / Next.js not-found page. useCustomer(id) hook is fully implemented (fetches user doc + bookings + stats) but no page consumes it.
Root cause: Missing route.
Recommended fix: Add src/app/customers/[id]/page.tsx using the existing useCustomer hook, matching the providers/[id] pattern; or remove the button until it exists.
Regression risk: None — additive fix.
Label: CODE VERIFIED
```

```
Issue ID: PERF-1
Severity: High
Affected system: Admin Panel
Feature: List pages (Customers, Providers, Bookings, Withdrawals, Topups, Transactions, Reviews) + Dashboard
Evidence: lintho-admin/src/lib/hooks/index.ts — getDocs(collection(db,'users')) + getDocs(collection(db,'bookings')) (295-296), providers+bookings (400-401), withdrawalRequests+providers+wallets (1084-1086), transactions+providers (1439-1440), collectionGroup(db,'reviews')+providers (1649-1650), an unbounded onSnapshot(query(collection(db,'bookings'), orderBy('createdAt','desc'))) with no limit (652), dashboard stats reading bookings+users+providers whole (66-68).
Relevant function/class: useCustomers, useProviders, useBookings, useWithdrawals, useTransactions, useReviews, useDashboardStats
How to reproduce: Open any of these pages against a Firestore project with several thousand documents in the relevant collections.
Expected behavior: Server-side paginated/limited queries.
Actual behavior: Every hook downloads the entire collection into the browser and filters/sorts/paginates client-side; useBookings holds a live unbounded listener open on the whole collection for the page's lifetime, re-delivering the full set on every write anywhere in the collection.
Root cause: Pagination/search/sort implemented entirely client-side instead of via Firestore query cursors.
Recommended fix: Move filters into where() clauses, paginate with limit()+startAfter(cursor); replace the raw unbounded onSnapshot with a limited/paginated query.
Regression risk: Medium — exact-total-count UX and search behavior both need to change alongside the fix.
Label: CODE VERIFIED
```

```
Issue ID: PERF-2
Severity: High
Affected system: Admin Panel
Feature: Search filter bar (Customers/Providers/Bookings/Withdrawals/Transactions/Reviews)
Evidence: lintho-admin/src/components/shared/index.tsx:314-320 — search &lt;input&gt; onChange calls onSearch directly, no debounce. lintho-admin/src/lib/hooks/index.ts:34 — search text is part of the React Query cache key.
Relevant function/class: FilterBar, useCustomers/etc. queryKey
How to reproduce: Type a 6-character name into the Customers search box.
Expected behavior: Debounced (e.g. 300ms) before triggering a new query.
Actual behavior: Every keystroke changes the query key, which — combined with PERF-1 — triggers a brand-new full-collection read on every character. A 6-character term reads the entire users AND bookings collections 6 times in a row.
Root cause: No debounce on the search input; search folded directly into a cache key that gates full re-fetch.
Recommended fix: Debounce the input before it reaches the data hooks; longer-term, filter already-cached data locally when only search changed.
Regression risk: Low.
Label: CODE VERIFIED
```

---

## 13. Medium Issues

```
Issue ID: SEC-2 | Severity: Medium | System: Storage Rules / sensitive-data exposure
Feature: KYC ID/selfie and top-up slip images use getDownloadURL() bearer-token URLs
Evidence: lib/booking_repository.dart:725-732, 887-919 — .getDownloadURL() persisted into Firestore docs admins read from. storage.rules correctly restricts the Storage SDK path (owner-only) but the returned URL itself is a capability token independent of that rule.
Reproduce: Anyone who obtains a stored kycIdUrl/kycSelfieUrl/slipUrl (leaked log, screenshot, shared ticket) gets indefinite unauthenticated read access to that image.
Fix: For these two high-sensitivity categories, mint short-lived signed URLs on-demand via a Cloud Function instead of persisting a permanent download-token URL.
Regression risk: Medium (new callable + admin-panel image-resolution change). Label: CODE VERIFIED
```

```
Issue ID: BE-2 | Severity: Medium | System: Firestore Data Model (race condition)
Feature: Auto-match "send request to candidates" write
Evidence: lib/match_screen.dart:406-440 — bare .update() (not runTransaction) unconditionally forces status:'pending', unlike every other status-changing path in the app which re-reads current status inside a transaction first.
Reproduce (plausible sequence): write commits server-side but client times out locally → retry scheduler fires again → meanwhile a provider accepts (status→'accepted') → the stale retry's forced status:'pending' overwrites the acceptance, potentially letting a second provider accept the same job.
Fix: Wrap in runTransaction; only write if current status is still 'pending'.
Regression risk: Low. Label: CODE VERIFIED (race condition itself is an ASSUMPTION about network timing, not independently reproduced live)
```

```
Issue ID: EDGE-2 | Severity: Medium | System: Provider App
Feature: "Request additional charges" sheet has no double-tap guard
Evidence: lib/job_workflow_Screen.dart:866-985 — submit button not disabled while its own async call is in flight; sheet pops only after the await resolves (inconsistent with home_tab.dart's reject sheet, which pops synchronously before awaiting). booking_repository.dart:431-473 requestAdditionalCharges has no idempotency of its own.
Reproduce: Rapid double-tap "send request" before the first call resolves.
Fix: Track a local _sending bool disabling the button while in flight, or pop the sheet synchronously before the await (mirroring the existing safer pattern).
Regression risk: Low. Label: CODE VERIFIED
```

```
Issue ID: EDGE-3 | Severity: Medium | System: Cloud Functions / Firestore / RTDB
Feature: Provider presence desync between Firestore isOnline and RTDB presence
Evidence: lib/online_provider.dart:99-130 writes providers/{uid}.isOnline directly to Firestore and separately sets RTDB presence with onDisconnect() — but onDisconnect only touches the RTDB path, never the Firestore field match_screen.dart actually queries. dispose() is fire-and-forget with no retry on failure. No Cloud Function reconciles the two (confirmed via grep — no presence/isOnline/onDisconnect references anywhere in functions/index.js).
Reproduce: Provider force-kills the app / loses network permanently before dispose() runs.
Fix: Add an RTDB onWrite trigger mirroring presence into Firestore isOnline, or filter match_screen.dart on location/lastSeen freshness in addition to isOnline.
Regression risk: Medium if implemented as a new trigger; Low if a client-side freshness filter. Label: CODE VERIFIED
```

```
Issue ID: PROV-NEW-2 | Severity: Medium | System: Provider App / Firestore Rules
Feature: After-photo retake allowed post-completion, then rejected by rules
Evidence: lib/job_workflow_Screen.dart:647-654 — after-photo tile stays tappable when status is inProgress OR completed. firestore.rules:311-312 — isValidProviderChargesRequest() unconditionally denies any provider write once status is completed/cancelled/rejected, regardless of which fields are actually being changed.
Reproduce: Provider retakes the after-photo on a completed job → Cloudinary upload succeeds (cost incurred, file orphaned) → Firestore write fails with permission-denied.
Fix: Lock the after-photo tile once completed (mirroring the before-photo tile's existing b.status != completed guard), and/or scope the rule's terminal-status check to only additionalCharges* fields as its name implies.
Regression risk: Low. Label: CODE VERIFIED (rule logic traced manually, not live-tested)
```

```
Issue ID: UI-3 | Severity: Medium | System: Customer App
Feature: Quick Book banner contrast regression
Evidence: lib/main.dart:1818-1830 — background changed from solid dark navy to a bright orange gradient (#FF8C00→#FFA500); subtitle text color left unchanged at Colors.white70.
Fix: Increase subtitle opacity or add a scrim; verify ≥4.5:1 contrast against both gradient stops.
Regression risk: Low. Label: PARTIALLY VERIFIED (colors code-verified; rendered contrast ratio not measured)
```

```
Issue ID: UI-4 | Severity: Medium | System: Customer App
Feature: Raw hex colors bypass the AppColors token system
Evidence: lib/main.dart:1821,1827 — two new Color(0xFF...) literals for the Quick Book banner, matching neither AppColors.orange nor any existing token.
Fix: Add a named token (or reuse AppColors.orange) instead of inline hex.
Regression risk: Low. Label: CODE VERIFIED
```

```
Issue ID: UI-5 | Severity: Medium | System: Customer/Provider App
Feature: New redesign widgets bypass AppTypography/AppSpacing/AppRadius entirely
Evidence: grep for AppTypography|AppSpacing|AppRadius returns 0 hits across all 7 in-scope diffed files; ad-hoc font sizes (10/11/11.5/12/13.5/14/17/18) and padding/radius values that don't map to the app's declared 4/8/12/16/24/32 spacing or 8/16/24 radius scale.
Fix: Map new widgets' sizing onto the existing token classes where feasible.
Regression risk: Low (maintainability, not a functional bug). Label: CODE VERIFIED
```

```
Issue ID: UI-6 | Severity: Medium | System: Customer App
Feature: Remaining emoji-as-icon usage in files actively being redesigned
Evidence: lib/main.dart lines 1777 (👋 greeting), 1832 (🚀), 2276 (📋 empty state), 2732 (👤 avatar fallback), 3575/3598 (✅/💾 save flow), 4416 (🧾), 4509 (🛡️) — sits alongside a comment in the same file documenting the intended migration to Icons.* for proper Semantics support.
Fix: Replace with Icons.* equivalents + Semantics where meaning isn't otherwise conveyed.
Regression risk: Low. Label: CODE VERIFIED
```

```
Issue ID: UI-7 | Severity: Medium | System: Provider App
Feature: KYC status badge emoji baked directly into localized strings (4 languages)
Evidence: lib/app_locale.dart kyc_pending/verified/rejected keys carry ⏳/✅/❌ prefixes in all 4 locale blocks; profile_tab.dart comments confirm this is intentionally substituting for a Material icon.
Fix: Strip the emoji prefix from all 12 strings, render a real Icon driven by the existing status→color switch.
Regression risk: Low (touches 4 locale files, each has a 1:1 status→color mapping already). Label: CODE VERIFIED
```

```
Issue ID: ADM-4 | Severity: Medium | System: Admin Panel
Feature: Reviews search box is fully dead
Evidence: lintho-admin/src/app/reviews/page.tsx:47-57 — search state wired to FilterBar but never passed to useReviews(); useReviews's param type has no search field at all.
Fix: Add a search param to useReviews (filter customerName/comment), pass it through from the page.
Regression risk: None. Label: CODE VERIFIED
```

```
Issue ID: ADM-5 | Severity: Medium | System: Admin Panel
Feature: Transactions status filter — 3 of 4 options permanently dead
Evidence: lintho-admin/src/lib/hooks/index.ts:1453 — every transaction row is mapped with status:'completed' as const, unconditionally, regardless of the underlying doc.
Fix: Remove the non-functional filter options, or implement a real status field on the ledger if a pending/failed state is meant to exist.
Regression risk: None. Label: CODE VERIFIED
```

```
Issue ID: PERF-3 | Severity: Medium | System: Admin Panel
Feature: Providers list — N+1 wallet-earnings reads
Evidence: lintho-admin/src/lib/hooks/index.ts:450-457 — Promise.all(providerIds.map(id => getDoc(doc(db,'wallets',id)))) for every provider in the whole collection, before the client-side pagination slice.
Fix: Denormalize totalEarnings onto the provider doc, or fetch wallet docs only for the currently-paginated slice.
Regression risk: Low if denormalized via the existing wallet-writing trigger. Label: CODE VERIFIED
```

```
Issue ID: PERF-4 | Severity: Medium | System: Admin Panel
Feature: Dashboard — duplicate full-collection reads across widgets
Evidence: lintho-admin/src/lib/hooks/index.ts — useDashboardStats, useDashboardCategoryStats, useTopProviders, useRecentActivity each independently getDocs() the full bookings (3x) / providers (2x) collections with no shared cache; useRecentActivity fetches everything just to .slice(0, limit) after sorting instead of using a server-side limit().
Fix: Combine bookings-derived stats into one query and derive the rest from it; add limit() server-side for recent activity.
Regression risk: Low. Label: CODE VERIFIED
```

---

## 14. Low Issues

```
EDGE-1 | Low | Firestore Rules | Past-date scheduledAt not validated server-side (only client-side); isValidNewBookingShape() never references scheduledAt. Fix: add a bound comparing scheduledAt to request.time for non-"book now" bookings. Label: CODE VERIFIED
```
```
EDGE-4 | Low | Customer App | Deep-clean sqm input has no upper bound; unrealistic values (e.g. a fat-fingered extra zero) surface a raw technical PERMISSION_DENIED exception at submit instead of inline validation. Fix: add an upper-bound check mirroring the existing lower-bound pattern. Label: CODE VERIFIED
```
```
EDGE-5 | Low | Customer App | CustomerBookingRepository.respondToAdditionalCharges is the one write method missed when the session-expiry-guard pattern (_uid.isEmpty check with a friendly message) was rolled out to every other method in the file. Label: CODE VERIFIED
```
```
SEC-3 | Low | Firestore Rules | Service pricing/FAQ content editable by any admin tier — no services:write permission exists yet in the RBAC model at all (rules correctly mirror this absence; product-design gap not a rules bug). Label: CODE VERIFIED
```
```
SEC-4 | Low (informational) | RTDB Rules | Provider presence write to presence/{uid} has no matching rule anywhere in database.rules.json — appears to silently fail every time (wrapped in try/catch), meaning this feature is currently dead code, not a security hole. Flagging for a fresh reviewer to confirm intent. Label: CODE VERIFIED
```
```
PROV-NEW-3 | Low | Provider App | Job-workflow error toasts show a generic "try again" message even when BookingNotifier already captured a specific, already-translated reason (e.g. "wait for the customer to confirm payment first"). Label: CODE VERIFIED
```
```
PROV-NEW-4 | Low | Provider App | "Call customer" button has no canLaunchUrl guard (unlike the equivalent customer-side "call provider" button in match_screen.dart, which does). Low real-world risk given the AndroidManifest already declares the DIAL intent query. Label: CODE VERIFIED
```
```
PROV-NEW-5 | Low (observation) | Provider App | Two different UI entry points (Reject sheet vs Cancel Job sheet) both reachable for a still-pending, directly-assigned job, recording different terminal states (rejected vs cancelled) for the same real-world action. Label: CODE VERIFIED
```
```
UI-8 | Low | Provider App | Two structurally different visual treatments (compact pill vs. full card+native Switch) for the identical online/offline feature, one in Home tab and one in the new Profile availability section. Label: CODE VERIFIED
```
```
UI-9 | Low | Customer App | Promo banner CTA pill's own hit area (~26dp) is below the 44dp guideline, though the parent card duplicates the same tap action so there's no functional dead-zone. Label: CODE VERIFIED
```
```
UI-10 | Low | Customer App | The old one-tap "jump to category" search filter shortcut was removed in the search-bar redesign with no replacement UI. Label: CODE VERIFIED
```
```
UI-11 | Low | Customer App | VerifiedPhoneDisplay widget is now fully orphaned (no call sites remain) after being removed from both booking screens in this diff. Label: CODE VERIFIED
```
```
UI-12 | Low | Customer App | Orphaned locale key see_services remains defined in all 4 language blocks with no remaining call site. Label: CODE VERIFIED
```
```
CUST-2 | Low | Customer App | Customer-tab logout (main.dart _confirmLogout) doesn't proactively clear the nav stack the way the uncommitted provider-tab logout fix and the existing delete-account flow both do. Not reliably reproducible under normal navigation today; would matter if a route is ever pushed above MainShell at logout time. Label: CODE VERIFIED (root cause); reachability PARTIALLY VERIFIED / NOT TESTABLE without a live device
```
```
ADM-6 | Low | Admin Panel | Coupon Status column always shows "Active" regardless of actual expiry (status is set once at creation and never re-evaluated); no way to manually deactivate a coupon short of deleting it. Display-only — actual redemption independently re-validates validUntil/usageLimit, so this does not allow expired-coupon abuse. Label: CODE VERIFIED
```
```
ADM-7 | Low (missing feature) | Admin Panel | No provider-reassignment action exists anywhere in the panel (grep for reassign/assignProvider across the whole repo returns zero matches). Label: CODE VERIFIED
```
```
PERF-5 | Low | Provider App | "This Month's Earnings" stat reuses a .limit(30) transaction-history query for a monthly aggregation; once a provider passes 30 transactions in a month, the total silently undercounts. Label: CODE VERIFIED
```
```
PERF-6 | Low | Customer App | 6 TextEditingControllers across 3 profile bottom-sheet helper methods are never explicitly disposed (currently harmless — locally scoped, torn down with the sheet's widget subtree — but deviates from the app's own established disposal convention elsewhere in the same file). Label: CODE VERIFIED
```

---

## 15. Passed Features (confirmed correct, not just present)

- Booking creation idempotency (both flows) via transaction-scoped `clientRequestId` as doc ID
- Full booking status state machine agreeing across UI, client validation, and `firestore.rules`
- One-review-per-booking (transaction, `bookingId` as doc ID, throws on duplicate)
- Wallet crediting idempotency for every financially-adjacent Cloud Function (transaction-scoped flag)
- Cash-vs-BCEL payment confirmation semantics, correctly gated client- and rule-side
- Customer/provider/admin data isolation in `firestore.rules` for the large majority of collections
- Provider self-approval of KYC/rating/stats explicitly denied at the rules layer
- KYC gating is real-time and independently re-verified server-side at accept-time
- Job visibility correctly excludes other providers' assigned/rejected/expired/mismatched jobs
- `getCloudinarySignature` requires auth and validates real folder ownership (no unsigned-upload path)
- `lintho-admin` RBAC is genuinely enforced via `firestore.rules`, not just hidden UI
- Withdrawal/top-up approve/reject: correct double-processing guards and reservation-reversal semantics
- Audit logging is real and Firestore-backed for every sensitive admin mutation checked
- Cloud Functions test suite: 16/16 passing (live tested)
- `npx tsc --noEmit` in `lintho-admin`: 0 errors (live tested)
- `flutter analyze`: 0 errors, 64 info/warning-level issues only (live tested)
- Android release build: minification, resource shrinking, real signing config all present
- Image uploads: all call sites constrain quality/dimensions before upload
- Localization sync for the new redesign's 24 keys: clean across all 4 languages

## 16. Not Implemented Features

- Provider reassignment in the Admin Panel (ADM-7) — workflow 7 in the E2E trace
- A real payment gateway (BCEL flow is counter-confirmation-based; cash is self-attested by design) — no true payment-failure path exists to test
- `services:write` / equivalent tier-scoped permission for pricing/FAQ edits (SEC-3)
- Rejected-KYC resubmit path reachable from the pending-approval screen (PROV-NEW-1) — the underlying resubmit UI exists but isn't wired to this state

## 17. Not Testable Features (this session)

- Live exploitation of any rules-level finding (no Firestore/Storage/RTDB emulator or deployed instance available)
- Actual deployment state of Cloud Functions (source and tests verified; whether it's live on Blaze was not re-checked this session)
- On-device OTP delivery, GPS permission prompts, real FCM push delivery/foreground banners
- Rendered contrast ratio for UI-3 (colors verified in code; not rendered)
- Admin cancel/reassign/refund workflows' full cross-repo trace back into customer/provider-visible state (partial coverage only — see §8, workflow 6)
- Exact reachability window for CUST-2 (would need a live device to race an FCM-triggered navigation against a logout tap)

## 18. Regression Risks

Fixes carrying more than "Low" regression risk, called out explicitly:
- **PERF-1** (Medium) — pagination UX changes (exact totals aren't free with cursor pagination); search behavior necessarily changes from client substring match to server-side filtering
- **SEC-2** (Medium) — requires a new Cloud Function callable and a change to how the admin panel resolves KYC/slip image URLs
- **EDGE-3** (Medium, if fixed via a new RTDB trigger) — new write-loop surface between client and trigger needs testing; Low if fixed via a client-side freshness filter instead
- **PROV-NEW-2** (Low-Medium if fixed rules-side) — touches a security rule with existing test coverage; re-run the rules test suite
- Every other fix in this report is assessed Low regression risk by its own auditing agent (see individual issue blocks).

## 19. Recommended Fix Order

1. **CUST-1 / CUST-1b** (Critical) — stop the financial exploit before anything else ships.
2. **SEC-1** (High) — one rules-array edit closes a real cross-tier admin bypass.
3. **ADM-2, ADM-3, ADM-1** (High) — restore basic admin-panel daily-use functionality (edit provider, view customer, filter bookings).
4. **BE-1** (High) — admin financial reporting is currently silently wrong; fix before anyone relies on those dashboard numbers.
5. **PROV-NEW-1** (High) — rejected providers are a dead end today; this blocks provider-side onboarding recovery.
6. **UI-1, UI-2** (High) — fix before the in-progress redesign (currently uncommitted) ships at all.
7. **PERF-1, PERF-2** (High) — architectural but urgent to schedule before real data volume arrives; not a blocker for an initial soft launch with a small dataset.
8. All Medium issues, grouped by system (Security's SEC-2 first given sensitivity of the data involved).
9. Low issues opportunistically alongside other work in the same files.

## 20. Production Readiness Score: 58 / 100

Rationale: the platform's core transactional integrity (booking lifecycle, wallet crediting, review uniqueness, RBAC enforcement) is independently verified solid by multiple agents working from different angles — this is not a shaky foundation. But one Critical issue is a real, easily-reachable financial exploit through completely ordinary customer UI actions, and three High issues break Admin Panel functionality staff would need on day one (edit provider, view a customer, filter bookings by service). The uncommitted UI redesign work in `lintho-app` — while not yet shipped — already contains two High-severity defects of its own. The admin panel's performance architecture (full-collection reads with no pagination, no search debounce) is a ticking clock rather than an immediate blocker, which keeps the score from being lower, but it needs a plan before real usage scales.

## 21. Final Decision

# NOT READY FOR PRODUCTION

Primary blockers: CUST-1 (Critical financial exploit), SEC-1 (admin RBAC bypass gap), ADM-1/ADM-2/ADM-3 (admin panel core workflows broken), BE-1 (admin financial reporting silently wrong). Once these — plus the two High UI defects in the currently-uncommitted redesign — are fixed and re-verified, this would reasonably move to CONDITIONALLY READY, with PERF-1/PERF-2 (admin scale) tracked as a near-term follow-up rather than a hard gate.
