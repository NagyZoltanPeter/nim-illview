## Poll-based input driver stub for non-POSIX platforms.
##
## Windows async input is out of scope: the Windows console handle is
## not selectable through the chronos POSIX selector, so readiness-driven
## input is not available. The intended (unimplemented) design is a chronos
## timer at ~60 Hz calling the vendored illwill `getKeyAsync(0)`-style
## PeekConsoleInput path and mapping results onto InputEvent — cheap enough
## on Windows, but a busy loop we refuse on POSIX. Deliberately deferred.

import ../core/events

{.warning: "illview: no input driver for this platform; App.run raises OSError (POSIX only)".}

type
  InputEventHandler* = proc(ev: InputEvent) {.gcsafe, raises: [].}

  InputDriver* = ref object
    onEvent: InputEventHandler

proc newInputDriver*(onEvent: InputEventHandler): InputDriver =
  InputDriver(onEvent: onEvent)

proc start*(dr: InputDriver) {.raises: [OSError].} =
  raise newException(OSError,
    "illview: async input is not implemented on this platform " &
    "(POSIX only; see docs/design-notes/WINDOWS-DRIVER.md)")

proc stop*(dr: InputDriver) {.raises: [].} =
  discard
