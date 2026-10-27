# bend-re24 — agent rules

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `./check.sh` before committing
- parallelize the code whenever possible

Project rules:
- `LAWS.bend` and `src/spec.bend` are human-owned: their text comes verbatim from the approved plan.
  Never alter, weaken, or delete a law statement or a spec definition. A law that looks wrong or
  unprovable is reported to the human, never rewritten.
- Every number `bin/re24` prints comes from `src/re24.bend`, `src/decisions.bend` or
  `src/bootstrap.bend`. Every counted observation comes from `RE.observe`.
- No `@unsafe`, no `f?`, no foreign effects (`import "./x.c"`) anywhere. IO effects appear only in
  `src/cli.bend`, `main.bend` and `gpu.bend`.
- Before every commit run `./check.sh`; it must print ALL PROOFS CHECK and exit 0. Until every law
  is proved, `bend PROOF.bend` may report open TODO laws but no type errors.
- The Retrosheet notice stays in `README.md`, `fixtures/NOTICE` and the report footer.
- Commits: Conventional Commits (`feat|fix|chore|docs|refactor|test[(scope)]: subject`).
