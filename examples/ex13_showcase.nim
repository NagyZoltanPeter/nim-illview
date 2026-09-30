## Iteration-5 showcase: a full app skeleton.
##
##   [ menu bar (declarative, EventBroker actions) ]
##   [ title bar                                    ]
##   [ tree of grouped examples | example ground    ]  <- Splitter
##   [ status bar: info items ...        clock (rt) ]
##
## Navigate the tree (Up/Down, Left/Right to fold); Enter opens the selected
## leaf as a floating window in the ground — a nested Desktop, the framework's
## tested MDI surface. Open several: click a window to activate it (double
## border + ◢ grip), drag its title to move, drag ◢ or Alt+Shift+Arrows to
## resize, [■] to close. File > Tile arranges them in a grid (click one
## afterwards to resize it). Right-click the tree for a context menu; File >
## Quit, Help > About; Esc quits. The status-bar clock ticks once a second.

import std/[times, strformat, unicode, tables]
import chronos
import brokers
import illview

# --- menu action events (2b: item(label, EventType) auto-emits these) --------

EventBroker:
  type QuitRequested = object
    tag: int
EventBroker:
  type AboutRequested = object
    tag: int
EventBroker:
  type TileRequested = object
    tag: int
EventBroker:
  type ShowConfirm = object
    tag: int
EventBroker:
  type ShowInput = object
    tag: int

# --- a centered title-bar strip ----------------------------------------------

type TitleBar = ref object of View
  caption: string

proc newTitleBar(caption: string): TitleBar =
  result = TitleBar(caption: caption)
  initView(result)
  result.dock = dkTop
  result.hint = (prefHint(0, stretch = 1), fixedHint(1))

method draw(t: TitleBar, dc: DrawContext) =
  let st = style(fgWhite, bgMagenta, bright = true)
  dc.fill(rect(0, 0, t.bounds.w, 1), " ", st)
  let x = max((t.bounds.w - t.caption.runeLen) div 2, 0)
  dc.write(x, 0, t.caption, st)

# --- example windows (opened in the ground on tree selection) ----------------

var exCache: tables.Table[string, Window]
  ## Persistent-membership (deviation #21): each example window is built ONCE
  ## and cached, then only add/removed from the ground. No dispose/rebuild
  ## churn — which also sidesteps the ORC cycle-collector SIGSEGV that hits
  ## when app-capturing closures are repeatedly freed under --mm:orc.

