## Measures how wide the terminal draws an emoji (deviation #46): print one
## at column 1, ask for the cursor position (DSR 6, `ESC[6n`), read the
## `ESC[row;colR` reply. The column moved is the width. Terminals differ:
## most native ones draw emoji 2 columns, xterm.js-based ones (without the
## Unicode 11 table) and some older terminals 1.
##
## Called by `App.enableTui` after the terminal is raw (so the reply is not
## echoed) and before the input driver reads it, once per process.

{.push raises: [].}

when defined(posix):
  import std/[posix, strutils, times]

  proc ttyFd(): cint =
    ## A separate read descriptor on the controlling tty (see driver_posix).
    for fd in [cint(STDIN_FILENO), cint(STDOUT_FILENO), cint(STDERR_FILENO)]:
      if isatty(fd) == 1:
        let name = ttyname(fd)
        if name != nil:
          let r = posix.open(name, O_RDONLY or O_NONBLOCK)
          if r >= 0:
            return r
    -1

  func parseCursorCol*(reply: string): int =
    ## Column from the last complete `ESC[row;colR` in `reply`, else 0.
    let r = reply.rfind('R')
    if r < 0:
      return 0
    let start = reply.rfind("\e[", last = r)
    if start < 0:
      return 0
    let parts = reply[start + 2 ..< r].split(';')
    if parts.len != 2:
      return 0
    try:
      parseInt(parts[1])
    except ValueError:
      0

  proc probeEmojiWidth*(output: File, timeoutMs = 300): int =
    ## 1 or 2, or 0 when the terminal did not answer in time (not a tty, no
    ## DSR support). Leaves the cursor at column 1 of a cleared line.
    let fd = ttyFd()
    if fd < 0:
      return 0
    defer:
      discard posix.close(fd)
    try:
      output.write("\r\xF0\x9F\x99\x82\e[6n") # U+1F642, then report position
      output.flushFile()
    except IOError:
      return 0
    var reply = ""
    let deadline = epochTime() + timeoutMs / 1000
    while reply.parseCursorCol == 0:
      let left = int((deadline - epochTime()) * 1000)
      if left <= 0:
        break
      var pfd = TPollfd(fd: fd, events: POLLIN)
      if poll(addr pfd, Tnfds(1), cint(left)) <= 0:
        continue
      var buf: array[64, char]
      let n = posix.read(fd, addr buf[0], buf.len)
      if n > 0:
        for i in 0 ..< n:
          reply.add buf[i]
    try:
      output.write("\r  \r") # wipe the probe
      output.flushFile()
    except IOError:
      discard
    let w = reply.parseCursorCol - 1 # started at column 1
    if w in 1 .. 2: w else: 0
else:
  proc probeEmojiWidth*(output: File, timeoutMs = 300): int =
    0 # Windows console: not probed (the default stays 2)

{.pop.}
