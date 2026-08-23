# 01 — Core Gameplay

> **POLICE BLOTTER** — *"Suspect described as 'small, fast, metallic.' Fled downward."*

This document covers the second-to-second game: physics feel, controls, the skill toolkit,
session structure (Nights), and the Bench. The rule of thumb throughout: **arcade pinball feel,
tuned for a phone held in two thumbs, deep enough that a good player is visibly, measurably
better than a lucky one.**

---

## 1. Controls (portrait, two thumbs)

| Input | Action | Notes |
|-------|--------|-------|
| Touch left / right half (bottom ~70% of screen) | Left / right flipper(s) | Multi-touch; hold to trap. A quick horizontal drag begun in a flipper zone adds one L/R nudge without consuming the hold or release. Upper mini-flippers ride the same sides — one thumb per side, always |
| Short swipe up on launch lane | Plunger ("The Drop-Off") | Starter hardware offers three coarse pull bands; Real Plunger keeps continuous charge/detents |
| Flick upper field / tap top corners | **Lean** (nudge) L/R/up | Quick horizontal/upward flicks classify once per touch; corner taps fire immediately. Also accelerometer option. Costs Inspector patience (see §5) |
| Hold both flippers 1.5s while ball is trapped | **Case the Joint** (aim mode) | Slows time slightly, shows a faint chalk trajectory line if The Planner is hired ([04](04-UPGRADE-TREE.md)) |
| Two-finger tap | **Union Break** (bullet time, if unlocked) | 3s slow-mo, long cooldown — late-game skill tool |
| Tap HUD elements | Collect ready bonuses, answer The Phone | Non-critical taps only; nothing twitchy lives in the HUD |

Design rules: **flipper zones stay authoritative for hold and release** during live play. A
quick horizontal drag that begins in a flipper zone may add one nudge, but it is additive and
never consumes or cancels the critical flip input; the shooter lane keeps plunger precedence.
Everything critical is reachable without re-gripping; every input has haptic + audio
confirmation (cheap Android haptics considered — patterns, not just buzzes).

## 2. Ball feel (the non-negotiables)

Feel targets, tuned in M0 before anything else exists ([10-ROADMAP](10-ROADMAP.md)):

- **120 Hz fixed-tick physics** with continuous collision detection; render interpolated at 60fps. A tunneling ball is a dead game.
- **Flippers snap.** Full extension in ≤ 45ms, with a tuned power curve along the bat (tip = fast/flat, base = slow/high). Input buffer of ~50ms so mobile touch latency never eats a flip.
- **The ball is heavy.** *(Settled in M0: 3800 px/s² at the 1080-wide scale — the original
  5.5–6.5 m/s² figure mapped to ~10k px/s² and was uncontrollable; current value gives a
  ~1.0 s full-table drop and validated flipper control. Revisit only with hands on a device.)*
  High ball mass, low bounciness on steel, controlled bounce on rubbers.
- **Live catch, dead bounce, drop catch, post pass, tap pass** must all be physically possible. We tune until an experienced pinball player can do their whole toolkit. This is the skill ceiling and it's sacred (P2).
- **Slow-mo drama frames:** 80ms micro-slowdowns on jackpot shots and near-drain saves. Never during aimed play.
- Camera: smart vertical follow with look-ahead, slight zoom-out during multiball ([09-TECH](09-TECH.md)).

## 3. Session structure: Nights and The Count

A **Night** is one classic pinball game reframed:

1. **Roll call.** Before the table goes live, the pre-Night **Roll Call** screen shows
   **Tonight's Work** (the jobs already rolled for this Night) and the available guys from
   the Bench. Select the guys and explicitly set their order; selection order is serve order.
   There is no drag-reorder interaction. The target is up to three slots — pinball's three
   balls — but a short Bench safely starts with every available guy.
2. **Work.** Play until each guy is pinched (drained). Mid-night events fire: Jobs, draws, briefcases, Heat, maybe a Raid.
3. **The Count.** The tally room: dirty cash counted (real bill-counter sample, numbers rolling up), laundering applied, Respect awarded, Heat resolved, newspaper headline generated from your night ("LAUNDROMAT REPORTS RECORD SOCK SEASON").

Nights are short by design (3–8 min). The Count is the dopamine ritual and natural stopping
point — and the "one more Night" button sits right there, lit like a jukebox.

**Between Nights** the idle layer runs: owned rackets earn dirty cash into your Safe (capped),
crew specialists do their passive work, jailed guys serve time. See [03-ECONOMY](03-ECONOMY.md).

## 4. The Bench — balls are guys

The signature twist. Your balls are **named goons** with one trait each, generated with
period-appropriate nicknames (Sal "Two Shoes", Franny the Wrench, Little Enzo).

