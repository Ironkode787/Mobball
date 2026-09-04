# 18 — Visual Polish Roadmap

> **Target:** KINGPIN should feel like one premium paperback-noir pinball machine, not a
> collection of individually themed prototype screens.

This pass is presentation-only. It may change layout, typography, copy, authored art,
animation, and feedback, but it must not change physics, economy, collision geometry, save
contracts, or gameplay timing.

This document describes the broad visual overhaul. For ongoing changes, use the proportional
verification policy in `CLAUDE.md`: review affected screens and relevant stress states, and
reserve the wider device matrix for shared-layout changes and release review.

## 1. Current-state diagnosis

The visual concept is already distinctive. The weak point is execution consistency.
`PresentationTheme` exists, but screen code still contains many one-off decisions: duplicated
palette definitions, five coarse text sizes, hard-coded offsets, locally styled controls, and
screen-specific density rules. The latest 486×864 captures expose the result:

- The **Attract screen** has a strong cabinet silhouette but is too dark, repeats the KINGPIN
  lockup, and gives the player several similarly weighted status lines before the primary action.
- **House Rules** reads like a developer settings panel: tall outlined slabs, default-looking
  sliders, dense all-caps privacy copy, and state conveyed by flooding the whole control green.
- **Roll Call** has good raw ingredients but too many columns and labels. Names and metadata
  clip, the job board becomes decorative rather than useful, and the main selection path is not
  obvious at a glance.
- The **Night HUD** compresses five concepts into a thin strip without a clear order. The first
  table is so low-contrast and empty that the playfield reads as unfinished rather than humble.
- **The Count** has the best scene-setting art, but the live UI floats over it as a translucent
  form. Number windows, roster, headline, toast, scrollbar, and footer compete for the same
  vertical band.
- **The Ledger** has an attractive material idea but weak phone composition: a large dead header,
  tiny cards, large empty board regions, controls at three different visual weights, and a
  centered subtitle/toast that hides the object being inspected.
- The expanded table has more content but not more visual organization. Thin outlines, competing
  rail colors, small labels, and mixed rendering detail make the earned empire harder to read.

This is primarily a hierarchy, typography, component, and composition problem. More decoration
alone would make it noisier.

## 2. The quality bar

Every frame should communicate in this order:

1. **Where am I?** One unmistakable scene identity.
2. **What matters now?** One dominant gameplay fact or choice.
3. **What can I do?** One primary action, with secondary actions visibly secondary.
4. **What changed?** Feedback appears near its cause and clears without hiding the next action.

The presentation uses two coordinated registers:

- **Paperback Noir** for decisions, results, dossiers, receipts, and menus.
- **Electric Brass** for the live table, earned hardware, lamps, and high-energy feedback.

Screens may favor one register, but typography, spacing, control behavior, and semantic colors
must remain shared. Reserved dirty, clean, heat, and police colors communicate those concepts
only. Green is not the generic selected-state color; red is not a generic close-button color.

Accept a change when its affected screens meet the relevant criteria in section 8 and no
known material defect remains in that scope. The capture matrix guides coverage; completing
every combination is not a prerequisite for a routine edit.

## 3. Foundation pass — fix once, improve everywhere

### 3.1 Expand the token system

Make `PresentationTheme` and `CitySkin` the only sources of presentation decisions.

- Replace the five size constants with named roles: hero, screen title, section title, primary
  value, body, caption, metadata, button, and micro-label.
- Add line-height, letter-spacing, maximum line length, and tabular-number rules.
- Add a complete 4/8-point spacing scale, safe-page gutters, content widths, control heights,
  radii, border weights, elevation/shadow, and overlay-opacity tokens.
- Add neutral material tokens for ink glass, newsprint, aged paper, cork, wood, brass, and felt.
- Keep semantic gameplay colors separate from material and interactive-state colors.
- Move Ledger palette aliases and HUD mode colors into the shared theme/city skin.
- Define compact-phone and standard-phone breakpoints through layout profiles, not scattered
  aspect-ratio branches and pixel offsets.

### 3.2 Replace `PaperKit` with production primitives

