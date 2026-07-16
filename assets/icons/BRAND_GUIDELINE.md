# LinTho brand guideline

## The idea

One shape, one letter, one story: **L**. The upright's top-left corner is sliced
on a diagonal — a subtle roofline cue (home service). That's the entire brand
mark. No house outline, no separate AC unit, no swoosh bolted on. The roof cue
is secondary; the L is always the hero and must remain recognizable even if the
cut were removed entirely.

Path (100x100 grid): `M50,16 L50,66 L82,66 L82,84 L28,84 L28,34 Z`

## Files

| File | Use |
|---|---|
| `lintho_logo.svg` | Primary mark, transparent background |
| `lintho_app_icon.svg` | 1024x1024 app icon, blue gradient background |
| `lintho_logo_mono.svg` | Single-color version (`currentColor`) for theming, watermarks, dark/light auto-adapt |
| `lintho_logo_horizontal.svg` | Mark + wordmark lockup, side by side |
| `lintho_logo_login.svg` | Mark above wordmark, for login/auth screens |
| `lintho_splash.svg` | Full-bleed splash screen (400x800), mark + wordmark + tagline |
| `lintho_favicon.svg` | Favicon, tuned for 16-32px rendering |

## Color

<!-- ✅ [Phase 3 — updated to match the shipped app] This file previously
documented a blue-only system (#0F6FFF/#0B4FCC/#1A7BFF) that predates the
app's actual palette — green has been the primary action color throughout
the live product for some time, with navy/gold as supporting accents.
Values below are the canonical tokens; source of truth is
lib/theme/app_theme.dart's AppColors class. -->

| Role | Hex | Use |
|---|---|---|
| Navy | `#001B4B` | Mark on light backgrounds, app bar/nav accents, splash & launcher background |
| Green (primary) | `#22C55E` | Primary buttons, primary action color app-wide |
| Gold | `#FBBF24` | Secondary accent — ratings, highlights, rewards |
| Ink | `#0F172A` | Primary text |
| Teal | `#14B8A6` | Secondary brand accent (ColorScheme.secondary) |
| White | `#FFFFFF` | Mark on navy/dark backgrounds |
| Background | `#F8FAFF` | App scaffold background |

The mark is always one flat color — never gradient-filled itself. Gradients,
where used, live in the background only (app icon, splash) and should use
navy tones, not the retired blue gradient.

## Clear space and minimum size

- Keep clear space around the mark equal to at least 20% of its width on every
  side.
- Never render the mark below 16px (favicon) or 24px (in-app). At 32px and
  above the roof cue is visible; below that, the L silhouette alone still
  reads correctly — this is intentional and acceptable.

## Backgrounds

- **White / light:** navy mark (`#001B4B`), no container needed.
- **Brand navy:** white mark.
- **Dark (`#11141A` or darker):** white mark.
- Never place the navy mark on a navy background, or white mark on white/light
  background — contrast must be immediate.

## Do

- Use the mark at full opacity.
- Scale proportionally only.
- Use the mono version when you need the mark to inherit a UI theme color.
- Keep the bevel cut sharp — it is a straight diagonal line, not curved.
- Use green (`#22C55E`) as the one primary action color across buttons/CTAs;
  reserve gold for ratings/highlights and navy for chrome/nav — don't
  introduce a fourth "primary" candidate (see the design review's button
  hierarchy findings for why this matters).

## Don't

- Don't add a house outline, separate roof shape, or AC vent lines back in —
  the brief is one dominant idea (L), not a scene.
- Don't rotate, skew, or add drop shadows/outlines/strokes to the mark.
- Don't set the wordmark in anything but the navy/green pairing defined above.

## Wordmark

`LinTho` — "Lin" in `#001B4B`, "Tho" in `#22C55E` on light backgrounds; both
words solid white when reversed on navy/dark. Set in a bold sans-serif
(Helvetica/Arial 800, or the app's bold UI font), sentence case as shown — not
all caps.
