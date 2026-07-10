## Phase 24 exit criteria (plan-4 D18): key-level Input.filter rejects runes
## at input time (silently), the shipped helpers behave, and the intRange
## bindRequest provider vetoes out-of-range values. No terminal.

import std/[unittest, unicode]
import results
import ../src/illview/core/[view, events]
import ../src/illview/widgets/input

proc typeInto(i: Input, s: string) =
  for r in s.runes:
    discard i.handleEvent(Event(kind: evKey, ikey: keyEvent(Key.None, r)))

suite "key filters (plan-4 D18)":
  test "digitsOnly rejects non-digits silently":
    let i = newInput()
    i.filter = digitsOnly()
    typeInto(i, "1a2b3")
    check i.text == "123"

  test "maxLen caps the length":
    let i = newInput()
    i.filter = maxLen(3)
    typeInto(i, "abcdef")
    check i.text == "abc"

  test "charSet restricts to a set":
    let i = newInput()
    i.filter = charSet("abcdef0123456789")
    typeInto(i, "ca7xz9")
    check i.text == "ca79"

  test "allOf composes filters (digits, capped at 4)":
    let i = newInput()
    i.filter = allOf(digitsOnly(), maxLen(4))
    typeInto(i, "12ab3456")
    check i.text == "1234"

  test "paste is filtered too":
    let i = newInput()
    i.filter = digitsOnly()
    discard i.handleEvent(Event(kind: evPaste, pasteText: "a1b2c3"))
    check i.text == "123"

  test "no filter accepts everything":
    let i = newInput()
    typeInto(i, "aZ9 !")
    check i.text == "aZ9 !"

suite "intRange provider (plan-4 D18, value-level)":
  test "vetoes out-of-range, passes in-range and empty":
    let p = intRange(1, 100)
    check p("50").isOk
    check p("50").get == "50"
    check p("1").isOk
    check p("100").isOk
    check p("0").isErr
    check p("101").isErr
    check p("").isOk      # in-progress empty is allowed
    check p("12x").isErr  # not an integer
