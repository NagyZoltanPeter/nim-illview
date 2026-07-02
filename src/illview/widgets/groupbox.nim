## GroupBox (Phase 8): titled, bordered container for radio/checkbox/button
## groups. Pure decoration + Group behavior — the Phase 7 engine draws the
## frame and insets the children automatically. Hosts dock/box layouts and
## works as a `{.view, vbox.}` base type in mount().

import ../core/[theme, view]

type
  GroupBox* = ref object of Group

proc newGroupBox*(title: string): GroupBox =
  result = GroupBox(borderTitle: title)
  initView(result)
  result.border = bkSingle

method titleStyle*(g: GroupBox): Style {.gcsafe, raises: [].} =
  g.styleOf(tkGroupBox)
