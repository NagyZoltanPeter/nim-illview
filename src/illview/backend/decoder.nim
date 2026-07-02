## Incremental, terminal-free input decoder (§3.1, Phase 0).
##
## The escape-sequence → Key mapping tables and the SGR mouse bit layout are
## ported from the vendored illwill; the state machine itself is new: illwill's
## `getKey()` issues multiple blocking `read()` calls mid-sequence, which cannot
## work on a non-blocking, chunked byte stream. `feed()` is pure with respect to
## the terminal: bytes in, events out, partial sequences buffered across calls.
##
## Bare-ESC ambiguity: a lone 0x1B may be the ESC key or the start of a
## sequence whose tail hasn't arrived yet. `feed()` keeps it pending; the
## driver calls `flush()` once the input fd is drained, which resolves a
## pending lone ESC to Key.Escape.

import std/unicode
import ../core/events

type
  Decoder* = object
    buf: seq[byte]        # pending, not-yet-decoded bytes
    inPaste: bool         # inside a bracketed paste (CSI 200~ .. CSI 201~)
    pasteBuf: string

const
  Esc = 0x1B'u8
  # illwill's lookup tables (illwill_vendored.nim KEYS_D/E/F/G)
  KeysD = [Key.Up, Key.Down, Key.Right, Key.Left, Key.None, Key.End,
           Key.None, Key.Home]                          # CSI/SS3 A..H
  KeysE = [Key.Delete, Key.End, Key.PageUp, Key.PageDown, Key.Home, Key.End]
  KeysF = [Key.F1, Key.F2, Key.F3, Key.F4, Key.F5, Key.None, Key.F6, Key.F7,
           Key.F8]                                      # CSI 11~..19~, SS3 P..S
  KeysG = [Key.F9, Key.F10, Key.None, Key.F11, Key.F12] # CSI 20~..24~
  PasteEnd = [Esc, byte('['), byte('2'), byte('0'), byte('1'), byte('~')]

{.push warning[HoleEnumConv]: off.}
func toKey(c: int): Key =
  try:
    Key(c)
  except RangeDefect:
    Key.None
{.pop.}

func csiMods(param: int): set[Modifier] =
  ## xterm modifier parameter: value-1 is a bitmask (1=shift, 2=alt, 4=ctrl).
  let m = param - 1
  if (m and 1) != 0: result.incl modShift
  if (m and 2) != 0: result.incl modAlt
  if (m and 4) != 0: result.incl modCtrl

func parseParams(body: string): seq[int] =
  var cur = 0
  var any = false
  for c in body:
    if c in {'0'..'9'}:
      cur = cur * 10 + (ord(c) - ord('0'))
      any = true
    elif c == ';':
      result.add(if any: cur else: 0)
      cur = 0
      any = false
    else:
      return @[] # non-numeric params: caller handles specially
  if any:
    result.add cur

func utf8Len(b: byte): int =
  if b < 0x80: 1
  elif (b and 0xE0) == 0xC0: 2
  elif (b and 0xF0) == 0xE0: 3
  elif (b and 0xF8) == 0xF0: 4
  else: 0 # invalid lead byte

proc decodeSingleByte(b: byte, mods: set[Modifier] = {}): InputEvent =
  ## Control bytes and printable ASCII. Follows illwill's parseStdin aliasing:
  ## 10 and 13 both map to Enter, 8 and 127 both to Backspace (so CtrlH/CtrlJ
  ## are unreachable — same behavior as upstream illwill).
  case b
  of 10, 13: keyEvent(Key.Enter, Rune(13), mods)
  of 8, 127: keyEvent(Key.Backspace, Rune(127), mods)
  else: keyEvent(toKey(int(b)), Rune(b), mods)

