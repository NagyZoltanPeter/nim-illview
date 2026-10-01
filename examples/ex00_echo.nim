## Phase 1 demo: stdin -> decoder -> app callback -> dirty-driven render.
## Press keys, click/scroll the mouse, paste text. ESC quits.

import std/[strformat, unicode]
import chronos
import illview/core/app
import illview/core/events
import illview/backend/illwill_vendored

proc describe(ev: InputEvent): string =
  case ev.kind
  of ikKey:
    let r = if ev.rune.int32 >= 32: " '" & ev.rune.toUTF8 & "'" else: ""
    &"key   {ev.key}{r} mods={ev.keyMods}"
  of ikMouse:
    &"mouse {ev.action} {ev.button} @ {ev.mx},{ev.my} mods={ev.mouseMods}"
  of ikPaste:
    &"paste ({ev.text.len} bytes) \"{ev.text}\""
  of ikResize:
    "resize"

proc main() {.async.} =
  var lines: seq[string]
  let app = newApp()

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()
      return
    lines.add describe(ev)
    if lines.len > 500:
      lines.delete(0)
    app.requestRedraw()

  app.onRender = proc(tb: var TerminalBuffer) {.gcsafe, raises: [].} =
    tb.write(0, 0, "illview 00_echo - keys / mouse / paste are echoed, ESC quits")
    let visible = tb.height - 2
    let start = max(0, lines.len - visible)
    for i in start ..< lines.len:
      tb.write(0, 2 + i - start, lines[i])

  await app.run()

waitFor main()
