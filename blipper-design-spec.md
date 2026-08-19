# Blipper — Visual Design Spec

Reflects what is actually implemented in `batsignal/Theme/` as of 2026-08-18.
Where this document and the code disagree, the code is right and this is stale —
the tokens in `BlipperTheme.swift` are the source of truth.

## Concept

This palette is drawn from a specific moment: surfing at dusk in Santa Cruz, just after
a bright orange sunset had faded into pink and deep red, with the sky and sea settling
into dark, melancholic blues. The water was mostly calm with a slight wind. Yellow
lights dotted the coastline from town, and the moon was soft and muffled behind fog.

The palette should feel moody, coastal, and a little melancholic — calm rather than
energetic, atmospheric rather than flat.

The app is pinned to `.preferredColorScheme(.dark)`. Every surface and text color
assumes a dark base; there is no light mode.

---

## Color Palette

| Name | Hex | Role |
|---|---|---|
| Dusk Navy | `#16283A` | Background base; card surfaces (at 92% opacity); text on moonlight fills |
| Swell Blue | `#2F4E63` | Bottom of the background gradient; avatar icon fill; the user's own location dot |
| Harbor Light Amber | `#E0A83F` | **The signal color.** Event icon rings and fills, time remaining, the wordmark |
| Afterglow Rose (dark) | `#93443A` | Urgency/destructive, as a fill — the LIVE badge |
| Afterglow Rose (mid) | `#C1594B` | Urgency/destructive, as text and icons on the dark base |
| Muffled Moonlight | `#C7D0D4` | **The interactive color.** Buttons, icons, chevrons, borders, toolbars, dividers |
| Fog Haze | `#8A9096` | Muted/secondary text — timestamps, subtitles, helper text. A flat neutral gray |
| Moonlight White | `#EAEEEF` | Primary text: headers, names, high-emphasis content |

### On-accent text

Text sitting on an accent takes a dark, desaturated version of that hue rather than
black or white, so the pairing stays warm rather than clinical.

- On Harbor Light Amber → `#3A2506`
- On Muffled Moonlight → `#16283A` (Dusk Navy)
- On Afterglow Rose → `#2E100A`, or `#E8D3CE` for lighter badge text on a rose fill

### Derived surfaces

| Token | Definition |
|---|---|
| `surface` | Dusk Navy at 92% — cards and panels, so the gradient bleeds through |
| `surfaceRaised` | Swell Blue at 55% — a card sitting on another card |
| `hairline` | Moonlight at 15% — borders and dividers |
| `track` | Moonlight at 12% — the unfilled part of a progress bar |

### Background gradient

Two tones, top to bottom: dark navy sky easing into the mid-blue of the water.

```swift
LinearGradient(colors: [duskNavy, swellBlue], startPoint: .top, endPoint: .bottom)
```

Backgrounds only — cards and badges sit on flat Dusk Navy instead. Applied with
`.blipperBackground()`, which also clears the system's scroll background.

> The original six-stop version ended in two warm tones (`#5C4640` → `#75504A`).
> Those were removed so that nothing on a background competes with the rose that
> signals urgency.

---

## Color Roles — the three-way split

The palette works because each of the three accents means exactly one thing. Keeping
them apart matters more than any individual placement.

**Harbor Light Amber = "a signal."** Never an affordance. It appears on:

- an event icon's ring, at every size, in every context
- an event icon's *fill*, but only on the map pin and in the create/edit flow
- a running signal's time remaining (the progress bar, at all levels — no urgency ramp)
- the app wordmark
- the `+` on the create-signal prompt card, and the swipe-to-send lines once there is
  something to send

**Muffled Moonlight = "you can touch this."** The interactive color, and secondary
chrome. It backs the `AccentColor` asset *and* the root `.tint`, so `Color.accentColor`
resolves here and system-drawn controls follow. Buttons, icons, chevrons, card borders,
toggles, toolbar items, dividers.

> The asset alone was not enough — SwiftUI toolbar buttons ignored it and came out
> system blue until the root `.tint(Blipper.moonlight)` was added.