proc decodeSgrMouse(body: string, release: bool): InputEvent =
  ## body is "<b;x;y" (without the final M/m). Bit layout per illwill's
  ## fillGlobalMouseInfo: bits 0-1 button, bit 2 shift, bit 3 alt, bit 4 ctrl,
  ## bit 5 move, bit 6 scroll (bit 0 then selects scroll direction).
  let params = parseParams(body[1..^1])
  if params.len != 3:
    return InputEvent(kind: ikResize) # never emitted; caller checks len==3
  let (b, x, y) = (params[0], params[1] - 1, params[2] - 1)
  var mods: set[Modifier]
  if (b and 4) != 0: mods.incl modShift
  if (b and 8) != 0: mods.incl modAlt
  if (b and 16) != 0: mods.incl modCtrl
  if (b and 64) != 0:
    let action = if (b and 1) != 0: maWheelDown else: maWheelUp
    mouseEvent(action, mbNone, x, y, mods)
  elif (b and 32) != 0:
    let button = case b and 3
      of 0: mbLeft
      of 1: mbMiddle
      of 2: mbRight
      else: mbNone
    mouseEvent(maMove, button, x, y, mods)
  else:
    let button = case b and 3
      of 0: mbLeft
      of 1: mbMiddle
      of 2: mbRight
      else: mbNone
    mouseEvent(if release: maRelease else: maPress, button, x, y, mods)

type ParseStatus = enum
  psEvent    # consumed bytes, produced an event
  psSkip     # consumed bytes, no event (unknown/discarded sequence)
  psNeedMore # incomplete sequence at end of buffer; keep pending

proc decodeCsi(d: var Decoder, body: string, final: char,
               ev: var InputEvent): ParseStatus =
  if body.len > 0 and body[0] == '<' and final in {'M', 'm'}:
    if parseParams(body[1..^1]).len == 3:
      ev = decodeSgrMouse(body, release = final == 'm')
      return psEvent
    return psSkip
  let params = parseParams(body)
  let mods = if params.len >= 2: csiMods(params[1]) else: {}
  case final
  of 'A'..'D', 'F', 'H':
    ev = keyEvent(KeysD[ord(final) - ord('A')], mods = mods)
    psEvent
  of 'P'..'S': # CSI 1;mP form of F1-F4
    ev = keyEvent(KeysF[ord(final) - ord('P')], mods = mods)
    psEvent
  of 'Z': # CSI Z = Shift-Tab
    ev = keyEvent(Key.Tab, Rune(9), {modShift})
    psEvent
  of '~':
    if params.len == 0:
      return psSkip
    let n = params[0]
    case n
    of 1, 7: ev = keyEvent(Key.Home, mods = mods)
    of 2: ev = keyEvent(Key.Insert, mods = mods)
    of 3: ev = keyEvent(Key.Delete, mods = mods)
    of 4, 8: ev = keyEvent(Key.End, mods = mods)
    of 5: ev = keyEvent(Key.PageUp, mods = mods)
    of 6: ev = keyEvent(Key.PageDown, mods = mods)
    of 11..15, 17..19: ev = keyEvent(KeysF[n - 11], mods = mods)
    of 20, 21, 23, 24: ev = keyEvent(KeysG[n - 20], mods = mods)
    of 200:
      d.inPaste = true
      d.pasteBuf = ""
      return psSkip
    else:
      return psSkip
    psEvent
  else:
    psSkip

