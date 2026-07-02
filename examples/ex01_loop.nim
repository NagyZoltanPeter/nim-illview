## Phase 1 demo: dirty-driven capped rendering + opt-in TUI lifecycle.
##
## - an async producer bumps a tick counter once a second (mutate + redraw)
## - the frame counter shows renders only happen when something changed
## - 'd' disables the TUI for 2 seconds, then re-enables it (clean toggle)
## - ESC quits

import std/strformat
import chronos
import ../src/illview/core/app
import ../src/illview/core/events
import ../src/illview/backend/illwill_vendored

proc main() {.async.} =
  let app = newApp()
  var ticks = 0
  var frames = 0
  var keys = 0
  var lastKey = "-"

  proc ticker() {.async.} =
    while true:
      await sleepAsync(1.seconds)
      if not app.running: # checked after the first sleep: run() started by then
        break
      inc ticks
      app.requestRedraw()

  proc toggle() {.async.} =
    app.disableTui()
    echo "TUI disabled for 2s (daemon-style headless mode), still running..."
    await sleepAsync(2.seconds)
    if app.running:
      app.enableTui()

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey:
      case ev.key
      of Key.Escape:
        app.stop()
        return
      of Key.D:
        asyncSpawn toggle()
        return
      else:
        inc keys
        lastKey = $ev.key
      app.requestRedraw()

  app.onRender = proc(tb: var TerminalBuffer) {.gcsafe, raises: [].} =
    inc frames
    tb.write(2, 1, "illview 01_loop - dirty-driven, fps-capped render loop")
    tb.write(2, 3, &"ticks (1/s async producer): {ticks}")
    tb.write(2, 4, &"keys pressed:               {keys} (last: {lastKey})")
    tb.write(2, 5, &"frames rendered:            {frames}")
    tb.write(2, 7, "frames only advance on ticks/keys - idle costs nothing")
    tb.write(2, 8, "'d' = disable TUI for 2s, ESC = quit")

  asyncSpawn ticker()
  await app.run()

waitFor main()
