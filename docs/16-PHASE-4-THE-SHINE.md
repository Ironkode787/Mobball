# Phase 4 — The Shine

Phase 4 turns the existing content-complete game into a considerate mobile presentation:
the first live minute teaches itself, sensory options are player-facing and persistent, and
the presentation budget can be measured on the same rounded/cutout phone profile used by the
earlier phases. Gameplay rules, collision, scoring, and physics timing remain unchanged.

## First-Night rehearsal

- The first Night installs one touch-transparent coach card only.
- It asks for the real pull-down/release launch gesture until `ball_launched` confirms it.
- It then teaches left/right flipping until the first active dirty earning event confirms a
  meaningful hit. A short dirty-cash acknowledgement follows, then the coach leaves.
- The card stays above the flipper region, ends before the shooter lane, and is removed before
  The Count. It never advertises Lucky's or laundering before that hardware is available.
- Later Nights do not create the coach. The Count retains the authored first-$200 wash lesson.

## House Rules

`HOUSE RULES` is reachable at the front door and between Nights without adding another control
to the compact gameplay header. It exposes:

- reduced motion;
- reduced flash;
- haptics;
- subtitles; and
- independent Music, Mechanics, Fiction, and UI bus levels.

Choices live in `user://presentation.cfg`, outside the career save, and apply immediately.
Reduced motion removes nudge shake, snaps necessary camera framing instead of easing, skips
construction and Count/Ledger theatre, and keeps all information. Reduced flash freezes the
fast cabinet chase, raid spotlights, and wrench telegraph while the pooled feedback renderer
retains its 25-percent cap.

Inspector and high-Heat warnings now have both a visual banner and a semantic haptic, so
turning haptics off never removes the warning itself.

## Dialogue and subtitles

The nine muted-brass specialist voices have authored caption lines for greeting, quip, and
grumble moods. `AudioDirector.say()` emits the matching caption, and a mouse-transparent
safe-area strip renders it above persistent Count/Ledger actions. Hiring a specialist is the
first production caller; the device probe exercises the same audio-to-caption path.

## Safe glass and the compact HUD

- Settings, coach, and subtitle surfaces all consume `Presentation.safe` margins.
- The 486×864 acceptance profile uses asymmetric physical insets `44,96,72,54` plus a 56px
  rounded-corner guard.
- The live HUD remains the Phase 3 104-logical-pixel smoked strip below the unsafe top. Phase 4
  adds no gameplay-header button and fixes the mode stack's allocation to its actual 11 rows.

## Sensory budget evidence

`SensoryAudit` observes the live renderer rather than trusting declared pool sizes. The final
phone Night measured:

- 0 live `Light2D` nodes (limit 8);
- 4 live feedback emitters in the fixture (limit 12);
- 3 active audio voices (limit 24); and
- 194 draw calls against the roadmap's 120 target.

Lights, emitters, and audio are hard-gated in the device journey. Draw calls are deliberately
recorded as an unresolved optimization baseline rather than hidden by raising the target. A
static-layer caching/atlas pass is still required before the min-spec release gate can claim
the 120-call budget.

Cities 3–5, Play Games services, private release signing, store assets, and the physical
30-minute thermal/device matrix remain release-program work, not changes to this presentation
vertical slice.

## Verification

- Godot 4.5 import and 600-frame boot.
- 8,292 unit checks, zero failures.
- All 12 simulation scenes.
- Real 486×864 input journey through Attract, House Rules, Roll Call, launch, first earning,
  compact Night HUD, feedback budget, specialist subtitle, Count, Ledger pinch zoom, and save
  restart, with asymmetric cutout and rounded-corner guards.

No new bitmap gap appeared in this phase. Settings, captions, coach marks, and sensory-policy
changes are sharper and cheaper as native UI/drawing, so ImageGen was not used.
