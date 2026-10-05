## Output capture (deviation #41, POSIX): while the TUI is up, fd 1 and fd 2
## point at a pseudo-terminal, so everything written to stdout/stderr — Nim
## `echo`, C `printf`, child processes — is collected instead of landing on the
## alternate screen. The renderer keeps drawing to the real terminal through
## illwill's `setOutput` handle.
##
## A pty (not a pipe) keeps `isatty(1)` true: libraries keep their colours and
## C stdio stays line-buffered. A pty buffers only ~1 KiB (macOS) / ~4 KiB
## (Linux), so the loop thread cannot be the reader — a larger synchronous
## write from that same thread would block forever. A small drain thread
## `read()`s the pty master into a fixed-size shared ring (drop-oldest) under
## a lock and wakes the loop through a pipe; it touches no GC memory, so it
## behaves the same under refc and ORC. No cross-thread API is exposed.

import std/[posix, locks, termios]
import chronos
import ./illwill_vendored

proc posix_openpt(flags: cint): cint {.importc, header: "<stdlib.h>".}
proc grantpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc unlockpt(fd: cint): cint {.importc, header: "<stdlib.h>".}
proc ptsname(fd: cint): cstring {.importc, header: "<stdlib.h>".}
var TIOCSWINSZ {.importc, header: "<sys/ioctl.h>".}: culong # not in std/termios

type
  Shared = object
    ## Owned by the drain thread and the loop; plain memory (allocShared).
    lock: Lock
    master: cint
    stopFd: cint  # read end: a byte here ends the drain thread
    wakeFd: cint  # write end: one byte per chunk wakes the loop
    ring: ptr UncheckedArray[char]
    cap: int
    written: int  # total bytes ever stored; ring index = written mod cap
    shown: int    # bytes already on the real terminal (replayed or passed through)
    ttyFd: cint   # the real terminal, for passthrough
    passthrough: bool # terminal mode: copy each chunk to ttyFd as it arrives

  OutputCapture* = ref object
    active: bool
    sh: ptr Shared
    thread: Thread[ptr Shared]
    ttyFd: cint           # dup of the real terminal: the renderer writes here
    ttyOut: File
    savedOut, savedErr: cint
    stopW, wakeR: cint    # stop pipe write end, wake pipe read end
    consumed: int         # bytes already handed to sinks
    limit: int
    onChunk*: proc(chunk: string) {.gcsafe, raises: [].}
      ## Raw captured bytes, as they arrive (loop thread).

# crash path (app.nim's restoreOnSignal): plain globals, no allocation
var gCapSavedOut*: cint = -1
var gCapSavedErr*: cint = -1
var gCapShared*: pointer = nil

proc newOutputCapture*(limit = 1 shl 20): OutputCapture =
  OutputCapture(limit: max(limit, 4096), savedOut: -1, savedErr: -1, ttyFd: -1)

func active*(c: OutputCapture): bool = c != nil and c.active

# --- ring (caller holds the lock) ---------------------------------------------

proc ringAppend(sh: ptr Shared, buf: ptr UncheckedArray[char], n: int) =
  for i in 0 ..< n:
    sh.ring[sh.written mod sh.cap] = buf[i]
    inc sh.written

proc writeAll(fd: cint, p: pointer, n: int) =
  var off = 0
  while off < n:
    let w = posix.write(fd, cast[pointer](cast[int](p) + off), n - off)
    if w > 0:
      off += w
    elif w < 0 and errno == EINTR:
      continue
    else:
      break

proc ringCopy(sh: ptr Shared, fromPos: int): tuple[data: string, upto: int] =
  ## Bytes [fromPos, written) still held by the ring (older ones are gone).
  let start = max(fromPos, sh.written - sh.cap)
  result.upto = sh.written
  result.data = newString(max(sh.written - start, 0))
  for i in start ..< sh.written:
    result.data[i - start] = sh.ring[i mod sh.cap]

# --- drain thread ---------------------------------------------------------------

