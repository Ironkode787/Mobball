# 06 — Prestige & Cities

> **WITNESS RELOCATION FORM 12-B** — *Name: [REDACTED]. New identity: [REDACTED].
> Requested personal item: "the ball. just the ball."*

---

## 1. Skip Town (the prestige act)

Available from R7 (or offered early after a failed RICO raid — never forced). The framing:
the Feds finally have you… or they would, if you weren't already gone. A quiet cutscene made
of table parts: lights shut off zone by zone (the music sheds stems one at a time, the reverse
of the whole game — a genuinely melancholy beat), one guy carries a suitcase up the launch
lane, and the screen stamps **CASE CLOSED**. Then a train window. A new city skyline. A new
bare table, lit by one bulb.

**You keep:** Juice (computed below), the Black Book, Museum relics, boss signature spoils
(as unlockable-again "old friends" — see §5), cosmetics, and your rap-sheet stats.
**You lose:** cash (both colors), the table, ranks/Respect, specialists (unless Black-Booked),
the Bench (except one — you may name **one guy** who "comes with you"; players will agonize
over this and that is the point).

## 2. Juice (prestige currency)

`Juice = floor( sqrt(lifetime_clean / 1e9) ) + bosses_beaten + heists_cleared + raids_survived + floor(excess_respect / 500)`

The sqrt on wealth keeps grinding sane (doubling wealth ≠ doubling Juice); the flat adds reward
*doing things* over pure farming. First Skip Town target: 8–15 Juice. A completed city on a
later loop: 25–60.

## 3. The Black Book (permanent tree, spends Juice)

| Cost | Perk | Notes |
|-----:|------|-------|
| 1 | **Old Contacts** ↻ | start each city at +1 rank (max R3 start) |
| 1 | **Kept Man** ↻ | one chosen specialist survives Skip Town (slot per level) |
| 2 | **Traveling Light** | Pocket Money auto-clean scales with city # |
| 2 | **Reputation Precedes You** | first Commission boss of each city starts at phase 2 |
| 3 | **The Stash** | begin each city with 5% of previous city's clean cash (dirty, ha) |
| 3 | **Everybody Knows Somebody** | Bench starts with 2 leveled guys |
| 5 | **★ Double Life** | previous city's idle income keeps flowing at 10% (stacking cities = the empire never really resets) |
| 5 | **★ The Big Sleep** ↻ | retire a maxed specialist forever → he becomes a **patron-saint statue** on all future tables: a small aura zone with his power at half strength, always on. The roster of saints grows across prestiges — your history literally watches over the table |
| 8 | **★ Museum of Crime** | unlocks the relic gallery: heist relics socket into set bonuses (3 Museum pieces = permanent +1 casino edge, etc.) |
| 8 | **Fast Learner** | ☆ requirements −20% in cities you've beaten before |
| 10 | **★ The Golden Era** | unlock the Golden Ball tier in every city at T5 instead of T7 |
| 15 | **★ Silent Empire** | offline Safe cap doubles AND fills with 10% clean directly |
| 25 | **★ The Sixth Family** | New Game++: all five cities' Commissions rolled into one repeatable gauntlet table (post-launch content hook) |

## 4. The cities (five launches, five eras, five rule-twists)

Each city = a table reskin + zone remix + **one signature rule** that bends the strategy
without invalidating skills. Cities unlock in order; later loops choose freely (order becomes a
build decision). Era shifts also re-skin music (same stems concept, new arrangements — see
[08-AUDIO](08-AUDIO.md) §7) and newspaper mastheads.

| # | City & era | Look | Signature rule | Remix highlights |
|---|-----------|------|----------------|------------------|
| 1 | **Eastport, 1972** (launch city) | brick, neon, rain | — (the baseline) | as designed in [02](02-TABLE-AND-CAREER.md) |
| 2 | **New Carthage, 1927** — Prohibition | sepia, speakeasies, jazz age | **Cash is booze.** Dirty cash physically exists as crates on the field; raids SMASH crates present on the table (get them to the drop-off truck = banked). Laundering = "the pharmacy prescription" | spinner is a ceiling fan; the Club is a speakeasy behind a bookcase (hidden until knocked) |
| 3 | **Costa Verde, 1984** — neon Miami | pastel, chrome, palms, synthwave stems | **Two drains.** A center drain splits the flippers wider (real pinball nightmare geometry)… but smuggling pays triple and the Docks are half the table | airboat kickback; cigarette-boat truck route; Heat hardware is a helicopter spotlight |
| 4 | **Silver Gulch, 1899** — frontier | wood, brass, oil lamps | **No electricity.** Lights are oil lamps that must be LIT by shots (features pay nothing until their lamp is lit each Night) — a lamplighter route optimization layer | the Wire is the telegraph; raids are the Pinkertons; casino is a riverboat mini-field |
| 5 | **Neon City, 1999** — Vegas turned up | the sensory-overload city | **The whole table is the casino.** Every feature has a jackpot state; variance everywhere; the Wire draws every 30s; house edge applies to BUMPERS (they pay 0 sometimes, ×10 sometimes) | Empire Mode is the default state you fight to MAINTAIN; final city, maximum spectacle |

City 2 or 3 should land inside week one for an engaged player — era shift is the retention
"whoa" after the Club deck.

## 5. Old friends & momentum

On later loops, absorbed boss spoils reappear as **"old friend" side-jobs** (find Sammy in the
new city, do his favor, re-earn the spare flipper early). This converts prestige repetition
into a reunion tour instead of a re-grind, and gives the writing room its best material.

## 6. Prestige pacing

- Loop 1 (Eastport): days 3–5. Loop 2: ~2× faster to R7. Each subsequent city introduces its
  rule-twist as the new learning curve, so speed gains come from Black Book + player skill, not
  from the game getting shallower.
- Endless tail: after city 5, **"The Heat Death Tour"** — repeatable city remixes with stacked
  modifiers and a Juice multiplier, for the 1%ers, until v2 content.
