# nim-illview — Iteration 3 plan (Phases 11–15): instance-ctx events & signals

Follow-up to [BUILD-PLAN-2.md](BUILD-PLAN-2.md). Same rules: phase by phase,
each phase compiles + tests green + demoable, commit per phase. Deviations
continue numbering in [DESIGN-DEVIATIONS.md](DESIGN-DEVIATIONS.md).

Scope (confirmed 2026-07-10): widget identity moves from payload
(`senderId`) into **routing** — every widget instance owns a
`BrokerContext`; a fixed framework vocabulary of EventBroker events
(widget → app) and SignalBroker directives (app → widget) rides those
contexts; `mount(T)` installs per-instance handlers declaratively.

What this does NOT replace:

| Existing tier | Status |
|---------------|--------|
| `bindTo:` sync slots (tier 1) | kept — fastest path, fires inside dispatch |
| `action:` / `UiAction` bus (tier 2) | kept — menus/statusbar command channel |
| `emits:` + `uiEvents(T)` semantic events | kept — model listens to *intent* on the default ctx |
| `bindValue:` widget → field store | kept — gains an inverse (D10) |
| string domain bus (`IvDomainEvent`, `net/*`) | kept — observability widgets (NetViz) |

Guidance baked into docs: **model listens semantic by default;
instance-ctx listening is the escape hatch** for genuinely widget-bound
concerns (mirroring, metrics, autosave).

---

## 0. Design decisions (CONFIRMED 2026-07-10)

### D7. Every View owns a BrokerContext; identity lives in the route

`View` gains:

```nim
brokerCtx*: BrokerContext                             # instance route
disposers*: seq[proc() {.gcsafe, raises: [].}]        # (type, ctx) teardowns
```

Allocation: one process-wide `gAppClassCtx = NewBrokerContext()` (module
init; single chronos thread per prime directive §0.1, so no threadvar
gymnastics), then `initView` does
`v.brokerCtx = newInstanceCtx(gAppClassCtx)` — same classCtx low-16, fresh
instanceCtx high-16.

Ceiling: instanceCtx is uint16, monotonic, `doAssert` at 65 535
(nim-brokers `broker_context.nim:104`), **no recycling yet** → Phase 11
adds `releaseInstanceCtx` to nim-brokers. Until that lands, dynamic-UI
apps burn ids on every widget construction; acceptable for the iteration,
not for release.

### D8. Framework vocabulary — `src/illview/vocab.nim`, defined ONCE

Payloads carry **no identity** (no senderId — the ctx is the identity).

Events (EventBroker, many listeners per (type, ctx)):

| Event | Payload | Emitted by |
|-------|---------|------------|
| `Clicked` | — | Button |
| `TextChanged` | `text: string` | Input, Editor (live edits) |
| `Submitted` | `text: string` | Input (Enter) |
| `Toggled` | `checked: bool` | Checkbox |
| `SelectionChanged` | `selected: int` | Radio, ListView, Table |
| `Activated` | `selected: int` | ListView, Table (Enter/double-click) |

Signals (SignalBroker, SINGLE handler per (type, ctx) = the mounted widget):

| Signal | Payload | Handled by |
|--------|---------|------------|
| `SetText` | `text: string` | Input, Editor, Label |
| `SetChecked` | `checked: bool` | Checkbox |
| `SetSelected` | `selected: int` | Radio, ListView, Table |
| `SetProgress` | `value: int` | ProgressBar |
| `FocusMe` | — | any focusable |

Widgets emit on their own ctx inside the existing activation paths
(e.g. `Button.activate` adds `Clicked.emit(b.brokerCtx)` after the tier-1/2
publishes) and install their signal handlers in their constructors,
recording teardown in `disposers`.

Echo guard: widgets with a value + change slot (Input, Editor, Checkbox,
Radio, ListView, Table) gain `applying: bool`; inbound signal application
sets it; the outbound emit path checks it. Signal → `setText` →
`onChange` still fires tier-1 slots (they observe the change), but does
NOT re-emit `TextChanged`.

### D9. `on:` pragma — declarative per-instance listener installation

```nim
run    {.child, caption: "Run",    on: {Clicked: "onRun"}.}: Button
host   {.child, on: {TextChanged: "onHostEdit", Submitted: "onHostDone"}.}: Input
```

