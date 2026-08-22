# SPEC — M2 content design (casino rules, specialists, T4–T5, bosses)

Design-owned. Feeds META-2 and BOSS-1 (sub-wave 2) and the content JSON I author after the
balance sim's first report. Numbers are opening bids, sim-tunable; RULES are design.

## 1. Casino games (the Club deck economy)

One bet vehicle, one multiplier vehicle, one grind vehicle — legible under pressure (P4):

- **Roulette (the bet).** Entering the deck arms "table stakes": each `roulette_landed`
  resolves an auto-bet of `min(held_dirty × STAKE_FRACTION, stake_cap)`. Player pockets
  (5 of 8) pay `PAYOUT×` the stake **in clean** (the Casino Wash — the house launders for
  you); house pockets (3) take the stake. Knobs (data): `STAKE_FRACTION` 5%,
  `PAYOUT` 1.48 (≈ −7.5% EV baseline), stake_cap scales with rank. **Influence buys pocket
  count and payout, never outcomes**: Loaded Dice ↻ converts one house pocket to player at
  max level and nudges PAYOUT toward 1.55 (≈ +4% player EV at full investment — the only
  positive-EV laundry in the game, paid for in variance and Ledger money, per docs/03 §3).
  The Cooler pity rule: 5 consecutive losing spins → next win +50% (upgradeable +100%).
- **High Roller saucer (the multiplier).** Hold = your NEXT casino payout ×2/×3/×5; each
  step adds Heat (+3/+6/+12). Auto-eject at ×5. Skill = choosing when greed stops.
- **Slots (the grind).** Drop-target grid pays flat `casino`-group values; clearing all 3
  columns in one deck visit = **Jackpot**: pays `JACKPOT_MINUTES` (8) of total idle rate,
  clean. Re-arm next deck visit.

Heat interplay: casino wins do NOT feed the heat window (it's the wash, not hot money) —
but High Roller holds and Jackpots add flat Heat. The deck is where you go to cool the
wallet and warm the meter.

## 2. Specialists (CREW branch becomes people)

A specialist = a crew-branch node (hire cost + a Job requirement) + repeatable level-ups ↻.
Powers hook via NEW effects vocabulary (meta lane extends Stats; core hooks orchestrator-
approved):

| kind | consumer |
|------|----------|
| `heat_decay_mult` / `bail_discount` | flow (Cohen) |
| `auto_collect_interval` | flow: Manny auto-collects one lit award per N s (visible run) |
| `casino_edge_add` | flow casino logic (Eddie Odds) |
| `job_reroll_add` / `job_respect_mult` | flow jobs (Consigliere) |
| `serve_speed_mult` | table ball service (Skids) |
| `auto_launder_per_sec` | flow (Nussbaum — distinct from storefront passive wash) |
| `kickback_cooldown_mult` | table (Big Sal, + at L5 unlocks right kickback) |
| `aim_line` | core Case-the-Joint ghost line (Professor) — orchestrator patch |
| `all_dirty_mult` | Stats value fold (Rosa) |

M2 hires: Skids (T1 retrofit), Nussbaum (T2), Big Sal (T2), Professor (T3), Rosa (T3),
Cohen (T4), Manny (T4), Eddie Odds (T5), Consigliere (T5). Each gets a portrait slot,
an instrument voice (audio wave 3), and one Count-screen one-liner pool (writing: mine).

## 3. T4–T5 Ledger additions (~24 nodes; JSON authored post-sim-report)

**T4 (R4 gate, 1–20M):** RACKETS club_license (unlocks `club_deck`+`staircase_ramp`+idle),
house_rake ↻ (casino idle +30%), vending_racket (bumpers drop briefcase tokens);
FRONTS ★casino_wash (REQUIRED for clean payouts — until bought, casino wins pay dirty!),
high_roller (unlocks saucer), comps (1 free stake/Night); MUSCLE second_set (unlocks
`club_flippers`), steel_balls (ball tier 2: +12% all values), right_hand_man (right
kickback); CREW cohen, manny; INFLUENCE loaded_dice ↻, coolers_fired, inspector_vacation
(lit target → 20s free nudging).

**T5 (R5 gate, 20–500M; docks nodes deferred to M3 with the geometry):** CREW eddie_odds,
consigliere; MUSCLE wrecking_crew ↻ (bumper/sling power +8%/lvl — faster ball, riskier),
insurance_policy (TILT → guy limps at half value 10s instead of pinch); INFLUENCE
police_scanner (10s pre-warning of heat-tier hardware), ★rain_insurance (once/Night negate
raid confiscation), wiretap_wire (see next Wire number 15s early). RACKETS ★fight_night
moves to M3 (needs mature multiball betting UI — deliberate cut, docs/10 cut-line).

## 4. Family Meeting (2-ball multiball, FLOW-2 + BallRegistry)

Start: `backroom_entered` with `club_deck` owned and meeting lit (lights after 2 Jackpots
or a completed Collection Round — re-lights each Night). Rules: second guy joins the table
(named ball!), 8s grace ball-save on both; while 2 balls live, ALL dirty ×2 and the
backroom re-entry pays a growing Meeting Jackpot (clean); ends when one ball remains.
Camera zooms out one step during multiball (feel spec'd in M0 docs). Bench note: the
second ball is a real guy from the roster — if he drains he is pinched like anyone (the
crew out together, docs/01 §4).

## 5. Commission bosses (BOSS-1 lane)

Shared frame: triggered from the Count ("SAMMY'S WAITING" button) once rank respect is met
+ story job done; the fight replaces the next Night; economy paused (earn_switch suppressed;
victory pays a fixed clean purse × rank scale); no timer — pressure is mechanical; loss =
retry next Night, no penalty beyond the Night; victory = rank-up ceremony + spoil + front
page.

**Sammy Two-Flippers (gates R3→R4).**
P1: his sedan crosses the upper field on a rail — hit it 4× while every 8s a wrench gag
telegraphs (2s) then JAMS one flipper for 1.5s (input eaten, bat droops — play around it).
P2: three goon standups armor the bumpers (bumpers pay 0 until goons down).
P3: sedan parks center, 3 hits to win; jam cadence accelerates to 5s.
Spoil `sammys_spare`: once per Night, instant self-unjam + 1 free Lean (also converts
future flipper-jam effects to 0.5s).

**The Butcher (gates R4→R5).**
P1: refrigerated truck circles the orbit path; only orbit-speed hits count (3×) — teaches
the Getaway Loop as a weapon; meanwhile bumpers are "cold storage" armored (pay 0, store
value: every would-be payout banks into a visible frozen meter).
P2: truck door = a 2×3 drop bank, break it twice.
P3: bumper frenzy 25s — armor off, bumpers pay the ENTIRE frozen meter split across hits,
×2 if the player lit all three rollovers during P1–P2 (hidden depth for repeat fights).
Spoil `cold_storage`: permanently, disabled/armored bumpers bank 50% of denied value and
pay out when re-enabled.

## 6. Count-screen specialist one-liners & club headlines

Writing added to headlines.json at content-authoring time: club/casino conditions
("CASINO REPORTS GUESTS 'UNUSUALLY LUCKY', HIRES PRIEST"), boss-victory front pages, and a
`specialist_quips` table (subtitled muted-brass, docs/08 §5).
