# Reproducers

## `orc_churn_crash.nim` — ORC cycle-collector crash

A standalone illview app that **SIGSEGVs under `--mm:orc`** while navigating the
tree, and **runs cleanly under `--mm:refc`** — the signature of an ORC
cycle-collector bug (see [DESIGN-DEVIATIONS #22](../docs/DESIGN-DEVIATIONS.md)).

```sh
nim c -r --mm:orc  repro/orc_churn_crash.nim   # crashes (exit signal 11) navigating to "Confirm"
nim c -r --mm:refc repro/orc_churn_crash.nim   # no crash, same navigation
```

Each tree selection builds a fresh example window whose widgets/closures capture
`app` (app→tree→closure→app cycles) and frees the previous one; the collector
faults on the churn. The production fix (persistent-membership: build once,
add/remove, never rebuild) lives in `examples/ex13_showcase.nim`.

Minimization did not reduce below the full app graph — a pure-stdlib closure
churn and several smaller illview subsets did not reproduce it.

**Re-tested after deviation #28** (instance ctx allocated lazily, brokers
3.4.0), driven through a pty at 84×24 with the documented key sequence, three
runs per build: unchanged. Before (`febd604`, brokers 3.3.0) and after, ORC
dies with SIGSEGV on the 10th key (building "Confirm") every run; refc
survives the drive and exits 0 on Esc every run. Per-view broker-context
allocation is therefore not the trigger.
