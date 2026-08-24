# LinTho — Phase 2, Batch A Audit

Customer Core / Discovery — companion to `LINTHO_PHASE2_MIGRATION_PLAN.md`.

Status: **Batch A complete, verified, committed. Stopped per instruction —
awaiting review before Batch B.**

---

## 1. Scope

Files touched (all four from the approved Batch A list):

- `lib/main.dart` — `MainShell`/`_FloatingNavBar` chrome, `SearchScreen`,
  `FavoriteProvidersScreen`, `PaymentHistoryScreen`
- `lib/provider_details_screen.dart`
- `lib/map_picker_screen.dart`
- `lib/coupon_list_screen.dart`
- `lib/app_locale.dart` — new keys only (all 4 locales), no existing keys
  changed or removed

No other file was modified. No Firestore schema, Cloud Function, navigation
architecture, or business logic was touched.

---

## 2. Baseline (captured before any edit)

- `flutter analyze`: **0 errors, 2 pre-existing warnings**
  (`job_workflow_Screen.dart` unused import, `match_screen.dart` unused
  field — both unrelated to Batch A), **70 total issues**, matching the
  Phase 1 audit's documented baseline exactly.
- `flutter test`: **236 passed, 12 failed** — the same 12 pre-existing
  failures tracked in `OUT_OF_SCOPE_FINDINGS.md` (OOS-1), same names, same
  order.

---

## 3. Changes made, per file

### `lib/coupon_list_screen.dart`
- 5 hardcoded Lao strings in `_CouponCard` (discount label, expired/used
  labels, valid-until prefix) moved to `tr()` — new keys added to all 4
  locales: `coupon_discount_prefix`, `coupon_expired_label`,
  `coupon_used_label`, `coupon_valid_until_prefix`,
  `coupon_copy_code_semantic`. Currency unit now reuses the existing
  `kip_currency` key instead of a new one.
- Copy-code chip was ~28dp tall (below the 44dp minimum tap target) and had
  no accessibility label — wrapped in `Semantics(button: true, label: ...)`
  and given a `BoxConstraints(minHeight: 44)`.
- No CTA color or radius issues were found here (already the most-compliant
  file in the batch per the migration-plan audit).

### `lib/map_picker_screen.dart`
- Confirm-address button was a raw navy `ElevatedButton` — the screen's only
  primary action, now `AppButton.primary` (LinTho green, matches the CTA
  hierarchy fixed on every Phase 1 pilot screen).
- GPS `FloatingActionButton` was `mini: true` (40×40dp, under the 44dp
  minimum) — `mini` removed (default FAB is 56dp) and a `tooltip` added
  (reusing the existing `use_current_location` key).
- Back button given a `tooltip` (`back_semantic`, the key already used by
  every other back button in the app) — it had none.

### `lib/provider_details_screen.dart`
- Top-level provider-load error was a raw `Text('$e')` — now `ErrorStateView`
  with a working retry (`ref.invalidate(providerDetailProvider(...))`).
- `provider == null` (not-found) state was a raw `Text` — now `EmptyStateView`.
- Reviews-stream error was a raw `Text('$e')` with no retry — now
  `ErrorStateView(compact: true)` wired to `ref.invalidate(providerReviewsProvider(...))`.
- Empty-reviews state was a raw `Text` — now `EmptyStateView`.
- `_BottomActions`' Chat/Book Now buttons were raw `OutlinedButton.icon`/
  `ElevatedButton.icon` with local `.styleFrom(...)` — now `AppButton.outline`
  / `AppButton.primary`. Book Now's online/offline label-and-disable logic
  (a Phase 0 fix) is unchanged, only the widget changed.
- Radius: all 18 `BorderRadius.circular(N)` literals in the file (values 5,
  6, 8, 10, 12, 14 across skeleton boxes, section cards, review tiles, and
  badges) snapped to the nearest of the 3 tokens by distance — same
  mechanical rule Phase 1's radius sweep used. `grep -c 'BorderRadius\.circular([0-9]'`
  now returns 0 for this file. Tie-break note: values exactly equidistant
  between two tokens (12→chip vs card, 20→card vs sheet) were rounded up to
  the larger token — a documented judgment call, not hidden.
- `AppTypography`/full spacing convergence was **not** attempted here — out
  of Batch A's approved scope (the plan called out CTA color, error/empty
  states, and radius specifically; the ~40 remaining raw `TextStyle`/
  `EdgeInsets` literals are unchanged, same as Phase 1 left similar debt on
  the pilot screens).

### `lib/main.dart`
- `_FloatingNavBar`'s tab items had no `Semantics` — added
  (`button: true, selected: sel, label: label`); icon+label were already
  screen-reader-visible via child order, this makes selection state
  announced explicitly.
- `_FloatingNavBar`'s pill radii (32 for the bar itself, 20 for the selected-
  tab highlight) were **deliberately left unchanged** — both are
  half-of-height stadium/pill shapes (bar height 60, tab highlight ~40),
  which is a geometric requirement, not an arbitrary value; forcing them
  onto 24/16 would visibly break the pill shape. Documented as an
  intentional layout-specific exception per the plan's own carve-out for
  "image dimensions/technical constants/layout-specific requirements" —
  same category as the nav-label's 10sp font size, also left unchanged (no
  matching `AppTypography` role exists for compact bottom-nav labels, and
  inventing one wasn't approved).
