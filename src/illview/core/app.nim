## App context and the dirty-driven, fps-capped render loop (§3.7, Phase 1).
##
## Rendering is demand-scheduled rather than a fixed ticker: `requestRedraw`
## sets the dirty flag and arms a one-shot frame task that waits out the
## remainder of the fps period (default 30) before calling the blocking,
## single-shot `frame()`. An idle app therefore has *no* pending timers and
## zero render cost — strictly stronger than the plan's "capped ticker"
## wording, same observable behavior.
##
## Phase 1 exposes `onInput`/`onRender` hooks; Phase 2 replaces them with
## view-tree routing and drawing (the hooks remain as escape hatches).

import chronos
import ../backend/illwill_vendored
import ../widgets/desktop
import ./events, ./view, ./routing, ./geometry, ./drawcontext, ./bus, ./theme

when defined(posix):
  import ../backend/driver_posix
else:
  import ../backend/driver_fallback

export illwill_vendored.TerminalBuffer

type
  App* = ref object
    desktop*: Desktop
    bus*: EventBus # StubBus by default; real nim-brokers bus in Phase 6
    fpsCap*: int
    running*: bool
    onInput*: proc(ev: InputEvent) {.gcsafe, raises: [].}
    onRender*: proc(tb: var TerminalBuffer) {.gcsafe, raises: [].}
    dirty: bool
    renderPending: bool
    tuiActive: bool
    tb: TerminalBuffer
    driver: InputDriver
    lastFrame: Moment
    quitFut: Future[void]
    lastClick: tuple[t: Moment, x, y: int, button: events.MouseButton, count: int]
    disabledCommands: seq[Command] # P22/D19: greyed + non-activatable
    modalStack: seq[tuple[view: Group, fut: Future[Command]]]
    when compileOption("threads"):
      loopThreadId: int

func nextClicks*(last: tuple[t: Moment, x, y: int, button: events.MouseButton, count: int];
                 t: Moment; x, y: int; button: events.MouseButton;
                 window = milliseconds(300)): int =
  ## Click count for a fresh press given the previous one: same button, within
  ## one cell, inside the double-click window => increment; else a new single.
  if button == last.button and abs(x - last.x) <= 1 and abs(y - last.y) <= 1 and
     (t - last.t) <= window:
    last.count + 1
  else:
    1

proc handleInput(app: App, ev: InputEvent) {.gcsafe, raises: [].}
proc requestRedraw*(app: App) {.gcsafe, raises: [].}
proc execView*(app: App, v: Group): Future[Command] {.gcsafe, raises: [].}
proc endModal*(app: App, cmd: Command) {.gcsafe, raises: [].}

proc newApp*(fpsCap = 30, theme: Theme = nil): App =
  let app = App(fpsCap: fpsCap)
  app.driver = newInputDriver(
    proc(ev: InputEvent) {.gcsafe, raises: [].} = app.handleInput(ev))
  app.bus = newStubBus()
  app.desktop = newDesktop(theme)
  app.desktop.invalidateCb = proc() {.gcsafe, raises: [].} =
    app.requestRedraw()
  app.desktop.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
    if app.bus != nil:
      {.cast(raises: []).}:
        app.bus.publish(a)
  app.desktop.runModalCb = proc(g: Group) {.gcsafe, raises: [].} =
    discard app.execView(g) # commands flow via the bus; future unused here
  app.desktop.endModalCb = proc(cmd: Command) {.gcsafe, raises: [].} =
    app.endModal(cmd)
  app.desktop.commandEnabledCb = proc(cmd: Command): bool {.gcsafe, raises: [].} =
    cmd notin app.disabledCommands
  app

proc focus*(app: App): View =
  ## The focused leaf of the desktop chain (deviation #5: derived, not stored).
  app.desktop.focusedLeaf

proc isCommandEnabled*(app: App, cmd: Command): bool =
  cmd notin app.disabledCommands

proc disableCommand*(app: App, cmd: Command) =
  ## Grey out and block a command across menu/status/buttons (plan-4 D19).
  if cmd != cmdNone and cmd notin app.disabledCommands:
    app.disabledCommands.add cmd
    app.requestRedraw()

proc enableCommand*(app: App, cmd: Command) =
  let i = app.disabledCommands.find(cmd)
  if i >= 0:
    app.disabledCommands.delete(i)
    app.requestRedraw()

proc scope(app: App): Group =
  ## Routing scope: top modal view when a modal is active, else the desktop.
  if app.modalStack.len > 0:
    app.modalStack[^1].view
  else:
    Group(app.desktop)

proc tuiActive*(app: App): bool = app.tuiActive

proc assertLoopThread(app: App) =
  ## Single-thread invariant (plan §6). Without --threads there is nothing to
  ## check — the program cannot have a second thread.
  when compileOption("threads"):
    if app.loopThreadId == 0:
      app.loopThreadId = getThreadId()
    else:
      assert getThreadId() == app.loopThreadId,
        "illview: frame()/input callback left the chronos loop thread"

