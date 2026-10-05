## Stock dialogs (Phase 25, plan-4 D20): messageBox / inputBox / confirm built
## as plain compositions over the App modal loop (execView). Esc cancels,
## Enter fires the default (OK) path; button captions take ~tilde~ accelerators.

import std/[options, unicode]
import chronos
import ../core/[geometry, theme, bus, view, events, hotkey, app]
import ./window, ./button, ./label, ./input
import ../layout/layout

type
  Dialog = ref object of Window
    cancelCmd: Command

method handleEvent*(d: Dialog, ev: Event): bool {.gcsafe, raises: [].} =
  if ev.kind == evKey and ev.ikey.key == Key.Escape:
    d.endModal(d.cancelCmd)
    return true
  procCall Window(d).handleEvent(ev)

proc closeWith(c: Command): proc(s: Button) {.gcsafe, raises: [].} =
  ## Factory so each button's onClick binds its OWN command (a closure created
  ## directly in a loop body would share one location — Nim capture gotcha).
  (proc(s: Button) {.gcsafe, raises: [].} = s.endModal(c))

proc buttonRow(buttons: seq[(string, Command)]): BoxLayout =
  result = newHBox(spacing = 1)
  result.dock = dkBottom
  for i, (cap, cmd) in buttons:
    let b = newButton(cap)
    b.onClick = closeWith(cmd)
    b.isDefault = i == 0 # first button = default (Enter)
    result.add b

proc buttonsWidth(buttons: seq[(string, Command)]): int =
  for (cap, _) in buttons:
    result += parseHotkey(cap).text.runeLen + 4 + 1 + 1 # "> cap <" + shift cell + spacing

proc newDialog(app: App, title: string, w, h: int, cancel: Command): Dialog =
  result = Dialog(borderTitle: title, closable: false, zoomable: false,
                  cancelCmd: cancel)
  initView(result)
  result.border = bkSingle
  result.palette = pGray # TV dialogs use the gray window palette (deviation #34)
  let dw = max(app.desktop.contentW, w)
  let dh = max(app.desktop.contentH, h)
  result.bounds = rect((dw - w) div 2, (dh - h) div 2, w, h) # centred

proc messageBox*(app: App, title, text: string,
                 buttons: seq[(string, Command)] = @[("~O~K", cmOk)],
                 cancel = cmCancel): Future[Command] =
  ## Modal message with a button row; the future resolves to the chosen
  ## command (or `cancel` on Esc). Default button = the first, focused.
  let w = max(text.len, buttonsWidth(buttons)) + 4
  let dlg = newDialog(app, title, w, 7, cancel)
  let lbl = newLabel(text)
  lbl.dock = dkTop
  dlg.add lbl
  dlg.add buttonRow(buttons)
  app.execView(dlg)

proc confirm*(app: App, text: string, title = "Confirm"): Future[bool] {.async.} =
  ## Yes/No dialog -> bool. Esc == No.
  let cmd = await messageBox(app, title, text,
    @[("~Y~es", cmYes), ("~N~o", cmNo)], cancel = cmNo)
  return cmd == cmYes

proc inputBox*(app: App, title, prompt: string, initial = "",
               filter: KeyFilter = nil): Future[Option[string]] {.async.} =
  ## Prompt for a line of text -> some(text) on OK/Enter, none on Cancel/Esc.
  ## `filter` (D18) applies to the field.
  let inp = newInput(initial)
  inp.filter = filter
  inp.dock = dkTop
  inp.onSubmit = proc(s: Input) {.gcsafe, raises: [].} =
    s.endModal(cmOk) # Enter in the field accepts
  let w = max(prompt.len, 20) + 4
  let dlg = newDialog(app, title, w, 8, cmCancel)
  let lbl = newLabel(prompt)
  lbl.dock = dkTop
  dlg.add lbl
  dlg.add inp
  dlg.add buttonRow(@[("~O~K", cmOk), ("~C~ancel", cmCancel)])
  let cmd = await app.execView(dlg)
  if cmd == cmOk: some(inp.text) else: none(string)
