# 03 — Economy

> **IRS FIELD NOTE** — *"Subject's laundromat claims to wash 40,000 shirts per minute.
> Agent unable to disprove; machines very loud."*

Five interlocking currencies. Design intent per currency, then flows, formulas, and tuning
targets. Numbers here are opening bids for the balance sim ([09-TECH](09-TECH.md) §7), not
gospel.

---

## 1. Currency overview

| Currency | Icon | Earned by | Spent on | Resets on prestige? |
|----------|------|-----------|----------|---------------------|
| **Dirty Cash** | red-banded bills | ALL table scoring, rackets' idle income, raids won | Bail, bribes, casino bets, Pawn shop, loan interest | Yes (confiscated — fed into Juice calc) |
| **Clean Cash** | green bills | Laundering dirty (loops, casino wins, fronts), Heists, bonds | **The Ledger — every permanent upgrade** | Yes (converted to Juice) |
| **Respect ☆** | brass star | Jobs, skill shots, ×3+ combos, bosses, raid survivals — **never purchasable** | Nothing — it's a threshold ladder (ranks, some milestone gates) | Yes (partly banked in Juice) |
| **Heat 🔥** | thermometer 0–100(+) | Earning fast, loud rackets, heists, leaning on cops | (anti-currency; reduced by bribes/lawyer/laying low) | Yes (fresh city, cold trail) |
| **Juice** | gold pinky ring | Skipping Town (prestige) | Black Book permanent perks | **Never** |

**The core tension:** the table pays in dirty. The Ledger only takes clean. The conversion is a
*gameplay act* — shots, bets, and businesses — not a menu. Every second of play, the player is
choosing between **earn** (dirty faucets), **wash** (conversion shots), and **risk** (casino,
Heat surfing). That triangle is the strategy layer.

## 2. Dirty → Clean: the laundering pipeline

