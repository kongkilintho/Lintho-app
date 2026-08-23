# LinTho — Phase 1 Audit

Design System Enforcement — pilot rollout. Companion to
`LINTHO_PHASE0_PHASE1_PLAN.md` (the pre-work plan) and
`OUT_OF_SCOPE_FINDINGS.md` (issues discovered but not touched).

Status: **pilot complete — 5/5 screens migrated, 0 regressions, awaiting review before any wider rollout**

---

## 1. Scope actually executed

Per the plan's scoping note (flagged before any code was written): a full
line-by-line token rewrite of 5 screens — one of them ~4,000 lines — was not
attempted. This pass fixes the **concrete violations already identified** by
the prior UI/UX re-audit and this session's own inspection: CTA color drift,
dead design tokens, missing accessibility labels, sub-44dp tap targets,
emoji-as-icon holdouts, and two real bugs (a contrast failure, a data-flicker
bug) found along the way. Every screen still has un-migrated raw
`TextStyle`/`EdgeInsets`/`BorderRadius.circular(N)` literals that don't
reference `AppTypography`/`AppSpacing`/`AppRadius` directly — that full
convergence is **not** claimed as done here (see §5).

---

## 2. Components created

| Component | File | Purpose |
|---|---|---|
| `AppButton` | `lib/widgets/app_button.dart` | primary/secondary/outline/ghost/destructive variants. Does not accept a color override — the direct fix vehicle for the navy-vs-green CTA drift, since a shared widget removes the *ability* to override color per call site. |
| `AppText` | `lib/widgets/app_text.dart` | One constructor per `AppTypography` role (`.display`/`.title`/`.heading`/`.body`/`.label`/`.caption`). |
| `AppCard` | `lib/widgets/app_card.dart` | Wraps the existing `CardTheme` with a sane padding default and an InkWell+Material tap variant. |
| `AppSection` | `lib/widgets/app_section.dart` | Standard section-header spacing + optional trailing action, with a built-in 44dp tap target on the action. |
| `AppTextField` (extended) | `lib/widgets/app_text_field.dart` | Added `errorText`/`errorColor` — the file already existed from before this session; this closes the gap against the Master Prompt's `AppInput` spec (label/hint/error/focus). |

`AppIconButton` and `AppStatus`/`status_stepper.dart` already existed and
needed no changes — reused as-is throughout the pilot migration.

**Deliberately not created:** `AppIcon`. The real bugs in this area (sub-44dp
targets, missing `Semantics`) live in the *interactive* icon case, which
`AppIconButton` already covers. A plain icon-sizing wrapper would be
decoration without a concrete problem to solve.

---

## 3. Screens migrated (pilot set, as specified by the Master Prompt)

| # | Screen | Commit |
|---|---|---|
| 1 | Home (`lib/main.dart`) | `809f3cb` |
| 2 | Quick Booking | `656254a` |
| 3 | Booking Form (scoped — see §1) | `e99a97e` |
| 4 | Booking Detail | `9700432` |
| 5 | Tracking / Match | `f3d8dd6` |

Foundation commit: `d440953` (shared components, before any screen touched).

---

## 4. Before → After