`mount(T)` lowers each pair to a ctx-scoped listen against **that field's
widget instance**:

```nim
discard Clicked.listen(self.run.brokerCtx,
  proc(e: Clicked): Future[void] {.async: (raises: []), gcsafe.} =
    {.cast(gcsafe).}: onRun(self))
self.disposers.add proc() {.gcsafe, raises: [].} =
  asyncSpawn Clicked.dropAllListeners(self.run.brokerCtx)
```

Two handler arities, resolved with `when compiles()` at the expansion
site: `proc(self: T)` and `proc(self: T, e: EvType)`.

Pragma grammar: `on:` takes an `nnkTableConstr` of `EventTypeIdent:
"handlerName"` (string literal, same rule as `bindTo`). The event ident is
spliced as a fresh ident so app-defined `uiEvents` types work too — `on:`
is not restricted to vocab.nim types.

Two buttons, same `Clicked` type, zero cross-talk: different ctx buckets.
The model may attach additional listeners on the same ctx (EventBroker is
multi-listener) — a `BrokerContext` is a plain uint32 **capability
handle**: passable to model code at wiring time, safely dead after
dispose (signals return `err`, events fan out to nobody).

### D10. `bindValue` becomes two-way: generated `set<Field>` writer

Per `bindValue: "hostVal"` field, `uiEvents(T)` additionally generates:

```nim
proc setHostVal*(self: ConnectForm, v: string) {.gcsafe, raises: [].} =
  self.hostVal = v
  discard SetText.signal(self.host.brokerCtx, text = v)
```

Explicit `set<Field>` naming, NOT a `hostVal=` property: mount/uiEvents
expand in the type's defining module, where direct field access always
shadows a same-named setter — the property idiom would silently bypass
the signal exactly where it's most used. Rejected.

No loop by construction: widget→field direction (`bindValueSlot`) writes
the field directly; field→widget direction goes through the signal whose
handler sets `applying`.

### D11. Teardown protocol — `dispose(v)`

```nim
proc dispose*(v: View) =
  for c in v.children: dispose(c)      # leaves first
  for d in v.disposers: d()            # drop listeners / signal handlers
  v.disposers.setLen 0
  # Phase 11: releaseInstanceCtx(v.brokerCtx)
```

Contract, stated in docs: **broker listener closures capture `self` (ref)
— an undisposed view is kept alive by the broker registry.** Under both
refc and ORC this is a plain strong-ref leak (no cycle needed: the
registry is a global), so `dispose` is part of the widget lifecycle, not
optional hygiene. Wiring: `Desktop.remove`/`Window.close` call `dispose`;
hand-built UIs call it explicitly.

Signal teardown uses
`SetX.replaceSignalHandler(ctx, default(SetXSignalHandler))`; event
teardown uses `dropAllListeners(ctx)` per type. Note: `dispose` drops the
form's OWN installations; model-attached listeners on a widget's ctx are
the model's to drop (it holds the listener handles).

### D12. nim-brokers prerequisite: instanceCtx recycling (cross-repo)

Add to nim-brokers (target 3.3): `releaseInstanceCtx(ctx: BrokerContext)`
returning the high-16 id to a free-list consumed by `newInstanceCtx`
before the monotonic counter. Release does NOT purge listener buckets
(brokers are per-type generated globals — no cross-type enumeration), so
the contract is *drop-then-release*, which D11's ordering guarantees.
Known hazard: a stale listener surviving into a recycled id receives the
new instance's traffic — debug builds get an assert hook (bucket must be
empty on release) to catch violations loudly.

---

## Phase 11 — nim-brokers 3.3: `releaseInstanceCtx` (in ~/dev/status/nim-brokers)

- Free-list (seq[uint16] + threadvar, matching existing single-thread
  model) behind `newInstanceCtx` / `releaseInstanceCtx`.
- Debug-only `assertCtxDrained(ctx)` helper: walks nothing globally, but
  each generated broker exposes `hasListeners(ctx)` / `hasSignalHandler(ctx)`
  so illview's debug dispose can assert per type it tears down.
- Tests in nim-brokers: recycle round-trip, exhaustion no longer asserts
  under create/release churn, stale-listener assert fires in debug.
- Tag 3.3.0; bump `illview.nimble` requires + refresh localdeps.