proc drain(sh: ptr Shared) {.thread.} =
  var buf: array[4096, char]
  var fds = [TPollfd(fd: sh.master, events: POLLIN), TPollfd(fd: sh.stopFd, events: POLLIN)]
  var stopping = false
  while true:
    if not stopping:
      fds[0].revents = 0
      fds[1].revents = 0
      if poll(addr fds[0], 2, -1) < 0:
        if errno == EINTR: continue
        break
      if (fds[1].revents and POLLIN) != 0:
        stopping = true # final non-blocking sweep, then exit
        discard fcntl(sh.master, F_SETFL, fcntl(sh.master, F_GETFL) or O_NONBLOCK)
    let n = posix.read(sh.master, addr buf[0], buf.len)
    if n > 0:
      withLock sh.lock:
        ringAppend(sh, cast[ptr UncheckedArray[char]](addr buf[0]), n)
        if sh.passthrough: # terminal mode: show it live, in order with replays
          writeAll(sh.ttyFd, addr buf[0], n)
          sh.shown = sh.written
      var b = 'w'
      discard posix.write(sh.wakeFd, addr b, 1) # full pipe: the loop is awake anyway
      continue
    if n < 0 and errno == EINTR:
      continue
    # n == 0 / EIO: every slave fd is closed; EAGAIN while stopping: drained
    if stopping or n == 0 or errno != EAGAIN:
      break

# --- loop side --------------------------------------------------------------------

proc pull*(c: OutputCapture): string =
  ## New bytes since the last pull (loop thread), also fed to `onChunk`.
  if c.sh == nil:
    return ""
  var got: tuple[data: string, upto: int]
  withLock c.sh.lock:
    got = ringCopy(c.sh, c.consumed)
  c.consumed = got.upto
  if got.data.len > 0 and c.onChunk != nil:
    c.onChunk(got.data)
  got.data

proc onWake(arg: pointer) {.gcsafe, raises: [].} =
  let c = cast[OutputCapture](arg)
  var b: array[256, byte]
  while posix.read(c.wakeR, addr b[0], b.len) > 0:
    discard
  {.cast(gcsafe).}:
    discard c.pull()

proc syncSize*(c: OutputCapture) =
  ## Give captured programs the real terminal size (call on resize).
  if not c.active:
    return
  var ws: IOctl_WinSize
  if ioctl(c.ttyFd, TIOCGWINSZ, addr ws) == 0:
    discard ioctl(c.sh.master, TIOCSWINSZ, addr ws)

proc fail(msg: string) {.raises: [OSError].} =
  raiseOSError(osLastError(), msg)

proc start*(c: OutputCapture) {.raises: [OSError, IOError, ResourceExhaustedError].} =
  ## Redirect fd 1/2 into the pty and point the renderer at the real terminal.
  if c.active:
    return
  flushFile(stdout)
  flushFile(stderr)
  c.ttyFd = dup(1)
  if c.ttyFd < 0: fail("dup(1)")
  if not open(c.ttyOut, FileHandle(c.ttyFd), fmWrite):
    fail("fdopen(tty)")
  let master = posix_openpt(O_RDWR or O_NOCTTY)
  if master < 0 or grantpt(master) != 0 or unlockpt(master) != 0: fail("posix_openpt")
  let slave = posix.open(ptsname(master), O_RDWR or O_NOCTTY)
  if slave < 0: fail("open(pty slave)")
  var stopP, wakeP: array[2, cint]
  if pipe(stopP) != 0 or pipe(wakeP) != 0: fail("pipe")
  discard fcntl(wakeP[0], F_SETFL, fcntl(wakeP[0], F_GETFL) or O_NONBLOCK)
  discard fcntl(wakeP[1], F_SETFL, fcntl(wakeP[1], F_GETFL) or O_NONBLOCK)

  if c.sh != nil: # the previous period was replayed on stop: drop it
    gCapShared = nil
    deinitLock(c.sh.lock)
    deallocShared(c.sh.ring)
    deallocShared(c.sh)
  c.sh = createShared(Shared)
  initLock(c.sh.lock)
  c.sh.master = master
  c.sh.stopFd = stopP[0]
  c.sh.wakeFd = wakeP[1]
  c.sh.cap = c.limit
  c.sh.ring = cast[ptr UncheckedArray[char]](allocShared0(c.limit))
  c.sh.ttyFd = c.ttyFd
  c.stopW = stopP[1]
  c.wakeR = wakeP[0]
  c.consumed = 0

  c.active = true
  c.syncSize()
  c.savedOut = dup(1)
  c.savedErr = dup(2)
  discard dup2(slave, 1)
  discard dup2(slave, 2)
  discard posix.close(slave) # fd 1/2 keep it open
  gCapSavedOut = c.savedOut
  gCapSavedErr = c.savedErr
  gCapShared = c.sh
  setOutput(c.ttyOut)
  createThread(c.thread, drain, c.sh)
  if register2(AsyncFD(c.wakeR)).isErr or
     addReader2(AsyncFD(c.wakeR), onWake, cast[pointer](c)).isErr:
    raise newException(OSError, "illview capture: watch wake pipe")

