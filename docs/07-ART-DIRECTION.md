# 07 — Art Direction

> **GALLERY REVIEW** — *"It's as if a 1972 crime paperback swallowed a Wurlitzer and is
> extremely happy about it."*

**Style name: PAPERBACK NOIR × ELECTRIC BRASS.** Two registers that grow together:

- **Paperback Noir** — the world's "daytime" register: newsprint cream, ink black, halftone
  shading, grease-pencil annotations, evidence photos, pulp-cover composition. Owns the UI,
  The Count, the Ledger, headlines, mugshots.
- **Electric Brass** — the table's "night" register: deep felt greens and blacks, warm brass
  and wood, and NEON as the only saturated light source. Neon accumulates with the empire —
  at R0 the table has one buzzing bulb; at R7 it's a canyon of signage. **Light growth = the
  progress bar** (P1/P4).

The two registers meet in one trick used everywhere: **saturated light on unsaturated matter.**
Everything physical is ink, paper, wood, felt, steel; everything *earned* glows.

---

## 1. Palette

| Token | Hex | Use |
|-------|-----|-----|
| Ink | `#12100E` | line work, table base, backgrounds |
| Newsprint | `#F2E8D5` | paper UI, body text |
| Felt | `#1E3D2F` | playfield base (city 1) |
| Brass | `#C9A227` | rails, plunger, trims, ☆ |
| **Dirty red** | `#E23D3D` | dirty cash, string on the corkboard, danger |
| **Clean green** | `#3FBF6F` | clean cash, confirmed states |
| **Neon rose** | `#FF2E63` | signage, casino |
| **Neon teal** | `#2EE6D6` | laundromat, water, docks |
| **Cop blue** | `#3A8DFF` | police, Federal meter |
| Heat ember | `#FF7A2E` | Heat meter, raid wash |
| Violet velvet | `#8C4DFF` | penthouse, high-roller |

Rule: dirty/clean/heat/cop colors are **reserved** — nothing decorative may use them (P4:
every color carries one meaning). Cities re-theme the ambient palette, never the reserved four.

## 2. Rendering & shaders (Godot canvas stack)

