# 10 — Roadmap

> **PAROLE HEARING** — *"And what will you do upon release?" — "Milestones, your honor.
> Small, testable milestones."*

Solo-dev/small-team assumptions; durations are effort-relative, not calendar promises.
Each milestone ends in a **playable build with a kill-question** — the thing that must be true
or we change course before building more.

---

## M0 — "The Feel" (2–3 weeks)

Bare table: flippers, plunger, one bumper, slings, drain, nudge, tilt. 120Hz physics, camera,
haptics, real sampled flipper/bumper sounds. No economy — a debug dollar counter.

**Kill-question:** do testers voluntarily keep flipping for 5+ minutes with *zero*
progression? If the toy isn't fun naked, nothing downstream saves it.

## M1 — "The Hook" (4–6 weeks)

R0→R3 content: growing table (alley→block segments), dirty/clean + laundromat loop, The Count,
Nights & the Bench v1 (names, pinch, bail — no traits yet), first ~25 Ledger nodes on corkboard
v1, Jobs v1, Heat v1 + first Raid, idle Safe, save system, stem stack layers 1–4.
**The goosebump gate** ([08-AUDIO](08-AUDIO.md) §1) lives here.

**Kill-question:** D1 retention instinct-check with ~10 outside testers — do they come back
*unprompted*? Does "dirty cash you can't spend yet" read within 2 minutes without a tutorial
wall?

## M2 — "The Empire" (6–8 weeks)

R4–R5: the Club deck (casino games, Casino Wash, Family Meeting 2-ball), the Docks + smuggling,
Heists 1–3, specialists 1–6, guy traits, Collection Rounds, the Wire, briefcases, bosses 1–2,
Ledger to ~80 nodes, corkboard face-down reveal system, newspaper generator.

**Kill-question:** does the mid-game *decision triangle* (earn/wash/risk) show up in tester
behavior — do different players run visibly different builds and defend them?

## M3 — "The Fall & The Rise" (5–7 weeks)

R6–R7: Penthouse, Commission chairs, bosses 3–5, Elections, Federal Heat + RICO raid, Empire
Mode, 5-ball Reunion, The Rat arc, Skip Town + Juice + Black Book, city 2 (New Carthage,
booze-crate rule, 1927 stem re-arrangement), full Ledger (~130).

**Kill-question:** does the first Skip Town feel like a *victory lap decision* rather than a
loss? (Watch faces during the stem-shedding sequence.)

## M4 — "The Shine" (4–6 weeks)

Sensory-overload polish pass against budget ([09-TECH](09-TECH.md) §8), cities 3–5 (remixes are
cheap by construction), balance CI green across all tuning targets, accessibility pass
(reduced-flash, subtitles, haptic substitutes), Play Games services, onboarding polish (first
90 seconds rehearsed like a demo), credits ("The Usual Suspects"), store assets.

## M5 — "The Opening" (2–4 weeks)

Closed beta (Play early access track), telemetry-lite funnel review, tuning hotfix loop, ASO
basics, launch. Post-launch backlog seeded: Sixth Family gauntlet, weekly "Biggest Night"
board, seasonal table dressing, v2.0 "RETIREMENT" card mystery.

---

## MVP definition (the smallest thing that proves the game)

M0 + M1 **is** the MVP: the naked toy plus the hook loop (grow table R0→R3, launder, Count,
Bench, first Raid). Everything after is compounding content on proven bones.

## Biggest risks, ranked

1. **Physics feel on touchscreens** — mitigated by M0-first and the golden-replay harness.
2. **Economy readability** (dirty vs clean confusing early) — mitigated by reserved colors,
   Pocket Money grace, M1 kill-question.
3. **Open-source music coherence** — mitigated by the three-route sourcing strategy and the
   goosebump gate; worst case, music is the one commissioned line item.
4. **Scope** (this doc set is ambitious) — mitigated by the segment/data-driven architecture:
   every zone, boss, job, and city is content on fixed rails, cuttable without surgery. The
   cut-line order is pre-agreed: city 5 → city 4 → Elections → The Rat → heists 4–5 → Fight
   Night. Core loop and Club deck are never cut.
