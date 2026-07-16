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

| Role | Hex | Use |
|---|---|---|
| Brand blue | `#0F6FFF` | Mark on light backgrounds, primary buttons, links |
| Brand blue (dark) | `#0B4FCC` | Gradient end, wordmark second word, pressed states |
| Brand blue (bright) | `#1A7BFF` | Gradient start on app icon / splash |
| White | `#FFFFFF` | Mark on blue/dark backgrounds |
| Near-black | `#11141A` | Dark-mode tile background |

The mark is always one flat color — never gradient-filled itself. Gradients,
where used, live in the background only (app icon, splash).

## Clear space and minimum size

- Keep clear space around the mark equal to at least 20% of its width on every
  side.
- Never render the mark below 16px (favicon) or 24px (in-app). At 32px and
  above the roof cue is visible; below that, the L silhouette alone still
  reads correctly — this is intentional and acceptable.

## Backgrounds

- **White / light:** blue mark (`#0F6FFF`), no container needed.
- **Brand blue:** white mark.
- **Dark (`#11141A` or darker):** white mark.
- Never place the blue mark on a blue background, or white mark on white/light
  background — contrast must be immediate.

## Do

- Use the mark at full opacity.
- Scale proportionally only.
- Use the mono version when you need the mark to inherit a UI theme color.
- Keep the bevel cut sharp — it is a straight diagonal line, not curved.

## Don't

- Don't add a house outline, separate roof shape, or AC vent lines back in —
  the brief is one dominant idea (L), not a scene.
- Don't recolor the mark with a second/accent color (no more green, teal,
  etc.) — the system is blue + white/black only.
- Don't rotate, skew, or add drop shadows/outlines/strokes to the mark.
- Don't set the wordmark in anything but the brand blue pairing defined above.

## Wordmark

`LinTho` — "Lin" in `#0F6FFF`, "Tho" in `#0B4FCC` on light backgrounds; both
words solid white when reversed on blue/dark. Set in a bold sans-serif
(Helvetica/Arial 800, or the app's bold UI font), sentence case as shown — not
all caps.
