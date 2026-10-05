## Deviation #41: stdout/stderr capture — pure text helpers everywhere, the
## pty capture itself on POSIX builds with threads.

import std/[unittest, strutils]
import ../src/illview/backend/ansitext

suite "ansi text helpers (deviation #41)":
  test "replay keeps text, SGR colours, CR/LF/TAB":
    let s = "\e[31mred\e[0m plain\tx\r\n"
    check sanitizeForReplay(s) == s

  test "replay strips cursor moves, clears, modes, OSC titles, bells":
    let s = "a\e[2J\e[H\e[3;5Hb\e[K\e[?1049h\e[?25l\e]0;title\ac\e]2;t\e\\d\a\e7\e8\e(Be"
    check sanitizeForReplay(s) == "abcde"

  test "stripAnsi leaves plain text only":
    check stripAnsi("\e[1;32mok\e[0m done\r\n") == "ok done\n"

  test "truncated sequences at the end are dropped, not kept":
    check sanitizeForReplay("x\e[31") == "x"
    check sanitizeForReplay("x\e") == "x"
    check sanitizeForReplay("x\e]0;unterminated") == "x"

  test "line splitter holds partial lines across chunks":
    var ls: LineSplitter
    check ls.feed("one\ntw") == @["one"]
    check ls.feed("o\nthree") == @["two"]
    check ls.feed("") == newSeq[string]()
    check ls.flush() == "three"
    check ls.flush() == ""

when defined(posix) and compileOption("threads"):
  import chronos
  import ../src/illview/backend/capture_posix

  proc settle() =
    waitFor sleepAsync(150.milliseconds) # let the drain thread and the wake reader run

  suite "pty capture (deviation #41)":
    test "fd 1 and fd 2 writes are captured, in order; stop restores them":
      let c = newOutputCapture()
      var chunks = ""
      c.onChunk = proc(chunk: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: chunks.add chunk
      c.start()
      check c.active
      stdout.write "to stdout\n"
      stdout.flushFile()
      stderr.write "to stderr\n"
      stderr.flushFile()
      settle()
      c.stop()
      check not c.active
      let got = c.pending
      check "to stdout" in got and "to stderr" in got
      check got.find("to stdout") < got.find("to stderr") # one channel keeps order
      check "to stdout" in chunks                          # live sink saw it too
      c.markReplayed()
      check c.pending == ""
      c.dispose()

    test "drop-oldest beyond the limit keeps the newest bytes":
      let c = newOutputCapture(limit = 4096)
      c.start()
      stdout.write repeat('a', 10_000) & "TAIL\n"
      stdout.flushFile()
      settle()
      c.stop()
      let got = c.pending
      check got.len <= 4096
      check got.endsWith("TAIL\r\n") # pty output processing: LF -> CRLF
      c.dispose()

    test "a write far beyond the pty buffer does not block the writer":
      let c = newOutputCapture()
      c.start()
      stdout.write repeat('z', 100_000) # one synchronous write, ~100x the pty buffer
      stdout.flushFile()
      settle()
      c.stop()
      check c.pending.count('z') == 100_000
      c.dispose()

    test "capture can be restarted (terminal mode in/out)":
      let c = newOutputCapture()
      for round in 1 .. 2:
        c.start()
        stdout.write "round " & $round & "\n"
        stdout.flushFile()
        settle()
        c.stop()
        check ("round " & $round) in c.pending
        c.markReplayed()
      c.dispose()

when defined(posix) and compileOption("threads"):
  import std/posix

  suite "passthrough (deviation #41)":
    test "terminal mode: backlog replayed once, then live; pane sink sees everything":
      # make the 'real terminal' a pipe we can read
      var p: array[2, cint]
      check pipe(p) == 0
      discard fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) or O_NONBLOCK)
      flushFile(stdout)
      let realOut = dup(1)
      discard dup2(p[1], 1)
      let c = newOutputCapture()
      var sink = ""
      c.onChunk = proc(chunk: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: sink.add chunk
      c.start()                       # ttyFd = dup(1) = our pipe
      stdout.write "desktop line\n"
      stdout.flushFile()
      settle()
      check c.pending.contains("desktop line")
      c.setPassthrough(true)          # replay backlog, then live
      check c.pending == ""
      stdout.write "terminal line\n"
      stdout.flushFile()
      settle()
      check c.pending == ""           # shown live, nothing left to replay
      c.setPassthrough(false)         # back to the TUI: collect again
      stdout.write "desktop again\n"
      stdout.flushFile()
      settle()
      check c.pending.contains("desktop again")
      c.stop()
      c.dispose()
      discard dup2(realOut, 1)
      discard close(realOut)
      var buf = newString(4096)
      let n = read(p[0], addr buf[0], buf.len)
      let term = if n > 0: buf[0 ..< n] else: ""
      check term.find("desktop line") >= 0
      check term.find("terminal line") > term.find("desktop line") # replay first, then live
      check term.count("desktop line") == 1                        # never twice
      check "desktop again" notin term                             # collected, not shown
      check "desktop line" in sink and "terminal line" in sink and "desktop again" in sink
      discard close(p[0])
      discard close(p[1])
