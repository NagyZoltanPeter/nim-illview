## Phase 0 exit criteria: drive raw byte arrays through Decoder.feed() and
## assert exact InputEvents. No terminal required.

import std/unittest
import std/unicode
import ../src/illview/core/events
import ../src/illview/backend/decoder

proc feedS(d: var Decoder, s: string): seq[InputEvent] =
  d.feed(s)

suite "decoder: plain keys":
  test "printable ASCII":
    var d: Decoder
    check d.feedS("a") == @[keyEvent(Key.A, Rune('a'))]
    check d.feedS("Z") == @[keyEvent(Key.ShiftZ, Rune('Z'))]
    check d.feedS(" ") == @[keyEvent(Key.Space, Rune(' '))]

  test "control keys":
    var d: Decoder
    check d.feedS("\x03") == @[keyEvent(Key.CtrlC, Rune(3))]
    check d.feedS("\x09") == @[keyEvent(Key.Tab, Rune(9))]
    check d.feedS("\x0D") == @[keyEvent(Key.Enter, Rune(13))]
    # illwill aliasing: LF -> Enter, BS/DEL -> Backspace
    check d.feedS("\x0A") == @[keyEvent(Key.Enter, Rune(13))]
    check d.feedS("\x08") == @[keyEvent(Key.Backspace, Rune(127))]
    check d.feedS("\x7F") == @[keyEvent(Key.Backspace, Rune(127))]

  test "multiple events in one feed":
    var d: Decoder
    check d.feedS("ab\e[B") == @[
      keyEvent(Key.A, Rune('a')),
      keyEvent(Key.B, Rune('b')),
      keyEvent(Key.Down)]

suite "decoder: escape sequences":
  test "CSI arrows, Home/End":
    var d: Decoder
    check d.feedS("\e[A") == @[keyEvent(Key.Up)]
    check d.feedS("\e[B") == @[keyEvent(Key.Down)]
    check d.feedS("\e[C") == @[keyEvent(Key.Right)]
    check d.feedS("\e[D") == @[keyEvent(Key.Left)]
    check d.feedS("\e[H") == @[keyEvent(Key.Home)]
    check d.feedS("\e[F") == @[keyEvent(Key.End)]

  test "SS3 arrows and F1-F4":
    var d: Decoder
    check d.feedS("\eOA") == @[keyEvent(Key.Up)]
    check d.feedS("\eOP") == @[keyEvent(Key.F1)]
    check d.feedS("\eOS") == @[keyEvent(Key.F4)]

  test "tilde sequences: nav block and function keys":
    var d: Decoder
    check d.feedS("\e[2~") == @[keyEvent(Key.Insert)]
    check d.feedS("\e[3~") == @[keyEvent(Key.Delete)]
    check d.feedS("\e[5~") == @[keyEvent(Key.PageUp)]
    check d.feedS("\e[6~") == @[keyEvent(Key.PageDown)]
    check d.feedS("\e[15~") == @[keyEvent(Key.F5)]
    check d.feedS("\e[17~") == @[keyEvent(Key.F6)]
    check d.feedS("\e[24~") == @[keyEvent(Key.F12)]

  test "modifiers: Ctrl/Shift/Alt-arrows, Shift-Tab":
    var d: Decoder
    check d.feedS("\e[1;5C") == @[keyEvent(Key.Right, mods = {modCtrl})]
    check d.feedS("\e[1;2A") == @[keyEvent(Key.Up, mods = {modShift})]
    check d.feedS("\e[1;3D") == @[keyEvent(Key.Left, mods = {modAlt})]
    check d.feedS("\e[Z") == @[keyEvent(Key.Tab, Rune(9), {modShift})]

  test "Alt-combos":
    var d: Decoder
    check d.feedS("\ex") == @[keyEvent(Key.X, Rune('x'), {modAlt})]
    check d.feedS("\e\x0D") == @[keyEvent(Key.Enter, Rune(13), {modAlt})]

  test "unknown CSI is discarded, stream continues":
    var d: Decoder
    check d.feedS("\e[999q" & "a") == @[keyEvent(Key.A, Rune('a'))]

