## Copy to the system clipboard (deviation #47). Two routes, both taken:
##
## - OSC 52 (`ESC ] 52 ; c ; <base64> BEL`) on the renderer's output: the
##   terminal sets the clipboard, also over ssh (kitty, WezTerm, Alacritty,
##   foot, iTerm2 when allowed in its settings, tmux with set-clipboard on).
## - The OS tool, when one is found: `pbcopy` on macOS (Terminal.app ignores
##   OSC 52); `wl-copy`, `xclip` or `xsel` on Linux.

import std/[base64, os, osproc, streams]
import ../backend/illwill_vendored

var copyHook*: proc(s: string) {.gcsafe, raises: [].}
  ## Replaces both routes when set (tests, or an app with its own clipboard).

func osc52*(s: string): string =
  "\e]52;c;" & encode(s) & "\a"

proc nativeCopyCommand*(): seq[string] =
  ## The OS clipboard tool and its arguments, or @[] when none is found.
  when defined(macosx):
    if findExe("pbcopy").len > 0: return @["pbcopy"]
  else:
    if existsEnv("WAYLAND_DISPLAY") and findExe("wl-copy").len > 0:
      return @["wl-copy"]
    if existsEnv("DISPLAY"):
      if findExe("xclip").len > 0: return @["xclip", "-selection", "clipboard"]
      if findExe("xsel").len > 0: return @["xsel", "--clipboard", "--input"]
  @[]

proc nativeCopy(s: string) {.raises: [].} =
  try:
    let cmd = nativeCopyCommand()
    if cmd.len == 0:
      return
    let p = startProcess(cmd[0], args = cmd[1 .. ^1], options = {poUsePath})
    p.inputStream.write(s)
    p.inputStream.close() # EOF: the tool takes the text
    discard p.waitForExit(1000) # xclip / wl-copy fork to serve the selection
    p.close()
  except CatchableError:
    discard # no clipboard tool working: OSC 52 is still sent

proc copyToClipboard*(s: string) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if copyHook != nil:
      copyHook(s)
      return
    try:
      output().write(osc52(s))
      output().flushFile()
    except IOError:
      discard
    nativeCopy(s)