**Afterglow Rose = "this is urgent or destructive."** Nothing else. Live indicators,
"end signal", sign out, delete account, error text. Use the mid rose for text and icons
on the dark base (the dark rose is illegible there) and the dark rose for fills.

**Fog Haze and Moonlight are supporting, not decorative.** They should never be the
loudest thing on a screen. Fog Haze in particular stays a flat, calm gray — resist
tinting it blue, which muddies its role as the quiet neutral.

---

## Typography

Two families, both variable fonts, in `batsignal/Resources/Fonts/`.

### Instrument Sans — the wordmark, and nothing else

- **Weight 700, italic, in Harbor Light Amber**
- Used at exactly three sites: `HomeView`, `AuthFlowView`, `ProfileSetupView`
- Only the italic file (`InstrumentSans-Italic.ttf`) is bundled, so the family carries
  the italic trait and anything drawn in it is italic without asking
- Its `wght` axis runs 400–700 only

It is the app's signature. Spending it on headers or names is what dilutes it — those
are Inter. There is deliberately no second display use anywhere in the app.

### Inter — everything else

Headers, names, body copy, labels, timestamps. The scale in use:

| Role | Style | Weight |
|---|---|---|
| Section headers, screen headlines | `.title2` / `.title3` | 600 |
| Card titles, event activity | `.headline` | 600 |
| People's and groups' names | `.subheadline` | 600 |
| Body, status, message text | `.subheadline` / `.body` | 400–500 |
| Timestamps, helper text, secondary labels | `.caption1` / `.caption2` | 400, Fog Haze |
| Small badge text, avatar initials | `.caption2` / fixed size | 600 |
| Verification code entry | `.title2` | 500, tabular figures |

Navigation bar titles are Inter 600 — a nav title names the screen, not the app.

**SF Symbols and emoji keep the system font.** Every `.font(.system(size:))` in the app
is a symbol or an emoji; giving them a text typeface changes nothing but risks metric
shifts.

---

## The event icon

One component, `EventIconView`, in two styles. They differ only in color.

| | `.avatar` | `.signal` |
|---|---|---|
| Fill | Swell Blue | Harbor Light Amber |
| Content (initials) | Moonlight White | `#3A2506` |
| Used by | List avatars, joined stack, profile and settings photos, comment avatars, home header | Map pin, create/edit preview circle |

Both wear the amber ring — a `strokeBorder` so it sits fully inside the circle, leaving
the boundary free for the separator ring the avatar stack draws over it. Ring width is
`min(max(size * 0.05, 1.5), 3)`: scaled off the icon, capped at both ends, since the
component runs from 26pt in the avatar stack to 140pt on the profile screen. On the
signal style it lands amber on amber and simply reads as a clean edge.

### What the icon shows, in order

The photo branch wins over the label branch, so the precedence has to be resolved
where the data is assembled, not in the view:

1. the event's own image
2. the event's own emoji
3. the creator's profile photo
4. the creator's initials

The creator's photo is only reachable when the event has no emoji. Resolving the photo
and the label independently — each with its own fallback — lets a profile photo
silently swallow an event's emoji.

### The map pin

`EventAnnotationView` = a `.signal` icon plus a tail. Default 44pt, up to 220pt for a
focused "hero" pin; total height is `size * 1.2`.

- The tail is a triangle in the same fill, overlapping the circle by a third so the two
  join without a seam, drawn **behind** the circle via `zIndex(-1)` so it never sits
  across a photo. It must keep contributing its height to the stack — the map anchors
  annotations at `.bottom` so the tail's tip marks the coordinate.
- The haze (`box-shadow` equivalent) is amber at radius `max(size * 0.28, 10)`, cast
  from the **whole pin** rather than the circle, so it draws behind the tail rather
  than over it, and traces the pin's real silhouette.
- A black drop shadow at 25%, also on the whole pin, holds it off the map.

No haze on the create/edit preview circle. A shadow draws outside its view's bounds and
a form row clips to them, so it came out sliced flat top and bottom; reserving room
would cost ~100pt of height on a form that cannot scroll.

---

## Map treatment

**Vignette** (`MapFogVignette`) — fog rolling in off the water. The map stays clear
where you are standing and thickens toward the edges, which also pulls the eye to the
middle of the screen.

