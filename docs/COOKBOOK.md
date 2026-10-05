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
# model side, no form knowledge. emits: fires on the app's SESSION ctx —
# never the global DefaultBrokerContext — so listen there (recipe 21).
# listenIt = brokers listener-body sugar; the event value is injected as `it`.
discard RunRequested.listenIt(app.sessionCtx):
  asyncSpawn model.startRun()

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
let h = TextChanged.listenIt(form.host.brokerCtx):  # `it` = the event
  model.hostDraft = it.text
# ... later:
waitFor TextChanged.dropAllListeners(form.host.brokerCtx)
```

(`listenIt`/`onSignalIt` expand to the same `{.async: (raises: []), gcsafe.}`
listener proc you would write by hand — pure sugar, `await` allowed.)

## 9. Live domain feeds (NetViz)

String topics with `prefix/*` wildcards — for observability streams where
dynamic topics beat typed payloads:

```nim
import illview/bus_brokers

app.bus = newBrokersBus()
let nv = newNetViz()
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

Declarative alternative — items emit typed broker events (the type IS the
action; `~X~` marks the accelerator):

```nim
EventBroker:
  type TileRequested = object

let mb = menuBar(
  menu("~F~ile", @[
    item("~T~ile windows", TileRequested),   # activation auto-emits
    sep(),
    submenu("~R~ecent", @[item("a.nim", cmdOpenA)]),
    item("~Q~uit", QuitRequested)]))

discard TileRequested.listenIt:   # NB: menu items emit on the DEFAULT ctx
  ground.tile()                   # (not the session ctx — see recipe 21)
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
  initView(result)              # captures the session scope; the instance
  result.focusable = true       # ctx is allocated on first brokerCtx use
  let d = result
  d.installSignal(SetProgress): # single handler on d's ctx + teardown,
    d.value = clamp(sig.value, 0, 100) # installed when the ctx materializes
    d.invalidate()
  d.installFocusMe()

proc turned(d: Dial) =          # user-driven path emits; setters don't
  if d.hasBrokerCtx:            # nobody can listen on a route never handed out
    SelectionChanged.emit(d.brokerCtx, SelectionChanged(selected: d.value))

# to use Dial as a {.child.} field in a {.view.} type, tell mount() how to
# build one (without this, mount() is a compile error, not a silent Dial()):
proc createView*(t: typedesc[Dial]): Dial = newDial()
# optional: let it join emits:/bindValue with a `selected` payload
template uiValueKind*(t: typedesc[Dial]): UiPayloadKind = upSelected
proc widgetValue*(w: Dial): int = w.value
proc bindValueSlot*(w: Dial, h: proc(sender: Dial) {.gcsafe, raises: [].}) =
  w.onTurn = h                  # whatever change slot your widget exposes
```

See [EXTENDING.md](EXTENDING.md) for the full extension contract.

## 16. Two-column forms, alignment & anchoring

```nim
type Settings {.view, form, spacing: 1.} = ref object of Group
  nameLbl {.child, caption: "Name".}: Label
  name    {.child, bindValue: "nameVal".}: Input
  noteLbl {.child, caption: "Note", alignSelf: alEnd.}: Label
  note    {.child, padding: 1.}: Input
  nameVal: string
```

`form` = a two-column `FormLayout` (label col auto-sizes, control col
stretches). `alignSelf` places a child within its cell (`alStretch` default,
`alStart`/`alCenter`/`alEnd`); `padding(n)` insets content; `anchors({aLeft,
aRight})` keeps a `dkNone` child's edges pinned as the parent resizes.

## 17. Scrolling: Scroller + a synced ScrollBar

```nim
let sc = newScroller(bigContent)            # bigContent taller than the viewport
# newScroller sets a stretchy size hint (deviation #30), so the viewport fills its
# slot; give it a fixed hint instead if you want a specific size.
let bar = newScrollBar(axV)
bar.onScroll = proc(pos: int) = sc.scrollTo(0, pos)   # bar drives scroller
row.add sc; row.add bar                     # side by side in an HBox
# keep the bar in step after each input (post-routing):
app.onInput = proc(ev: InputEvent) =
  bar.setRange(sc.virtualSize.h, sc.contentH, sc.offY)
```

Tab into an off-screen widget and the `Scroller` auto-scrolls to reveal it.
For a quick indicator without a live bar, set `list.showScrollbar = true`.

## 18. A draggable splitter

```nim
let split = newSplitter(axH, leftPane, rightPane, pos = 20)
split.dock = dkFill
win.add split          # drag the divider, or Tab to it and Alt+Left/Right
```

## 19. A tree with lazy children

```nim
let root = treeNode("project")
root.loader = proc(n: TreeNode): seq[TreeNode] =   # fires once, on first expand
  @[treeNode("src"), treeNode("docs")]
let tv = newTreeView(@[root])
tv.onActivate = proc(t: TreeView) = open(t.selectedNode.label)
```

## 20. Hotkeys, command gating & stock dialogs

```nim
let run = newButton("~R~un")        # Alt+R triggers it anywhere in scope
app.disableCommand(cmSave)          # greys + blocks every item carrying cmSave

# a label that focuses its field:
let lbl = newLabel("~N~ame"); lbl.linkTo = nameInput

# modal dialogs over the app loop:
if await confirm(app, "Save changes before exit?"):
  save()
let port = await inputBox(app, "Server", "Port:", filter = digitsOnly())
if port.isSome: connect(port.get)
```

`Input.filter` rejects keystrokes live (`digitsOnly`, `maxLen(n)`,
`charSet(s)`, `allOf(...)`); `intRange(lo, hi)` is a `bindRequest` provider for
value-level validation. `Input.history` + Down opens a recency picker.

## 21. Session context: where events fire & sandboxing

Every view's `brokerCtx` = a shared session `classCtx` + a unique per-instance
id, allocated the first time something asks for it (a listener, a signal, a
binding — deviation #28); a widget nobody talks to costs no id.
`view.sessionCtx` / `app.sessionCtx` is the shared part — common to all
widgets of the app. It is **the thread's `globalBrokerContext()`** at build
time (deviation #27): a plain `newApp()` on a bare thread lands on
`DefaultBrokerContext`, the same scope a host process (a node embedding the
TUI) keys its own brokers on. `newApp` never installs a thread context.

Who emits where (deviations #26/#27):

| Source                                | Context                     |
| ------------------------------------- | --------------------------- |
| `emits:` fields (uiEvents)            | `app.sessionCtx`            |
| vocab events (`Clicked`, `TextChanged`) | the widget's `brokerCtx`  |
| menu `item(label, EventType)`         | the host view's `sessionCtx`, `senderId = host.id` |
| bus `UiAction` / domain topics        | `DefaultBrokerContext`      |

Isolation is opt-in. To sandbox a UI (or keep a handle for deep model code),
install your own scope before building, or pass it explicitly:

```nim
let myCtx = NewBrokerContext()
setThreadBrokerContext(myCtx)     # BEFORE building any view: adopted by all
let app = newApp()                # app.sessionCtx == myCtx
discard RunRequested.listenIt(myCtx):   # your saved ctx receives emits
  asyncSpawn model.startRun()

let app2 = newApp(sessionCtx = otherCtx) # bound for views built after it,
                                         # thread ctx left untouched
```

## 22. MDI: floating windows in a nested Desktop

`Desktop` is the tested window surface — and it nests. Use one as the "ground"
pane whenever windows should float inside a sub-area (tile/cascade/raise/
move/resize all run the same framework code as the top level):

```nim
let ground = newDesktop()                 # right pane of a splitter, say
let split = newSplitter(axH, tree, ground, pos = 22)
split.dock = dkFill

let w = newWindow("peer list", rect(2, 1, 34, 10))   # dkNone = floating
ground.add w                               # movable, resizable, closable
ground.tile()                              # or ground.cascade()
```

Click a window to activate it (double border + `◢` resize grip) — that works
even for windows with no focusable content. After `tile()` focus is unchanged,
so click one before resizing. `onClose` that only detaches (no `dispose`) makes
windows reopenable from a cache — the persistent-object pattern (recipe 12).

## 23. Chronicles logs in a pane + TUI suspend/resume

Chronicles defaults to **stdout — the renderer owns stdout**, so route logs
through the `dynamic` sink instead (full demo: `examples/ex14_logpane.nim`).
Build with (per-file `.nim.cfg` works):

```
--define:"chronicles_sinks=textlines[dynamic]"
--define:chronicles_colors=off
```

One persistent writer routes by mode — pane while the TUI is up, plain stderr
when it is not (exactly what the program would print without a TUI):

```nim
defaultChroniclesStream.outputs[0].writer =
  proc(level: LogLevel, rec: LogOutputStr) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if gApp != nil and gApp.tuiActive:
        gLogView.addLine rec.strip(leading = false, chars = {'\r', '\n'})
        gApp.requestRedraw()
      else:
        try: stderr.write rec except IOError: discard
```

`app.disableTui()` / `app.enableTui()` are re-entrant: suspend leaves the alt
screen (shell scrollback returns, logs stream to the terminal); resume
re-registers input and forces a full redraw. The input driver stops with the
TUI, so wait for the resume key on a **dedicated tty fd** with a private
`O_NONBLOCK` — never on fd 0, whose flags are shared with stdout (see
`terminalMode` in ex14). For foreign code writing straight to fd 2, redirect
via `pipe()` + `dup2` and drain with a chronos reader instead.

## 24. A dialog the Turbo Vision way

Groups pop out by colour, no frame needed; the field and the buttons are
obvious at a glance (deviation #34). `docs/assets/tvdialog.svg` is exactly
this code (`tools/screenshots.nim` `tvDialogScene`).

```nim
let dlg = newWindow("Demo Dialog", rect(12, 2, 46, 15))
# windows and dialogs are lightgray by default; win.palette = pBlue opts out
let body = newVBox(spacing = 1)
body.dock = dkFill
body.padding = 1

let cheeses = newGroupBox("Cheeses")      # borderless: heading + cyan block
cheeses.hint = (fixedHint(16), fixedHint(3))
let cb = newVBox()
cb.dock = dkFill
cb.add newCheckbox("~H~varti")
cb.add newCheckbox("~J~arlsberg", checked = true)
cheeses.add cb
body.add cheeses

let lbl = newLabel("~D~elivery Instructions")
let inp = newInput("Leave it on the doorstep")
lbl.linkTo = inp                          # label lights up while inp is focused
body.add lbl
body.add inp

let btns = newHBox(spacing = 2)
btns.hint = (prefHint(0, stretch = 1), fixedHint(1))
let ok = newButton("O~K~")
ok.isDefault = true                       # Enter anywhere in the dialog
btns.add ok
btns.add newButton("~C~ancel")
body.add btns
dlg.add body
```

Want a frame around a group after all? `cheeses.border = bkSingle`. The old
all-blue look:
`newApp(theme = classicBlueTheme())`.

## 25. Windows as tabs

A `TabView` embeds windows frameless and switches between them; each page
keeps its state and its last-focused widget (deviation #39). This is
`examples/ex15_tabs.nim`, trimmed:

```nim
let tabs = newTabView()
tabs.dock = dkFill

let form = newWindow("Form", rect(0, 0, 0, 0))   # title = tab label
form.closable = false                            # no × on its tab
form.add buildForm()
let logw = newWindow("Log", rect(0, 0, 0, 0))
logw.palette = pBlue                             # a blue page
logw.add log

tabs.addPage(form)
tabs.addPage(logw)                               # closable: × calls close()
tabs.onSelect = proc(t: TabView) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}: log.addLine "tab " & $t.selected
win.add tabs
```

Switch with Ctrl+PgUp / Ctrl+PgDn, a click, or Tab to the strip and the
arrows. `tabs.select(i)` and `SetSelected.signal(tabs.brokerCtx, …)` switch
without firing `onSelect`. `tabs.removePage(w)` hands the window back
(framed again, not disposed) — add it to the desktop to float it.
Declaratively, `{.child.}` windows of a `{.view.}` TabView subtype become the
pages in declaration order.
