## Read-only text widgets, selection, copy and cut (deviation #47).

import std/[unittest, unicode, deques, base64]
import ../src/illview/backend/illwill_vendored except Style
import ../src/illview/core/[geometry, theme, drawcontext, view, events, selection,
                            clipboard]
import ../src/illview/backend/decoder
import ../src/illview/widgets/[input, editor, textview]

var copied: seq[string]
copyHook = proc(s: string) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}: copied.add s

proc key(k: Key, mods: set[Modifier] = {}, r = Rune(0)): Event =
  Event(kind: evKey, ikey: keyEvent(k, r, mods))

proc ch(c: char): Event =
  Event(kind: evKey, ikey: keyEvent(Key.None, Rune(c)))

proc mouse(a: MouseAction, x, y: int, mods: set[Modifier] = {}): Event =
  Event(kind: evMouse, imouse: mouseEvent(a, mbLeft, x, y, mods))

proc paste(s: string): Event =
  Event(kind: evPaste, pasteText: s)

proc lastCopy(): string =
  {.cast(gcsafe).}: copied[^1]

suite "selection model":
  test "ordered, half-open, multi-line text":
    let lines = @["héllo", "日本", "end"]
    let (lo, hi) = ordered(textPos(2, 1), textPos(0, 1))
    check lo == textPos(0, 1)
    check selected(lo, hi, textPos(0, 1))
    check not selected(lo, hi, textPos(2, 1)) # the caret's character is out
    check lines.selectedText(lo, hi) == "éllo\n日本\ne"
    check lines.selectedText(textPos(1, 1), textPos(1, 2)) == "本"
    check lines.selectedText(textPos(1, 1), textPos(1, 1)) == ""

  test "works on a Deque":
    var d = initDeque[string]()
    d.addLast "ab"
    d.addLast "cd"
    check d.selectedText(textPos(0, 1), textPos(1, 1)) == "b\nc"

  test "OSC 52 encoding":
    check osc52("hi ✓") == "\e]52;c;" & encode("hi ✓") & "\a"

suite "decoder keys used for selection":
  test "Shift+arrows, F5, F6, Ctrl+Insert, Shift+Delete, Ctrl+A":
    var d: Decoder
    check d.feed("\e[1;2C") == @[keyEvent(Key.Right, mods = {modShift})]
    check d.feed("\e[1;2H") == @[keyEvent(Key.Home, mods = {modShift})]
    check d.feed("\e[2;5~") == @[keyEvent(Key.Insert, mods = {modCtrl})]
    check d.feed("\x01") == @[keyEvent(Key.CtrlA, Rune(1))]
    check d.feed("\e[15~") == @[keyEvent(Key.F5)]
    check d.feed("\e[17~") == @[keyEvent(Key.F6)]
    check d.feed("\e[3;2~") == @[keyEvent(Key.Delete, mods = {modShift})]

suite "editor":
  test "Shift+arrows select, F5 copies, typing replaces":
    let e = newEditor("hello\nworld")
    e.curLine = 0
    e.curCol = 1
    check e.handleEvent(key(Key.Right, {modShift}))
    check e.handleEvent(key(Key.Right, {modShift}))
    check e.selectedText == "el"
    check e.handleEvent(key(Key.F5))
    check lastCopy() == "el"
    check e.handleEvent(ch('X'))
    check e.text == "hXlo\nworld"
    check not e.hasSelection
    check not e.handleEvent(key(Key.F5)) # nothing selected: bubbles

  test "plain navigation drops the selection":
    let e = newEditor("abc")
    e.curCol = 0
    discard e.handleEvent(key(Key.End, {modShift}))
    check e.selectedText == "abc"
    discard e.handleEvent(key(Key.Left))
    check not e.hasSelection

  test "F6 cuts across lines, Backspace and paste replace":
    let e = newEditor("one\ntwo\nthree")
    e.curLine = 0
    e.curCol = 2
    discard e.handleEvent(key(Key.Down, {modShift}))
    discard e.handleEvent(key(Key.Down, {modShift}))
    check e.selectedText == "e\ntwo\nth"
    check e.handleEvent(key(Key.F6))
    check lastCopy() == "e\ntwo\nth"
    check e.text == "onree"
    check (e.curLine, e.curCol) == (0, 2)
    discard e.handleEvent(key(Key.End, {modShift}))
    check e.handleEvent(key(Key.Backspace))
    check e.text == "on"
    discard e.handleEvent(key(Key.Home, {modShift}))
    check e.handleEvent(paste("A\nB"))
    check e.text == "A\nB"

  test "Ctrl+A selects all; Ctrl+Insert copies; Shift+Delete cuts":
    let e = newEditor("a\nb")
    discard e.handleEvent(key(Key.CtrlA))
    check e.handleEvent(key(Key.Insert, {modCtrl}))
    check lastCopy() == "a\nb"
    discard e.handleEvent(key(Key.Home, {modShift}))
    check e.selectedText == "a\n"
    check e.handleEvent(key(Key.Delete, {modShift}))
    check lastCopy() == "a\n"
    check e.text == "b"
    check not e.handleEvent(key(Key.Delete, {modShift})) # nothing selected
    check not e.handleEvent(key(Key.CtrlC)) # Ctrl+C is not a copy key

  test "read-only: editing keys bubble, selection and copy work":
    let e = newEditor("fixed text")
    e.readOnly = true
    var changes = 0
    e.onChange = proc(s: Editor) {.gcsafe, raises: [].} = inc changes
    check not e.handleEvent(ch('x'))
    check not e.handleEvent(key(Key.Enter))
    check not e.handleEvent(key(Key.Backspace))
    check not e.handleEvent(paste("p"))
    discard e.handleEvent(key(Key.CtrlA))
    check not e.handleEvent(key(Key.F6))
    check not e.handleEvent(key(Key.Delete, {modShift}))
    check e.handleEvent(key(Key.F5))
    check lastCopy() == "fixed text"
    check e.text == "fixed text"
    check changes == 0

  test "mouse drag selects, Shift+click extends":
    let e = newEditor("abcdef\nghijkl")
    e.arrange(rect(0, 0, 10, 2))
    check e.handleEvent(mouse(maPress, 1, 0))
    check e.handleEvent(mouse(maMove, 3, 1))
    check e.handleEvent(mouse(maRelease, 3, 1))
    check e.selectedText == "bcdef\nghi"
    discard e.handleEvent(mouse(maPress, 5, 1, {modShift}))
    check e.selectedText == "bcdef\nghijk"

  test "selected cells use tkTextSelection":
    let e = newEditor("abcd")
    e.theme = defaultTheme()
    e.arrange(rect(0, 0, 6, 1))
    e.curCol = 1
    discard e.handleEvent(key(Key.Right, {modShift}))
    discard e.handleEvent(key(Key.Right, {modShift}))
    let tb = newTerminalBuffer(6, 1)
    e.draw(initDrawContext(tb))
    let sel = defaultTheme().style(tkTextSelection)
    check tb[1, 0].bg == sel.bg
    check tb[2, 0].bg == sel.bg
    check tb[0, 0].bg != sel.bg