Keep the name if useful, but turn it into a real component library:

- `ScreenScaffold`: full-bleed scene art, safe content, fixed header/footer, optional scroll body.
- `TypeLabel`: typography roles with predictable wrapping and truncation behavior.
- `ActionButton`: primary, secondary, quiet, destructive, and icon-only variants with consistent
  pressed, disabled, focus, and loading states.
- `ToggleRow`: label plus a compact mechanical switch/check, never a full-width green slab.
- `SliderRow`: bus label, live value, custom rail, fill, thumb, mute endpoint, and reset action.
- `PaperCard`, `GlassPanel`, `ReceiptRow`, `DossierCard`, `ValueWindow`, `SectionHeader`, and
  `BottomActionBar`.
- `Toast` and `Subtitle`: distinct components with placement rules and priority arbitration.
- `IconLabel`: code-native icon plus text so meaning never depends on color alone.

All components must ship with every state visible in a development-only component gallery.

### 3.3 Typography and copy rules

- Oswald owns display titles and short action labels; Libre Franklin owns readable prose and
  data labels; Courier Prime owns evidence, receipts, annotations, and metadata.
- Do not use all caps for sentences or explanatory copy.
- Use sentence case for instructions, descriptions, privacy text, and status explanations.
- Use consistent currency formatting, thousands separators, abbreviations, and tabular figures.
- Remove redundant labels. A value's color may reinforce its meaning, but its name or icon must
  remain visible.
- Replace technical phrasing with in-world clarity. Flavor may decorate an instruction, never
  obscure it.
- No ellipsis or clipped text is acceptable in the core journey. Responsive copy variants are
  preferred to silent truncation.

### 3.4 Visual texture and effects

- Apply paper grain, halftone, vignette, and glass treatments through a small shared material
  stack with intensity tokens. Do not bake a different effect into each panel.
- Increase contrast on functional table marks before adding glow.
- Standardize shadow direction, brass edge lighting, paper aging, and ink density across bitmap
  and code-native art.
- Give transitions a common timing curve and hierarchy: navigation, reveal, confirmation,
  ceremony. Reduced-motion variants remain immediate but composed.

## 4. Screen-by-screen polish

### 4.1 Attract / front door

**Intent:** one confident invitation into a living machine.

- Use one KINGPIN lockup. Let the illuminated backglass carry the brand; the safe-area content
  should carry only a short invitation and the primary action.
- Raise table and backglass luminance enough to reveal material detail without losing noir.
- Reduce the status row to the two facts that affect the next action. Move career metadata into a
  quieter secondary line or a resumable-career card.
- Make `ROLL CALL` the sole dominant control. Present `HOUSE RULES` as a quiet text/brass action.
- Restyle pending Safe collection as an earned interruption with cash value and one collect action,
  not another equal-weight panel.
- Add a restrained attract loop: warm bulbs, a single lamp chase, ball glint, and ambient parallax.
  It should settle, not pulse continuously.

### 4.2 House Rules

**Intent:** a handsome, calm setup sheet rather than a debug menu.

- Use a compact title band and one-sentence intro, then group `Comfort`, `Sound`, `Beta`, and
  `Credits` as distinct paper sections.
- Replace four large toggle buttons with labeled rows and mechanical switches. Keep labels and
  states readable without semantic green/red fills.
- Replace default sliders with custom brass tracks, large thumbs, live percentages, speaker icons,
  and a mute affordance.
- Rewrite beta privacy copy in sentence case and progressive disclosure. Keep the allow toggle,
  local-event count, export, and clear actions together.
- Make destructive `CLEAR BETA DATA` visually specific and add an inline confirmation state.
- Keep `DONE` in a compact fixed footer with a subtle top separation; it must not look like a fifth
  settings choice.

### 4.3 Credits / The Usual Suspects

**Intent:** a designed final page of the case file.

- Use a newspaper/case-file hierarchy with section mastheads, short readable paragraphs, and
  credited items rather than one monolithic text block.
- Add the project mark, Godot mark only if licensing and asset policy permit, and small type/art/
  audio glyphs.
- Include asset provenance and license access without making legal copy the visual focal point.
- Preserve a fixed, clearly secondary return action.

