# illview cookbook

Copy-paste recipes for working with the library. The full option surface
(every pragma, widget, event, signal) is in [REFERENCE.md](REFERENCE.md).
Runnable end-to-end programs live in `examples/` (`nimble examples`).

All recipes assume:

```nim
import chronos
import illview                       # umbrella: widgets, mount, vocab
import illview/dsl/uievents          # uiEvents(T) — when noted
```

## 1. Minimal app

```nim
proc main() {.async.} =
  let app = newApp()
  let win = newWindow("hello", rect(0, 0, 0, 0))
  win.dock = dkFill
  win.add newLabel("Hello, illview")
  app.desktop.add win

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
```

## 2. A declarative form

Describe the screen as a type; `mount(T)` constructs and wires it.

```nim
type
  LoginForm {.view, vbox, spacing: 1.} = ref object of Group
    l1   {.child, caption: "user:".}: Label
    user {.child, bindValue: "userVal".}: Input
    ok   {.child, caption: "Login", on: {Clicked: "onLogin"}.}: Button
    userVal: string

uiEvents(LoginForm)

proc onLogin(self: LoginForm) {.gcsafe, raises: [].} =
  discard # self.userVal is already current here

let form = mount(LoginForm)
```

Nested components: give the field a `{.view.}` type — mount recurses.
Dynamic rows: use the `ui:` escape hatch (recipe 11).

## 3. Reacting to a click — pick the right tier

```nim
# tier 1 — sync slot, fires inside dispatch (fastest, tightly coupled):
run {.child, bindTo: "onRunSlot".}: Button
proc onRunSlot(self: F, sender: Button) {.gcsafe, raises: [].} = ...

# tier 3 — instance-ctx event: same Clicked type, per-widget routing:
run    {.child, on: {Clicked: "onRun"}.}: Button
cancel {.child, on: {Clicked: "onCancel"}.}: Button   # zero cross-talk
proc onRun(self: F) {.gcsafe, raises: [].} = ...

# tier 3b — semantic event the MODEL listens to (survives UI restructuring):
run {.child, emits: "RunRequested".}: Button
# model side, no form knowledge:
discard RunRequested.listen(
  proc(ev: RunRequested): Future[void] {.async: (raises: []), gcsafe.} =
    asyncSpawn model.startRun())

# tier 2 — command palette (menus/statusbar share the same channel):
run {.child, action: cmdRun.}: Button   # -> UiAction on app.bus
```

They compose: one field can carry all four.

## 4. Two-way value binding

