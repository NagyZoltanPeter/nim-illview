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
import ./events

when defined(posix):
  import ../backend/driver_posix
else:
  import ../backend/driver_fallback

export illwill_vendored.TerminalBuffer

type
  App* = ref object
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
    when compileOption("threads"):
      loopThreadId: int

proc handleInput(app: App, ev: InputEvent) {.gcsafe, raises: [].}

proc newApp*(fpsCap = 30): App =
  let app = App(fpsCap: fpsCap)
  app.driver = newInputDriver(
    proc(ev: InputEvent) {.gcsafe, raises: [].} = app.handleInput(ev))
  app

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
  if app.onRender != nil:
    app.onRender(app.tb)
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
      app.frame()
  asyncSpawn frameSoon()

proc requestRedraw*(app: App) {.gcsafe, raises: [].} =
  app.dirty = true
  app.scheduleFrame()

proc handleInput(app: App, ev: InputEvent) {.gcsafe, raises: [].} =
  app.assertLoopThread()
  if ev.kind == ikResize:
    app.requestRedraw() # frame() re-sizes the buffer
  if app.onInput != nil:
    app.onInput(ev)

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
