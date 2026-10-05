## Pure text helpers for captured terminal output (deviation #41). No I/O.
##
## `sanitizeForReplay` keeps text and SGR colour (`ESC[…m`) but drops what
## could mangle the terminal when the capture is replayed into the scrollback:
## cursor movement, screen/line clears, mode and alt-screen switches, OSC
## titles, bells. `stripAnsi` removes every escape sequence (a TextView shows
## plain text). `LineSplitter` turns arbitrary chunks into complete lines.

type
  LineSplitter* = object
    partial: string

proc skipEscape(s: string, i: int): tuple[next: int, keep: bool] =
  ## `s[i]` is ESC. Returns the index after the sequence and whether it is SGR.
  if i + 1 >= s.len:
    return (s.len, false)
  case s[i + 1]
  of '[': # CSI: parameters / intermediates, then a final byte 0x40..0x7E
    var j = i + 2
    while j < s.len and s[j] notin {'\x40' .. '\x7E'}:
      inc j
    if j >= s.len:
      return (s.len, false)
    (j + 1, s[j] == 'm')
  of ']': # OSC: until BEL or ST (ESC \)
    var j = i + 2
    while j < s.len:
      if s[j] == '\a':
        return (j + 1, false)
      if s[j] == '\e' and j + 1 < s.len and s[j + 1] == '\\':
        return (j + 2, false)
      inc j
    (s.len, false)
  of '(', ')', '*', '+': # charset designation: ESC ( X
    (min(i + 3, s.len), false)
  else: # two-byte escapes: ESC 7 / 8 / c / = / > / M …
    (i + 2, false)

proc filterAnsi(s: string, keepSgr: bool, keepCr: bool): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    let ch = s[i]
    if ch == '\e':
      let (next, sgr) = skipEscape(s, i)
      if sgr and keepSgr:
        result.add s[i ..< next]
      i = next
    elif ch in {'\n', '\t'} or ch >= ' ' and ch != '\x7F':
      result.add ch
      inc i
    elif ch == '\r' and keepCr:
      result.add ch
      inc i
    else:
      inc i # other C0 controls (BEL, BS, …) are dropped

func sanitizeForReplay*(s: string): string =
  ## Text + SGR colour + CR/LF/TAB; everything else removed.
  {.cast(noSideEffect).}:
    filterAnsi(s, keepSgr = true, keepCr = true)

func stripAnsi*(s: string): string =
  ## Plain text: all escape sequences and CRs removed.
  {.cast(noSideEffect).}:
    filterAnsi(s, keepSgr = false, keepCr = false)

proc feed*(ls: var LineSplitter, chunk: string): seq[string] =
  ## Complete lines in `chunk` (plus the held partial); the rest is kept.
  for ch in chunk:
    if ch == '\n':
      result.add ls.partial
      ls.partial.setLen 0
    else:
      ls.partial.add ch

proc flush*(ls: var LineSplitter): string =
  ## The held partial line (if any), clearing it.
  result = ls.partial
  ls.partial.setLen 0
