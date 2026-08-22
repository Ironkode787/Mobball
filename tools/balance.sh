#!/usr/bin/env bash
# The balance autoplayer (docs/09-TECH.md §7, specs/m2-empire.md SIM lane).
#
#   tools/balance.sh                          # 14 days, all three profiles, 3 seeds
#   tools/balance.sh --days 3 --profile shark --seeds 1
#   tools/balance.sh --report /tmp/run2.md --quiet
#
# Counterfactual flags: --capped-clean (casino/Jackpot/Meeting clean eats the wash cap)
# is live; --stake-ladder and --flat-skill are retired — both counterfactuals WON and are
# the shipped rules now (the flags parse and do nothing).
#
# `--help` prints the full option list.
#
# Not part of tools/check.sh on purpose: this is a tuning instrument, not a build gate.
# tests/test_sim_smoke.gd keeps the sim itself honest inside the normal harness.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"

exec "$GODOT" --headless --path . --script game/sim/balance_cli.gd -- "$@"