proc parseOne(d: var Decoder, start: int, consumed: var int,
              ev: var InputEvent): ParseStatus =
  ## Parse one event starting at d.buf[start]. Never called while inPaste.
  template buf: untyped = d.buf
  let n = buf.len
  let b0 = buf[start]

  if b0 == Esc:
    if start + 1 >= n:
      return psNeedMore # lone ESC: pending until more bytes or flush()
    let b1 = char(buf[start + 1])
    case b1
    of '[': # CSI: params 0x30-0x3F, intermediates 0x20-0x2F, final 0x40-0x7E
      var i = start + 2
      while i < n and buf[i] in 0x20'u8..0x3F'u8:
        inc i
      if i >= n:
        return psNeedMore
      if buf[i] notin 0x40'u8..0x7E'u8:
        consumed = i - start + 1 # malformed; drop it
        return psSkip
      var body = newString(i - (start + 2))
      for k in 0..<body.len:
        body[k] = char(buf[start + 2 + k])
      consumed = i - start + 1
      return d.decodeCsi(body, char(buf[i]), ev)
    of 'O': # SS3
      if start + 2 >= n:
        return psNeedMore
      let c = char(buf[start + 2])
      consumed = 3
      if c in {'A'..'D', 'F', 'H'}:
        ev = keyEvent(KeysD[ord(c) - ord('A')])
        return psEvent
      elif c in {'P'..'S'}:
        ev = keyEvent(KeysF[ord(c) - ord('P')])
        return psEvent
      return psSkip # unknown SS3, discarded (same as illwill)
    of '\x1B': # ESC ESC: emit one Escape, re-parse the second
      consumed = 1
      ev = keyEvent(Key.Escape, Rune(27))
      return psEvent
    else: # Alt + following char (single byte or UTF-8 rune)
      let len = utf8Len(buf[start + 1])
      if len == 0:
        consumed = 2
        return psSkip
      if start + 1 + len > n:
        return psNeedMore
      consumed = 1 + len
      if len == 1:
        ev = decodeSingleByte(buf[start + 1], {modAlt})
      else:
        var s = newString(len)
        for k in 0..<len:
          s[k] = char(buf[start + 1 + k])
        ev = keyEvent(Key.None, s.runeAt(0), {modAlt})
      return psEvent

  let len = utf8Len(b0)
  if len == 0:
    consumed = 1 # invalid UTF-8 lead byte, drop
    return psSkip
  if len == 1:
    consumed = 1
    ev = decodeSingleByte(b0)
    return psEvent
  if start + len > n:
    return psNeedMore
  consumed = len
  var s = newString(len)
  for k in 0..<len:
    s[k] = char(buf[start + k])
  ev = keyEvent(Key.None, s.runeAt(0))
  psEvent

proc consumePaste(d: var Decoder, start: int, consumed: var int,
                  ev: var InputEvent): ParseStatus =
  ## Accumulate paste content until the CSI 201~ terminator.
  var i = start
  while i < d.buf.len:
    if d.buf[i] == Esc:
      let remaining = d.buf.len - i
      let cmp = min(remaining, PasteEnd.len)
      var isEnd = true
      for k in 0..<cmp:
        if d.buf[i + k] != PasteEnd[k]:
          isEnd = false
          break
      if isEnd:
        if remaining < PasteEnd.len:
          consumed = i - start
          return psNeedMore # partial terminator; keep it pending
        consumed = i - start + PasteEnd.len
        d.inPaste = false
        ev = InputEvent(kind: ikPaste, text: d.pasteBuf)
        d.pasteBuf = ""
        return psEvent
    d.pasteBuf.add char(d.buf[i])
    inc i
  consumed = i - start
  psNeedMore

proc feed*(d: var Decoder, bytes: openArray[byte]): seq[InputEvent] =
  ## Incremental: may buffer an incomplete sequence and emit it on a later
  ## feed. Pure and terminal-free.
  for b in bytes:
    d.buf.add b
  var i = 0
  while i < d.buf.len:
    var consumed = 0
    var ev: InputEvent
    let status =
      if d.inPaste: d.consumePaste(i, consumed, ev)
      else: d.parseOne(i, consumed, ev)
    i += consumed
    case status
    of psEvent: result.add ev
    of psSkip: discard
    of psNeedMore: break
  if i > 0:
    d.buf = d.buf[i..^1]

proc feed*(d: var Decoder, s: string): seq[InputEvent] =
  d.feed(s.toOpenArrayByte(0, s.high))

proc flush*(d: var Decoder): seq[InputEvent] =
  ## Call after the input fd has been drained: a pending lone ESC is the
  ## Escape key, not the start of a sequence.
  if d.buf.len == 1 and d.buf[0] == Esc:
    d.buf.setLen(0)
    result.add keyEvent(Key.Escape, Rune(27))

func pendingBytes*(d: Decoder): int =
  ## Number of buffered, not-yet-decoded bytes (diagnostics/tests).
  d.buf.len
