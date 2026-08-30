# Phase 2 — Screen Set Pieces

Phase 2 turns the first-journey screens into short game rituals while leaving physics,
economy, save data, and state-machine contracts unchanged.

## Delivered

- **Attract:** cabinet frame, animated incandescent marquee, smoked-glass reveal, stronger
  KINGPIN lockup, and a branded Roll Call invitation. Reduced motion uses a static lit rail.
- **Roll Call:** tactile dossier cards, stable Phase 1 portraits, persistent ball identity,
  numbered serve badges, a three-slot serve-order rail, and specialist archive cards.
- **The Count:** adding-machine receipt, counted bill stacks, mechanical value windows, and a
  staged headline print. A tap still completes the whole count immediately.
- **The Ledger:** fixed cork-and-brass cabinet rails, tacks, specialist portraits, and a local
  PINNED purchase stamp. Reduced motion suppresses the card/stamp tween.
- **Transitions:** shutter, cabinet-light, receipt, and dossier reveals mask screen-tree swaps
  without delaying the synchronous gameplay state change.

No new bitmap files were required. Phase 2 reuses the approved Phase 1 ImageGen plates and
portraits; the new receipts, bills, frames, tacks, bulbs, strings, and odometer faces are
deterministic code-native presentation.

## Curved-screen rules

- Full-bleed plates and decorative cabinet rails may reach the physical edge.
- Text, buttons, value windows, and serve-order controls remain inside the OS safe area plus
  the conservative rounded-corner guard.
- The Count body scrolls independently of its fixed action footer, including late-career
  Commission, War Room, and Skip Town content.
- The Black Book purchase control receives the Ledger's right and bottom safe insets.
- Device validation intersects controls with ancestor clip rectangles, so off-scroll controls
  are not misreported as rendered while visible controls retain the full safe-rect assertion.

## Verification target

- Pinned Godot 4.5 import, unit suite, boot smoke, and every simulation scene.
- First-ten-minutes journey and exported-pack probe.
- 486×864 device walkthrough with asymmetric physical insets and a 56px rounded-corner guard.
- Visual inspection of Attract, Roll Call, Count, and Ledger captures.
