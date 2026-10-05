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
when defined(posix):
  from std/termios import Termios, tcGetAttr, tcSetAttr, TCSANOW
  # posix stays qualified (`posix.`): its `write`/`signal` clash with chronos'
  # and its `Group` clashes with view.Group.
  from std/posix import nil
import brokers/broker_context
import ../widgets/desktop
import ./events, ./view, ./routing, ./geometry, ./drawcontext, ./bus, ./theme

when defined(posix):
  import ../backend/driver_posix
else:
  import ../backend/driver_fallback
import ../backend/ansitext
import ../widgets/textview

# stdout/stderr capture needs POSIX fds + an internal drain thread (deviation #41)
const CaptureSupported* = defined(posix) and compileOption("threads")
when CaptureSupported:
  import ../backend/capture_posix

export illwill_vendored.TerminalBuffer

type
  App* = ref object
    desktop*: Desktop
    bus*: EventBus # NullBus by default; set newBrokersBus() for real routing
    sessionCtx*: BrokerContext # session scope every view under this app shares
    fpsCap*: int
    running*: bool
    onInput*: proc(ev: InputEvent) {.gcsafe, raises: [].}
    onRender*: proc(tb: var TerminalBuffer) {.gcsafe, raises: [].}
    captureOutput*: bool # while the TUI is up, collect stdout/stderr (deviation #41)
    captureLimit*: int   # bytes kept for replay (drop-oldest)
    onCapturedOutput*: proc(chunk: string) {.gcsafe, raises: [].}
      ## Raw captured bytes as they arrive (loop thread).
    captureSinks: seq[proc(chunk: string) {.gcsafe, raises: [].}]
    when CaptureSupported:
      capture: OutputCapture
    dirty: bool
    renderPending: bool
    tuiActive: bool
    tb: TerminalBuffer
    driver: InputDriver
    lastFrame: Moment
    quitFut: Future[void]
    lastClick: tuple[t: Moment, x, y: int, button: events.MouseButton, count: int]
    disabledCommands: seq[Command] # P22/D19: greyed + non-activatable
    modalStack: seq[tuple[view: Group, fut: Future[Command], prevFocus: View]]
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

# --- terminal restore on a fatal crash (POSIX) -------------------------------
# Nim runs `addExitProc` only on quit(), NOT on an unhandled exception or a
# signal, so a crash would otherwise leave the terminal in raw + mouse-tracking
# mode ("trash on mouse move"). A signal handler using only async-signal-safe
# write(2)/tcsetattr/sigaction fixes this, including for the SIGSEGV the ORC
# collector can raise. Normal exit still goes through run()'s `finally:
# disableTui`. The handler CHAINS (deviation #31): whatever action was installed
# before it — a host's crash reporter, Nim's own traceback handler — is
# re-installed and invoked, so embedding illview in a daemon does not silence
# the daemon's crash handling.
when defined(posix):
  type SigInfoHandler = proc (x: cint, y: ptr posix.SigInfo, z: pointer) {.noconv.}
  var gOrigTermios: Termios
  var gTermiosSaved = false
  var gSignalRestoreInstalled = false
  var gPrevActions: array[0 .. 63, posix.Sigaction] # indexed by signal number
  let CrashSignals = [posix.SIGSEGV, posix.SIGABRT, posix.SIGBUS, posix.SIGILL,
                      posix.SIGFPE] # importc vars, not compile-time constants
  const RestoreSeq =
    "\e[?1002l\e[?1003l\e[?1006l" & # mouse tracking off
    "\e[?2004l" &                   # bracketed paste off
    "\e[?25h" &                     # show cursor
    "\e[?1049l" &                   # leave the alt screen
    "\e[0m"                         # reset attributes

  proc restoreOnSignal(sig: cint, info: ptr posix.SigInfo, ctx: pointer) {.noconv.} =
    when CaptureSupported:
      captureCrashFds() # fd 1/2 back on the terminal first (deviation #41)
    discard posix.write(cint(1), cast[pointer](cstring(RestoreSeq)), RestoreSeq.len)
    if gTermiosSaved:
      discard tcSetAttr(cint(0), TCSANOW, addr gOrigTermios)
    when CaptureSupported:
      captureCrashDump() # then the captured tail, on the main screen
    # Hand the signal on. sa_handler/sa_sigaction share one union slot on every
    # POSIX we build for, so the cast reads whichever the previous owner set.
    var prev = gPrevActions[int(sig)]
    discard posix.sigaction(sig, prev, nil)
    if (prev.sa_flags and posix.SA_SIGINFO) != 0:
      cast[SigInfoHandler](prev.sa_handler)(sig, info, ctx)
    elif prev.sa_handler != posix.SIG_DFL and prev.sa_handler != posix.SIG_IGN:
      prev.sa_handler(sig)
    # else: returning re-runs the faulting op under the default action

  proc installCrashRestore*() =
    ## Idempotent; called by `enableTui` unless `-d:noCrashRestore`. Exported
    ## so the chaining behavior is testable without a terminal.
    if gSignalRestoreInstalled:
      return
    gSignalRestoreInstalled = true
    gTermiosSaved = tcGetAttr(cint(0), addr gOrigTermios) == 0
    var act: posix.Sigaction
    act.sa_handler = cast[proc (x: cint) {.noconv.}](restoreOnSignal)
    act.sa_flags = posix.SA_SIGINFO
    discard posix.sigemptyset(act.sa_mask)
    for s in CrashSignals:
      discard posix.sigaction(s, act, gPrevActions[int(s)])
