## Text selection shared by Editor, Input and TextView (deviation #47): a
## position is (line, rune index); a selection runs from an anchor to the
## caret, half-open (the caret's own character is not selected).

import std/unicode

type
  TextPos* = object
    line*, col*: int ## line index, rune index in that line

func textPos*(line, col: int): TextPos =
  TextPos(line: line, col: col)

func `<`*(a, b: TextPos): bool =
  a.line < b.line or (a.line == b.line and a.col < b.col)

func `<=`*(a, b: TextPos): bool =
  not (b < a)

func ordered*(a, b: TextPos): (TextPos, TextPos) =
  if b < a: (b, a) else: (a, b)

func selected*(lo, hi, p: TextPos): bool =
  ## True when `p` lies in [lo, hi).
  lo <= p and p < hi

func runeSlice(s: string, a, b: int): string =
  ## Runes [a, b) of `s`, clamped.
  var i = 0
  for r in s.runes:
    if i >= b:
      break
    if i >= a:
      result.add r.toUTF8
    inc i

proc selectedText*[T](lines: T, lo, hi: TextPos): string =
  ## The text in [lo, hi) of `lines` (anything with `len` and `[]` giving
  ## strings: a seq or a Deque), lines joined with "\n".
  if hi <= lo or lines.len == 0:
    return ""
  let first = clamp(lo.line, 0, lines.len - 1)
  let last = clamp(hi.line, 0, lines.len - 1)
  for i in first .. last:
    let a = if i == lo.line: lo.col else: 0
    let b = if i == hi.line: hi.col else: high(int)
    result.add runeSlice(lines[i], a, b)
    if i < last:
      result.add '\n'
