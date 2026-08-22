# 08 — Audio

> **NOISE COMPLAINT #4,411** — *"It started as one bass player. There are now eleven of them
> and a choir. I have called the city. The city says it sounds great."*

Audio carries half this game's fantasy and most of its "sensory overload" promise. Two laws:

1. **The band grows with the empire.** The soundtrack is vertically layered: one stem per
   owned racket/zone. Empire size is *audible*.
2. **Every sound is a stat.** Each game event has exactly one sound, taught once, never reused.
   A skilled player can play eyes-closed-ish; at full overload the mix stays legible because
   meanings never collide (P4).

> **AMENDED (decision record, docs/11):** all audio is now **composed and synthesized
> in-house** by `tools/audiogen` (Python DSP: Karplus-Strong strings, FM/additive
> instruments, exciter→resonator foley). We own every byte; nothing is sourced. The design
> intent below (what things sound like, the stem system, "every sound is a stat") stands
> unchanged; the sourcing strategy sections are superseded by `specs/audio-pipeline.md`.

---

## 1. The living score (vertical layering)

One song per city, written as a **stem stack in a fixed key/tempo** (city 1: ~92 BPM, D minor,
swung). Stems fade in permanently as the empire grows:

| Unlock | Stem | Feel |
|--------|------|------|
| R0 | upright bass + finger snaps | one hungry guy in an alley |
| First rackets | brushed drum kit | things moving |
| R2 the Wire | vibraphone | streetlight shimmer |
| R3 the Block | muted trumpet | the neighborhood knows you |
| R4 the Club | organ + horn section | it's a scene now |
| R5 the Docks | baritone sax + congas | heavy industry, heavy money |
| R6 Penthouse | string section | velvet menace |
| R7 / Empire Mode | full band + choir stabs + timpani | the whole city is the orchestra |

**States modulate the stack** (mix automation, not new songs): Heat 70+ side-chains in a tense
ostinato and thins the comfort instruments; Heat 90+ adds a heartbeat kick + distant sirens
*in tempo*; RAID hard-cuts to drums+bass halftime with police-radio interjections; The Count is
solo piano over the bill-counter as percussion; Skip Town plays the stack *shedding stems one
by one* — the game's saddest and best musical moment; Going-Legit Hours swaps everything for a
chipper 1950s exotica loop (the front!).

**Implementation:** Godot `AudioStreamSynchronized` (sample-locked stem sync) +
`AudioStreamInteractive` for state transitions ([09-TECH](09-TECH.md) §5). Stems are loop-cut
OGGs on one bus per family with mix snapshots per state.

**Sourcing strategy (open source, in order of preference):**
1. Assemble from **same-BPM/key loop packs** (CC0/CC-BY: FreePD, OpenGameArt loop packs,
   dig.ccmixter stems/pells) — curate ONE coherent combo per city; retime/retune in a DAW
   where licenses allow derivatives (CC0/CC-BY do).
2. Public-domain-composition route: record/sequence our own arrangement of PD jazz-era
   compositions (pre-1930 published works) using free orchestral/jazz sample libraries
   (VSCO2 CE is CC0) — full control of stems, zero license risk on the composition.
3. If a city's sound can't be assembled credibly, commission later; design never depends on it.

Prototype validation gate in M1: 30 seconds of the R0→R4 stem growth must give goosebumps or we
re-source (this feature is a pillar carrier; it gets a milestone check like code does).

## 2. Table mechanics (the real-pinball layer)

Sampled from actual machines — this is where "real sampled sounds" pays off hardest. Freesound
is full of authentic pinball recordings (search: flipper, plunger, pop bumper, slingshot, tilt
bell, ball trough, glass thump; filter CC0/CC-BY, verify per file):

flipper thock (velocity-layered ×3) · plunger spring + release · pop-bumper skelp ·
sling snap · rollover click · drop-target clack (single + bank) · ball-on-wood roll loop
(pitch = speed) · ball-on-metal ramp rattle · saucer kick · knocker THWACK (reserved for
rank-ups — the classic "you won something real" sound) · tilt bell · chimes unit (Wire draws
use real Gottlieb-style chime arpeggios).