- Hand-drawn-look vector/high-res raster sprites with ink outlines; halftone dot shading via a
  cheap canvas shader (world-space dots so they don't swim).
- **Neon** = emissive sprites + WorldEnvironment 2D glow; flicker/ballast-hum animation on a
  per-sign personality curve. Budgeted Light2D count with baked glow textures as the fallback ([09-TECH](09-TECH.md) §8).
- Film grain + subtle vignette overlay; paper-texture overlay on all UI panes.
- The ball: real-time-ish fake reflection (matcap-style) so the metallic ball reads *expensive*.
- Slow-mo moments get a halftone-enlarging "printed frame" effect — the game freeze-frames like
  a pulp panel.

### Ball identity (shared live/preview renderer)

Every named Bench guy keeps a persistent numeric ID. `BallDesign` deterministically derives the
ball's metallic base, a high-contrast band geometry, crest mark, and orientation from that ID;
names, traits, and palette color are not identity inputs. The band geometry and crest are always
part of the read, so identity is never color-only. `BallDesign.draw_ball()` is the shared
renderer used by the live `Ball` and the Roll Call `BallPreview`, keeping the preview and table
face in lockstep. Empty/anonymous debug balls use the original plain steel treatment — no
identity band or crest.

## 3. Character art

Little guys everywhere (builders, corner boys, Manny scurrying) are 2–4 frame silhouette
animations with strong hat/coat shapes — cheap, readable, funny. Mugshots and specialist
portraits are the flagship art pieces: pulp-painting style faces, heavy ink, one accent color
per character (matches their instrument-voice, [08-AUDIO](08-AUDIO.md) §5).

**Sourcing option (verify licensing at import):** the NSW Police "specials" glass-negative
mugshots (1920s Sydney, widely published as public domain / no known copyright) are a stunning
authentic base for *style reference or processed textures*. Treatment pipeline: posterize +
halftone + ink overlay so no recognizable real face ships as a character. If clearance is
murky, we draw our own in that style — the pipeline is the same.

## 4. The Ledger UI (corkboard conspiracy map)

The upgrade tree IS the game's centerpiece menu ([04-UPGRADE-TREE](04-UPGRADE-TREE.md)):

- A city map (drawn like a 1970s transit map) under glass, pinned over cork. Branches =
  districts; nodes = polaroids, index cards, matchbooks, napkin sketches; connections = red
  string with real catenary sag (tiny physics, big charm).
- Face-down cards for undiscovered nodes; bought nodes stamped and pinned flat; affordable
  nodes' pushpins *glint*.
- Buying plays: pin-punch sound, string snaps taut to neighbors, polaroid develops.
- The board zooms/pans with standard gestures; a thumb-reachable "next affordable" compass.

Other UI set-pieces: **The Count** (green-lamp counting room, bills fanning under a bill
counter, tally on adding-machine paper), **newspaper front pages** (procedural headlines from
a madlib grammar over the Night's stats), **rap sheet** (stats screen as a case file),
**Sunday Dinner** (top-down table that fills with dishes).

## 5. Typography (all Google Fonts, OFL)

| Role | Face | Why |
|------|------|-----|
| Marquee / logo | **Limelight** | deco theater marquee |
| Headlines / numbers | **Six Caps** or **Bebas Neue** | tall condensed tabloid punch |
| Newspaper masthead | **UnifrakturMaguntia** (or Chomsky, OFL, self-host) | blackletter masthead |
| Case files / UI labels | **Courier Prime** | typewriter; repository-local OFL static TTF |
| Body / small print | **Libre Franklin** | the actual newspaper workhorse |
| Handwriting (red pen) | **Caveat** | corkboard annotations |

Numbers on the HUD use tabular figures; money counts up with slot-machine odometer motion.

## 6. Open-license asset pipeline (art)

| Need | Source | License |
|------|--------|---------|
| UI furniture, panels, icons base | **Kenney.nl** packs (UI Pack, Game Icons, Casino/Boardgame packs) | CC0 |
| Thematic icons (fedora, dice, money bags, wiretap, etc.) | **game-icons.net** (~4,000 icons) | CC BY 3.0 (credit file) |
| Textures: felt, wood, brass, paper, cork | **ambientCG**, **CC0-Textures** | CC0 |
| Palettes / reference | **Lospec** | reference |
| Period photos/textures (newsprint, city) | Library of Congress & public-domain archives; NYPL Digital Collections PD sets | PD (verify per item) |
| Anything gap-filling | **OpenGameArt** (filter CC0/CC-BY) | per item |

Pipeline rules: an `ASSETS.md` manifest tracks every imported file with source URL + license +
required credit; CC-BY credits render in an in-game "The Usual Suspects" credits screen; no
NC/ND-licensed assets ever (they poison commercial release); everything passes through our
posterize/halftone/ink treatment so mixed sources land in ONE style. The treatment shader/
action IS the art direction's consistency guarantee.

## 7. Motion & juice standards

- Every currency change has: number pop + flight-to-HUD particle + sound. Dirty flies as red
  bundles, clean as green, ☆ as brass glints. (Sensory audit tool in [09-TECH](09-TECH.md) §8 keeps
  particle budgets honest.)
- Screen-shake budget: reserved for jackpots, raid door-kick, boss phases; never for base hits
  (or shakes become noise — P4).
- Haptics vocabulary: light tick (flip), detent ramp (plunger), double-thud (collection),
  heartbeat pattern (Heat 90+), long rumble (raid). One meaning each, like colors.
- 60fps is an art requirement, not just tech: the whole style reads "expensive mechanical
  object", and hitches break the spell.