### Brand consistency (the headline finding from the UI/UX re-audit)
- **Before:** primary CTA color flipped between green (Booking Form,
  Tracking, Match) and navy (Quick Booking's 3 CTAs, Booking Detail's
  Track/Rate, Match's Retry/Track-in-confirmed-view) with no discernible rule.
- **After:** every primary CTA across all 5 pilot screens now renders via
  `AppButton.primary`, which cannot be given a custom background color. The
  navy/yellow overrides are gone from all of them.

### Dead design tokens
- **Before:** `promoBannerBlue`/`Green`/`Orange` — declared in
  `app_theme.dart` specifically for the Home promo carousel — were never
  referenced anywhere in the app.
- **After:** each of the 4 Home banners has its own color from that set (AC =
  blue, cleaning = green, promotion = orange; membership stays navy as a
  deliberate premium choice, since there are 4 banners and 3 tokens).

### Emoji → icon
- **Before:** Quick Booking's entire Step 1 (service cards) and checkout
  summary were the one screen in the whole app with zero emoji-migration
  progress. Booking Form had two residual spots (`acTypeEmoji()` on cart
  tiles, `ℹ️`/`🚗`/`⚠️` on the travel-fee and refill-notice boxes).
- **After:** all of the above now render `Icon(IconData)`, reusing
  `serviceIconForCategory()` (Quick Booking) or a new parallel
  `acTypeIcon()` next to the existing `acTypeEmoji()` (Booking Form, so
  nothing that still reads the emoji string elsewhere breaks).

### Accessibility (44dp targets, Semantics/Tooltip)
- Fixed: Quick Booking's GPS and coupon-clear icon buttons (tooltips added);
  Tracking's bottom-sheet call button (migrated to `AppIconButton`) and map
  FAB (tooltip added); Match's only cancel/back control during search — was
  40×40 with no label, now `AppIconButton` (44dp minimum + mandatory label
  enforced by the widget itself); Booking Form's price-disclaimer info icon —
  was a bare `GestureDetector` with a ~15px hit area, directly violating this
  file's own documented "InkWell + Material every tap target" rule; Home's
  "see all" link — was a 4px-radius `InkWell` around bare text, now
  `AppSection`'s action slot (44dp built in).

### Two real bugs found and fixed along the way (not pre-planned, surfaced by touching this code)
- **WCAG AA contrast failure**, Home header subtitle: `Colors.white70` on the
  green→teal gradient computed to ~2:1 contrast. A near-identical issue on
  the Quick-Book banner one section down had already been fixed (opacity
  raised to `.92`) but never propagated up to this more prominent instance —
  same fix applied here.
- **Price-line flicker**, Home: `_PriceLine` called `fetchPricing()` fresh
  inside `build()`. Async calls return a new `Future` every invocation even
  on a cache hit, and `MainShell` rebuilds `HomeScreen()` from scratch on
  every tab switch/locale change — so the starting-price text on every
  category tile and popular card blanked and reflowed on every visit to the
  tab. Converted `_PriceLine` to a `StatefulWidget` that creates the `Future`
  once in `initState()`.

### One judgment call worth flagging explicitly
Booking Form's bottom-bar CTA had `elevation: 4` + a custom `shadowColor`,
contradicting the app's flat-button convention. It was **not** converted to
`AppButton` — its existing `_ButtonSkeleton` loading state is a better,
already-established pattern than `AppButton`'s plain `CircularProgressIndicator`,
and forcing the shared component in would have downgraded it just for
consistency's sake. Only the elevation/shadow override was removed. This is
the kind of "each site needs a one-line judgment call" case the plan warned
about before any code was written.

---

## 5. Design-system acceptance check (against §20 of the Master Prompt)

| Check | Status |
|---|---|
| Primary CTA consistently LinTho Green | ✅ within the 5 pilot screens |
| Navy has a defined semantic role | ✅ `AppButton.secondary` now names it explicitly; Home's membership banner documents the deliberate exception |
| No unexplained hardcoded colors | ⚠️ Partial — the specific violations found by the audit are fixed; an exhaustive sweep of every literal in these 5 files was not done (see §1) |
| Shared buttons/cards used | ✅ where a violation existed; pre-existing correct usages (e.g. Booking Form's flat buttons elsewhere) were left alone |
| Functional emoji removed | ✅ within the 5 pilot screens (both files' last remaining spots fixed) |
| Touch targets ≥ 44dp | ✅ every specific instance found; not an exhaustive sweep of all interactive elements in all 5 files |
| AppTypography/AppSpacing adoption | ❌ **Not attempted at scale.** These 5 screens still contain hundreds of raw `TextStyle`/`EdgeInsets` literals. `AppText` exists and is ready to absorb this work, but doing so file-by-file for ~4,000+ lines (Booking Form alone) was explicitly out of scope for this pass per the plan's own risk assessment. |

**Honest summary:** this pass measurably improves brand consistency and
fixes concrete, cited defects. It does **not** claim the 5 pilot screens are
now fully "AppTypography/AppSpacing everywhere" — that remains the largest
gap and the most likely candidate for a dedicated follow-up pass (ideally
supported by a codemod/lint rule per the plan's Phase 4 recommendation,
rather than manual per-line edits).

---

## 6. Files changed

```
lib/widgets/app_button.dart      (new)
lib/widgets/app_card.dart        (new)
lib/widgets/app_section.dart     (new)
lib/widgets/app_text.dart        (new)
lib/widgets/app_text_field.dart  (extended — errorText/errorColor)
lib/main.dart                    (Home)
lib/quick_booking_screen.dart
lib/booking_detail_screen.dart
lib/booking_form_screen.dart
lib/tracking_screen.dart
lib/match_screen.dart
```
11 files, +603/-248 lines across the 5 screen-migration commits (shared
components counted separately, +341 lines, 0 deletions — pure addition).

---

## 7. Remaining violations (known, not fixed in this pass)

- `AppTypography`/`AppSpacing` adoption in the 5 pilot screens themselves —
  see §5.
- The 40 non-pilot screens were never in scope for this pass (`§19`: "Only
  after these five screens pass audit should you migrate the remaining
  screens").
- Everything catalogued in the original UI/UX Re-Audit that isn't one of the
  P0/P1/concrete-P2 items addressed in Phase 0/1 — e.g. Rewards/Referral/
  Review localization gaps, the referral VIP-token misapplication, the
  missing brand mark at Splash/Login (partially: Splash/Login weren't in the
  Phase 0/1 scope at all).
- Booking Form's ~4,000-line size itself is unaddressed — no file-splitting
  was done (out of scope: "no unnecessary architecture rewrite").

---

## 8. Tests

- `flutter analyze` (full project, post-Phase-1): **0 errors, 0 warnings**,
  70 info-level lints (up from the Phase-0-end baseline of 64 — the delta is
  new `prefer_const_constructors`-class suggestions on the new components,
  not new categories of issue).
- `flutter test` (full project, post-Phase-1): same **12 pre-existing
  failures** as the Phase 0 baseline, same names, same order — reconfirms
  zero regressions from the Phase 1 changes. (These 12 are tracked in
  `OUT_OF_SCOPE_FINDINGS.md`, unrelated to this pass.)
- No new test file was added for Phase 1 — the changes are visual/structural
  (color, spacing, component swaps) rather than new business logic, and this
  project's existing test convention (source-text regression guards) is
  poorly suited to asserting "this button is now `AppButton.primary`"
  beyond what `flutter analyze` already confirms (the file compiles and
  references the right widget). Happy to add targeted tests if you want
  them regardless.

---

## 9. Issues requiring your approval before going further

1. **AppTypography/AppSpacing adoption** was explicitly descoped from this
   pass (§1, §5). If you want the 5 pilot screens to actually hit "no
   unnecessary one-off TextStyles" from the Master Prompt's acceptance
   checklist, that's a meaningfully larger follow-up — recommend treating it
   as its own approved step rather than assuming it's covered.
2. **Rollout to the remaining ~40 screens** is explicitly gated behind your
   review of this pilot per the Master Prompt (`§19`). Nothing beyond the 5
   pilot screens has been touched.
3. **Booking Form's `_ButtonSkeleton`-vs-`AppButton` judgment call** (§4) —
   flagging so you can override it if you'd rather force full consistency
   even at the cost of the better loading pattern.

No code beyond the 5 pilot screens and the new shared components has been
changed.

---

## 10. Addendum — Typography/Spacing/Radius follow-up sweep

Per explicit user request after this audit was first written, a dedicated
follow-up pass converged the 5 pilot screens further on §5's flagged gap.
Three commits, in order:

1. **Radius** (`cc6a4a2`) — all ~151 `BorderRadius.circular(N)`/
   `Radius.circular(N)` literals across the 5 screens snapped to the nearest
   of the 3 official values (chip=8/card=16/sheet=24) by distance. **100%
   converged** — `grep -c 'BorderRadius\.circular([0-9]'` across all 5 files
   now returns 0.
2. **Spacing** (`6a44033`) — `SizedBox(height/width:)`, `EdgeInsets.all()`,
   and `EdgeInsets.symmetric(horizontal:/vertical:)` literals converted to
   `AppSpacing.*` **only where the literal exactly equals a token value**
   (4/8/12/16/24/32/48) — a zero-visual-change, lossless substitution. Values
   that don't land on the grid (10, 20, 6, 14 — themselves common, e.g. "10"
   appeared 60 times) were deliberately left as literals rather than forced
   onto the nearest token, per the Master Prompt's own caution against
   mechanically replacing spacing "blindly."
3. **Typography** (`9e5dff1`) — ~44 `AppTypography.*` references added,
   covering the clearest, most-repeated muted/label/body patterns
   (`AppTypography.<role>` directly where color already matched the role's
   default, `.copyWith(...)` where a color/weight override was needed,
   including dynamic/conditional colors). `match_screen.dart` was
   deliberately exempted in full — its TextStyles are almost entirely
   one-off, colored white/yellow for its dark-gradient UI with no
   consolidation value.

**Final measured state** (`grep -c` per file, post-sweep):

| File | AppRadius refs | AppSpacing refs | AppTypography refs | Raw `TextStyle(` remaining |
|---|---|---|---|---|
| quick_booking_screen.dart | 10 | 22 | 5 | 12 |
| booking_detail_screen.dart | 7 | 17 | 5 | 17 |
| tracking_screen.dart | 20 | 32 | 2 | 20 |
| match_screen.dart | 23 | 61 | 0 (deliberate) | 46 |
| booking_form_screen.dart | 94 | 88 | 32 | 73 |

**Honest bottom line:** Radius is fully converged. Spacing is converged for
every literal that could be losslessly mapped (a large majority of the
grid-aligned instances) — the remaining literals are off-grid values that
would need a real, reviewed layout decision to force onto the scale, not a
mechanical refactor. Typography made real, verified progress (~44 sites) on
the clearest wins, but a large tail of raw `TextStyle(` calls remains,
concentrated in `booking_form_screen.dart` (73 remaining, the largest file)
and in category-specific semantic-accent-colored text (e.g.
`categoryAddonValueText`, `categoryAcAccent`, `noteWarningText`) that isn't
a design-system violation so much as intentional per-category styling. A
full typography convergence — every remaining `TextStyle(` literal
individually reviewed and mapped — is a larger, separate effort; doing it
safely by hand across ~170 more remaining call sites (vs. this sweep's ~45)
was judged lower value than flagging it honestly here.

`flutter analyze` (full project, post-sweep): 0 errors, 0 warnings, 70
info-level issues (unchanged). `flutter test` (full project): same 12
pre-existing failures, zero regressions across all three commits.
