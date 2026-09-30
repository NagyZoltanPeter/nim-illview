# nim-illview — design & build history

Retained-mode, TurboVision-inspired TUI widget framework for Nim, built on a
vendored fork of [illwill](https://github.com/johnnovak/illwill), driven by a
single-thread [chronos](https://github.com/status-im/nim-chronos) update loop,
with framework-owned input routing and nim-brokers as the domain event bus.

- **Design brief:** [BUILD-PLAN.md](BUILD-PLAN.md)
- **Deviations found during execution:** [DESIGN-DEVIATIONS.md](DESIGN-DEVIATIONS.md)

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

Iteration-2 brief: [BUILD-PLAN-2.md](BUILD-PLAN-2.md).

Phase 6 note: the real broker bus lives in `illview/bus_brokers` (import it
explicitly; the umbrella keeps the broker macro expansion out of the default
import graph). Wiring `enableTui`/`disableTui` into the LogosDelivery daemon
happens in the `logos-delivery` repo — see
[DESIGN-DEVIATIONS.md §9](DESIGN-DEVIATIONS.md).

## Dataflow (model / view / control)

Three channels, each one-directional, none of them holding a widget
reference on the model side (plan-5 P35 wording; mechanics unchanged):

| Direction | Channel | Carrier |
| --- | --- | --- |
| widget → app (intent) | `emits:` / `item(label, EventType)` | typed EventBroker event on `app.sessionCtx`, `senderId` only — a controller never needs a `View` |
| widget → model (state) | `bindValue: "field"` / `"model.field"` | store on the view or on a `ref` model the view holds; `bindRequest` routes through a replaceable validator |
| model → widget | `set<Field>` writer, `notify<Field>`, or a vocab signal (`SetText.signal(w.brokerCtx, …)`) | SignalBroker on the widget's instance ctx; stale handle → `err`; never re-emits |

Rendering is dirty-flag driven: any of the above ends in `invalidate()` →
root closure → `requestRedraw()` → one fps-capped `frame()`. Model state
mutated behind the framework's back repaints only after `notify<Field>` or
a signal. Contexts: [EMBEDDING.md §2](EMBEDDING.md).

## Build & test

```sh
nimble test
```

Requires Nim >= 2.2.4; `--mm:orc` and `--mm:refc` are both CI-gated. POSIX
terminals only for now; Windows async input is a documented stub (see plan
§0.7). Embedding in a host process: [EMBEDDING.md](EMBEDDING.md); extending
the widget set: [EXTENDING.md](EXTENDING.md).