proc fillExample(app: App, body: Group, name: string) =
  case name
  of "Buttons & choices":
    body.add newButton("~O~K")
    body.add newCheckbox("enable feature", checked = true)
    body.add newRadio(@["refc", "orc", "arc"], selected = 1)
  of "Input & validation":
    let port = newInput("8080")
    port.filter = digitsOnly()
    body.add newLabel("digits only:")
    body.add port
    let hist = newInput("")
    hist.history = @["wss://a.example", "wss://b.example"]
    body.add newLabel("Down = history:")
    body.add hist
  of "List & table":
    var items: seq[string]
    for i in 1 .. 20: items.add &"item {i:02}"
    let lst = newListView(items)
    lst.showScrollbar = true
    body.add lst
  of "Progress & tree":
    let pb = newProgressBar(); pb.setValue(62)
    body.add pb
    body.add newTreeView(@[treeNode("root", @[treeNode("a"), treeNode("b")])])
  of "Box / grid":
    let g = newGrid(cols = 3, spacing = 1)
    g.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1)) # fill the box body
    for i in 1 .. 6:
      let l = newLabel(&"cell {i}")
      l.styleOv.bg = (if i mod 2 == 0: bgBlue else: bgGreen)
      g.add l
    body.add g
  of "Form layout":
    let f = newFormLayout(spacing = 1)
    f.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1)) # fill the box body
    f.add newLabel("Host"); f.add newInput("node.example")
    f.add newLabel("Port"); f.add newInput("8000")
    f.add newLabel("TLS"); f.add newCheckbox("", checked = true)
    body.add f
  of "Splitter":
    var items: seq[string]
    for i in 1 .. 12: items.add &"peer {i:02}"
    let log = newTextView()
    for i in 1 .. 20: log.addLine &"[{i:03}] event"
    let sp = newSplitter(axH, newListView(items), log, pos = 14)
    sp.dock = dkFill
    body.add sp
  of "Borders & shadows":
    let gb = newGroupBox("options")
    let inner = newVBox(); inner.dock = dkFill
    inner.add newCheckbox("bordered", checked = true)
    gb.add inner
    body.add gb
  of "Colors & focus":
    let a = newLabel("red on green"); a.styleOv.fg = fgRed; a.styleOv.bg = bgGreen
    let b = newInput("focus me — cyan"); b.styleOv.focusBg = bgCyan
    body.add a
    body.add b
  of "Message box":
    let btn = newButton("show ~m~essage")
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        discard messageBox(app, "Info", "Hello from illview!", @[("~O~K", cmOk)])
    body.add btn
  of "Confirm":
    # NB: the button emits a plain broker event that captures NOTHING; a
    # persistent listener (wired once, at startup) opens the dialog. Capturing
    # `app` in a per-example closure and rebuilding it churns app->…->closure->
    # app cycles that trip the ORC collector (deviation #22).
    let btn = newButton("~a~sk")
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} = emit(ShowConfirm())
    body.add btn
    body.add newLabel("(click to open a confirm dialog)")
  of "Input box":
    let btn = newButton("~e~nter name")
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} = emit(ShowInput())
    body.add btn
    body.add newLabel("(click to open an input dialog)")
  else:
    body.add newLabel("select an example on the left")

const exampleNames = [
  "Buttons & choices", "Input & validation", "List & table", "Progress & tree",
  "Box / grid", "Form layout", "Splitter",
  "Borders & shadows", "Colors & focus",
  "Message box", "Confirm", "Input box"]

proc prebuildExamples(app: App, ground: Group) =
  ## Build every example window ONCE, up front — SYNCHRONOUSLY, before the
  ## event loop starts. (Building app-capturing closures *inside* the poll loop
  ## trips the ORC cycle collector — deviation #22 — and the example buttons
  ## deliberately capture nothing.) The windows are floating MDI children of the
  ## ground: movable, resizable (◢), and closable ([■], which just detaches so
  ## the cache keeps them).
  for name in exampleNames:
    let win = newWindow(name, rect(0, 0, 34, 10)) # floating; cascaded on open
    win.onClose = proc(w: Window) {.gcsafe, raises: [].} = # detach, don't dispose
      if w.parent != nil:
        let p = w.parent
        p.remove(w)
        p.invalidate()
    let body = newVBox(spacing = 1)
    body.dock = dkFill
    fillExample(app, body, name)
    win.add body
    exCache[name] = win

proc openExample(app: App, ground: Group, name: string) =
  ## Open a pre-built example as a floating window in the ground. Already open?
  ## raise it. Multiple can coexist so File > Tile can arrange them.
  let win = exCache.getOrDefault(name)
  if win == nil:
    return
  if win.parent == ground: # already open -> bring to front
    raiseToTop(ground, win)
  else:
    let n = ground.children.len # cascade the new window
    win.bounds = rect(min(n * 2, max(ground.contentW - 34, 0)),
                      min(n * 1, max(ground.contentH - 10, 0)), 34, 10)
    ground.add win
  app.requestRedraw()

# --- the app -----------------------------------------------------------------

proc clockLoop(app: App, sb: StatusBar) {.async.} =
  while true:
    await sleepAsync(1000)
    if not app.running: break
    sb.setText(now().format("HH:mm:ss"))