proc execView*(app: App, v: Group): Future[Command] {.gcsafe, raises: [].}
proc endModal*(app: App, cmd: Command) {.gcsafe, raises: [].}

proc newApp*(fpsCap = 30, theme: Theme = nil,
             sessionCtx = BrokerContext(0), captureOutput = false): App =
  ## The App's session broker context: the scope uiEvents `emits:` events fire
  ## on and every view built under it shares (normalized to instanceCtx 0 so it
  ## equals `someView.sessionCtx`). Resolution (deviation #27): an
  ## explicit `sessionCtx` wins and is bound for views built afterwards;
  ## otherwise the thread's `globalBrokerContext()` is adopted AS-IS —
  ## `DefaultBrokerContext` included — so the UI lives on the same scope its
  ## host process keys everything on. `newApp` never installs a thread broker
  ## context; to sandbox, `setThreadBrokerContext(myCtx)` before building or
  ## pass it here. Listen with `Event.listen(app.sessionCtx, handler)`.
  let explicit = sessionCtx != BrokerContext(0)
  let raw = if explicit: sessionCtx else: globalBrokerContext()
  let sc = makeBrokerContext(classCtx(raw), 0'u16)
  bindSessionCtx(if explicit: sc else: BrokerContext(0))
  let app = App(fpsCap: fpsCap, sessionCtx: sc, captureOutput: captureOutput,
                captureLimit: 1 shl 20)
  app.driver = newInputDriver(
    proc(ev: InputEvent) {.gcsafe, raises: [].} = app.handleInput(ev))
  app.bus = newNullBus()
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
    when CaptureSupported:
      if app.capture.active:
        app.capture.syncSize() # captured programs see the new width
    app.requestRedraw() # frame() re-sizes the buffer; Phase 3 adds relayout
  if app.onInput != nil:
    app.onInput(ev) # observer hook, runs after routing

proc execView*(app: App, v: Group): Future[Command] {.gcsafe, raises: [].} =
  ## Modal loop (deviation #6): adds v on top of the desktop, confines
  ## routing to it and returns a future completed by endModal(). No nested
  ## event loop.
  let prevFocus = app.scope.focusedLeaf # remember focus BEFORE the modal steals it
  app.desktop.add v
  raiseToTop(app.desktop, v)
  let fut = newFuture[Command]("illview.execView")
  app.modalStack.add (v, fut, prevFocus)
  focusInto(app.scope, v)
  app.requestRedraw()
  fut

proc endModal*(app: App, cmd: Command) {.gcsafe, raises: [].} =
  ## Close the topmost modal view, restore the pre-modal focus, and complete
  ## its execView future.
  if app.modalStack.len == 0:
    return
  let (v, fut, prevFocus) = app.modalStack.pop()
  app.desktop.remove v
  if prevFocus != nil: # else the caller/next frame decides focus
    setFocus(app.scope, prevFocus) # scope is now the layer below the closed modal
  app.requestRedraw()
  if not fut.finished:
    fut.complete(cmd)

proc enableTui*(app: App) =
  ## Re-entrant: switch the terminal to TUI mode (altscreen, raw-ish termios,
  ## SGR mouse, bracketed paste) and start the async input driver.
  if app.tuiActive:
    return
  when defined(posix) and not defined(noCrashRestore):
    installCrashRestore() # capture the cooked termios BEFORE illwill goes raw
  when CaptureSupported:
    if app.captureOutput:
      if app.capture == nil:
        app.capture = newOutputCapture(app.captureLimit)
        app.capture.onChunk = proc(chunk: string) {.gcsafe, raises: [].} =
          for sink in app.captureSinks:
            sink(chunk)
          if app.onCapturedOutput != nil:
            app.onCapturedOutput(chunk)
      if app.capture.active:
        app.capture.setPassthrough(false) # back from terminal mode: collect again
      else:
        app.capture.start() # fd 1/2 -> pty; the renderer -> the real terminal
  illwillInit(fullScreen = true, mouse = true)
  invalidateScreen() # re-entry: full repaint, no stale diff/SGR cache (deviation #40)
  hideCursor(output()) # the renderer's handle (deviation #41)
  output().write("\e[?2004h") # bracketed paste on
  output().flushFile()
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
  output().write("\e[?2004l") # bracketed paste off
  output().flushFile()
  illwillDeinit() # exits altscreen, restores termios, shows cursor
  when CaptureSupported:
    if app.capture.active:
      try:
        output().flushFile() # the alt-screen exit reaches the terminal first
      except IOError:
        discard
      # replay the desktop-period backlog into the normal scrollback, then keep
      # passing output through live; capture (and the pane feed) stays on
      app.capture.setPassthrough(true, sanitizeForReplay)

proc captureTo*(app: App, tv: TextView) =
  ## Feed captured stdout/stderr into `tv` line by line (escape sequences
  ## stripped), as it arrives (deviation #41). Needs `captureOutput`.
  var splitter: LineSplitter
  app.captureSinks.add proc(chunk: string) {.gcsafe, raises: [].} =
    for line in splitter.feed(stripAnsi(chunk)):
      tv.addLine(line)

proc capturedOutput*(app: App): string =
  ## Captured bytes not yet replayed into the scrollback (raw).
  when CaptureSupported:
    if app.capture != nil:
      return app.capture.pending
  ""

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
    when CaptureSupported:
      if app.capture.active:
        app.capture.stop() # fd 1/2 back on the terminal for good
        app.capture.dispose()
