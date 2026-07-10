## Iteration-5 showcase: a full app skeleton.
##
##   [ menu bar (declarative, EventBroker actions) ]
##   [ title bar                                    ]
##   [ tree of grouped examples | example ground    ]  <- Splitter
##   [ status bar: info items ...        clock (rt) ]
##
## Navigate the tree (Up/Down, Left/Right to fold); landing on a leaf opens
## that example as a window in the ground. Right-click the tree for a context
## menu that acts on the selected node. Menu: File > Quit, Help > About. Esc
## quits. The clock on the status bar ticks once a second.

import std/[times, strformat, unicode]
import chronos
import brokers
import ../src/illview
import ../src/illview/layout/layout

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

proc clearGround(g: Group) =
  ## Example windows are genuinely-transient content: dispose (drop wiring)
  ## then detach. Contrast the menus, which are persistent and only detached.
  while g.children.len > 0:
    let c = g.children[^1]
    g.remove(c)
    dispose(c)

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
    g.dock = dkFill
    for i in 1 .. 6:
      let l = newLabel(&"cell {i}")
      l.styleOv.bg = (if i mod 2 == 0: bgBlue else: bgGreen)
      g.add l
    body.add g
  of "Form layout":
    let f = newFormLayout(spacing = 1)
    f.dock = dkFill
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
    let ans = newLabel("answer: —")
    let btn = newButton("~a~sk")
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        proc run() {.async.} =
          let yes = await confirm(app, "Proceed?")
          ans.setText("answer: " & (if yes: "yes" else: "no"))
        asyncSpawn run()
    body.add btn
    body.add ans
  of "Input box":
    let ans = newLabel("name: —")
    let btn = newButton("~e~nter name")
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        proc run() {.async.} =
          let v = await inputBox(app, "Name", "Your name:")
          if v.isSome: ans.setText("name: " & v.get)
        asyncSpawn run()
    body.add btn
    body.add ans
  else:
    body.add newLabel("select an example on the left")

proc openExample(app: App, ground: Group, name: string) =
  clearGround(ground)
  let win = newWindow(name, rect(0, 0, 0, 0))
  win.dock = dkFill
  let body = newVBox(spacing = 1)
  body.dock = dkFill
  fillExample(app, body, name)
  win.add body
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

  # main window: tree | ground, split
  let win = newWindow("examples", rect(0, 0, 0, 0))
  win.dock = dkFill
  let ground = newGroup()
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
  tree.onSelect = proc(t: TreeView) {.gcsafe, raises: [].} =
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

  # menu action listeners (the model side)
  discard QuitRequested.listen(proc(ev: QuitRequested): Future[void] {.
    async: (raises: []), gcsafe.} =
    {.cast(gcsafe).}: app.stop())
  discard AboutRequested.listen(proc(ev: AboutRequested): Future[void] {.
    async: (raises: []), gcsafe.} =
    {.cast(gcsafe).}: discard messageBox(app, "About",
      "illview showcase — iteration 5", @[("~O~K", cmOk)]))
  discard TileRequested.listen(proc(ev: TileRequested): Future[void] {.
    async: (raises: []), gcsafe.} =
    {.cast(gcsafe).}: app.desktop.tile())

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if ev.kind == ikKey and ev.key == Key.Escape:
        app.stop()
      elif ev.kind == ikMouse and ev.action == maPress and ev.button == mbRight:
        let o = tree.absOrigin
        if ev.mx >= o.x and ev.mx < o.x + tree.contentW and
           ev.my >= o.y and ev.my < o.y + tree.contentH:
          ctx.openAt(tree, point(ev.mx, ev.my))

  setFocus(app.desktop, tree) # start with the tree focused so arrows work
  sb.setText("--:--:--")
  asyncSpawn clockLoop(app, sb)
  await app.run()

waitFor main()
