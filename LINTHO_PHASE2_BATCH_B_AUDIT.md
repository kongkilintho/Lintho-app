# LinTho — Phase 2, Batch B Audit

Remaining Booking Migration — companion to `LINTHO_PHASE2_MIGRATION_PLAN.md`
and `LINTHO_PHASE2_BATCH_A_AUDIT.md`.

Status: **Batch B complete, verified, committed. Stopped per instruction —
awaiting review before Batch C.**

---

## 1. Files changed

- `lib/Booking.dart` — `JobStatusX.label`, `TxTypeX.label`
- `lib/main.dart` — `BookingScreen`, `_ActiveBookingCard`, `_BookingListSkeleton`
- `lib/booking_form_screen.dart` — 10 `TextStyle` migration sites (11 raw
  literals removed; see §7)
- `lib/app_locale.dart` — new keys only, all 4 locales; no existing key
  changed or removed

`git diff --stat`: 4 files changed, 198 insertions(+), 129 deletions(-).

No other file was modified. No Firestore schema, Cloud Function, payment
logic, provider-matching logic, or navigation architecture was touched.

---

## 2. Baseline (captured before any Batch B edit)

- `flutter analyze`: **0 errors, 2 pre-existing warnings**
  (`job_workflow_Screen.dart` unused import, `match_screen.dart` unused
  field), **70 total issues** — identical to Batch A's end state.
- `flutter test`: **236 passed, 12 failed** — same 12 pre-existing failures
  tracked in `OUT_OF_SCOPE_FINDINGS.md` (OOS-1).

## 3. Final `flutter analyze`

**0 errors, 2 pre-existing warnings (unchanged), 70 total issues — identical
to baseline.** No new lint categories.

## 4. Final `flutter test`

**236 passed, 12 failed — identical to baseline**, same 12 test names, same
order. Zero regressions.

---

## 5. Localization changes

### 5.1 `Booking.dart` impact analysis (performed before any edit)

Full-codebase grep for every consumer of `JobStatusX.label` and
`TxTypeX.label` before touching either getter:

- **`JobStatusX.label`** — exactly 2 live call sites: `home_tab.dart:536`
  (`StatusBadge`, used unconditionally by `JobCard` for every job status
  including `pending` — confirmed by reading `_JobListView`, which renders
  `pending` bookings through the same `JobCard`) and
  `tracking_screen.dart:819`. Both are pure display (`Text(status.label, ...)`).
  No comparison/filtering/Firestore-write/analytics usage found anywhere —
  `Booking.toMap()` writes `status.name` (the enum identifier), and the one
  place that used to compare against `.label` for *filtering* was already
  fixed to compare the enum directly (`booking_provider.dart`'s
  `jobFilterProvider`/`filteredHistoryProvider`, per an existing 🔒 AUDIT
  PROV-5 / 2026-08-02 comment in that file) — confirmed this fix is still in
  place and unaffected by this batch.
- **`TxTypeX.label`** — **zero live call sites** anywhere in `lib/`.
  `earnings_tab.dart`'s transaction UI uses `TxType` only for icon lookup
  (`_txIcons[TxType.earning]`) and `.isCredit`; nothing reads `.label`.
  Localized anyway for correctness/future-proofing, not because a visible
  bug exists today — noted explicitly below.

**Conclusion:** both getters are safely display-only. Internal identifiers
(`JobStatus`/`TxType` enum member names, used via `.name` for Firestore) were
not touched.

### 5.2 A correction made mid-batch (flagging transparently)

The first pass at `JobStatusX.label` delegated to the same `tr()` keys as
`booking_display_helpers.dart`'s `bookingStatusLabel()` (the canonical
customer-tracking status-label function), reasoning that reuse would prevent
the two from drifting apart. **This was wrong and was reverted before
committing**: comparing the two mappings word-for-word showed
`bookingStatusLabel()`'s wording differs from `JobStatusX.label`'s original
Lao text for 5 of 8 statuses (e.g. `pending` was `'ໃໝ່'`/"new" in
`JobStatusX.label` vs `bookingStatusLabel()`'s `'ລໍຖ້າ'`/"waiting" —
different words, not a translation variant). Reusing those keys would have
silently changed the Lao text existing users see on the provider job list
(`StatusBadge`, live on every `JobCard` including pending jobs) — a real
visible regression, not a localization fix.

