## Chronicles-in-a-pane demo + TUI toggle.
##
## chronicles is compiled with the `dynamic` sink (see ex14_logpane.nim.cfg),
## so every log record flows through ONE runtime writer that routes by mode:
##   TUI on  -> TextView pane (addLine + requestRedraw)
##   TUI off -> stderr, exactly as the program would log without a TUI
##
## A logger task ticks once a second. F2 suspends the TUI (alt screen is left,
## your shell scrollback returns, logs stream to the terminal); Enter resumes.
## Esc quits. Terminal-mode logs stay in the normal-screen scrollback, so you
## can still read them after the app exits.
##
## Output capture (deviation #41): every third tick the program also writes
## plainly to stdout (`echo`) and stderr — what a library or child process
## would do. With `captureOutput` those writes never touch the TUI: they show
## up in the pane (`captureTo`) and, on F2, are replayed into the terminal's
## scrollback, so you can scroll back to what was printed in desktop mode.
## Capture stays on in terminal mode too (output passes through live), so the
## pane and the scrollback both hold every line, whichever mode printed it;
## with capture on, chronicles simply writes to stderr like any other code.
##
## Memory model: builds under --mm:orc and --mm:refc. The chronicles writer is
## ONE persistent closure over two globals (no per-widget app-capturing
## closures, no churn — deviation #22 pattern).

import std/strutils
import chronos
import chronicles
from std/posix import nil # qualified: write/signal/raise clash with chronos
import illview

# --- log routing (the point of the demo) --------------------------------------

var gApp: App
var gLogView: TextView

proc installLogRouter() =
  ## chronicles -> widget while the TUI is up, else -> stderr (plain terminal
  ## behavior). The record arrives as one plain-text line (colors are off in
  ## the .cfg) with a trailing newline. The writer runs on whichever thread
  ## logs: here that is the single chronos loop thread. A host with logging
  ## worker threads must not route them through this sink into the widget —
  ## bring such records to the loop thread first (nim-brokers `(mt)`).
  defaultChroniclesStream.outputs[0].writer =
    proc(logLevel: LogLevel, logRecord: LogOutputStr) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if gApp != nil and gApp.captureOutput and CaptureSupported:
          # capture on: one path. stderr is captured -> the pane (captureTo)
          # and the terminal (replay on F2, live passthrough in terminal mode)
          try:
            stderr.write logRecord
          except IOError:
            discard
        elif gApp != nil and gApp.tuiActive and gLogView != nil:
          gLogView.addLine logRecord.strip(leading = false, chars = {'\r', '\n'})
          gApp.requestRedraw()
        else:
          try:
            stderr.write logRecord
          except IOError:
            discard

# --- periodic logging ----------------------------------------------------------

proc logLoop(app: App) {.async.} =
  var n = 0
  while true:
    await sleepAsync(1000)
    if not app.running:
      break
    inc n
    let mode = if app.tuiActive: "tui" else: "terminal"
    if n mod 5 == 0:
      warn "every fifth tick is a warning", tick = n, mode
    else:
      info "heartbeat", tick = n, mode
    if n mod 3 == 0: # plain writes, as a library would do them
      echo "plain stdout write, tick ", n
      try:
        stderr.writeLine "plain stderr write, tick " & $n
      except IOError:
        discard

# --- TUI suspend / resume -------------------------------------------------------

proc terminalMode(app: App) {.async.} =
  ## Leave the TUI: the input driver stops with it, so we wait for Enter on a
  ## DEDICATED tty fd. Private fd + O_NONBLOCK on purpose — fd 0/1/2 share one
  ## file description, so O_NONBLOCK on stdin would break stdout writes with
  ## EAGAIN (same pitfall documented in driver_posix.nim).
  app.disableTui()
  try:
    stderr.write "\n-- TUI suspended; chronicles logs stream here. " &
                 "Press Enter to resume --\n"
  except IOError:
    discard
  var fd: cint = -1
  let name = posix.ttyname(cint(0))
  if name != nil:
    fd = posix.open(name, posix.O_RDONLY or posix.O_NONBLOCK)
  if fd < 0:
    await sleepAsync(2000) # headless fallback: auto-resume
  else:
    var buf: array[64, byte]
    var resume = false
    while not resume and app.running:
      await sleepAsync(100)
      while true:
        let n = posix.read(fd, addr buf[0], buf.len)
        if n <= 0:
          break
        for i in 0 ..< n:
          if char(buf[i]) == '\n' or char(buf[i]) == '\r':
            resume = true
    discard posix.close(fd)
  if app.running:
    app.enableTui() # full-size redraw; the driver re-registers
    info "TUI resumed"

# --- the app ---------------------------------------------------------------------

proc main() {.async.} =
  installLogRouter()
  info "starting up (TUI not yet enabled: this line goes to the terminal)"

  let app = newApp(captureOutput = true) # stdout/stderr collected while the TUI is up
  let win = newWindow("chronicles log", rect(0, 0, 0, 0))
  win.dock = dkFill
  let log = newTextView(maxLines = 200)
  log.dock = dkFill
  win.add log
  app.desktop.add win
  app.captureTo(log) # captured stdout/stderr lines land in the same pane
  app.desktop.add newStatusBar(@[
    statusItem("F2 terminal mode", cmdNone),
    statusItem("Esc quit", cmdNone)])

  {.cast(gcsafe).}:
    gApp = app
    gLogView = log

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if ev.kind == ikKey:
        if ev.key == Key.Escape:
          app.stop()
        elif ev.key == Key.F2 and app.tuiActive:
          asyncSpawn terminalMode(app)

  asyncSpawn logLoop(app)
  info "TUI starting: subsequent records land in the pane"
  await app.run()
  info "TUI stopped (back on the terminal)"

waitFor main()
