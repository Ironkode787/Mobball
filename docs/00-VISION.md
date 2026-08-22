# 00 — Vision & Pillars

> **THE MIDTOWN TRIBUNE, Oct. 12** — *"Police baffled as neighborhood pinball machine reports
> quarterly earnings larger than the Port Authority."*

---

## 1. The fantasy

You are a nobody with a steel ball and bad intentions.

The machine in the back of Lucky's Laundromat doesn't pay out in free games. It pays out in
*money* — skimmed, scammed, and shaken down — and everyone in the neighborhood knows whose
machine it is. Yours. The fantasy of KINGPIN is the full arc of every great mob story compressed
into a pinball cabinet: the hungry early days when three trash cans and a busted flipper are
your whole world; the intoxicating middle where every week there's a new racket, a new guy, a
new room upstairs; and the paranoid, glittering top, where the music is loud, the lights never
go off, and every siren in the city is for you.

The player should feel three things, in this order, over their first month:

1. **Hunger** (day 1–3): every dollar is hand-earned with flipper skill. The table is small and honest and yours.
2. **Momentum** (week 1–2): rackets compound. The table sprouts new geometry weekly. Idle income hums while you sleep. You are *building something* and you can see it.
3. **Glorious paranoia** (week 3+): you run five-ball multiballs through a three-story city at max Heat because the multiplier is too good to walk away from. You know a Raid is coming. You stay anyway. That's the game.

## 2. Design pillars

Every feature must serve at least one pillar. Features that fight a pillar get cut, no matter
how fun they sound in a meeting.

### P1 — Points are money, money is the table
No abstraction between score and progression. The number that goes up when you hit a bumper is
the number you spend. And spending it changes the *physical playfield* — new lanes, new levels,
new machines bolted on. The player's skill literally builds the world.

### P2 — Skill is the engine, chance is the weather
The player's hands must always matter most. Randomness (casino games, number draws, raids,
mystery briefcases) decides *what situation* the player is in — never *whether they were good*.
Every random event resolves through aimed shots and timed flips. Corollary: **the player can buy
better odds but never buy outcomes.**

### P3 — The table tells the story
No cutscenes. Career progression, boss fights, betrayals, elections, federal raids — all of it
happens *on the playfield* through geometry, light, and sound, plus newspaper headlines between
Nights. If a story beat can't be expressed as something the ball interacts with, it doesn't
happen.

### P4 — Sensory overload you can sight-read
The endgame table should be an ecstatic wall of neon, brass, and jackpot bells — and a skilled
player should still parse every element at a glance, because **every light and every sound
carries exactly one meaning, taught early, never reused.** Loudness scales; legibility never
drops. (See [08-AUDIO](08-AUDIO.md): "every sound is a stat".)

### P5 — Respect the player's life
This is a compulsion-loop game built by people who like players. Sessions have a natural shape
(a Night, then The Count). Idle earnings reward coming back but never punish sleeping. No
energy timers, no fake scarcity, no pay-to-win. The game is generous with "one more Night" and
honest about everything else.

## 3. Tone

**Mob-movie satire, played straight by the characters, winked at by the presentation.**
Think 1970s crime-paperback covers, gangster-movie tropes lovingly exaggerated, newspaper
headlines that lampshade the absurd economy ("CRIME UP 4,000%; MAYOR REQUESTS RECOUNT").
Violence is implied, stylized, and cartoonish — a boss "defeated" is a limo that speeds off, a
guy "pinched" is a mugshot slide, nobody bleeds. Gambling is depicted (it's a mob game) but the
only currency ever wagered is fictional and earned in-game.

Target rating: **Teen / PEGI 12** (simulated gambling, mild cartoon violence, crime themes).
No real mob names, no film quotes, no trademarked anything. Our wiseguys are our own.

## 4. Genre position & audience

- **Genre:** Pinball × incremental (idle) × light RPG roster. Closest neighbors: the depth-behind-a-toy of *Luck be a Landlord* or *Balatro* (a classic machine hiding a build engine), the fuse-skill-with-idle of *Vampire Survivors*-era hybrids, and classic video pinball (*Zen*, *Demon's Tilt*) for feel.
- **Audience:** players who love "number goes up" but are bored of tapping; pinball fans who want persistence; the Balatro crowd — people who want a skill toy that becomes a build engine.
- **Session profile:** 3–8 minute Nights, 2–5 Nights per sitting, plus 30-second idle check-ins. First prestige around day 3–5. Content horizon at launch: 60–90 days of progression across 3 cities, then endless via prestige scaling.

## 5. The core loop

```
        ┌────────────────────────────────────────────────────────┐
        │                        A NIGHT                         │
        │                                                        │
        │   Send out a Guy ──► PLAY PINBALL ──► earn DIRTY CASH  │
        │        ▲               │      │                        │
        │        │               │      └─► shots at LAUNDERING  │
        │   Bench next guy       │           features convert    │
        │   (or pay Bail)        ▼           dirty ──► CLEAN     │
        │              Guy gets PINCHED                          │
        └───────────────────────┬────────────────────────────────┘
                                ▼
                          THE COUNT (tally)
                                │
        ┌───────────────────────┼────────────────────────────────┐
        ▼                       ▼                                ▼
   RESPECT ☆ from          CLEAN CASH ──► THE LEDGER        HEAT 🔥 rises
   Jobs & skill                │          (upgrade tree)    with success
        │                      ▼                                │
        ▼                 table GROWS: new zones,               ▼
   RANK UP ──► new district + Commission boss            RAIDS / bribes /
        │                      │                         risk-reward play
        └──────────────────────┴───────────► eventually: SKIP TOWN
                                             (prestige ► JUICE ► Black Book
                                              ► new city, new era)
```

Between Nights, owned rackets generate idle income (capped by your Safe). The pinball layer is
the *multiplier engine* on the idle layer: skilled play collects, boosts, and multiplies what
the rackets produce. Idle alone progresses slowly; play progresses fast; play *well* progresses
absurdly.

## 6. What makes this game novel

1. **Laundering as a shot economy** — score isn't spendable until you route it through table geometry. "Where do I put the ball" becomes a financial decision every second. No pinball game has made *score itself* a two-stage resource.
2. **The table that grows** — incremental games expand menus; we expand *the physical machine*, upward, matching the career ladder. The camera pulling back over weeks IS the progress bar.
3. **Balls with names** — the Bench turns pinball's oldest rule (3 balls) into a roster mini-game with attachment, bail-outs, jail timers, and a heartbreaking betrayal arc (see The Rat, [05](05-MODES-AND-EVENTS.md)).
4. **A band that assembles itself** — one instrument stem per racket owned; your empire's size is audible in the arrangement ([08-AUDIO](08-AUDIO.md)).
5. **Heat** — a single dial that fuses risk/reward multipliers, difficulty modulation, and narrative pacing, feeding the "on edge" feeling the whole design chases.

## 7. Non-goals (v1)

- No multiplayer, no leaderboard-driven design (a simple weekly "biggest single Night" board is fine later).
- No level editor, no user-generated tables.
- No literal firearms-as-powerups; muscle is expressed through table physics (flipper strength, enforcer saves, ball mass).
- No real-money wagering of any kind, obviously.
- No iOS at launch (design stays portable; Godot makes the port cheap later).
