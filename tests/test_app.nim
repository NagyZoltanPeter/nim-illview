## Deviation #31: App-level embedding hygiene, terminal-free. The default bus
## records nothing; the crash-restore signal handler chains to whatever was
## installed before it instead of replacing it. Deviation #48: termination
## signals restore and chain too; SIGINT stops the app.

import std/unittest
import chronos
import ../src/illview/core/[bus, app]

when defined(posix):
  from std/posix import nil

  var gPriorRan = false
  proc priorHandler(sig: cint) {.noconv.} =
    gPriorRan = true

  var gTermPriorRan = false
  proc termPriorHandler(sig: cint) {.noconv.} =
    gTermPriorRan = true

  var gIntPriorRan = false
  proc intPriorHandler(sig: cint) {.noconv.} =
    gIntPriorRan = true

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
      var termPrior: posix.Sigaction
      termPrior.sa_handler = termPriorHandler
      discard posix.sigemptyset(termPrior.sa_mask)
      discard posix.sigaction(posix.SIGTERM, termPrior, saved)
      installCrashRestore()
      discard posix.kill(posix.getpid(), posix.SIGSEGV)     # handled, not fatal
      check gPriorRan
      # the chain re-installed the prior action as the current one
      var cur: posix.Sigaction
      discard posix.sigaction(posix.SIGSEGV, prior, cur)
      check cur.sa_handler == priorHandler

    test "SIGTERM restores and chains to the handler installed before (#48)":
      discard posix.kill(posix.getpid(), posix.SIGTERM) # handled, not fatal
      check gTermPriorRan
      var ttou, none: posix.Sigaction # SIGTTOU ignored only during the restore
      discard posix.sigaction(posix.SIGTTOU, none, ttou)
      discard posix.sigaction(posix.SIGTTOU, ttou, nil)
      check ttou.sa_handler == posix.SIG_DFL
      var cur, prior: posix.Sigaction
      discard posix.sigaction(posix.SIGTERM, prior, cur)
      check cur.sa_handler == termPriorHandler

  suite "Ctrl+C stops the app (deviation #48)":
    test "SIGINT stops a running app; a second one is handed on; removal restores":
      var prior, saved: posix.Sigaction
      prior.sa_handler = intPriorHandler
      discard posix.sigemptyset(prior.sa_mask)
      discard posix.sigaction(posix.SIGINT, prior, saved)
      let a = newApp()
      a.running = true
      a.installInterruptStop()
      discard posix.kill(posix.getpid(), posix.SIGINT)
      waitFor sleepAsync(50.milliseconds) # the loop reads the self-pipe
      check not a.running
      check not gIntPriorRan
      discard posix.kill(posix.getpid(), posix.SIGINT) # stop already asked
      check gIntPriorRan
      a.removeInterruptStop()
      var cur: posix.Sigaction
      discard posix.sigaction(posix.SIGINT, saved, cur)
      check cur.sa_handler == intPriorHandler
