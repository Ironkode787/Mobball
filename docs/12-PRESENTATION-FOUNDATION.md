# 12 — Presentation Foundation

Phase 0 adds contracts for art, layout, and effects without changing KINGPIN's physics or
gameplay geometry. The procedural renderer remains the fallback and the source of truth for
hit-readable hardware.

## Screen-edge contract

Phone glass is decorative space, not guaranteed content space. Backgrounds, cabinet art,
felt, and non-interactive effects may bleed to every physical edge. Text, meters, buttons,
touch targets, and other critical information must live inside the presentation safe rect.

The presentation safe rect is the logical-viewport conversion of the OS-reported display
safe area, inset further by a conservative rounded-corner guard. On devices that report no
cutout, the corner guard still protects content from curved glass. Insets are recomputed when
the window, orientation, or stretch geometry changes. Desktop tests may inject a physical
safe rect and corner guard to simulate notches and rounded corners.

No critical control should merely be clipped to the safe rect: it must be laid out inside it.
Full-bleed art remains full bleed so safe-area support does not create black gutters.

For desktop QA, `KINGPIN_SAFE_INSETS=left,top,right,bottom` injects physical-pixel
cutouts and `KINGPIN_CORNER_GUARD` sets the logical rounded-glass guard. The device probe
captures every major flow screen and asserts that its primary controls are enclosed by the
resulting safe rect. It boots against `user://device_probe_save.json`, including restart
coverage, and erases that save and its backups so it never touches a player's career.

## Presentation layers

1. Full-bleed static cabinet, room, and playfield art.
2. Hit-readable procedural hardware and authored collision geometry.
3. Dynamic state overlays such as lamps, mode marks, and semantic color.
4. Transient pooled effects such as impacts, currency flights, and transitions.
5. Corner-safe HUD and screen controls.

Physics nodes, collision shapes, camera bounds, and table coordinates never depend on art.

## Semantic systems

- `PresentationTheme` owns shared palette, spacing, type roles, and surface tokens.
- `CitySkin` supplies ambient variation without changing reserved gameplay colors.
- `ArtCatalog` maps semantic IDs to optional textures and retains procedural fallbacks.
- `EffectBus` routes semantic feedback requests without gameplay knowing effect nodes.
- `PresentationBudget` tracks effect counts against the limits in [09-TECH](09-TECH.md).

## Phase 0 gate

- Major screen controls honor OS cutouts and the rounded-corner guard.
- Normal 1080×1920 layouts remain visually unchanged when no inset is present.
- Notch, asymmetric cutout, wide/tall viewport, and rounded-corner calculations are tested.
- Presentation systems introduce no physics dependencies and no missing-asset failures.
- Existing tests, simulations, pack probe, and device probe remain green.
