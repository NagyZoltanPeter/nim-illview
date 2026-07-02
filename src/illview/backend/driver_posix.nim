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
    origStdinFlags: cint
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
    let n = posix.read(STDIN_FILENO, addr buf[0], buf.len)
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
  dr.origStdinFlags = fcntl(STDIN_FILENO, F_GETFL, 0)
  setNonBlocking(STDIN_FILENO)

  if posix.pipe(dr.winchPipe) != 0:
    raiseOSError(osLastError(), "pipe")
  setNonBlocking(dr.winchPipe[0])
  setNonBlocking(dr.winchPipe[1])

  template checked(res: untyped, what: string) =
    if res.isErr:
      raise newException(OSError, "illview driver: " & what)

  checked register2(AsyncFD(STDIN_FILENO)), "register stdin"
  checked addReader2(AsyncFD(STDIN_FILENO), onStdinReadable,
                     cast[pointer](dr)), "watch stdin"
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
  discard removeReader2(AsyncFD(STDIN_FILENO))
  discard unregister2(AsyncFD(STDIN_FILENO))
  discard removeReader2(AsyncFD(dr.winchPipe[0]))
  discard unregister2(AsyncFD(dr.winchPipe[0]))
  discard close(dr.winchPipe[0])
  discard close(dr.winchPipe[1])
  discard fcntl(STDIN_FILENO, F_SETFL, dr.origStdinFlags)
