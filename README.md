# nim-illview

Retained-mode, TurboVision-inspired TUI widget framework for Nim, built on a
vendored fork of [illwill](https://github.com/johnnovak/illwill), driven by a
single-thread [chronos](https://github.com/status-im/nim-chronos) update loop,
with framework-owned input routing and nim-brokers as the domain event bus.

- **Design brief:** [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md)
- **Deviations found during execution:** [docs/DESIGN-DEVIATIONS.md](docs/DESIGN-DEVIATIONS.md)

## Status

| Phase | Content | State |
| ----- | ------- | ----- |
| 0 | Vendored illwill + incremental input decoder | done |
| 1 | chronos loop, POSIX stdin driver, opt-in TUI lifecycle | done |
| 2 | View tree, DrawContext clipping, mouse/key routing | done |
| 3 | Layout engine (HBox/VBox/Grid/dock) | done |
| 4 | Widget set with VCL-style closure slots | pending |
| 5 | Declarative layer (pragmas + `mount` macro) | pending |
| 6 | nim-brokers EventBus + network-event visualizer | pending |

## Build & test

```sh
nimble test
```

Requires Nim >= 2.0 (`--mm:orc`). POSIX terminals only for now; Windows async
input is a documented stub (see plan §0.7).