proc main() {.async.} =
  let app = newApp()

  # menu bar — declarative, items emit EventBroker actions (2b)
  let mb = menuBar(
    menu("~F~ile", @[
      item("~T~ile windows", TileRequested),
      sep(),
      item("~Q~uit", QuitRequested)]),
    menu("~H~elp", @[item("~A~bout", AboutRequested)]))
  app.desktop.add mb
  app.desktop.add newTitleBar("illview — showcase")

  let sb = newStatusBar(@[
    statusItem("↑↓ navigate", cmdNone),
    statusItem("Enter open", cmdNone),
    statusItem("RClick menu", cmdNone),
    statusItem("Esc quit", cmdNone)])
  app.desktop.add sb

  # main window: tree | ground, split. The ground is a nested Desktop — the
  # framework's tested MDI surface (deviation #25): example windows are its
  # floating children, so tile/cascade/raise/resize all run the same code as
  # the top-level desktop. The tree + splitter stay docked on the left.
  let win = newWindow("examples", rect(0, 0, 0, 0))
  win.dock = dkFill
  let ground = newDesktop()
  let tree = newTreeView(@[
    treeNode("Widgets", @[
      treeNode("Buttons & choices"), treeNode("Input & validation"),
      treeNode("List & table"), treeNode("Progress & tree")]),
    treeNode("Layout", @[
      treeNode("Box / grid"), treeNode("Form layout"), treeNode("Splitter")]),
    treeNode("Styling", @[
      treeNode("Borders & shadows"), treeNode("Colors & focus")]),
    treeNode("Dialogs", @[
      treeNode("Message box"), treeNode("Confirm"), treeNode("Input box")])])
  tree.roots[0].expanded = true
  tree.onActivate = proc(t: TreeView) {.gcsafe, raises: [].} = # Enter opens a leaf
    {.cast(gcsafe).}:
      let n = t.selectedNode
      if n != nil and not n.hasKids:
        openExample(app, ground, n.label)
  let split = newSplitter(axH, tree, ground, pos = 22)
  split.dock = dkFill
  win.add split
  app.desktop.add win

  # right-click context menu on the tree (built once, reused)
  let ctx = newContextMenu(@[
    item("~E~xpand", proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: tree.expand()),
    item("~C~ollapse", proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: tree.collapse()),
    sep(),
    item("~O~pen", proc() {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        let n = tree.selectedNode
        if n != nil and not n.hasKids: openExample(app, ground, n.label))])

  # menu action listeners (the model side) — listenIt body sugar (brokers 3.2.1)
  discard QuitRequested.listenIt:
    {.cast(gcsafe).}: app.stop()
  discard AboutRequested.listenIt:
    {.cast(gcsafe).}: discard messageBox(app, "About",
      "illview showcase — iteration 5", @[("~O~K", cmOk)])
  discard TileRequested.listenIt:
    {.cast(gcsafe).}: (ground.tile(); app.requestRedraw())
  # dialog examples: one persistent listener each (no per-example app capture)
  discard ShowConfirm.listenIt:
    {.cast(gcsafe).}:
      try:
        let yes = await confirm(app, "Proceed?")
        discard messageBox(app, "Result", "you chose: " & (if yes: "yes" else: "no"),
          @[("~O~K", cmOk)])
      except CatchableError: discard
  discard ShowInput.listenIt:
    {.cast(gcsafe).}:
      try:
        let v = await inputBox(app, "Name", "Your name:")
        discard messageBox(app, "Result",
          (if v.isSome: "you typed: " & v.get else: "(cancelled)"), @[("~O~K", cmOk)])
      except CatchableError: discard

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if ev.kind == ikKey and ev.key == Key.Escape:
        app.stop()
      elif ev.kind == ikMouse and ev.action == maPress and ev.button == mbRight:
        let o = tree.absOrigin
        if ev.mx >= o.x and ev.mx < o.x + tree.contentW and
           ev.my >= o.y and ev.my < o.y + tree.contentH:
          ctx.openAt(tree, point(ev.mx, ev.my))

  {.cast(gcsafe).}: prebuildExamples(app, ground) # build all windows up front
  setFocus(app.desktop, tree) # start with the tree focused so arrows work
  sb.setText("--:--:--")
  asyncSpawn clockLoop(app, sb)
  await app.run()

waitFor main()
