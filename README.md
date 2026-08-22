# KINGPIN — A Pinball Racket

> *"They said pinball was a game of chance. So we fixed it."*

**KINGPIN** (working title) is a premium mobile pinball game crossed with a deep incremental/idle
progression game, wrapped in a stylish mob-movie satire. Every point you score is money — dirty
money — and every dollar you spend physically builds your criminal empire **onto the table
itself**. You start flipping a bare-bones machine in a back alley; hundreds of upgrades later
you're running a five-ball Family Reunion multiball across a three-story neon city while the
Feds kick the door in.

**Platform:** Android first (portrait, one-handed thumbs). **Engine:** Godot 4 (proposed).
**Assets:** real sampled sounds and open-licensed art, sourced and credited.

---

## The pitch in five lines

1. **Points are money.** There is no abstract "score" — every bumper hit is cash skimmed. But it's *dirty* cash, and you must **launder it through shots on the table** before you can spend it.
2. **The table is your career.** Each career rank physically *grows the playfield*: new districts bolt on, the table gets taller, the city gets louder. Bottom of the table = the gutter. Top of the table = the penthouse. You climb it with a steel ball.
3. **Balls are your guys.** Draining doesn't "lose a ball" — your guy gets *pinched*. Bail him out, or send in the next man. Your bench of named goons is a roster you build, level, and mourn.
4. **Chance decides what happens; skill decides how it turns out.** Casinos, numbers rackets, mystery briefcases, and police raids keep you on edge — but every random event resolves through shots you aim and flips you time.
5. **A maxed table is a sensory overload that stays readable.** Music grows one instrument per racket you own. Every sound is a stat. Every light is information. Chaos you can sight-read is the whole point of pinball — we scale it to eleven.

---

## Document map (read in order)

| # | Document | What's inside |
|---|----------|---------------|
| 00 | [Vision & Pillars](docs/00-VISION.md) | Fantasy, design pillars, tone, audience, the core loop diagram |
| 01 | [Core Gameplay](docs/01-CORE-GAMEPLAY.md) | Pinball feel, controls, skill systems, Nights & The Count, the Bench (balls-as-guys), tilt as "The Inspector" |
| 02 | [The Table & The Career](docs/02-TABLE-AND-CAREER.md) | The growing table, all 8 career ranks, zone-by-zone layouts |
| 03 | [Economy](docs/03-ECONOMY.md) | Dirty vs. clean cash, laundering, Respect, Heat, Juice, formulas & tuning targets |
| 04 | [The Upgrade Tree](docs/04-UPGRADE-TREE.md) | The Ledger: 6 branches, 8 tiers, 120+ upgrades, milestone loop-changers |
| 05 | [Modes & Events](docs/05-MODES-AND-EVENTS.md) | Jobs, Heists, Raids, the Casino, Commission bosses, Elections, mystery events |
| 06 | [Prestige & Cities](docs/06-PRESTIGE-AND-CITIES.md) | Skip Town, the Black Book, five cities across five eras |
| 07 | [Art Direction](docs/07-ART-DIRECTION.md) | Noir-deco style, the corkboard UI, palette, type, open-source art pipeline |
| 08 | [Audio](docs/08-AUDIO.md) | Layered live-band soundtrack, "every sound is a stat", muted-trumpet voices, sample sourcing |
| 09 | [Tech](docs/09-TECH.md) | Engine choice, physics, modular table architecture, save system, performance budget |
| 10 | [Roadmap](docs/10-ROADMAP.md) | Milestones M0–M5, MVP cut, what we prove first |
| 11 | [Open Questions](docs/11-OPEN-QUESTIONS.md) | Decisions I want your call on, plus proposed alterations |

---

## Glossary (the family vocabulary)

| Term | Meaning |
|------|---------|
| **Night** | One play session with your current bench (classic "3 balls" = 3 guys sent out) |
| **The Count** | End-of-Night tally screen — the counting room |
| **Guy** | A ball. A named goon from your Bench. Draining = he gets *pinched* |
| **The Bench** | Your roster of guys (ball inventory with names & traits) |
| **Pinched** | Drained. The guy is in holding — post bail or wait out his stretch |
| **Dirty / Clean** | The two cash currencies. Dirty earns fast, spends narrow. Clean buys upgrades |
| **Respect (☆)** | Skill-earned rank currency. Cannot be bought. Gates career tiers |
| **Heat (🔥)** | Risk meter. High heat = higher multipliers *and* police on the table |
| **The Inspector** | The tilt mechanic. Bribe him for more nudge allowance |
| **Lean** | A nudge (tap table edge / flick device) |
| **The Ledger** | The upgrade UI — a corkboard conspiracy map over a city map |
| **Juice** | Prestige currency (gold pinky ring). Earned by Skipping Town |
| **Skip Town** | Prestige: new city, new era, table resets, Black Book perks persist |
| **The Commission** | Rank-up boss encounters against rival families |

---

*All design docs are drafts for discussion. Nothing here is sacred except the drain.*
