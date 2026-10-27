#!/bin/sh
# Commit gate: every law proven, by bend and again by the Lean-verified
# kernel (--verdict), then the native build.
set -eu
cd "$(dirname "$0")"
BEND=${BEND:-$HOME/.bend/bin/bend}

gate() {
  out=$("$BEND" PROOF.bend "$@" 2>&1) || true
  printf '%s\n' "$out"
  case $out in
    *"SOME PROOFS FAIL"*) echo "check: proofs fail" >&2; exit 1 ;;
    *"ALL PROOFS CHECK"*) ;;
    *) echo "check: no proof verdict" >&2; exit 1 ;;
  esac
}

gate
gate --verdict
mkdir -p bin
"$BEND" main.bend -o bin/re24
./tests/run.sh