### 4.4 Roll Call

**Intent:** choose tonight's job and crew in under ten seconds, while making each guy memorable.

- Turn the job board crop into a clear hero docket: job name, plain-language objective, reward,
  risk/scope, and one thematic prop. Remove duplicated scope phrases.
- Put the three serve slots directly below the job as the selection target. Use portraits/ball
  crests, names, and order numbers; empty slots should visibly invite a tap.
- Simplify crew cards to portrait, name, one trait line, availability, and selection control.
  Move level, persistent ID, and extended effect text into a tap-open dossier.
- Give selected cards a physical state change—clipped/pinned/raised—not a green outline plus
  repeated `SELECTED` copy.
- Eliminate all clipped names and metadata at compact width. Cards may become a vertical list;
  internal three-column layouts may not.
- Separate Specialists into a later, collapsible `Hired Hands` section so they do not compete with
  tonight's core choice.
- Keep `START NIGHT` fixed and show its requirement inline only when incomplete.

### 4.5 Live table and HUD

**Intent:** the ball and current shot remain dominant; the HUD is readable in a glance.

- Recompose the compact HUD into two intentional bands: money/status and guy/heat/respect. Use
  aligned value columns, tabular figures, compact icons, and less punctuation.
- Show only one short mode objective at a time in a priority stack. Secondary timers/statuses can
  collapse into small chips; eleven equal text rows are not a viable phone hierarchy.
- Give the Heat meter labeled thresholds and a non-color warning pattern. Give Respect a consistent
  star badge and progress-to-rank treatment.
- Restyle the plunger meter as part of the shooter lane, with detents and a launch affordance rather
  than a generic bottom progress bar.
- Move first-Night instruction closer to the controlled region, shorten it, and reveal one gesture
  at a time. The card may not cover the ball's likely trajectory or the flippers.
- Increase ball separation from felt using a brighter steel value, controlled rim highlight, and a
  contact shadow. Persistent band/crest identity must survive motion and phone scale.

### 4.6 Playfield and career growth

**Intent:** even Rank 0 looks deliberately sparse; each purchase makes the machine richer and more
readable.

- Establish a playfield value hierarchy: darkest cabinet void, readable felt, mid-value physical
  hardware, bright inserts, and saturated earned light.
- Replace hairline geometry that disappears at phone scale with authored minimum stroke weights.
- Give Rank 0 a complete visual composition: apron detail, lane guides, insert labels, subtle wear,
  and purposeful negative space. “Bare” must not look unrendered.
- Normalize perspective, outline weight, shadow, and texture detail between generated props and
  procedural hardware.
- Reserve branch colors for navigational/mode identity and keep dirty/clean/heat/police colors
  semantic. The expanded-table rail rainbow needs consolidation.
- Make every interactable shot readable in idle, armed, active, completed, disabled, and danger
  states. Validate these states in grayscale as well as color.
- Define a lamp choreography per rank: ambient attract, current objective, recent hit, mode start,
  jackpot, and cooldown. Never light everything equally.
- Audit camera framing at every table height so the active shot, ball, and nearest flippers remain
  legible; earned upper districts should feel revealed, not merely zoomed out.

### 4.7 Gameplay feedback, banners, subtitles, and transitions

**Intent:** feedback intensifies play without becoming a second HUD.

- Create four feedback levels: micro hit, reward, consequence, and ceremony. Lock size, duration,
  position, sound, haptic, and motion rules for each.
- Anchor hit and reward feedback to the source while keeping the amount readable. Currency flights
  should finish at the exact HUD value they update.
- Replace generic center banners with scene-aware placements. Critical ceremony may briefly own the
  center; ordinary status may not.
- Keep subtitles low and quiet but above persistent actions. They must never masquerade as a toast
  or obscure Ledger cards/Count values.
- Give speakers a consistent nameplate treatment and sentence-case captions.
- Ensure reduced motion and reduced flash preserve hierarchy, causality, and timing information.

### 4.8 The Count

**Intent:** a satisfying end-of-Night ritual that is readable before it is theatrical.

