## Phase 6 demo: live network-event visualizer on the REAL nim-brokers bus.
## A synthetic producer emits LogosDelivery-ish domain events on the chronos
## loop; they fan out through the broker to the NetVizWidget, which renders
## within one frame. The widget has zero input plumbing — the framework
## routes keys/mouse (scroll the feed with wheel/PageUp/PageDown).
## ESC (or the status bar item, via a broker UiAction) quits.

import std/[strformat, random]
import chronos
import results
import illview
import illview/bus_brokers

const cmdQuit = Command(101)

proc main() {.async.} =
  let app = newApp()
  app.bus = newBrokersBus() # the real thing, not the stub

  let nv = newNetViz()
  nv.dock = dkFill
  let rate = newSparkline(capacity = 60) # events per second, last minute
  rate.dock = dkTop
  let win = newWindow("network events - nim-brokers live", rect(0, 0, 0, 0))
  win.dock = dkFill
  win.add rate
  win.add nv
  var eventsThisSecond = 0
  app.desktop.add newStatusBar(@[statusItem("Esc Quit", cmdQuit)])
  app.desktop.add win

  # broker -> widget: domain events fan out with no per-widget plumbing
  discard onDomainEvent(
    proc(topic, payload: string) {.gcsafe, raises: [].} =
      nv.addEvent(topic, payload))
  # broker -> app: tier-2 UiActions (status bar Quit click)
  discard onUiAction(
    proc(a: UiAction) {.gcsafe, raises: [].} =
      if a.cmd == cmdQuit:
        app.stop())

  proc producer() {.async.} =
    var rng = initRand(42)
    var n = 0
    const topics = [
      ("peer", @["connected 16Uiu2HAm...", "disconnected 16Uiu2HAk...",
                 "score +1"]),
      ("relay", @["push 1.2 kB msgHash=0xa1f3...", "duplicate ignored",
                  "subscribed /waku/2/rs/0/1"]),
      ("store", @["query served (12 msgs)", "archive insert ok"])]
    while true:
      await sleepAsync(milliseconds(150 + rng.rand(500)))
      if not app.running: # checked after the first sleep: run() started by then
        break
      inc n
      inc eventsThisSecond
      let (topic, msgs) = topics[rng.rand(topics.high)]
      app.bus.publishDomain(topic, msgs[rng.rand(msgs.high)] & &"  #{n}")

  proc rateLoop() {.async.} =
    while true:
      await sleepAsync(1.seconds)
      if not app.running:
        break
      rate.push(eventsThisSecond) # model -> widget; the sparkline redraws itself
      eventsThisSecond = 0

  asyncSpawn producer()
  asyncSpawn rateLoop()

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