`bindValue` stores widget → field; `uiEvents(T)` generates the inverse
`set<Field>` writer (field → widget, via the widget's Set-signal):

```nim
host {.child, bindValue: "hostVal".}: Input
...
uiEvents(ConnectForm)

form.setHostVal("10.0.0.1")   # store + widget update + redraw
echo form.hostVal             # user edits keep this current
```

No echo loops: the writer fires no change slots and re-emits nothing;
user edits write the store directly.

## 5. Validated input (decoupled from the widget)

```nim
port {.child, bindValue: "portVal", bindRequest: "SetPortReq".}: Input
...
uiEvents(ConnectForm)

# swap the identity provider for a validator — anywhere in the program:
discard SetPortReq.replaceProvider(DefaultBrokerContext,
  proc(value: string): Result[string, string] =
    if value.len == 0 or value.allCharsInSet({'0'..'9'}):
      ok(value)          # or return a normalized value
    else:
      err("not a number"))  # veto: the field keeps its previous value
```

Note: `form.setPortVal(v)` bypasses the provider — the writer is
authoritative.

## 6. Driving widgets from async model code

Signals target ONE widget instance via its ctx. `err` means the widget is
gone — use it as the stop condition:

```nim
proc connectFlow(form: ConnectForm) {.async.} =
  for pct in countup(0, 100, 5):
    if SetProgress.signal(form.prog.brokerCtx, SetProgress(value: pct)).isErr:
      return                      # widget disposed -> stop the driver
    await sleepAsync(60.milliseconds)
  discard SetText.signal(form.status.brokerCtx, SetText(text: "done"))
```

Deep model code that must not know the form: hand the ctx out at wiring
time — it is a plain value.

```nim
model.progressTarget = form.prog.brokerCtx          # wiring
discard SetProgress.signal(model.progressTarget,    # deep in the model
                           SetProgress(value: done))
```

## 7. Focus control

```nim
discard FocusMe.signal(form.port.brokerCtx)   # focus the port input
```

Typical: jump focus on Enter — `on: {Submitted: "onHostDone"}` and signal
the next widget in the handler.

## 8. Mirroring one specific widget into the model

Instance-ctx listening is the escape hatch for widget-bound concerns.
Model-attached listeners are YOURS to drop (see recipe 12):

```nim
let h = TextChanged.listen(form.host.brokerCtx,
  proc(ev: TextChanged): Future[void] {.async: (raises: []), gcsafe.} =
    model.hostDraft = ev.text)
# ... later:
waitFor TextChanged.dropAllListeners(form.host.brokerCtx)
```

## 9. Live domain feeds (NetViz)

String topics with `prefix/*` wildcards — for observability streams where
dynamic topics beat typed payloads:

```nim
import illview/bus_brokers

app.bus = newBrokersBus()
let nv = newNetVizWidget()
discard app.bus.subscribeDomain("relay/*",
  proc(topic, payload: string) {.gcsafe, raises: [].} =
    nv.addEvent(topic, payload))

# from node/daemon code, same chronos loop:
app.bus.publishDomain("relay/push", "1.2 kB msgHash=0xa1f3...")
```

## 10. Menus, status bar, commands

```nim
const cmdQuit = Command(1)
let mb = newMenuBar(@[menu("File", @[menuItem("Quit", cmdQuit)])])
mb.dock = dkTop
let sb = newStatusBar(@[statusItem("~ESC~ Quit", cmdQuit)])
sb.dock = dkBottom

discard onUiAction(proc(a: UiAction) {.gcsafe, raises: [].} =
  if a.cmd == cmdQuit: app.stop())   # needs app.bus = newBrokersBus()
```

## 11. Dynamic / conditional content

```nim
let form = mount(MyForm)
ui(Group(form.children[0])):     # `it` = the target container
  for peer in peers:
    it.add newLabel(peer)

lv.setItems(names)               # ListView/Table have batch setters
tbl.addRow(@["16Uiu2...", "relay"])
```

## 12. Disposing correctly

```nim
let form = mount(ConnectForm)
# ... use it ...
dispose(form)   # exactly once, when permanently done:
                # drops mount's on:-listeners + widget signal handlers,
                # recycles every ctx; idempotent
```

Rules of thumb:
- `remove()` alone keeps broker wiring alive — that's intentional
  (re-add works). Dispose only on permanent teardown.
- Anything YOU listened on a widget's ctx: drop it yourself
  (`dropAllListeners(ctx)` / keep the listen handle) — dispose only tears
  down what the framework installed.
- Undisposed views are kept alive by the broker registry (refc AND ORC).

## 13. Styling

```nim
# declarative:
pass {.child, border: bkSingle, boxTitle: "secret",
       focusFg: fgYellow.}: Input

# imperative, same effect:
w.border = bkSingle
w.styleOv.fg = fgCyan

# subtree theme:
win.theme = myTheme   # children inherit unless they set their own
```

## 14. Testing patterns (no terminal needed)

```nim
import std/unittest
# StubBus records tier-2 publishes and dispatches domain events in sync:
let stub = newStubBus()
root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}: stub.publish(a)

# drive input through the real router:
setFocus(root, form.host)
discard dispatchKey(root, keyEvent(Key.H, Rune('h')))
discard dispatchKey(root, keyEvent(Key.Enter))

# broker listeners: suspension-free handlers run eagerly inside emit, but
# pump once to let anything spawned settle:
template pump() = waitFor sleepAsync(5.milliseconds)
```

Gotchas worth knowing in tests: `suite`/`test` bodies are module-level, so
closures over their vars need `{.cast(gcsafe).}`; drop your own ctx
listeners before widgets are disposed, or the recycled ctx inherits them.

## 15. Custom widget joining the vocabulary

```nim
import illview/vocab

type Dial* = ref object of View
  value*: int

proc newDial*(): Dial =
  result = Dial()
  initView(result)              # allocates result.brokerCtx
  result.focusable = true
  let d = result
  d.installSignal(SetProgress): # single handler on d's ctx + teardown
    d.value = clamp(sig.value, 0, 100)
    d.invalidate()
  d.installFocusMe()

proc turned(d: Dial) =          # user-driven path emits; setters don't
  SelectionChanged.emit(d.brokerCtx, SelectionChanged(selected: d.value))
```