- Treat the central sheet as opaque adding-machine paper with a stable content column. Let the room
  art frame it rather than show through it.
- Fix the masthead composition so `THE COUNT`, night, rank, and tally indicator never overlap.
- Replace long labeled bars with aligned receipt rows: label, optional annotation, and one strong
  mechanical value window. Dirty, washed, clean, Respect, and jobs should scan vertically.
- Reveal one row at a time, but reserve final positions from frame one so the layout does not jump.
- Make the newspaper headline a torn clipping with publication/date/kicker hierarchy, not a plain
  bordered textarea.
- Separate `Tonight's Crew` from `In Holding`; give bail/walk-time actions adequate width and a
  clear affordability state.
- Convert tutorial notes and specialist remarks into margin annotations or a dedicated caption
  lane instead of center-screen overlays.
- Use a fixed two-action footer (`Ledger`, `Next Night`) and place `House Rules` as a quiet tertiary
  action. The scroll body must end above it.
- Apply the same structure to boss calls, war room, heist, safe collection, club, federal, and
  endgame variants. Each variant gets one hero module; shared tally/roster/footer remain stable.

### 4.9 Ledger board

**Intent:** a tactile strategic centerpiece that works at phone scale.

- Compress the header into a branded title/wallet strip plus page switch. Use neutral navigation
  colors; Black Book rose is an accent inside the page, not the generic tab fill.
- Design a phone-native board viewport. Default framing must show one complete decision cluster with
  readable cards; empty cork should never dominate the opening frame.
- Increase card size and simplify face content to title, branch, state, and cost. Put long effect
  text and comparisons in the Docket.
- Make lines/string quieter than cards, and show locked dependencies through shape/style as well as
  opacity.
- Replace `ZOOM` with a clear fit/focus control and make `NEXT BUY` the single floating action.
  Panning/zoom instructions appear once, contextually.
- Dock the selected-card Docket to the lower safe area. It may never cover the selected card and must
  support compare, buy, and close states without a second modal.
- Distinguish hidden, revealed, affordable, unaffordable, selected, purchased, and newly unlocked
  states using material, pin, stamp, and icon—not color alone.

### 4.10 Black Book

**Intent:** a prestigious permanent collection, visibly distinct from the career corkboard.

- Use a leather dossier/book material, restrained rose accents, and chapter-like perk groups.
- Make Juice, owned perks, available perks, and boss spoils a clear top-to-bottom hierarchy.
- Present trophies/spoils as collectible evidence with silhouettes and reveal states, not more
  Ledger cards.
- Keep purchase comparison and confirmation consistent with the Ledger Docket.

### 4.11 Store-facing visuals

**Intent:** the icon and store graphic promise exactly the visual quality in the build.

- Revisit the launcher/adaptive icon after the in-game lockup and color system are final.
- Rebuild the feature graphic from final in-game materials and typography.
- Capture store screenshots only from accepted device states; use captions outside gameplay,
  never fake UI inside it.

## 5. Copy pass

Run one dedicated content pass after layouts stabilize:

- Build a vocabulary sheet for job, crew, Night, money, Heat, rank, table modes, and meta actions.
- Give each screen one headline, one explanatory layer, and one action vocabulary.
- Remove repeated state words (`selected`, `serve`, `night`) when position or component state already
  communicates them.
- Shorten live instructions to verb-first phrases. Put flavor on the second line only when space
  allows.
- Review every empty, locked, unaffordable, offline, error, and destructive-confirmation state.
- Read all copy at 486×864 with large-text simulation; revise wording before shrinking type.

## 6. Recommended implementation order

### Phase A — Design lock and component gallery

Create final tokens, typography specimens, component states, and three representative compositions:
Attract, Night HUD, and Count. Do not roll the system across the app until these establish the bar.

**Exit:** art-direction sign-off on still captures at compact and standard phone sizes.

### Phase B — Core journey

Implement Attract, House Rules, Roll Call, Night HUD/coach, Count, Ledger, and return flow using the
new primitives.

**Exit:** the first-Night device journey has no clipping, placeholder styling, duplicate hierarchy,
or obstructive overlays.

