# Embedding illview in a host process

How a TUI built with illview lives inside another chronos program — a
logos-delivery node, a daemon with a `--tui` flag — without the host having
to adapt to it. Everything here is the single-loop model: **illview is
single-threaded** (`BUILD-PLAN.md §0.1`); the host and the UI share one chronos
loop on one thread.

## 1. The loop is the host's

`App.run()` (`src/illview/core/app.nim`) is an ordinary `{.async.}` proc: it
calls `enableTui()`, awaits a quit future, and `disableTui()`s in `finally`.
It never calls `waitFor`/`runForever`, never owns the dispatcher. So:

```nim
let node = await Waku.new(conf)      # host, on the loop
let app  = newApp()                  # UI, same loop, same thread
buildScreen(app)
asyncSpawn app.run()                 # or: await, if the UI is the program
await node.start()
```

Rendering is demand-scheduled: `requestRedraw()` sets a dirty flag and arms a
one-shot, fps-capped frame task. An idle UI has **zero** pending timers. Input
is a chronos `addReader2` on a dedicated tty fd (`backend/driver_posix.nim`),
`O_NONBLOCK`, no polling — the host loop is never starved.

### Which calls are loop-thread-only

All of them. `frame()` and the input callback assert the loop thread when
`--threads:on` (`assertLoopThread`, `core/app.nim`); everything else assumes
it. If a host worker thread has something to show, bring it to the loop
thread first with the host's own nim-brokers `(mt)` broker, then touch
widgets from the listener. illview provides no cross-thread primitive and
does not need one.

## 2. Broker context resolution (deviation #27)

`newApp()` **adopts** the thread's `globalBrokerContext()` and never installs
one, so the UI shares the scope the host already keys its brokers on.

| Situation | `app.sessionCtx` | `threadGlobalBrokerContext()` after `newApp` |
| --- | --- | --- |
| bare thread, `newApp()` | `DefaultBrokerContext` | unchanged (`Default`) |
| host did `setThreadBrokerContext(nodeCtx)` earlier, `newApp()` | `nodeCtx` | unchanged (`nodeCtx`) |
| `newApp(sessionCtx = uiCtx)` | `uiCtx` (views built afterwards too) | unchanged |
| two UIs in one process | pass each its own `sessionCtx` | unchanged |

`emits:` events (uiEvents) and `item(label, EventType)` menu actions fire on
`app.sessionCtx`; a host listener written before the UI existed —
`SomeEvent.listen(globalBrokerContext(), …)` — hears them without knowing
illview is there. Construction order (node first or UI first) does not
matter: both read the same thread-global value.

### Reaching a widget from the host

Model → view goes through the framework signal vocabulary on the widget's
own `brokerCtx` (`src/illview/vocab.nim`); a stale handle just returns `err`:

```nim
discard SetText.signal(peerLabel.brokerCtx, SetText(text: $peers))
discard SetProgress.signal(rateBar.brokerCtx, SetProgress(value: pct))
```

See `examples/ex10_instance_ctx.nim` — the model never calls a widget proc.

## 3. Daemon mode: TUI on and off

`enableTui` / `disableTui` are re-entrant (`core/app.nim`). Disabled, the app
is headless: no reader registered, no timers, zero cost — the process is a
plain daemon with the UI object still alive. `examples/ex14_logpane.nim`
demonstrates F2 → `disableTui()` (logs stream to the terminal) and Enter →
`enableTui()`.

## 4. Crash handling in a host

`enableTui` installs terminal-restore handlers for `SIGSEGV`/`SIGABRT`/
`SIGBUS`/`SIGILL`/`SIGFPE` so a crash never leaves the terminal in raw +
mouse-tracking mode. They **chain**: the previous action (the host's crash
reporter, Nim's traceback handler) is re-installed and invoked after the
terminal is restored (`installCrashRestore`, `core/app.nim`; test:
`tests/test_app.nim`). Opt out entirely with `-d:noCrashRestore`.

## 5. Default bus

`app.bus` is a `NullBus`: `UiAction`s go nowhere, string domain topics
dispatch to subscribers synchronously, nothing is recorded — a long-running
process accumulates no history. `app.bus = newBrokersBus()`
(`import illview/bus_brokers`) routes both tiers over nim-brokers.

## 6. Memory model and platform support

| Platform | `--mm:orc` | `--mm:refc` | Reason |
| --- | --- | --- | --- |
| macOS | CI gate | CI gate | single loop thread, no cross-thread closures; both gated by `.github/workflows/ci.yml` (plan-5 P32) |
| Linux | CI gate | CI gate | same |
| Windows | renders | renders | async input driver is a documented stub (`docs/WINDOWS-DRIVER.md`, deviation #18): not interactive yet |

Both memory managers: broker registrations hold strong refs to views, so an
undisposed view leaks under refc **and** ORC — call `dispose()` exactly once
when a subtree is permanently done (deviation #16). Known ORC-only issue:
churning subtrees whose closures capture the App can fault in the collector
(deviations #22/#23, `repro/orc_churn_crash.nim`; refc is clean). Pattern:
build persistent views once, `add`/`remove` them, dispose at teardown.