- An elliptical gradient, transparent to 35%, Dusk Navy at 35% opacity by 65%, and
  `#101C28` at 75% opacity at the edge
- Centred at 46% height — slightly above middle, matching where the eye rests on a
  screen whose bottom is taken by the carousel
- Anchored to the screen, not to the user's marker: the map is normally centred on you
  anyway, and a vignette sliding under a pan would draw attention to itself
- `allowsHitTesting(false)` — every pan, zoom and pin tap passes through it

SwiftUI has no per-axis elliptical radii, so the ellipse is shaped by sizing the
gradient's *frame* (1.2× width, 1.08× height) rather than by radius fractions. The
height is over 1.0 on purpose: a gradient draws nothing outside its own frame, and at
1.0 the bottom edge of the map was left as an unfogged bright band.

**The user's own location dot** is the system dot, filled Swell Blue via the map's
`.tint` — which keeps its white ring, accuracy circle and heading wedge.

### Not implemented

Two ideas from the original spec are deliberately absent, because both are layout
changes rather than styling:

- distance-based marker sizing/opacity (smaller, dimmer, softer-glowing when far away)
- a larger size and halo ring distinguishing the user's own marker

---

## Implementation notes

Things that cost real time and are not obvious from reading the result.

**Variable fonts.** Both families ship as a single file carrying the whole weight
range. iOS only exposes the family's default instance by name, and both default to a
weight lighter than anything the UI wants — so every weight is cut at runtime by
setting `kCTFontVariationAttribute` on a `UIFontDescriptor`, with axis tags as
FourCharCode integers. An out-of-range axis request *fails to match* rather than
clamping, so per-family ranges are enforced in code. Dynamic Type is applied with
`UIFontMetrics` before the face is cut, so Inter's optical-size axis matches the size
the glyphs actually render at.

**Font file names are not family names.** The display family is "Instrument Sans" but
the file is `InstrumentSans-Italic.ttf`, so registration works from an explicit file
list.

**`listRowBackground` does not propagate from a List down to its rows** — only from a
Section. `.blipperBackground()` therefore cannot set it, and Sections whose rows do not
draw a card of their own need `.blipperRows()` or they keep the system's near-black
grouped fill.

**Shadows draw behind the view they are attached to**, and outside its bounds. That is
why the pin's haze hangs on the whole pin rather than the circle, and why a glow inside
a clipping list row gets sliced.

**The wordmark needs uneven vertical padding to look centred.** A stack centres a
text's *line box*, but "Blipper" has descenders and the all-caps LIVE badge beside it
does not, so their inked glyphs do not line up. The home header pays 2pt off the top
and 2pt onto the bottom (same 12pt total, so the backdrop is unchanged). **Re-measure
this whenever the display face or its size changes** — it was 3pt under the previous
face. Measure by registering the font in a `swift` script and comparing
`CTLineGetImageBounds` against the line box.

---

## Decisions and history

Recorded so they are not re-litigated:

- **Display face.** Fraunces (original spec) → Manrope → **Instrument Sans Italic**.
  Fraunces was rejected for its look and for being used in too many places; Manrope for
  its look. The scope narrowed at the same time, from "anything that names or
  identifies something" to the wordmark alone.
- **Amber's reach.** Originally the primary accent for all actions and identity. That
  read as far too much amber, so the interactive role moved to Moonlight and amber
  narrowed to signals. It has since been let back onto the progress bar, the wordmark,
  the create-prompt `+`, and the ready state of swipe-to-send.
- **Progress bar urgency ramp removed.** It ran amber → dark rose → bright rose as time
  ran out; it is now amber throughout. The bar's *width* already communicates time
  remaining. If urgency is wanted back, deepen the amber or fade its opacity rather
  than reintroducing red.
- **Tried and reverted:** a Fog Haze–colored vignette (grey lightens the map's edges
  rather than shading them, and read as far too assertive at the same opacities), and
  monochrome emoji via `.grayscale(1).colorMultiply(...)` on the amber fill.
- **Rose's boundary.** Rose stays urgent/destructive. It is the one role that has not
  moved, and the two-tone background exists partly to protect it.
