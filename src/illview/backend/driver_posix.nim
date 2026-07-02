## chronos-based POSIX stdin input driver (Phase 1).
##
## STDIN is registered with the chronos selector (`register2` +
## `addReader2`); on readability the callback drains all available bytes
## (O_NONBLOCK), runs them through the incremental decoder and hands each
## InputEvent to the app callback — no threads, no polling.
##
## SIGWINCH is delivered via the self-pipe trick (deviation #11 in
## docs/DESIGN-DEVIATIONS.md): the signal handler write()s one byte into a
## pipe whose read end is registered with the same selector, so resize events
## reach the event loop synchronously and signal-safely.

import std/posix
import chronos
import ../core/events
import ./decoder

when not declared(SIGWINCH):
  const SIGWINCH = cint(28) # same value on macOS and Linux

type
  InputEventHandler* = proc(ev: InputEvent) {.gcsafe, raises: [].}

  InputDriver* = ref object
    decoder: Decoder
    onEvent: InputEventHandler
    active: bool
    inFd: cint                # /dev/tty (own fd) or STDIN_FILENO fallback
    ownsFd: bool
    origStdinFlags: cint      # only used in the stdin-fallback path
    winchPipe: array[2, cint] # [read, write]

var gWinchWriteFd: cint = -1 # signal handlers cannot capture state

proc winchHandler(sig: cint) {.noconv.} =
  if gWinchWriteFd >= 0:
    var b = 'w'
    discard posix.write(gWinchWriteFd, addr b, 1)

proc newInputDriver*(onEvent: InputEventHandler): InputDriver =
  InputDriver(onEvent: onEvent)

proc dispatch(dr: InputDriver, evs: seq[InputEvent]) {.raises: [].} =
  for ev in evs:
    dr.onEvent(ev)

proc onStdinReadable(arg: pointer) {.gcsafe, raises: [].} =
  let dr = cast[InputDriver](arg)
  var buf: array[1024, byte]
  while true:
    let n = posix.read(dr.inFd, addr buf[0], buf.len)
    if n > 0:
      dr.dispatch(dr.decoder.feed(buf.toOpenArray(0, n - 1)))
    elif n == 0:
      break # EOF
    else:
      if errno == EINTR:
        continue
      break # EAGAIN: drained
  dr.dispatch(dr.decoder.flush())

proc onWinchReadable(arg: pointer) {.gcsafe, raises: [].} =
  let dr = cast[InputDriver](arg)
  var buf: array[64, byte]
  while posix.read(dr.winchPipe[0], addr buf[0], buf.len) > 0:
    discard # drain; any number of pending signals collapses into one event
  dr.dispatch(@[InputEvent(kind: ikResize)])

proc setNonBlocking(fd: cint) {.raises: [OSError].} =
  let flags = fcntl(fd, F_GETFL, 0)
  if flags < 0 or fcntl(fd, F_SETFL, flags or O_NONBLOCK) < 0:
    raiseOSError(osLastError(), "fcntl(O_NONBLOCK)")

proc start*(dr: InputDriver) {.raises: [OSError].} =
  ## Register stdin + the SIGWINCH self-pipe with the chronos selector.
  ## Re-entrant: no-op when already active.
  if dr.active:
    return
  # Read the terminal through a DEDICATED fd: on a tty, fd 0/1/2 usually
  # share one file description, so O_NONBLOCK on stdin would make stdout
  # writes fail with EAGAIN mid-frame. Open the tty's real device name
  # (ttyname) — NOT /dev/tty, which macOS kqueue refuses to watch — for a
  # separate description; termios (set by illwillInit on fd 0) is
  # per-device, so raw mode still applies. Fallback: stdin + O_NONBLOCK.
  dr.inFd = -1
  for fd in [cint(STDIN_FILENO), cint(STDOUT_FILENO), cint(STDERR_FILENO)]:
    if isatty(fd) == 1:
      let name = ttyname(fd)
      if name != nil:
        dr.inFd = posix.open(name, O_RDONLY or O_NONBLOCK)
        if dr.inFd >= 0:
          break
  dr.ownsFd = dr.inFd >= 0
  if not dr.ownsFd:
    dr.inFd = STDIN_FILENO
    dr.origStdinFlags = fcntl(STDIN_FILENO, F_GETFL, 0)
    setNonBlocking(STDIN_FILENO)

  if posix.pipe(dr.winchPipe) != 0:
    raiseOSError(osLastError(), "pipe")
  setNonBlocking(dr.winchPipe[0])
  setNonBlocking(dr.winchPipe[1])

  template checked(res: untyped, what: string) =
    if res.isErr:
      raise newException(OSError, "illview driver: " & what)

  checked register2(AsyncFD(dr.inFd)), "register terminal input fd"
  checked addReader2(AsyncFD(dr.inFd), onStdinReadable,
                     cast[pointer](dr)), "watch terminal input fd"
  checked register2(AsyncFD(dr.winchPipe[0])), "register winch pipe"
  checked addReader2(AsyncFD(dr.winchPipe[0]), onWinchReadable,
                     cast[pointer](dr)), "watch winch pipe"

  gWinchWriteFd = dr.winchPipe[1]
  signal(SIGWINCH, winchHandler)
  dr.active = true

proc stop*(dr: InputDriver) {.raises: [].} =
  ## Unregister everything and restore stdin flags. Re-entrant.
  if not dr.active:
    return
  dr.active = false
  signal(SIGWINCH, SIG_DFL)
  gWinchWriteFd = -1
  discard removeReader2(AsyncFD(dr.inFd))
  discard unregister2(AsyncFD(dr.inFd))
  discard removeReader2(AsyncFD(dr.winchPipe[0]))
  discard unregister2(AsyncFD(dr.winchPipe[0]))
  discard close(dr.winchPipe[0])
  discard close(dr.winchPipe[1])
  if dr.ownsFd:
    discard close(dr.inFd)
  else:
    discard fcntl(STDIN_FILENO, F_SETFL, dr.origStdinFlags)