proc frame*(app: App) =
  ## Blocking single-shot render: (re)size buffer to the terminal, clear,
  ## draw, display(). The ONLY place display() is ever called.
  if not app.tuiActive:
    return
  app.assertLoopThread()
  # some ptys report 0x0 before a size is set; keep the buffer constructible
  let w = max(terminalWidth(), 1)
  let h = max(terminalHeight(), 1)
  if app.tb == nil or app.tb.width != w or app.tb.height != h:
    app.tb = newTerminalBuffer(w, h)
  else:
    app.tb.clear()
  if app.desktop != nil:
    # arrange every frame: pure and cheap at TUI scale, and it makes resize
    # reflow free (frame only runs when dirty anyway)
    app.desktop.arrange(rect(0, 0, w, h))
    app.desktop.draw(initDrawContext(app.tb))
  if app.onRender != nil:
    app.onRender(app.tb) # escape hatch: draws over the tree
  app.tb.display()
  app.dirty = false
  app.lastFrame = Moment.now()

proc scheduleFrame(app: App) {.gcsafe, raises: [].} =
  if app.renderPending or not app.tuiActive:
    return
  app.renderPending = true
  proc frameSoon() {.async.} =
    let minPeriod = milliseconds(1000 div max(app.fpsCap, 1))
    let sinceLast = Moment.now() - app.lastFrame
    if sinceLast < minPeriod:
      await sleepAsync(minPeriod - sinceLast)
    app.renderPending = false
    if app.dirty and app.tuiActive:
      try:
        app.frame() # display()/terminalWidth() can raise IOError
      except CatchableError:
        discard # a failed frame must not kill the loop; next redraw retries
  asyncSpawn frameSoon()

proc requestRedraw*(app: App) {.gcsafe, raises: [].} =
  app.dirty = true
  app.scheduleFrame()

proc handleInput(app: App, ev: InputEvent) {.gcsafe, raises: [].} =
  app.assertLoopThread()
  case ev.kind
  of ikKey:
    discard dispatchKey(app.scope, ev)
  of ikMouse:
    var clicks = 1
    if ev.action == maPress:
      let now = Moment.now()
      clicks = nextClicks(app.lastClick, now, ev.mx, ev.my, ev.button)
      app.lastClick = (now, ev.mx, ev.my, ev.button, clicks)
    dispatchMouse(app.scope, ev, clicks)
  of ikPaste:
    discard dispatchPaste(app.scope, ev.text)
  of ikResize:
    app.requestRedraw() # frame() re-sizes the buffer; Phase 3 adds relayout
  if app.onInput != nil:
    app.onInput(ev) # observer hook, runs after routing

proc execView*(app: App, v: Group): Future[Command] {.gcsafe, raises: [].} =
  ## Modal loop (deviation #6): adds v on top of the desktop, confines
  ## routing to it and returns a future completed by endModal(). No nested
  ## event loop.
  app.desktop.add v
  raiseToTop(app.desktop, v)
  let fut = newFuture[Command]("illview.execView")
  app.modalStack.add (v, fut)
  focusInto(app.scope, v)
  app.requestRedraw()
  fut

proc endModal*(app: App, cmd: Command) {.gcsafe, raises: [].} =
  ## Close the topmost modal view and complete its execView future.
  if app.modalStack.len == 0:
    return
  let (v, fut) = app.modalStack.pop()
  app.desktop.remove v
  app.requestRedraw()
  if not fut.finished:
    fut.complete(cmd)

proc enableTui*(app: App) =
  ## Re-entrant: switch the terminal to TUI mode (altscreen, raw-ish termios,
  ## SGR mouse, bracketed paste) and start the async input driver.
  if app.tuiActive:
    return
  illwillInit(fullScreen = true, mouse = true)
  hideCursor()
  stdout.write("\e[?2004h") # bracketed paste on
  stdout.flushFile()
  app.tb = nil # force full-size rebuild on first frame
  app.tuiActive = true
  app.driver.start()
  app.requestRedraw()

proc disableTui*(app: App) =
  ## Re-entrant: stop the driver and restore the terminal. A disabled app is
  ## headless: no reader registered, no timers armed, zero UI cost.
  if not app.tuiActive:
    return
  app.tuiActive = false
  app.driver.stop()
  stdout.write("\e[?2004l") # bracketed paste off
  stdout.flushFile()
  illwillDeinit() # exits altscreen, restores termios, shows cursor

proc stop*(app: App) {.gcsafe, raises: [].} =
  ## Ends run(). Safe to call from any handler.
  if app.running:
    app.running = false
    if app.quitFut != nil and not app.quitFut.finished:
      app.quitFut.complete()

proc run*(app: App) {.async.} =
  ## Enable the TUI and return when stop() is called.
  app.running = true
  app.quitFut = newFuture[void]("illview.app.run")
  app.enableTui()
  try:
    await app.quitFut
  finally:
    app.disableTui()
