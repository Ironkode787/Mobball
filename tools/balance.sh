#!/usr/bin/env bash
# The balance autoplayer (docs/09-TECH.md §7, specs/m2-empire.md SIM lane).
#
#   tools/balance.sh                          # 14 days, all three profiles, 3 seeds
#   tools/balance.sh --days 3 --profile shark --seeds 1
#   tools/balance.sh --report /tmp/run2.md --quiet
#
# M2 counterfactuals (SIM-2 report — both OFF by default, so a bare run always measures the
# shipped economy). Use these to price a ruling before anybody edits game/flow:
#   tools/balance.sh --stake-ladder            # High Roller arms the next STAKE, not the PAYOUT
#   tools/balance.sh --capped-clean            # casino/Jackpot/Meeting clean eats the wash cap
#
# `--help` prints the full option list.
#
# Not part of tools/check.sh on purpose: this is a tuning instrument, not a build gate.
# tests/test_sim_smoke.gd keeps the sim itself honest inside the normal harness.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"

exec "$GODOT" --headless --path . --script game/sim/balance_cli.gd -- "$@"
