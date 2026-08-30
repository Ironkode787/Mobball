# 13 — Phase 1: First Ten Minutes

Phase 1 converts the first playable journey from functional prototype UI into a coherent
game presentation without changing physics, economy, collision shapes, or table coordinates.

## Shipped journey

1. **Attract** — the live table and illuminated Eastport backglass remain the title scene.
2. **Roll Call** — the job board, four fictional crew mugshots, persistent ball identities,
   licensed typography, and 96-pixel touch controls form one readable selection screen.
3. **The table** — backglass and key racket props sit below deterministic lamps and state
   marks; generated art never owns collision or interaction.
4. **The Count** — a full-bleed count-room still life frames the live tally while the action
   footer remains pinned inside the device safe rect.
5. **The Ledger** — production typography, tactile controls, explicit meters, and a safe-area
   header carry the player through the first purchase.

## Production contracts

- `PresentationTheme` resolves Oswald, Libre Franklin, and Courier Prime from repository-local
  OFL files. No Phase 1 screen depends on a platform fallback font.
- `Presentation.art` registers the 13 selected ImageGen assets by semantic ID during autoload
  initialization. Procedural fallbacks remain valid.
- Circular opaque prop plates use `circular_decal.gdshader`; collision nodes remain unchanged.
- Every interactive button introduced or touched in this phase is at least 96 logical pixels
  tall. The device probe recursively checks visible buttons against the safe rect.
- Full-bleed art may enter rounded corners. Copy, meters, and controls may not.

## QA evidence

The Phase 1 device probe runs at a 486×864 phone window with asymmetric physical insets and a
56-logical-pixel rounded-corner guard. It captures Attract, Roll Call, table, Count, Ledger,
return, and restart frames under `artifacts/phase1_device_safe/` (local, ignored). The probe
also verifies touch navigation, Ledger pinch zoom, first-purchase hardware persistence, and
every on-screen button against the safe rect.
