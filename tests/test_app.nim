## Deviation #31: App-level embedding hygiene, terminal-free. The default bus
## records nothing; the crash-restore signal handler chains to whatever was
## installed before it instead of replacing it.

import std/unittest
import ../src/illview/core/[bus, app]

when defined(posix):
  from std/posix import nil

  var gPriorRan = false
  proc priorHandler(sig: cint) {.noconv.} =
    gPriorRan = true

suite "default bus (deviation #31)":
  test "newApp's bus is a NullBus: dispatches domain topics, records nothing":
    let app = newApp()
    check app.bus of NullBus
    var got: seq[string]
    discard app.bus.subscribeDomain("net/*",
      proc(t, p: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: got.add t & "=" & p)
    app.bus.publishDomain("net/peer", "up")
    app.bus.publish(UiAction(cmd: Command(1), senderId: 7))
    check got == @["net/peer=up"]

when defined(posix):
  suite "crash-restore handler chains (deviation #31)":
    test "the handler installed before installCrashRestore still runs":
      var prior, saved: posix.Sigaction
      prior.sa_handler = priorHandler
      discard posix.sigemptyset(prior.sa_mask)
      discard posix.sigaction(posix.SIGSEGV, prior, saved) # a host's reporter
      installCrashRestore()
      discard posix.kill(posix.getpid(), posix.SIGSEGV)     # handled, not fatal
      check gPriorRan
      # the chain re-installed the prior action as the current one
      var cur: posix.Sigaction
      discard posix.sigaction(posix.SIGSEGV, prior, cur)
      check cur.sa_handler == priorHandler
