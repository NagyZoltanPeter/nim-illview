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
| 4 | Widget set with VCL-style closure slots | done |
| 5 | Declarative layer (pragmas + `mount` macro) | done |
| 6 | nim-brokers EventBus + network-event visualizer | done |
| 7 | Declarative styling: border/title/shadow/color + focus overrides | done |
| 8 | GroupBox, Table, ProgressBar | done |
| 9 | bindValue/bindRequest state binding, uiEvents typed broker events, open bus | done |
| 10 | Window move/resize (mouse drag + Alt+Arrows) | done |

Iteration-2 brief: [docs/BUILD-PLAN-2.md](docs/BUILD-PLAN-2.md).

Phase 6 note: the real broker bus lives in `illview/bus_brokers` (import it
explicitly; the umbrella keeps the broker macro expansion out of the default
import graph). Wiring `enableTui`/`disableTui` into the LogosDelivery daemon
happens in the `logos-delivery` repo — see
[DESIGN-DEVIATIONS.md §9](docs/DESIGN-DEVIATIONS.md).

## Build & test

```sh
nimble test
```

Requires Nim >= 2.0 (`--mm:orc`). POSIX terminals only for now; Windows async
input is a documented stub (see plan §0.7).