suite "input":
  test "select, copy, replace, cut (F6, Shift+Delete)":
    let i = newInput("abcdef")
    discard i.handleEvent(key(Key.Home))
    discard i.handleEvent(key(Key.Right, {modShift}))
    discard i.handleEvent(key(Key.Right, {modShift}))
    check i.selectedText == "ab"
    check i.handleEvent(key(Key.F5))
    check lastCopy() == "ab"
    check i.handleEvent(ch('Z'))
    check i.text == "Zcdef"
    discard i.handleEvent(key(Key.End, {modShift}))
    check i.handleEvent(key(Key.F6))
    check lastCopy() == "cdef"
    check i.text == "Z"
    discard i.handleEvent(key(Key.CtrlA))
    check i.handleEvent(paste("new"))
    check i.text == "new"
    discard i.handleEvent(key(Key.Left, {modShift}))
    check i.handleEvent(key(Key.Delete, {modShift}))
    check lastCopy() == "w"
    check i.text == "ne"

  test "read-only: Enter, Down and edits bubble; copy works":
    let i = newInput("16Uiu2HAm")
    i.readOnly = true
    var submitted = false
    i.onSubmit = proc(s: Input) {.gcsafe, raises: [].} = submitted = true
    i.history = @["old"]
    check not i.handleEvent(ch('x'))
    check not i.handleEvent(key(Key.Backspace))
    check not i.handleEvent(key(Key.Enter))
    check not i.handleEvent(key(Key.Down))
    check not i.handleEvent(paste("p"))
    check not submitted
    check i.handleEvent(key(Key.CtrlA))
    check i.handleEvent(key(Key.F5))
    check lastCopy() == "16Uiu2HAm"
    check i.text == "16Uiu2HAm"

  test "mouse drag selects":
    let i = newInput("a日bc")
    i.arrange(rect(0, 0, 10, 1))
    discard i.handleEvent(mouse(maPress, 1, 0)) # 日's left half
    discard i.handleEvent(mouse(maMove, 4, 0))  # c
    check i.selectedText == "日b"

suite "textview":
  test "drag selects, copy, Ctrl+A":
    let tv = newTextView()
    tv.arrange(rect(0, 0, 20, 3))
    for s in ["first line", "second", "third"]: tv.addLine s
    check tv.handleEvent(mouse(maPress, 6, 0))
    check tv.handleEvent(mouse(maMove, 3, 1))
    check tv.handleEvent(mouse(maRelease, 3, 1))
    check tv.selectedText == "line\nsec"
    check tv.handleEvent(key(Key.F5))
    check lastCopy() == "line\nsec"
    check tv.handleEvent(key(Key.CtrlA))
    check tv.selectedText == "first line\nsecond\nthird"

  test "selection keeps its text when old lines drop; view stops following":
    let tv = newTextView(maxLines = 3)
    tv.arrange(rect(0, 0, 20, 2))
    for s in ["a", "b", "c"]: tv.addLine s
    discard tv.handleEvent(mouse(maPress, 0, 0)) # "b" (follow: top = 1)
    discard tv.handleEvent(mouse(maMove, 1, 1))  # "c"
    check tv.selectedText == "b\nc"
    check not tv.follow
    tv.addLine "d" # drops "a"
    check tv.selectedText == "b\nc"
    check not tv.handleEvent(key(Key.F6)) # read-only: no cut

  test "a click without a drag selects nothing":
    let tv = newTextView()
    tv.arrange(rect(0, 0, 20, 2))
    tv.addLine "x"
    discard tv.handleEvent(mouse(maPress, 0, 0))
    discard tv.handleEvent(mouse(maRelease, 0, 0))
    check not tv.hasSelection
    check tv.follow
    check not tv.handleEvent(key(Key.F5))
