# Phase 3 — Gameplay Feedback

Phase 3 gives the live table one coordinated response vocabulary. Existing authored audio
remains authoritative; a pooled screen-space renderer and mobile haptic actuator now answer
the same semantic events without changing camera, collider, ball, economy, or physics timing.

## Delivered

- **Hits and combos:** switch-position impact rings/rays, strength-scaled haptic ticks, and a
  safe-area combo callout. Ceremony haptics can supersede a same-frame switch tick.
- **Money:** separate red dirty and green clean flights terminate at their safe HUD lanes.
  Idle income is intentionally silent visually so passive ticks cannot flood the table.
- **Laundering:** clean flight plus a distinct `WASHED CLEAN` ceremony on the canonical
  laundering event; direct clean rewards have their own immutable event contract.
- **Consequences:** raw drain, guy pinched, and bail responses use their existing audio and
  add distinct motion, color, text, and haptic weight.
- **Modes:** Family Meeting, Smuggling Run, Heist, Sit-Down, Empire Mode, Raid, and Tilt starts
  use deduplicated banners. Raid outcomes retain a closing response.
- **Milestones:** jackpots, real in-Night rank-ups, boss start/phase changes, and boss defeat
  receive the strongest safe-area ceremony treatment.

Slot-reel and Family Meeting jackpots now share a canonical jackpot signal. Direct clean
payouts publish their amount and source without masquerading as laundering, preserving the
Count invariant that laundering is dirty money converted to clean.

## Runtime contract

- One `CanvasLayer` at layer 50 draws all gameplay feedback in a single mouse-transparent
  `Control`; transitions remain above it at layer 100.
- Twelve preallocated slots match the presentation emitter budget. Frequent impacts and
  currency flights recycle only an oldest peer; ceremonies drop observably when saturated.
- Allocation failure immediately returns the tentative budget token. Clear, teardown, and
  leaving the Night return every token.
- Event callbacks copy semantic payloads and enqueue presentation state only. No effect keeps
  a ball node, writes a transform, changes camera state, awaits, or enters a physics process.
- Existing gameplay audio is never replayed by the feedback renderer.

## Accessibility and curved screens

- Reduced motion keeps the information but removes travel, lift, scale, and burst rays.
- Reduced flash caps the renderer's opacity contribution to 25 percent.
- Haptics respect the existing enable flag and actuate only on supported handheld platforms.
- Important text and currency destinations derive from `Presentation.safe.content_rect()`.
  Currency trails may begin under curved glass, but their readable number is independently
  clamped. Decorative rings and low-alpha atmosphere may bleed; readable content never does.
- Tall phones use a smoked, two-row HUD panel below the safe top. The unsafe notch/corner cap
  remains full-bleed table art instead of becoming a large black spacer, so only 104 logical
  pixels of playfield are obscured by the information panel.
- The overlay mirrors the logical viewport explicitly because a `CanvasLayer` is not a
  `Control` parent, and it never intercepts phone touches.

No new bitmap assets were required. The pass is deterministic code-native motion and drawing,
so ImageGen was not used to create decorative assets that the runtime can render more sharply
and cheaply itself.

## Verification target

- Pinned Godot 4.5 import, unit suite, 600-frame boot, and every simulation scene.
- First-ten-minutes journey and exported-pack probe.
- 486×864 device walkthrough with asymmetric physical insets and a 56px rounded-corner guard.
- Live capture of impact/combo/dirty/clean feedback and jackpot ceremony, plus assertions for
  pool bounds, touch transparency, safe content, and budget cleanup across the Night handoff.