**Final approach:** `JobStatusX.label` gets its own 8 dedicated keys
(`job_status_label_pending` … `job_status_label_rejected`), with the **`lo`
value copied byte-for-byte from the original hardcoded string** for every
status, and EN/TH/ZH written fresh to match. The only observable change is
that EN/TH/ZH users now see translated text instead of leftover Lao — Lao
rendering is provably unchanged (diffed old vs. new `lo` values before
committing).

### 5.3 New locale keys added (all 4 locales: lo/en/th/zh)

| Key | lo (unchanged from original) | en | th | zh |
|---|---|---|---|---|
| `job_status_label_pending` | ໃໝ່ | New | ใหม่ | 新 |
| `job_status_label_accepted` | ຮັບແລ້ວ | Accepted | รับแล้ว | 已接单 |
| `job_status_label_on_the_way` | ກຳລັງໄປ | On the way | กำลังไป | 前往中 |
| `job_status_label_arrived` | ຮອດແລ້ວ | Arrived | ถึงแล้ว | 已到达 |
| `job_status_label_in_progress` | ກຳລັງເຮັດ | In progress | กำลังทำงาน | 进行中 |
| `job_status_label_completed` | ສຳເລັດ | Completed | เสร็จสิ้น | 已完成 |
| `job_status_label_cancelled` | ຍົກເລີກ | Cancelled | ยกเลิก | 已取消 |
| `job_status_label_rejected` | ປະຕິເສດ | Rejected | ปฏิเสธ | 已拒绝 |
| `tx_type_earning` | ລາຍຮັບ | Earning | รายได้ | 收入 |
| `tx_type_withdrawal` | ຖອນເງິນ | Withdrawal | ถอนเงิน | 提现 |
| `tx_type_bonus` | ໂບນັດ | Bonus | โบนัส | 奖金 |
| `tx_type_refund` | ຄືນເງິນ | Refund | คืนเงิน | 退款 |
| `tx_type_topup` | ຕື່ມເງິນ | Top-up | เติมเงิน | 充值 |
| `tx_type_adjustment` | ຍອດປັບປຸງ | Adjustment | รายการปรับปรุง | 调整 |
| `coupon_discount_prefix`, `coupon_expired_label`, `coupon_used_label`, `coupon_valid_until_prefix`, `coupon_copy_code_semantic`, `clear_search_semantic` | *(Batch A keys, listed for completeness — not part of Batch B)* | | | |

`tx_type_*` keys currently have zero call sites (§5.1) — dead but correct;
not a new bug surface since nothing renders them yet.

### 5.4 `BookingScreen`'s Cancelled tab label

`_tabLabels[BookingTab.cancelled]` was `tr('cancel')` — the imperative verb
("Cancel") on a tab that *lists already-cancelled bookings*. EN distinguishes
this clearly (`'cancel'` → "Cancel", `'cancelled'` → "Cancelled"). Changed to
`tr('cancelled')`, the exact key `bookingStatusLabel()` already uses for this
status. No new key needed; zero risk (both keys already existed and are
already correctly translated in all 4 locales).

---

## 6. `BookingScreen` migration (`main.dart`)

Per the required UX audit checklist:

| Item | Before | After |
|---|---|---|
| Ongoing/Completed/Cancelled tabs | Custom `InkWell`+`Container`, radius 12 | Same structure, `AppRadius.card` token; Cancelled label fixed (§5.4) |
| Active-booking highlight card | Already used `AppRadius`/`AppSpacing` tokens; "View details" was a raw `ElevatedButton` (already correctly green) | `AppButton.primary` |
| Status display | `bookingStatusLabel()`/`AppStatus` (already centralized, untouched) | unchanged |
| Provider info | Name shown when present, unchanged | unchanged |
| CTA hierarchy | "View details" green (correct), "Rate" was a raw `OutlinedButton.icon` (navy border, yellow star icon) | "Rate" → `AppButton.outline` (secondary, correctly subordinate to the card's own tap-to-detail action). Note: the star icon lost its yellow color — `AppButton` doesn't accept per-instance icon color overrides by design (see §8), so it now renders navy like the label. Flagging as a minor, expected visual side effect of adopting the shared component, not a defect. |
| Empty state | Ad hoc `Center`/`Column`/`Icon`/`Text`/raw `ElevatedButton`, despite `EmptyStateView`/`ErrorStateView` already used correctly elsewhere in this same file | `EmptyStateView` with an `AppButton.primary` action |
| Loading state | `_BookingListSkeleton` (already a good custom pattern, kept) | radius tokens converged (18/14/6/5/20 → `AppRadius.card`/`.card`/`.chip`/`.chip`/`.sheet`) |
| Error state | Ad hoc `Center`/`Icon`/`Text`/`OutlinedButton.icon` — **no error branch existed on the active-booking card's own logic**, but the list *did* check `snapshot.hasError`, just rendered it by hand | `ErrorStateView(onRetry: () => setState(() {}))` |
| Retry | `setState(() {})` re-triggers the same `StreamBuilder`'s stream reference — works because `FirestoreService.getMyBookings()` returns a stream tied to a live Firestore listener, not a one-shot future; confirmed this is the same retry pattern already used elsewhere in `main.dart` | unchanged mechanism, now wired to `ErrorStateView` |
| Navigation to detail | `Navigator.push`/`MaterialPageRoute` to `BookingDetailScreen` | unchanged |
| Book Again | Not part of this screen (lives in `review_screen.dart`, already fixed in a prior Phase 0 pass) | n/a |
| Cancellation UI | Deliberately absent from the list per an existing code comment ("cancel moved to detail screen, prevents mis-taps") — confirmed still true, not reintroduced | unchanged |
| Touch targets | List card's whole surface is one `InkWell` (fine); tabs are `Expanded`+10dp vertical padding (fine); no icon-only controls in this scope | unchanged, no gaps found |
| Localization | All strings already routed through `tr()` except the Cancelled-tab bug (§5.4) | fixed |

Radius: 11 raw `BorderRadius.circular(N)` literals in this scope (18×3,
14×2, 20×2, 12×2, 6, 5) → 100% converged to `AppRadius.card`/`.chip`/`.sheet`
by nearest-distance, same mechanical rule Phase 1's radius sweep used.
Verified via `awk`-scoped grep: 0 raw literals remain in
`_ActiveBookingCard`/`BookingScreen`/`_BookingListSkeleton`.

---

## 7. `booking_form_screen.dart` — TextStyle classification

73 raw `TextStyle(` literals audited individually (not sampled). Classification rule set, applied consistently:

- **A (migrate)** — `(fontSize, fontWeight)` matches an `AppTypography` role
  pair exactly or near-exactly, with only `color` (an existing `AppColors`
  token) differing → `AppTypography.<role>.copyWith(...)`.
- **B (intentional, preserve)** — any of: category-accent-colored text
  (`C.categoryAcAccent`/`categoryCleanAccent`/`categoryAddonValueText`/
  `categoryAddonLabelText`/`noteWarningText`/`noteWarningTextDark`/
  `mutedLight` — the exact exemption Phase 1's own audit already
  established); fractional (`.5`) font sizes (12.5/13.5/10.5/9.5) — a
  deliberate fine-tuned micro-scale distinct from the integer
  `AppTypography` grid; decorative/emoji-sized text; dynamic
  selected-state card typography in the ~15 private per-step selector
  widgets (`_ModeCard`, `_SmallTypeCard`, `_QuickBookCard`, `_BigCatCard`,
  `_PaymentCard`, `_RoomTile`, `_AcTypeCard`, `_BtuSelector`, `_TimeToggle`,
  `_TimeSlots`, `_AddonCheckRow`, etc.) where size/weight is bespoke to that
  card family and color is conditional on `selected`; `_BillRow`'s and
  `_PriceLine`'s deliberate two-state (bold/non-bold) bill-line typography
  system (doesn't map to any single role by construction — it needs 2
  sizes×weights from one component, and inventing a 7th `AppTypography` tier
  to fit it is explicitly prohibited by this batch's global rules); the
  `_BottomBar` primary button, which an **existing Phase 1 comment**
  explicitly documents as a deliberate non-`AppButton` exception (its
  `_ButtonSkeleton` loading pattern predates and beats `AppButton`'s plain
  spinner) — not re-litigated here.
- **C (requires review)** — `TextStyle` with **no explicit `fontSize`** in a
  non-button context, where the effective rendered size depends on ambient
  `DefaultTextStyle` and/or pairs with a dynamic conditional color —
  genuinely ambiguous without visual inspection, flagged rather than guessed.

### Result

| Category | Count | Action |
|---|---|---|
| A — migrated | 10 sites (11 raw literals — one site had 2 identical occurrences) | Migrated to `AppTypography.<role>.copyWith(...)` |
| B — intentional, preserved | 60 sites | Unchanged, reason documented above (grouped, not narrated per-line) |
| C — requires review | 3 sites | Unchanged, flagged below |

`grep -c 'TextStyle('`: **73 → 62**.

**A — migrated (10 sites):**
1. AppBar step title (18/w800 = `appBarTitle` exactly, color override)
2. "Now" ETA note (13/w600 = `label` exactly, color override)
3. Dispatch notice (12 = `caption` size, color override)
4. AC cart tile line total (12 = `caption` size, weight+color override)
5. Coupon-applied badge text (13 = `label` size, weight+color override)
6. Review-card "Edit" link (12 = `caption` size, weight+color override)
7. `_SqmInput`'s hint style — was the *only* `TextField` hint in this file
   not already using `AppTypography.caption` (every sibling field does);
   fixed for in-file consistency, not just token-matching
8. Sqm min/max error messages ×2 (12 = `caption` size, weight+color override)
9. `_Label` — the shared section-header widget used **~30 times** across
   every step of the form (15 = `body` exactly, weight+color override) — one
   fix converges every call site at once
10. Bottom-bar "Estimated total" caption (13/w600 = `label` exactly, color override)

**C — requires review (3 sites, unresolved, flagged for a human decision):**
- `_buildStep2()`'s selected-datetime text (no `fontSize`, color conditional
  on whether a time is picked) — line ~1651 pre-batch
- `_buildStep3()`'s "use current address (GPS)" prompt (no `fontSize`) —
  line ~1736 pre-batch
- `_SqmInput`'s `suffixStyle` (no `fontSize`, only `color`+`fontWeight`) —
  line ~3244 pre-batch

None of these are visually broken today (they render via Flutter's ambient
default) — flagging because forcing a role onto them without visual
verification risked an incorrect guess, which this batch's instructions
explicitly warned against.

**No business logic, step behavior, Firestore schema, payment calculation,
or provider-matching logic was touched anywhere in this file** — every edit
is a `style:` value swap in place.

---

## 8. Design-system violations before/after

| Scope | Before | After |
|---|---|---|
| `Booking.dart` | 2 hardcoded-Lao extension getters bypassing `tr()` entirely | 0 — both localized, Lao rendering unchanged, EN/TH/ZH now correct |
| `main.dart` (BookingScreen scope) | 2 raw buttons, ad hoc empty/error state despite shared widgets used elsewhere in the same file, 11 raw radius literals, 1 wrong tab-label key | 0 raw buttons in scope, `EmptyStateView`/`ErrorStateView` adopted, 0 raw radius literals, tab label fixed |
| `booking_form_screen.dart` | 73 raw `TextStyle(` | 62 (10 legitimate migrations; 60 documented intentional; 3 flagged for review) |

**Open design-system question surfaced, not resolved (flagging per §8 of the
approved plan, not deciding unilaterally):** `_BillRow`/`_PriceLine`'s
two-state bold/non-bold price typography is used consistently across ~8
call sites in this file. It's a real, coherent system — just not one that
maps onto the current 6-role `AppTypography` scale. Whether this deserves a
7th role (e.g. a "priceEmphasis" tier) is a design-system-extension decision
outside this batch's authority (global rule: "do not introduce new
typography tiers") — noted for whoever reviews Batch B, not acted on.

---

## 9. UX findings

- **`_BillRow`/`_PriceLine`, `_ModeCard`-family selectors**: confirmed
  visually coherent as-is; no UX defect, just off-token styling (§8).
- **`AppButton.outline`'s star icon losing its yellow color** on the Rate
  button (§6): a real, minor visual delta from adopting the shared
  component. Not reverted — consistent with the Master Prompt's own
  rationale for `AppButton` (removing the *ability* to override color per
  call site is the point, not a bug to route around).
- **Retry semantics verified real, not cosmetic**: `BookingScreen`'s
  `ErrorStateView(onRetry: () => setState(() {}))` genuinely re-subscribes
  because the `StreamBuilder`'s `stream:` parameter calls
  `FirestoreService.getMyBookings()` fresh on every `build()` — confirmed by
  reading the method (returns a live Firestore query snapshot stream, not a
  cached reference).
- **No dead buttons, no missing confirmations found** in either
  `BookingScreen` or the audited `booking_form_screen.dart` sections —
  cancellation is deliberately absent from the list (by design, per existing
  comment) and gated to the detail screen; nothing in this batch's scope
  performs a destructive action requiring a new confirmation dialog.
- **3 sites left ambiguous (§7, category C)** rather than guessed — flagged
  for the next reviewer with exact locations.

---

## 10. Business logic verification

Confirmed **not modified**, by direct inspection of every file touched:

- `Booking.fromFirestore()`/`toMap()`/`copyWith()` — untouched; `.name`
  (Firestore-persisted identifier) is a completely separate code path from
  `.label` (display-only getter), confirmed by reading both before editing.
- `booking_provider.dart`'s `jobFilterProvider`/`filteredHistoryProvider` —
  read, not edited; confirmed the enum-based comparison (not `.label`-based)
  fixed by a prior audit (PROV-5) is still in place.
- `BookingScreen`'s Firestore query (`FirestoreService.getMyBookings()`),
  tab-filtering logic (`bookingTabOf()`), and trackable-status logic
  (`bookingIsTrackable()`) — all called, none edited.
- `booking_form_screen.dart`'s pricing (`AppPricing.*`), step-navigation
  (`_step`, `_canNext`), and submit (`_submit()`) logic — not touched; every
  edit in this file is confined to a `style:` argument.

## 11. Out-of-scope findings

None discovered this batch requiring a new `OUT_OF_SCOPE_FINDINGS.md` entry.
The 3 category-C `TextStyle` sites (§7) and the `_BillRow`/`_PriceLine`
typography-tier question (§8) are logged in this audit itself, per the
instruction to document rather than expand scope — neither is a bug, so
neither needed `OUT_OF_SCOPE_FINDINGS.md`'s bug-tracking format.

## 12. Regression assessment

**Zero regressions.** `flutter analyze` and `flutter test` are both
byte-for-byte identical to the Batch B baseline (which was itself identical
to Batch A's end state). The one substantive correction made mid-batch
(§5.2, the `JobStatusX.label` key-reuse mistake) was caught and fixed
*before* committing, specifically by diffing old vs. new Lao output — not
left for review to catch.

## 13. Commit

One commit for all of Batch B. See git log for the hash.

## 14. Next step

Awaiting review of this audit before starting **Batch C — Customer
Account** (`ProfileScreen`, `notification_screen.dart`, `review_screen.dart`
— including reverting its documented `tr()`-removal regression,
`rewards_screen.dart`, `referral_screen.dart`, `chat_screen.dart`,
`support_help.dart`), per the approved migration plan.