Exit criteria: nim-brokers suite green; 100k create/release cycles pass.
(Phases 12–14 only *call* release inside `when declared()` guards, so
illview work can proceed in parallel against 3.2.0.)

## Phase 12 — vocab + View ctx + widget wiring

- `src/illview/vocab.nim` (D8), exported from `illview.nim`.
- `View.brokerCtx` + `disposers` + `dispose` (D7, D11) in `core/view.nim`
  (`initView` blast radius: every widget constructor — run
  `gitnexus_impact` on `initView` before touching).
- Widget deltas: emit calls in Button/Checkbox/Radio/ListView/Table/Input/
  Editor activation paths; signal handler installation + `applying` guard
  in Input/Editor/Checkbox/Radio/ListView/Table/Label/ProgressBar
  constructors; `FocusMe` handler in `initView` itself (focusable check at
  signal time).
- `Desktop.remove` / `Window.close` call `dispose`.

Exit criteria (new `tests/test_ctx_vocab.nim`, StubBus-free, real brokers):
- two Buttons emit `Clicked` on distinct ctxs; listeners see only their own;
- `SetText.signal` updates an Input and does NOT re-emit `TextChanged`
  (echo guard), while a tier-1 `onChange` slot still fires;
- `signal` to a disposed widget's ctx returns `err`;
- dispose drops listeners (emit after dispose reaches nobody);
- all prior suites green (`nimble test`).

## Phase 13 — `mount(T)`: `on:` pragma

- Parse `on:` table-constructor pragma; lower to ctx-scoped `listen` +
  disposer registration (D9); both handler arities via `compiles()`.
- Composes with existing `bindTo` / `action` / `emits` on the same field
  (all four may coexist; document firing order: slot → UiAction → ctx
  event, matching activate()).
- `on:` accepts app-defined `uiEvents` types as well as vocab types.

Exit criteria (extend `tests/test_mount.nim`):
- mounted form with two buttons on `{Clicked: ...}` routes to the right
  form procs; two mounted instances of the SAME form type are isolated;
- payload arity handler receives typed payload (`TextChanged.text`);
- `dispose(form)` tears down everything mount installed;
- `on:` + `bindTo` on one field both fire.

## Phase 14 — two-way bindValue: `set<Field>` writers

- `uiEvents(T)` generates `set<Field>` per `bindValue` field whose widget
  type has a matching Set-signal (Input/Editor→SetText, Checkbox→
  SetChecked, Radio/ListView/Table→SetSelected) (D10). Fields whose widget
  has no signal (none currently) are a compile error with a clear message.
- Store-write remains direct in `bindValueSlot` (no loop).

Exit criteria (extend `tests/test_bindings.nim`):
- `form.setHostVal("x")` → widget text is "x", field is "x", no
  `TextChanged` emitted;
- user edit → field updated (existing path unchanged), `TextChanged`
  emitted once;
- `bindValue` + `bindRequest` + `set<Field>` compose: setter bypasses the
  request provider (writer is authoritative), documented.

## Phase 15 — example, docs, release hygiene

- `examples/ex10_instance_ctx.nim`: ConnectForm from the design discussion —
  two buttons/one event type, `on:` payload handlers, `setHostVal`
  two-way, async `SetProgress` driver stopping on `err`, a model-side
  extra listener on a widget ctx, and two mounted forms proving isolation.
- README: new "Communication model" section with the tier table + the
  semantic-vs-mechanical guidance; DESIGN-DEVIATIONS.md entries for
  anything that shifted during implementation.
- `nimble examples` includes ex10; screenshots task optionally regenerated.

Exit criteria: full `nimble test` + `nimble examples` green; ex10 runs;
`gitnexus_detect_changes` scope review before each phase commit.

---

## Risks / open points (tracked, not blocking)

1. **instanceCtx churn before Phase 11 lands** — 65 535 lifetime widget
   constructions per process; fine for tests/examples, release-noted.
2. **Recycled-ctx stale listeners** (D12) — debug assert; contract is
   drop-then-release.
3. **`asyncSpawn dropAllListeners` in disposers** — drop is async; between
   dispose and the spawn's turn an in-flight emit may still land. Same
   single-loop ordering as today's broker semantics; if it bites, Phase 12
   switches disposers to collect futures and `dispose` returns them for
   awaiting in async contexts.
4. **Label has no change slot** — `SetText` handler only, no echo concern.