Rule: mechanical sounds stay DRY and center; music sits behind them; fiction sounds pan with
table position. The machine must always feel like a physical object in a room.

## 3. Money & fiction foley

bill counter brrrrrip (The Count's percussion) · cash register cha-ching (clean conversions
ONLY — the single most-taught association in the game) · coin cascade (jackpots) · paper
shuffle (jobs) · pin-punch + string creak (Ledger) · washing machine sloshes (laundromat,
pitch-shifts UP with wash rate — you can HEAR your laundering tier) · pizza oven door ·
pawn-shop bell · pigeons · rain on the glass (idle/menu ambience) · pneumatic door + camera
flash (mugshots) · pallet drop + gull screams (docks) · roulette rattle, chip stacks, card
riffles (Kenney casino audio pack is CC0 and covers most of this) · siren (period wind-up,
distance-mixed by Heat) · police radio squelch (raids) · courtroom gavel (trials).

## 4. Heat as a mix (the tension instrument)

Heat is mixed, not just displayed: 0–39 full comfort mix · 40+ comfort instruments −3dB, add
room noise · 70+ ostinato in, reverb tightens (the room gets smaller) · 90+ heartbeat + sirens
in tempo + everything non-essential ducked (the mix "holds its breath") · 100 raid slam. This
is the cheapest strongest "on edge" lever we have. The Silent Don boss and the RICO wiretap
phase then weaponize *silence* — see [05](05-MODES-AND-EVENTS.md) — with full visual/haptic
redundancy so reduced-hearing players lose nothing (accessibility note §6).

## 5. Voices: the muted-trumpet mob

No voice acting. Characters "speak" **wah-wah muted brass** (the grown-ups-in-a-comic-strip
trick), one instrument per character = their voice AND their stem presence:

Big Sal = tuba · Nussbaum = clarinet · Rosa = alto sax · Whispers Cohen = violin glisses ·
Manny = kazoo-ish cornet stabs · Eddie Odds = trombone slides · The Professor = oboe ·
Consigliere = cello · the Inspector = a bicycle bell and a sigh · The Rat = ...a thin whistle,
heard only twice, ever (players will learn to dread it).

Subtitled one-liners carry the actual jokes. This is thematically perfect, fully sourceable
(solo instrument phrases, CC0/CC-BY), hilarious, and localizes for free.

## 6. Mix architecture & accessibility

Buses: `Master → [Mechanics] [Music(stems)] [Fiction] [UI] [Ambience]`, per-bus user sliders.
Ducking sidechains: mechanics duck fiction; raid VO ducks music. Limiter on master (phone
speakers), optional "headphone mode" widening. Accessibility: every audio cue has a visual
twin (P4 makes this nearly free); subtitle all trumpet-speech; a "reduced flash" mode caps
neon flicker and raid strobes; haptics can substitute for the Heat heartbeat.

## 7. Per-city sound identities

Same system, new arrangement: New Carthage 1927 = hot jazz combo + Victrola crackle on the
music bus only · Costa Verde 1984 = synthwave stems (bass synth replaces upright, gated snare;
sirens become helicopter) · Silver Gulch 1899 = saloon upright piano, banjo, anvil percussion;
"neon" hum becomes lamp-oil hiss · Neon City 1999 = big-band-meets-house, slot-hall ambience.
The stem-growth *structure* is identical in every city, so the player's audio literacy carries.

## 8. Deliverable checklist (audio)

- [ ] `ASSETS.md` manifest with license + credit per file (enforced by import script)
- [ ] Stem stack city 1 (8 stems, loop-cut, level-matched) + state snapshots (calm/hot/raid/count/legit)
- [ ] ~90 SFX events (list above → event map), velocity layers where physical
- [ ] Haptics map (7 patterns, [07-ART](07-ART-DIRECTION.md) §7)
- [ ] The goosebump gate: R0→R4 growth demo approved
