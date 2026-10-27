#!/bin/sh
# Fixture tests for bin/re24; check.sh runs them after the build.
set -eu
cd "$(dirname "$0")/.."

fail() {
  echo "tests: $1 failed" >&2
  exit 1
}

has() {
  printf '%s\n' "$1" | grep -Eq "$2"
}

# Two clean games: the summary, and every RE line against an awk oracle that
# sums event_runs + fate_runs per starting state straight from the CSV.
out=$(bin/re24 run fixtures/plays-mini.csv) || fail mini-run
has "$out" '^GAMES 2 2 0$' || fail mini-games
has "$out" '^HALVES 32 0$' || fail mini-halves
has "$out" '^PLAYS 148$' || fail mini-plays
want=$(awk -F, 'NR > 1 { r[$5 " " $4] += $9 + $10; n[$5 " " $4]++ }
  END { for (o = 0; o < 3; o++) for (b = 0; b < 8; b++) print "RE", b, o, r[b " " o] + 0, n[b " " o] + 0 }' \
  fixtures/plays-mini.csv)
got=$(printf '%s\n' "$out" | awk '$1 == "RE" { print $1, $2, $3, $4, $5 }')
[ "$want" = "$got" ] || fail mini-re

# One run claim off by one: that game is rejected, the other still counts.
bad=$(bin/re24 run fixtures/plays-bad.csv) || fail bad-run
has "$bad" '^GAMES 2 1 1$' || fail bad-games
has "$bad" '^BADGAME 1 [0-9]+ runs$' || fail bad-badgame

# The bootstrap prints the same intervals on one thread and on 24.
one=$(bin/re24 boot fixtures/plays-mini.csv 7 +RTS --threads 1 -RTS) || fail boot-run
many=$(bin/re24 boot fixtures/plays-mini.csv 7 +RTS --threads 24 -RTS) || fail boot-run
[ "$one" = "$many" ] || fail boot-threads