proc stop*(c: OutputCapture) =
  ## Put fd 1/2 back, drain what is left, stop the thread. The ring keeps the
  ## history for `replay`.
  if not c.active:
    return
  try:
    flushFile(stdout)
    flushFile(stderr)
  except IOError:
    discard
  discard dup2(c.savedOut, 1)
  discard dup2(c.savedErr, 2)
  gCapSavedOut = -1
  gCapSavedErr = -1
  var b = 's'
  discard posix.write(c.stopW, addr b, 1)
  joinThread(c.thread)
  discard removeReader2(AsyncFD(c.wakeR))
  discard unregister2(AsyncFD(c.wakeR))
  discard c.pull() # the last bytes go to the sinks too
  setOutput(stdout)
  try:
    c.ttyOut.close() # closes ttyFd
  except CatchableError:
    discard
  for fd in [c.savedOut, c.savedErr, c.stopW, c.wakeR, c.sh.stopFd, c.sh.wakeFd, c.sh.master]:
    discard posix.close(fd)
  c.active = false

proc pending*(c: OutputCapture): string =
  ## Captured bytes not yet shown on the real terminal (still in the ring).
  if c.sh == nil:
    return ""
  withLock c.sh.lock:
    result = ringCopy(c.sh, c.sh.shown).data

proc markReplayed*(c: OutputCapture) =
  ## Treat everything captured so far as shown.
  if c.sh != nil:
    withLock c.sh.lock:
      c.sh.shown = c.sh.written

proc setPassthrough*(c: OutputCapture, on: bool,
                     filter: proc(s: string): string {.noSideEffect, gcsafe, raises: [].} = nil) =
  ## Terminal mode on: replay the not-yet-shown backlog (through `filter`),
  ## then copy every new chunk to the terminal live — one locked step, so no
  ## byte is lost or shown twice. Off (back to the TUI): stop copying.
  if not c.active:
    return
  if on:
    c.syncSize()
  withLock c.sh.lock:
    if on:
      let backlog = ringCopy(c.sh, c.sh.shown).data
      let shown = if filter != nil: filter(backlog) else: backlog
      if shown.len > 0:
        writeAll(c.sh.ttyFd, unsafeAddr shown[0], shown.len)
      c.sh.shown = c.sh.written
    c.sh.passthrough = on

proc dispose*(c: OutputCapture) =
  ## Free the shared ring (after `stop`; the history is gone).
  if c.sh != nil and not c.active:
    deinitLock(c.sh.lock)
    deallocShared(c.sh.ring)
    deallocShared(c.sh)
    c.sh = nil
    gCapShared = nil

# --- crash path ---------------------------------------------------------------------

proc captureCrashFds*() {.raises: [].} =
  ## From a fatal-signal handler, first step: put fd 1/2 back on the terminal
  ## (dup2 is async-signal-safe), so the restore sequence reaches it.
  if gCapSavedOut < 0:
    return
  discard dup2(gCapSavedOut, 1)
  discard dup2(gCapSavedErr, 2)

proc captureCrashDump*() {.raises: [].} =
  ## Second step, after leaving the alt screen: write the not-yet-replayed
  ## captured bytes with write(2). No allocation, no locks (best effort).
  let sh = cast[ptr Shared](gCapShared)
  if sh == nil:
    return
  let start = max(sh.shown, sh.written - sh.cap)
  var i = start
  while i < sh.written:
    let idx = i mod sh.cap
    let n = min(sh.written - i, sh.cap - idx) # contiguous slice up to the wrap
    discard posix.write(cint(1), addr sh.ring[idx], n)
    i += n