- **Traits** (one per guy, small but felt): *Heavy* (+mass, smashes gates, slower), *Lucky* (+5% briefcase odds), *Slippery* (one free outlane escape per Night), *Loud* (+10% dirty, +10% Heat), *Careful* (−15% Heat), *Fast* (+velocity cap, harder to control, +value), *Old-Timer* (+Respect from Jobs).
- **Experience:** guys level slowly by surviving Nights (cap +2 traits). Losing a leveled guy *hurts* — by design.
- **Pinched:** a drained guy sits in holding. After the Night he either walks (base: free after 1 Night off) or you **post Bail** (dirty cash — a core money sink) to use him again immediately. Raids can hand out longer stretches.
- **Ball identity:** each persistent guy ID deterministically defines a metallic ball face — a
  high-contrast band geometry and crest over the metallic base — so the same guy is recognizable
  in Roll Call and on the live table. Identity is never color-only; an anonymous/debug ball
  deliberately remains plain steel.
- **Bench depth:** starts at 4 guys; upgrades expand it. If fewer than three are available,
  Roll Call requires only that smaller set and the Night serves them safely. Between Nights the
  Bench walks released holding guys and hires a fresh nobody when needed, so the game never
  hard-locks.
- **Multiball = the crew out together.** "Family Meeting" is literally three of your named guys on the table at once. The endgame "Family Reunion" is five. Survivors all bank their earnings; you feel who made it home.

Why this works: it converts pinball's oldest abstraction into attachment, gives drains
*narrative* sting instead of just numeric sting, creates a bail/jail money sink that scales
forever, and sets up late-game drama (The Rat, [05](05-MODES-AND-EVENTS.md) §7). Complexity is
capped hard: one visible trait line, no equipment, no menus mid-play.

## 5. Tilt: The Inspector

Nudging is a real skill and we want it — taxed, themed, and upgradeable.

- A little pixel-art city inspector leans on the cabinet at the table's edge. Each **Lean**
  fills his suspicion meter (three stages: raised eyebrow → notepad → TILT).
- TILT = classic punishment: flippers die for the current guy, he's pinched, plus a Heat spike.
- Suspicion decays between balls. **Bribes** (Ledger upgrades) raise his tolerance from 3 leans
  per guy up to 8, add faster decay, and eventually "Inspector On Vacation" windows — 20s of
  free nudging when a lit target is hit. The physical nudge impulse itself never grows; only
  *permission* does (P2: buy odds, not outcomes).

## 6. The skill toolkit (what separates a shark from a fish)

| Skill | Mechanic | Payoff |
|-------|----------|--------|
| **Shot making** | Every lane/ramp/target has a purpose and a lit state | The whole economy |
| **The Drop-Off** (skill shot) | Plunger power bands select the entry lane; a moving "delivery window" light cycles lanes | Choose your opening racket + ☆1 Respect on a clean drop |
| **Clean Hits** | Flipping in the sweet 20% of the bat's arc adds +25% shot power and a chalk "CLEAN" flourish | Faster ramps, reachable upper decks, satisfaction |
| **Clean Work** (combos) | Chaining different lit shots within 4s each: ×1, ×2, ×3… cap ×8 | Multiplies dirty earnings of the chain; ☆ at ×3+ |
| **Trapping & Casing** | Trap the ball, hold to aim (§1) | Precision under pressure; feeds P2 |
| **Leaning** | Nudge outlane saves, bumper steering | Survival, at Inspector cost |
| **Bank management** | *Choosing* laundering shots vs. earning shots vs. casino risk in real time | The strategic layer — see [03-ECONOMY](03-ECONOMY.md) |
| **Heat surfing** | Playing deliberately at Heat 70–99 for multipliers, bailing via bribe shots before 100 | The "on edge" endgame skill |

**Assists that don't cheapen skill** (all optional, some purchasable in-fiction): The Planner's
chalk aim line, slightly wider Enforcer save windows, Union Break slow-mo. Assists ease
*execution*, never *decisions*, and the hardest content (Heists, Commission fights, Federal
Raids) scales its demands assuming assists exist.

## 7. Difficulty over a run

Early table: gentle outlanes, slow ball, big targets — a nobody can survive a Night.
As the table grows, *the geometry itself raises stakes*: upper decks feed faster returns,
docks add a second drain risk, max-Heat cop hardware actively hunts the ball, and endgame
multiball economy demands real trapping skill. Upgrades never reduce raw difficulty to zero;
they add **tools and second chances** (kickbacks, loans, tunnels) that skilled players convert
into streaks. Target: a maxed table played badly earns ~15% of what it earns played well.
That gap is the game's soul (P2). We tune the gap with the autoplayer harness ([09-TECH](09-TECH.md) §7).

## 8. Failure states

- **A pinched guy** is a beat, not a punishment: mugshot slide, one-liner, next man up.
- **A lost Raid** confiscates a cut of *dirty* (never clean) cash and jails guys — recoverable within 1–2 Nights, and it always leaves a story headline.
- **Bankruptcy is impossible** by construction: base racket trickle + free nobody guys means the machine always restarts.
- **TILT** is the only "your fault, full stop" fail, and it's always one guy, never the Night.