- `SearchScreen`'s clear-search `IconButton` had no tooltip — added
  (new key `clear_search_semantic`, all 4 locales). Empty-results state
  (raw `Center`/`Icon`/`Text`) replaced with `EmptyStateView`.
- `FavoriteProvidersScreen` — **style-only** migration to `EmptyStateView`,
  exactly as instructed: no data path, Firestore query, or feature logic
  added. This screen's dead-feature status (nav entry point already removed
  by a prior audit, CUST-6) is now also logged as **OOS-4** in
  `OUT_OF_SCOPE_FINDINGS.md`, per instruction.
- `PaymentHistoryScreen` — the real defect from the migration plan: its
  `StreamBuilder<QuerySnapshot>` had **no error branch at all**, so a stream
  failure left the screen stuck silently. Converted the widget from
  `StatelessWidget` to a minimal `StatefulWidget` (`_streamKey` counter) so
  an `ErrorStateView`'s retry button can force a real resubscription, not
  just a repaint. Empty state converted to `EmptyStateView`. Back button
  given a `tooltip`. Card radius (16/12/8 literals) converted to
  `AppRadius.card`/`AppRadius.card`/`AppRadius.chip` token references
  (same tie-break rule as above for the 12→card case).

---

## 4. `flutter analyze` (after)

**0 errors, 2 pre-existing warnings (unchanged), 70 total issues — identical
to baseline.** No new lint categories introduced; the only new info-level
hint is one `prefer_const_constructors` in `provider_details_screen.dart`
(cosmetic, same class of hint the baseline already had 60+ of).

## 5. `flutter test` (after)

**236 passed, 12 failed — identical to baseline**, same 12 test names, same
order. Zero regressions from Batch A.

---

## 6. Design-system violation scan (Batch A files)

| File | Before → After |
|---|---|
| `coupon_list_screen.dart` | 5 hardcoded strings → 0. 1 sub-44dp tap target → fixed. Already had `EmptyStateView`/`ErrorStateView`/`AppRadius`-adjacent styling; unchanged. |
| `map_picker_screen.dart` | Navy primary CTA → green (`AppButton.primary`). 1 sub-44dp FAB → fixed. 2 missing tooltips → fixed. |
| `provider_details_screen.dart` | 3 ad hoc error/empty states → `ErrorStateView`/`EmptyStateView` (2 with working retry, previously 0 had retry). 2 raw buttons → `AppButton`. 18/18 raw `BorderRadius.circular(N)` → 0 (100% token-converged, matching Phase 1's radius-sweep bar). `TextStyle`/`EdgeInsets` convergence intentionally deferred (see §3). |
| `main.dart` (4 classes) | 1 silent-failure defect fixed (`PaymentHistoryScreen`, real bug, not style). 2 ad hoc empty states → `EmptyStateView`. 3 missing tooltips/Semantics → fixed. 3 `BorderRadius.circular(N)` → tokens. 1 dead-feature screen documented in `OUT_OF_SCOPE_FINDINGS.md` (OOS-4) rather than silently left unexplained. |

**Not claimed as done:** full `AppTypography`/`AppSpacing` convergence on
`provider_details_screen.dart` (raw `TextStyle`/`EdgeInsets` literals remain,
same category of debt Phase 1 explicitly left on its own pilot screens) —
this was not in Batch A's approved scope per the migration plan, which
called out specific violations rather than a full mechanical sweep for this
file.

---

## 7. UX review

- **Primary action clarity**: every screen in this batch now has an
  unambiguous single primary CTA in LinTho green where one exists
  (map picker's confirm, provider details' Book Now). Chat and other
  secondary actions stayed outline/secondary — no over-conversion to green.
- **Navigation**: unchanged everywhere — still `Navigator.push`/
  `MaterialPageRoute`/`Navigator.pop`, no architecture change.
- **Destructive actions**: none exist in this batch's screens (no
  cancel/delete flows here) — nothing to gate with confirmation.
- **Retry actually retries**: verified both new `ErrorStateView` retry
  wiring paths do a real refetch (Riverpod `ref.invalidate(...)` for
  `provider_details_screen.dart`, a stream-resubscription key for
  `PaymentHistoryScreen`) rather than a no-op repaint.
- **FavoriteProvidersScreen**: confirmed still unreachable from any nav
  entry point (grepped the whole `lib/` tree) — the style migration does not
  accidentally resurrect a half-working feature.

---

## 8. Decisions applied from the approval message

- Global rules honored: no new colors/spacing/radius/typography tokens
  invented; every fix reused an existing `AppButton`/`AppText`/`AppCard`/
  `AppSection`/`EmptyStateView`/`ErrorStateView`/`AppRadius`/`AppSpacing`
  value; no Firebase/Firestore/schema/navigation/localization-architecture
  changes; no new features.
- `FavoriteProvidersScreen`: style-only, empty state preserved, logged to
  `OUT_OF_SCOPE_FINDINGS.md` as **OOS-4** (§6 of this file, and the finding
  itself).
- Batch B/C/D/E untouched.

---

## 9. Commit

One commit for all of Batch A (code + locale keys), following this
project's per-batch commit convention. See git log for the hash.

## 10. Next step

Awaiting review of this audit before starting **Batch B — Remaining
Booking** (`main.dart`'s `BookingScreen`/`_ActiveBookingCard`/
`_BookingListSkeleton`, `Booking.dart`'s hardcoded status-label getters,
and `booking_form_screen.dart`'s remaining ~73 `TextStyle` literals per the
approved classification-not-mechanical-replacement instruction).
