# SPEC — Ledger data schema & effects vocabulary

Design-owned. The upgrade tree is **data**: `game/content/upgrades.json` (authored by design,
loaded by the meta workstream). This spec defines the schema and the v1 effects vocabulary.
Design context: docs/04-UPGRADE-TREE.md, costs per docs/03-ECONOMY.md §7.

## Node schema

```jsonc
{
  "id": "rackets.numbers_game",     // branch.slug — unique, stable forever (save data)
  "branch": "rackets",              // rackets|fronts|muscle|crew|influence|blackbook
  "tier": 1,                        // 0..7 — purchasable only when rank >= tier
  "name": "The Numbers Game",
  "flavor": "A bicycle wheel, a chalkboard, and suddenly everyone's a mathematician.",
  "cost": "2.5K",                   // clean cash, BigMoney.parse format (blackbook: juice int)
  "repeat": null,                   // or {"max": 20, "growth": 1.15} — cost×growth^level
  "requires": ["rackets.trash_3"],  // AND-list of node ids (red string edges)
  "reveal": {"rank": 1},            // visibility gate — see below; default: visible with tier
  "effects": [ ... ],               // see vocabulary
  "table_change": "a bicycle-wheel spinner appears in the left lane"
}
```

`reveal` variants: `{"rank": N}` · `{"event": "first_tilt"}` · `{"purchased": "node.id"}` ·
`{"dirty_held": "10K"}`. Face-down cards = nodes whose reveal is not yet met but whose
*parent* is revealed.

## Effects vocabulary v1 (the meta engine resolves these into a Stats context)

| kind | fields | meaning |
|------|--------|---------|
| `unlock_hardware` | `target` | table hardware id becomes present/active |
| `feature_flag` | `target` | boolean gameplay flag (e.g. `plunger_bands`) |
| `value_mult` | `target`, `value`, `per_level` | multiplies switch-group value (`bumpers`, `slings`, `spinner`, `wire`, `storefronts`, `all`) — per_level effects stack multiplicatively per owned level |
| `value_add` | `target`, `value` | adds flat dirty value to a switch group |
| `idle_rate_add` | `target`, `value` | adds dirty/sec to a named racket's idle rate |
| `launder_rate_add` | `value` | + wash fraction per laundromat-loop pass |
| `launder_cap_add` | `value` | + per-Night wash cap (BigMoney string) |
| `pocket_money_set` | `value` | auto-clean allowance per Night |
| `passive_wash_add` | `value` | +fraction/sec of held dirty washed while armed |
| `safe_hours_set` | `value` | offline Safe cap in hours |
| `bench_slot_add` | `value` | +Bench slots |
| `ball_save_charges` | `value` | ball saves per Night |
| `tilt_leans_add` | `value` | +Inspector lean allowance |
| `flipper_power_mult` | `value` | flipper strength multiplier |
| `kickback_unlock` | `target` | `left`/`right` outlane kickback |
| `bribe_unlock` | — | Beat Cop bribe target active |
| `job_slots_set` | `value` | active Job slips |
| `collect_minutes_mult` | `value`, `per_level` | storefront collection payout scale |

Rules for the engine: effects apply the moment a node is bought; repeatable per_level effects
recompute from level count; the whole Stats context is a pure recompute from (owned nodes,
levels) — no incremental mutation, so save/load and respec are trivial.

## Content files (design-owned, this branch)

- `game/content/upgrades.json` — M1 set: ~30 nodes, tiers 0–3 (see file).
- `game/content/jobs.json` — M1 job pool (id, name, description, respect, params,
  `check` id the flow code implements).
- `game/content/names.json` — Bench goon name generator material (first names, nicknames,
  surnames; combine as "First 'Nick' Surname" ~30% nickname chance) + trait pool for M2.

Numbers in these files are opening bids for the balance sim; tune freely with data-only
commits, never by hardcoding values in gameplay code.
