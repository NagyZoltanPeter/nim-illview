## Deviation #31: App-level embedding hygiene, terminal-free. The default bus
## records nothing; the crash-restore signal handler chains to whatever was
## installed before it instead of replacing it. Deviation #48: termination
## signals restore and chain too; SIGINT stops the app.

import std/[unittest, strutils, os, osproc]
import chronos
import ../src/illview/core/[bus, app]
import ../src/illview/backend/illwill_vendored

when defined(posix):
  # Deviation #50: re-run as a child that dies of an unhandled Defect.
  if paramCount() >= 1 and paramStr(1) == "crash-child":
    onUnhandledException = proc(msg: string) {.nimcall, gcsafe.} =
      try:
        stderr.write "PRIOR:" & msg
      except IOError:
        discard
    installCrashRestore()
    raise newException(AssertionDefect, "boom from the child")

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

suite "Ctrl+Z / fg terminal state (deviation #48)":
  test "suspend undoes and resume redoes, in order":
    check suspendSeqFor("\e[?1049l", true, true) ==
      "\e[?1002l\e[?1003l\e[?1006l\e[?2004l\e[0m\e[?25h\e[?1049l"
    check resumeSeqFor("\e[?1049h", true, true) ==
      "\e[?1049h\e[?1002h\e[?1003h\e[?1006h\e[?2004h\e[?25l"
    check suspendSeqFor("\e[2J\e[?47l\e8", false, false) == "\e[0m\e[?25h\e[2J\e[?47l\e8"
    check resumeSeqFor("", false, true) == "\e[?2004h\e[?25l" # no alt screen

  test "setBracketedPaste is recorded for suspend / resume":
    setBracketedPaste(true)
    check bracketedPaste()
    check "\e[?2004l" in suspendSeq()
    check "\e[?2004h" in resumeSeq()
    setBracketedPaste(false)
    check not bracketedPaste()
    check "\e[?2004" notin suspendSeq()

when defined(posix):
  suite "unhandled exceptions (deviation #50)":
    test "restore first, then the traceback to the handler installed before":
      let (output, code) = execCmdEx(quoteShell(getAppFilename()) & " crash-child")
      check code == 1
      let restore = output.find("\e[?1049l")
      let prior = output.find("PRIOR:")
      check restore >= 0
      check "\e[?1003l" in output # mouse tracking off
      check prior > restore
      check "boom from the child" in output
      check "[AssertionDefect]" in output