Ordered by lifecycle. Each method is worse than the next tier, so progression keeps re-solving
the same problem more elegantly (a career criminal's actual arc):

| Tier | Method | Rate / cap | Notes |
|------|--------|------------|-------|
| v0 | **Pocket Money** | auto-cleans first $400/Night | R0 grace so the first upgrades flow; fades in relevance |
| v1 | **Laundromat loop** | each pass washes 8% of held dirty, cap/Night scales with upgrades | The teaching feature: aim = income |
| v1.5 | **Front businesses** (Pizzeria, Pawn, later others) | passive: each washes X/s while its bank is armed | Idle laundering; upgradeable |
| v2 | **The Casino** | bet dirty at the tables; **winnings pay out clean** | House edge starts 8%, Influence upgrades push it to player-favored 4% — the only "positive EV laundry" and it's variance city |
| v3 | **Heists** | loot fences directly to clean | Skill-gated lump sums ([05](05-MODES-AND-EVENTS.md) §5) |
| v4 | **The Long Con** (bonds) | lock clean for 3 Nights → +35–60% | Late-game idle finance; can be "made" (guaranteed) via Black Book |
| v5 | **City Hall** | Empire Mode pays clean directly | You ARE the wash at this point |

Uncapped hoarding of dirty is allowed but dangerous: **held dirty is what raids confiscate**,
and past a threshold it passively generates Heat ("you're flashing it"). Big greasy stacks are
a choice with a blade over them.

## 3. Chance, priced honestly (P2)

All gambling features expose their odds in-fiction (the tote board shows payout lines; the
roulette rim is honest). Behind the scenes:

- **Casino games** use real odds with a visible house edge; **Influence upgrades buy edge
  points**, never scripted wins. Pity system: the *Cooler* rule — after 5 consecutive casino
  losses, the next win pays +50% (framed as "the cooler got fired").
- **The Wire** (numbers draw): base hit odds 1-in-10 on "last digit" tickets (pays ×6 dirty),
  1-in-100 exact (pays ×80, clean!). The spinner sets your ticket, so play sets the entry.
- **Mystery Briefcases**: 70% dirty wad / 20% temporary boon / 10% *setup* (Heat +15, a cop
  target spawns). Pawn-shop upgrade re-weights to 75/20/5. Setup can't fire twice in a row.
- **Raid trigger** at Heat 100 is deterministic; *when* Heat crosses is the player's throttle.

Rule: **randomness may swing a Night by ±30%; builds and skill swing it by ×20.**

## 4. Heat 🔥

One dial that makes success dangerous — the "edge of the seat" machine.

**Gains:** +1 per $2K dirty earned within 10s at R0, threshold ×3.5 per rank *(sim-tuned;
the original $50K/×10 placeholder left heat permanently dead)*; +5–15 per
loud act (smuggling run, briefcase setup, failed heist step); loud guys/rackets add %.
**Decay:** −0.5/s while playing calm (nothing loud for 8s); −10/Night laying low (skip a
Night's rackets = "close up shop", an actual strategic idle choice); Lawyer retainer improves both.
**Spends:** Beat Cop bribe shot (−20, costs dirty, the cost climbs each use per Night);
Sit-Down freeze (Penthouse).

**Effects while hot:**

| Heat | Multiplier on ALL dirty | Table effects |
|------|------------------------|----------------|
| 0–39 | ×1.0 | quiet |
| 40–69 | ×1.5 | patrol car crosses rear lanes (blocks orbits occasionally) |
| 70–89 | ×2.5 | + spotlight sweep: ball caught = Inspector suspicion +1 |
| 90–99 | ×4.0 | + paddy wagon parks over ONE outlane kickback (disables it); sirens in the mix |
| 100 | **RAID** | see [05](05-MODES-AND-EVENTS.md) §2 |

That ×4 band is deliberately irresistible. Surviving at 90+ is the highest-skill, highest-
tension play in the game — and the music knows it ([08-AUDIO](08-AUDIO.md) §4).

**Federal Heat (R7):** the meter grows a second, blue stage (100–200) with FBI mechanics —
wiretap vans, subpoena targets, and the RICO raid — detailed in [05](05-MODES-AND-EVENTS.md) §9.

## 5. Respect ☆

The skill spine. Sources (per Night, roughly): clean Drop-Off ☆1 · combo ×3 ☆2 and ×6 ☆5,
**first time each per Night** *(sim-tuned: per-chain ☆ made combos 95%+ of all Respect)* ·
Job completed ☆5–50 · Collection Round perfect ☆10 · boss beaten ☆100–400 · raid survived ☆25 ·
heist clean exit ☆40. **No purchase, no idle source, no conversion.** Rank thresholds in
[02](02-TABLE-AND-CAREER.md) §1. Excess ☆ beyond R7 banks into the Juice formula.

## 6. The idle layer

- Each owned racket has an income rate (dirty/s) that ticks **during play and away**.
- Away earnings accrue into **the Safe**: base cap 2h of income; safe upgrades → 4/8/12/24h.
  Collecting the Safe is the session-open ritual (bag-drop sound, count-up).
- **Pinball is the multiplier**: storefront "collections" instantly cash N minutes of that
  racket's rate (skill converts idle-time into now-money); Empire/modes multiply rates live.
- Crew specialists automate slices (auto-launder %, auto-collect) — never 100%: automation
  approaches but never reaches the skilled-play ceiling (target: full-idle earns ≤10%/h of an
  active hour; see P5 — check-ins are rewarded, grinding isn't required).

## 7. Growth curve & big numbers

- Value scale per rank: ~×3–4 measured, delivered **entirely by Ledger multipliers and
  new-tier content — never by an automatic rank multiplier** (sim finding: a single
  rank-scaled payout drowned the whole economy; `rank_scale` is a heat/bail normalizer
  only). Lifetime growth to the big numbers comes from tier stacking across 8 ranks ×
  5 cities. Numbers use short-scale suffixes ($1.2M, $3.4B, $7.7T) with mantissa+exponent
  arithmetic ([09-TECH](09-TECH.md) §6). Lifetime clean by first Skip Town: ~$5–20B.
- Upgrade cost bands per tier: T0 $50–500 · T1 1–10k · T2 10–100k · T3 0.1–1M · T4 1–20M ·
  T5 20–500M · T6 0.5–6B · T7 6B–120B *(T6/T7 sim-derived: 0.5–7 days of decent-profile
  clean income at the gating rank)*. Repeatables cost `base × 1.15^level` (classic
  incremental curve); one-offs sit at band edges.
- Newspaper headlines lampshade the absurdity on schedule ("LOCAL ECONOMY NOW 60% PINBALL").

## 8. Sinks (why money stays scarce at every stage)

Bail (scales with guy level & rap sheet) · bribes (per-Night escalating) · casino stakes ·
loan interest (Juice Loans skim 20% of earnings for 30s after a borrowed ball) · Pawn shop
consumables · bond lockups (liquidity sink) · Commission tributes (optional pre-boss softener)
· and the Ledger itself, whose T6–T7 one-offs are deliberately monstrous.

## 9. Tuning targets (day-one bid; autoplayer-verified)

| Metric | Target |
|--------|--------|
| First upgrade bought | at the first Count, ≤ 5 min in *(clean cash only exists from the pocket-money wash at a Count — "90 s into Night 1" was unreachable by construction)* |
| Time-to-R1 / R3 / R4 | 15 min / day 1 / day 2–3 |
| Median Night length | 3–8 min (R-scaled) |
| Active vs. pure-idle earn rate | ≥ ×10 |
| Skilled vs. unskilled active earn | ≈ ×6 (endgame ×20 incl. Empire uptime) |
| First prestige | day 3–5 |
| Second city cleared | ~2× faster than first |
| Session opens per day (healthy) | 2–4, driven by Safe cap — never by decay/punishment |
| Heat liveliness *(added by sim)* | ≥ 10% of live play above band 0 once R3+ |
| Casino EV at max Influence *(added by sim)* | +2% to +5%, monotone per purchase — variance is the product, never expectation |
