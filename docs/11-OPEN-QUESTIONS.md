# 11 — Open Questions & Proposals

## DECISION RECORD (2026-08-22 — boss sign-off: "Agreed")

The recommendations below were accepted as a package. Standing decisions:

| # | Decision |
|---|----------|
| Q1 | Title: **KINGPIN — A Pinball Racket** (repo remains Mobball) |
| Q2 | **Premium** (~€5), cosmetic city-skin packs later. No ads, no IAP progression |
| Q3 | **Bench lite ships in the MVP** (M1); full Bench in M2 |
| Q4 | **Eras-per-city confirmed** (1972 → 1927 → 1984 → 1899 → 1999) |
| Q5 | Nudge: **gesture default, accelerometer opt-in** |
| Q6 | Tone as designed (Teen, satire, fictional-currency gambling only) |
| Q7 | **Godot 4.5** signed off |
| NEW | **All audio is composed & synthesized in-house** (tools/audiogen) — no sourced samples anywhere. docs/08 amended. Art still uses the open-license pipeline of docs/07 |

Original questions kept below for the record.

---

Decisions I'd like your call on before/during M0. My recommendation is marked ►.

## Q1 — Title
- ► **KINGPIN** (double meaning: mob boss / the pin; strong icon potential — a gold pin as
  crown). Risk: common word, needs a subtitle for store search: *"KINGPIN: A Pinball Racket"*.
- Alternatives: **The Racket** (also a double meaning, quieter), **Made Ball**, **Tilt City**,
  **Mobball** (the repo name! honest, playful, ownable — genuinely viable).

## Q2 — Business model
- ► **Premium (~€5) + optional cosmetic city-skin packs later.** Cleanest fit for P5 and for
  a skill game's reputation; incremental+premium has strong precedent (Balatro).
- Alternative: free + fair ads (opt-in "Police Scanner broadcast": watch an ad to double the
  Safe on collect, hard-capped 2/day, zero ads otherwise) + one-time "remove ads" IAP. Higher
  reach, more design contamination. **This decision changes M1 scope slightly (ad hooks), so
  it's the most time-sensitive question here.**

## Q3 — The Bench (balls-as-guys): full, lite, or later?
- ► **Ship "Bench lite" in M1** (names, pinch, bail, one trait), full system (levels, training,
  the one-guy-comes-with-you prestige choice) in M2. It's the signature twist and I'd protect it.
- Alternative: classic anonymous balls for MVP, Bench added in M2 — lower risk, but we'd be
  testing a hook with its most human piece missing.

## Q4 — Eras-per-city
Cities changing era (1972 → 1927 → 1984 → 1899 → 1999) is bold and expensive-ish (art/music
re-skins, though the segment architecture contains it). Comfortable? The cheap fallback is one
era, five boroughs — same structure, less wow. ► I say eras; it's the prestige system's soul.

## Q5 — Accelerometer nudge default
Flick-gesture nudge is the reliable baseline; accelerometer (physically shake the phone) is
*delightful* but wildly device-variable. ► Ship both, gesture default, accel opt-in.

## Q6 — Tone check
Current tone: loving satire, cartoonish, Teen-rated; gambling is mechanically real but
fictional-currency only. Any lines you want drawn differently (e.g., no smoking imagery for
rating reasons, region sensitivities re: simulated gambling — notably Play Store policies in
some markets)?

## Q7 — Engine sign-off
Godot 4 recommendation in [09-TECH](09-TECH.md) §1. If you have Unity/libGDX history or a
strong preference, now's the moment — nothing in the design depends on the engine, but M0
starts by committing to one.

---

## Proposals beyond the brief (flagging, since they shape scope)

1. **Dirty vs. clean cash** — the brief asked "points = money"; I split money in two and made
   laundering a *shot* economy. I believe it's the design's best idea; it does add one concept
   to onboarding (mitigations in [03](03-ECONOMY.md) §2).
2. **The Bench** — balls as named guys with bail/jail. Not in the brief; makes drains
   *narrative*, adds a scaling sink, sets up The Rat.
3. **The band that assembles itself** — the layered-stem soundtrack as a progression readout.
4. **Muted-trumpet voices** — solves "real sampled voice acting" with style instead of budget.
5. **The Inspector** — tilt as a bribable character; nudging as an upgradable permission.
6. **Boss fights on your own table** (the Commission), culminating in the Old Kingpin using
   your build against you.
7. **Skill-based prestige send-off** (stem-shedding Skip Town scene) — prestige as a feeling,
   not a menu.

If any of these feels off-brief, say the word and I'll re-cut the docs.
