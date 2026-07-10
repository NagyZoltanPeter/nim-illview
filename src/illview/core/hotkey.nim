## Tilde hotkey markup (plan-4 P22): a caption like "~F~ile" declares 'F' as
## the Alt-accelerator and marks it for highlighting. Pure string parsing,
## shared by Button/Checkbox/Label/menu captions.

import std/unicode

type
  Hotkey* = object
    text*: string # caption with the tildes removed
    key*: Rune    # the accelerator rune; Rune(0) = none
    col*: int     # rune index of the accelerator in `text`; -1 = none

func parseHotkey*(s: string): Hotkey =
  ## "~F~ile" -> (text: "File", key: 'F', col: 0). A single leading tilde also
  ## works ("~File" -> same). No tilde -> the whole string, no accelerator.
  result.key = Rune(0)
  result.col = -1
  let runes = s.toRunes
  var i = 0
  var outp: seq[Rune]
  while i < runes.len:
    if runes[i] == Rune('~') and i + 1 < runes.len and result.col < 0:
      result.key = runes[i + 1]
      result.col = outp.len
      outp.add runes[i + 1]
      i += 2
      if i < runes.len and runes[i] == Rune('~'): # optional closing tilde
        inc i
    else:
      outp.add runes[i]
      inc i
  result.text = $outp

func hotkeyMatches*(a, b: Rune): bool =
  ## Case-insensitive accelerator comparison (Alt+f matches ~F~).
  a != Rune(0) and toLower(a) == toLower(b)
