## Phase 7 demo: declarative styling — borders, colors, focus styles and
## shadows, both via pragmas (mount) and imperative setters. Tab around to
## see focus overrides; ESC quits.

import chronos
import illview
import illview/dsl/pragmas
import illview/dsl/mount

type
  StyledForm {.view, vbox, spacing: 1.} = ref object of Group
    plain {.child, caption: "plain input".}: Input
    hot {.child, caption: "focus me", focusFg: fgBlack, focusBg: bgYellow.}: Input
    boxed {.child, caption: "bordered input", border: bkSingle,
            boxTitle: "name".}: Input
    warn {.child, caption: "red on green", fg: fgRed, bg: bgGreen.}: Label
    ok {.child, caption: "OK", shadow.}: Button

proc main() {.async.} =
  let app = newApp()

  let win = newWindow("styling gallery", rect(3, 2, 40, 16))
  win.shadow = true
  win.add block:
    let form = mount(StyledForm)
    form.dock = dkFill
    View(form)

  # imperative equivalents on a second window
  let win2 = newWindow("imperative", rect(30, 10, 34, 10))
  win2.shadow = true
  let lst = newListView(@["alpha", "beta", "gamma", "delta"])
  lst.border = bkDouble
  lst.borderTitle = "pick"
  lst.styleOv.fg = fgCyan
  lst.styleOv.bright = true
  lst.dock = dkFill
  win2.add lst

  app.desktop.add win
  app.desktop.add win2

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