suite "decoder: SGR mouse":
  test "press / release / move / wheel":
    var d: Decoder
    check d.feedS("\e[<0;10;5M") ==
      @[mouseEvent(maPress, mbLeft, 9, 4)]
    check d.feedS("\e[<0;10;5m") ==
      @[mouseEvent(maRelease, mbLeft, 9, 4)]
    check d.feedS("\e[<2;1;1M") ==
      @[mouseEvent(maPress, mbRight, 0, 0)]
    check d.feedS("\e[<35;7;8M") ==
      @[mouseEvent(maMove, mbNone, 6, 7)]
    check d.feedS("\e[<64;3;4M") ==
      @[mouseEvent(maWheelUp, mbNone, 2, 3)]
    check d.feedS("\e[<65;3;4M") ==
      @[mouseEvent(maWheelDown, mbNone, 2, 3)]

  test "mouse modifiers":
    var d: Decoder
    check d.feedS("\e[<16;2;2M") ==
      @[mouseEvent(maPress, mbLeft, 1, 1, {modCtrl})]
    check d.feedS("\e[<4;2;2M") ==
      @[mouseEvent(maPress, mbLeft, 1, 1, {modShift})]

suite "decoder: UTF-8":
  test "two-byte rune":
    var d: Decoder
    check d.feedS("é") == @[keyEvent(Key.None, "é".runeAt(0))]

  test "three-byte rune":
    var d: Decoder
    check d.feedS("€") == @[keyEvent(Key.None, "€".runeAt(0))]

  test "rune split across feeds":
    var d: Decoder
    check d.feedS("\xC3") == newSeq[InputEvent]()
    check d.pendingBytes == 1
    check d.feedS("\xA9") == @[keyEvent(Key.None, "é".runeAt(0))]
    check d.pendingBytes == 0

suite "decoder: incremental buffering":
  test "escape sequence split across two feeds":
    var d: Decoder
    check d.feedS("\e[") == newSeq[InputEvent]()
    check d.feedS("A") == @[keyEvent(Key.Up)]

  test "SGR mouse split mid-params":
    var d: Decoder
    check d.feedS("\e[<0;1") == newSeq[InputEvent]()
    check d.feedS("0;5M") == @[mouseEvent(maPress, mbLeft, 9, 4)]

  test "bare ESC resolves to Escape on flush":
    var d: Decoder
    check d.feedS("\e") == newSeq[InputEvent]()
    check d.flush() == @[keyEvent(Key.Escape, Rune(27))]
    check d.pendingBytes == 0

  test "flush does not break a pending sequence":
    var d: Decoder
    check d.feedS("\e[") == newSeq[InputEvent]()
    check d.flush() == newSeq[InputEvent]()
    check d.feedS("B") == @[keyEvent(Key.Down)]

  test "ESC ESC emits Escape and keeps parsing":
    var d: Decoder
    check d.feedS("\e\e[A") == @[keyEvent(Key.Escape, Rune(27)),
                                 keyEvent(Key.Up)]

suite "decoder: bracketed paste":
  test "simple paste":
    var d: Decoder
    check d.feedS("\e[200~hello\e[201~") ==
      @[InputEvent(kind: ikPaste, text: "hello")]

  test "paste split across feeds (terminator split too)":
    var d: Decoder
    check d.feedS("\e[200~hel") == newSeq[InputEvent]()
    check d.feedS("lo\e[2") == newSeq[InputEvent]()
    check d.feedS("01~x") == @[
      InputEvent(kind: ikPaste, text: "hello"),
      keyEvent(Key.X, Rune('x'))]

  test "paste containing a lone ESC byte":
    var d: Decoder
    check d.feedS("\e[200~a\ebc\e[201~") ==
      @[InputEvent(kind: ikPaste, text: "a\ebc")]