### Phase C — Table visual language

Polish Rank 0 first, then every earned hardware family and the full expanded table. Add state/lamp
matrices before adding more prop art.

**Exit:** every rank reads at phone scale in idle and active states; grayscale and reduced-effects
captures remain playable.

### Phase D — Long-tail states

Polish Count variants, all HUD mode states, boss/raid/casino/heist/federal feedback, Docket, Black
Book, Credits, Safe collection, settings confirmations, and error/empty/locked states.

**Exit:** changed screen families have representative screenshots and passing interaction checks.

### Phase E — Final shine and release visuals

Tune motion, haptics, audio/visual synchronization, textures, final copy, icon, feature graphic, and
store screenshots. Complete the draw-call optimization already identified in Phase 4.

**Exit:** final art review, accessibility review, min-spec performance gate, and release capture set.

## 7. Capture matrix — reference for broad visual and release reviews

Use these states to select relevant coverage for the change:

| Surface | Required states |
|---|---|
| Attract | new career, resumed career, Safe pending, reduced motion |
| House Rules | default, toggles mixed, scrolled Beta section, destructive confirmation |
| Credits | top, mid-scroll, bottom |
| Roll Call | empty order, partial order, full order, holding guy, specialists |
| Night HUD | Rank 0, dense late rank, max Heat, high Respect, long money values |
| Coach | launch, flip, earned confirmation |
| Playfield | each career rank, each active shot state, multiball, tilted, raid |
| Feedback | hit, dirty, clean, washed, combo, drain, bail, jackpot, boss, rank-up |
| Count | tally start, tally end, headline, holding/bail, each special variant |
| Ledger | overview, focused cluster, selected Docket, purchase, newly unlocked, locked |
| Black Book | empty, affordable, purchased, trophies/spoils, insufficient Juice |
| Subtitles/toasts | Count, Ledger, live table, collision with footer avoided |
| Transitions | every screen pair, normal and reduced motion |

Start with a representative phone size and the state most likely to expose the change's
failure mode. For shared-layout changes or release review, expand coverage using:

- 486×864 with the existing asymmetric insets and rounded-corner guard;
- 1080×1920 baseline portrait;
- one narrow device and one extra-tall device;
- default, large-text, reduced-motion, reduced-flash, and grayscale/color-blind review modes where
  relevant.

## 8. Acceptance gates

### Visual and content

- No clipped, overlapping, orphaned, or ellipsized core copy.
- One primary action per decision state; destructive actions cannot look primary by default.
- No raw/default Godot control styling in player-facing screens.
- No duplicated palette/type/layout definitions outside the theme and approved component modules.
- No reserved semantic color used decoratively or as a generic selection/navigation state.
- Body copy remains readable over every background; decorative art never reduces required contrast.
- A five-second glance test identifies location, current objective, and available action.

### Interaction and accessibility

- Every control meets the existing 96-logical-pixel touch contract or an explicitly approved compact
  control pattern with an equivalent hit area.
- Safe-area, focus, pressed, disabled, selected, loading, error, and confirmation states are tested.
- Information survives reduced motion, reduced flash, haptics off, subtitles off/on, and grayscale.
- Scroll positions, fixed footers, keyboards/controllers, and interrupted transitions do not trap
  focus or hide actions.

### Performance and engineering

- Physics, economy, save, and input contracts remain unchanged.
- No missing-art failure; procedural fallback remains valid where required.
- The 120 draw-call min-spec target is met in representative dense-table captures.
- 60 fps frame pacing is verified during dense table play and the strongest ceremonies.
- Relevant checks pass: `tools/check.sh` for routine code edits, affected simulations for
  gameplay changes, and `tools/ship.sh` for a release. Device checks cover changed interactions.

## 9. Review cadence

For a changed screen family:

1. Identify the concrete usability or visual problem and implement the change.
2. Inspect the result at a representative phone size plus the relevant stress state.
3. Run checks affected by the change; expand coverage only for an unresolved concern.

Stop when the scoped acceptance criteria pass. Keep useful evidence of the result without
requiring a separate report, review round, or exhaustive capture matrix for every edit.
