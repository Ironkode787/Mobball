# SPEC — Audio wave 2 (M1 additions)

Audio workstream follow-up to specs/audio-pipeline.md — same lane, same generator, same
quality bar. Two deliveries: the M1 SFX vocabulary and the music **state** system.

## 1. New SFX events (assets/audio/sfx/<event>.wav)

Mechanics: `rollover_click` (soft leaf-switch click) · `spinner_tick` (light metallic tick,
≤35 ms — fires per spin segment at high rate) · `drop_clack` (single drop target) ·
`drop_bank_down` (3-target bank completion thunk, meatier) · `drop_bank_reset` (mechanical
ratchet-up) · `kickback` (solenoid boom, biggest mechanical hit after knocker) ·
`orbit_whoosh` (filtered air swoosh, doppler-ish rise-fall, 400 ms).

Fiction: `storefront_collect` (register cha-ching + brief coin pour — the "collections"
signature) · `laundromat_wash` (watery slosh whoosh, 500 ms) · `bribe_paid` (bill riffle +
police-radio squelch chirp) · `guy_pinched` (camera-flash pop + cell-door clank, 700 ms) ·
`bail_paid` (heavy ledger stamp + coin clink) · `safe_open` (heavy door creak-clunk + coin
settle, for the offline-collect banner) · `stamp_thunk` (Ledger purchase: pin punch into
cork + paper thump) · `paper_slip` (paper slide) · `job_done` (short bright brass "bup!" +
desk bell) · `skill_shot_ding` (bright double chime, distinct from tilt_warning bell) ·
`combo_2` `combo_3` `combo_4` (ascending pitched blip family, D–F–A so they harmonize with
the score) · `headline_sting` (typewriter burst + carriage-return ding + paper whoosh,
900 ms) · `rankup_fanfare` (2 s three-note brass fanfare + timpani hit — layers over the
existing `knocker`) · `bill_counter` (1.2 s loopable brrrrip for The Count — make it
loop-clean) · `coin_drop` · `siren` (6–8 s loopable period siren wail, mixed distant) ·
`raid_start` (door-slam + drum hit + siren swell, 1.5 s) · `raid_win` (triumphant brass
stab + register, 1.5 s) · `raid_lose` (descending brass sag + cell door, 1.5 s).

## 2. Music states

New synced stems (exact same N frames as the base eight, added to the same
AudioStreamSynchronized):

- `09_tense.ogg` — the Heat ostinato: low staccato strings + muted ticking percussion on
  swung eighths, D pedal with occasional Eb neighbor (menace), sits UNDER the band.
- `10_raid_drums.ogg` — halftime heavy drum variant (big kick on 1 and 3, splashy snare on
  3, driving toms), designed to REPLACE `02_drums` when active.

Non-synced extra track:

- `count_piano.ogg` — solo piano, 4-bar loop, same key family (Dm), sparse and warm,
  ~55 BPM feel; its own loop length is fine (it never syncs with the band).

### AudioDirector API additions

`music_set_state(state: StringName)` with `&"calm"` `&"hot"` `&"raid"` `&"count"`:

| state | mix |
|-------|-----|
| calm | stems by `music_set_level` as today; tense & raid_drums muted; piano stopped |
| hot | calm mix + `09_tense` faded in; vibes/organ/strings each −4 dB |
| raid | only bass + `10_raid_drums` + tense at full; all other stems −60 dB (fast 0.4 s fades); `02_drums` muted |
| count | whole synced stack ducked to silence (1 s); `count_piano` plays looping; leaving count state reverses |

Fades tween volume_db, never stop/start the synced player (sample lock must survive every
state change). All state changes must be safe headless and idempotent.

## 3. Acceptance

- Generator additions deterministic; all new files in MANIFEST.txt; total assets stay < 16 MB
  (budget raised for wave 2).
- `tests/test_audio_assets.gd` extended: new events present; `09/10` stems frame-match the
  base stack; `bill_counter` and `siren` verified loop-clean (decoded seam check).
- `bash tools/check.sh` green. Report: same format as wave 1.
