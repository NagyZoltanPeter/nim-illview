## Phase 15 demo (plan-3): instance-ctx events & signals.
## TWO instances of the same ConnectForm are mounted side by side — every
## widget owns a BrokerContext, so the SAME event type (Clicked,
## TextChanged, ...) routes per instance with zero cross-talk, and the model
## drives widgets it never imports via Set-signals on their ctx.
##   - Run starts an async progress driver fed by SetProgress.signal; it
##     stops the moment the widget disappears (signal returns err)
##   - host uses the two-way binding: user edits store into hostVal
##     (bindValue), setHostVal() writes back to the widget (D10 writer)
##   - a model-side listener live-mirrors the LEFT form's host input only —
##     instance-ctx listening as the escape hatch (right form is untouched)
## ESC quits.

import chronos
import ../src/illview
import ../src/illview/dsl/pragmas
import ../src/illview/dsl/mount
import ../src/illview/dsl/uievents

type
  ConnectForm {.view, vbox, spacing: 1, border: bkDouble, shadow.} = ref object of Group
    l1 {.child, caption: "host:".}: Label
    host {.child, bindValue: "hostVal",
           on: {Submitted: "onHostDone"}.}: Input
    prog {.child.}: ProgressBar
    run {.child, caption: "Run", on: {Clicked: "onRun"}.}: Button
    cancel {.child, caption: "Reset", on: {Clicked: "onReset"}.}: Button
    status {.child, caption: "idle".}: Label
    hostVal: string

uiEvents(ConnectForm)

proc connectFlow(form: ConnectForm) {.async.} =
  ## The "model": drives widgets purely via ctx signals — no widget procs.
  for pct in countup(0, 100, 5):
    if SetProgress.signal(form.prog.brokerCtx, SetProgress(value: pct)).isErr:
      return # widget disposed — stop the flow
    await sleepAsync(60.milliseconds)
  discard SetText.signal(form.status.brokerCtx,
                         SetText(text: "connected to " & form.hostVal))

proc onRun(self: ConnectForm) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    discard SetText.signal(self.status.brokerCtx, SetText(text: "connecting..."))
    asyncSpawn self.connectFlow()

proc onReset(self: ConnectForm) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    self.setHostVal("") # D10 writer: store + SetText to the widget
    discard SetProgress.signal(self.prog.brokerCtx, SetProgress(value: 0))
    discard SetText.signal(self.status.brokerCtx, SetText(text: "idle"))
    discard FocusMe.signal(self.host.brokerCtx)

proc onHostDone(self: ConnectForm, ev: Submitted) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    discard FocusMe.signal(self.run.brokerCtx) # Enter jumps to Run

proc main() {.async.} =
  let app = newApp()
  let win = newWindow("instance ctx", rect(0, 0, 0, 0))
  win.dock = dkFill
  let cols = newHBox(spacing = 2)
  cols.dock = dkFill

  let left = mount(ConnectForm)
  let right = mount(ConnectForm) # same type, same event types, own ctxs
  left.borderTitle = "left"      # per-instance titles on the type-level
  right.borderTitle = "right"    # bkDouble border (+ shadow)
  left.hint = (prefHint(28, stretch = 1), prefHint(0, stretch = 1))
  right.hint = (prefHint(28, stretch = 1), prefHint(0, stretch = 1))

  let mirror = newTextView(maxLines = 50)
  mirror.hint = (prefHint(24, stretch = 1), prefHint(0, stretch = 1))
  mirror.addLine "model mirror (LEFT host only):"

  # model-side instance-ctx listener: mirrors ONLY the left form's input —
  # the right form emits the same TextChanged type and stays unmirrored
  discard TextChanged.listen(left.host.brokerCtx,
    proc(ev: TextChanged): Future[void] {.async: (raises: []), gcsafe.} =
      mirror.addLine "left host = \"" & ev.text & "\"")

  cols.add left
  cols.add right
  cols.add mirror
  win.add cols
  app.desktop.add win

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
