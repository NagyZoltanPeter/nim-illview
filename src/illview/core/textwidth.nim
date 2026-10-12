## Display width of text in terminal columns (deviation #45).
##
## 0 for combining marks, joiners and variation selectors (they attach to the
## character before them), 2 for East Asian Wide / Fullwidth characters,
## `emojiWidth()` (2 unless the terminal was measured to draw them 1 wide,
## deviation #46) for emoji with emoji presentation, 1 for everything else.
## A built-in range table (Unicode 15), no dependency.

{.push raises: [].}

import std/[strutils, unicode]

type R = tuple[lo, hi: int32]

const ZeroWidth: array[22, R] = [
  (0x0300'i32, 0x036F'i32), (0x0483'i32, 0x0489'i32), (0x0591'i32, 0x05BD'i32),
  (0x05BF'i32, 0x05C7'i32), (0x0610'i32, 0x061A'i32), (0x064B'i32, 0x065F'i32),
  (0x0670'i32, 0x0670'i32), (0x06D6'i32, 0x06ED'i32), (0x0E31'i32, 0x0E3A'i32),
  (0x0E47'i32, 0x0E4E'i32), (0x1AB0'i32, 0x1AFF'i32), (0x1DC0'i32, 0x1DFF'i32),
  (0x200B'i32, 0x200F'i32), (0x202A'i32, 0x202E'i32), (0x2060'i32, 0x2064'i32),
  (0x20D0'i32, 0x20FF'i32), (0xFE00'i32, 0xFE0F'i32), (0xFE20'i32, 0xFE2F'i32),
  (0xFEFF'i32, 0xFEFF'i32), (0x1F3FB'i32, 0x1F3FF'i32), (0xE0001'i32, 0xE007F'i32),
  (0xE0100'i32, 0xE01EF'i32),
]

const CjkWide: array[18, R] = [
  ## East Asian Wide / Fullwidth: every terminal draws these 2 columns.
  (0x1100'i32, 0x115F'i32), (0x2329'i32, 0x232A'i32), (0x2E80'i32, 0x303E'i32),
  (0x3041'i32, 0x33FF'i32), (0x3400'i32, 0x4DBF'i32), (0x4E00'i32, 0x9FFF'i32),
  (0xA000'i32, 0xA4CF'i32), (0xA960'i32, 0xA97F'i32), (0xAC00'i32, 0xD7A3'i32),
  (0xF900'i32, 0xFAFF'i32), (0xFE10'i32, 0xFE19'i32), (0xFE30'i32, 0xFE6F'i32),
  (0xFF00'i32, 0xFF60'i32), (0xFFE0'i32, 0xFFE6'i32), (0x16FE0'i32, 0x18CFF'i32),
  (0x1B000'i32, 0x1B2FF'i32), (0x1F200'i32, 0x1F2FF'i32), (0x20000'i32, 0x3FFFD'i32),
]

const Emoji: array[41, R] = [
  ## Emoji presentation: 2 columns in most terminals, 1 in some (xterm.js
  ## without its Unicode 11 table, older ones) -- see `setEmojiWidth`.
  (0x231A'i32, 0x231B'i32), (0x23E9'i32, 0x23EC'i32), (0x23F0'i32, 0x23F0'i32),
  (0x23F3'i32, 0x23F3'i32), (0x25FD'i32, 0x25FE'i32), (0x2614'i32, 0x2615'i32),
  (0x2648'i32, 0x2653'i32), (0x267F'i32, 0x267F'i32), (0x2693'i32, 0x2693'i32),
  (0x26A1'i32, 0x26A1'i32), (0x26AA'i32, 0x26AB'i32), (0x26BD'i32, 0x26BE'i32),
  (0x26C4'i32, 0x26C5'i32), (0x26CE'i32, 0x26CE'i32), (0x26D4'i32, 0x26D4'i32),
  (0x26EA'i32, 0x26EA'i32), (0x26F2'i32, 0x26F3'i32), (0x26F5'i32, 0x26F5'i32),
  (0x26FA'i32, 0x26FA'i32), (0x26FD'i32, 0x26FD'i32), (0x2705'i32, 0x2705'i32),
  (0x270A'i32, 0x270B'i32), (0x2728'i32, 0x2728'i32), (0x274C'i32, 0x274C'i32),
  (0x274E'i32, 0x274E'i32), (0x2753'i32, 0x2755'i32), (0x2757'i32, 0x2757'i32),
  (0x2795'i32, 0x2797'i32), (0x27B0'i32, 0x27B0'i32), (0x27BF'i32, 0x27BF'i32),
  (0x2B1B'i32, 0x2B1C'i32), (0x2B50'i32, 0x2B50'i32), (0x2B55'i32, 0x2B55'i32),
  (0x1F004'i32, 0x1F004'i32), (0x1F18E'i32, 0x1F18E'i32), (0x1F191'i32, 0x1F19A'i32),
  (0x1F300'i32, 0x1F3FA'i32), (0x1F400'i32, 0x1F64F'i32), (0x1F680'i32, 0x1F6FF'i32),
  (0x1F7E0'i32, 0x1F7EB'i32), (0x1F900'i32, 0x1FAFF'i32),
]

var gEmojiWidth = 2 ## see setEmojiWidth; a plain int, read on the UI thread

proc setEmojiWidth*(w: int) =
  ## How wide the terminal draws emoji: 1 or 2 (default 2). `App.enableTui`
  ## measures it once (deviation #46); ILLVIEW_EMOJI_WIDTH overrides.
  if w in 1 .. 2:
    gEmojiWidth = w

proc emojiWidth*(): int =
  gEmojiWidth

func inRanges(c: int32, t: openArray[R]): bool =
  var lo = 0
  var hi = t.high
  while lo <= hi:
    let mid = (lo + hi) div 2
    if c < t[mid].lo: hi = mid - 1
    elif c > t[mid].hi: lo = mid + 1
    else: return true
  false

func runeWidth*(r: Rune): int =
  ## Terminal columns `r` takes: 0, 1 or 2.
  let c = r.int32
  if c < 0x0300: 1 # fast path: ASCII, Latin-1, Latin Extended
  elif c.inRanges(ZeroWidth): 0
  elif c.inRanges(CjkWide): 2
  elif c.inRanges(Emoji):
    {.cast(noSideEffect).}:
      gEmojiWidth
  else: 1

func textWidth*(s: string): int =
  ## Terminal columns `s` takes.
  for r in s.runes:
    result += r.runeWidth

func clipWidth*(s: string, w: int): string =
  ## The longest prefix of `s` that fits in `w` columns (zero-width
  ## characters stay with the character before them).
  var used = 0
  var i = 0
  while i < s.len:
    let r = s.runeAt(i)
    let rw = r.runeWidth
    if used + rw > w:
      break
    used += rw
    i += s.runeLenAt(i)
  s[0 ..< i]

func colOf*(rs: openArray[Rune], idx: int): int =
  ## Display column where rune `idx` starts.
  for k in 0 ..< min(idx, rs.len):
    result += rs[k].runeWidth

func indexAtCol*(rs: openArray[Rune], col: int): int =
  ## Index of the rune covering display column `col` (rs.len past the end).
  ## Zero-width runes belong to the rune before them.
  var c = 0
  for k, r in rs:
    let w = r.runeWidth
    if w > 0 and col < c + w:
      return k
    c += w
  rs.len

func padWidth*(s: string, w: int): string =
  ## `s` clipped to `w` columns, then padded with spaces to exactly `w`.
  result = s.clipWidth(w)
  let used = result.textWidth
  if used < w:
    result.add spaces(w - used)

{.pop.}
