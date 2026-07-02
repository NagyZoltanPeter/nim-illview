## mount(T) — compile-time construction of a pragma-annotated view type
## (Phase 5): emits constructor, parent/child wiring, layout container
## selection and action/slot binding. The nested `ui:` template is the
## escape hatch for dynamic/loop/conditional content.

import std/[macros, unicode]
import ../core/[geometry, view, bus]
import ../layout/layout
import ../widgets/[window, label, button, checkbox, radio, list, input,
                   textview, statusbar, editor, groupbox, table, progress]

# --- construction defaults ---------------------------------------------------

proc createView*(t: typedesc[Label]): Label = newLabel("")
proc createView*(t: typedesc[Button]): Button = newButton("")
proc createView*(t: typedesc[Checkbox]): Checkbox = newCheckbox("")
proc createView*(t: typedesc[Radio]): Radio = newRadio(@[])
proc createView*(t: typedesc[Input]): Input = newInput()
proc createView*(t: typedesc[ListView]): ListView = newListView()
proc createView*(t: typedesc[TextView]): TextView = newTextView()
proc createView*(t: typedesc[Editor]): Editor = newEditor()
proc createView*(t: typedesc[StatusBar]): StatusBar = newStatusBar()
proc createView*(t: typedesc[Window]): Window = newWindow("", rect(0, 0, 0, 0))
proc createView*(t: typedesc[GroupBox]): GroupBox = newGroupBox("")
proc createView*(t: typedesc[Table]): Table = newTable()
proc createView*(t: typedesc[ProgressBar]): ProgressBar = newProgressBar()

# --- pragma appliers ----------------------------------------------------------

proc setCaption*(w: Button, s: string) =
  w.caption = s
  w.hint = (fixedHint(s.runeLen + 4), fixedHint(1))

proc setCaption*(w: Checkbox, s: string) =
  w.caption = s
  w.hint = (fixedHint(s.runeLen + 4), fixedHint(1))

proc setCaption*(w: Label, s: string) = w.setText(s)
proc setCaption*(w: Input, s: string) = w.setText(s)
proc setCaption*(w: Window, s: string) = w.title = s
proc setCaption*(w: GroupBox, s: string) = w.borderTitle = s

proc setStretch*(v: View, n: int) =
  v.hint.w.stretch = n
  v.hint.h.stretch = n

type SlotProc[W] = proc(sender: W) {.gcsafe, raises: [].}

proc chain[W](a, b: SlotProc[W]): SlotProc[W] =
  ## mount-generated consumers APPEND to a slot (plan-2 D4): value store ->
  ## bindTo handler -> emits, in wiring order.
  if a == nil:
    b
  else:
    proc(s: W) {.gcsafe, raises: [].} =
      a(s)
      b(s)

# primary (action) slots
proc bindSlot*(w: Button, h: SlotProc[Button]) = w.onClick = chain(w.onClick, h)
proc bindSlot*(w: Checkbox, h: SlotProc[Checkbox]) = w.onToggle = chain(w.onToggle, h)
proc bindSlot*(w: Radio, h: SlotProc[Radio]) = w.onSelect = chain(w.onSelect, h)
proc bindSlot*(w: ListView, h: SlotProc[ListView]) = w.onActivate = chain(w.onActivate, h)
proc bindSlot*(w: Input, h: SlotProc[Input]) = w.onSubmit = chain(w.onSubmit, h)
proc bindSlot*(w: Editor, h: SlotProc[Editor]) = w.onChange = chain(w.onChange, h)
proc bindSlot*(w: Table, h: SlotProc[Table]) = w.onActivate = chain(w.onActivate, h)

# value-change slots + value snapshots (plan-2 D4)
proc bindValueSlot*(w: Input, h: SlotProc[Input]) = w.onChange = chain(w.onChange, h)
proc bindValueSlot*(w: Editor, h: SlotProc[Editor]) = w.onChange = chain(w.onChange, h)
proc bindValueSlot*(w: Checkbox, h: SlotProc[Checkbox]) = w.onToggle = chain(w.onToggle, h)
proc bindValueSlot*(w: Radio, h: SlotProc[Radio]) = w.onSelect = chain(w.onSelect, h)
proc bindValueSlot*(w: ListView, h: SlotProc[ListView]) = w.onSelect = chain(w.onSelect, h)
proc bindValueSlot*(w: Table, h: SlotProc[Table]) = w.onSelect = chain(w.onSelect, h)

proc widgetValue*(w: Input): string = w.text
proc widgetValue*(w: Editor): string = w.text
proc widgetValue*(w: Checkbox): bool = w.checked
proc widgetValue*(w: Radio): int = w.selected
proc widgetValue*(w: ListView): int = w.selected
proc widgetValue*(w: Table): int = w.selected

# --- the macro ----------------------------------------------------------------

proc pragmaArg*(prag: NimNode, name: string): NimNode =
  ## Returns the argument of pragma `name` in a nnkPragma list, or nil.
  ## nil-safe on flag pragmas (returns an ident marker).
  if prag == nil or prag.kind != nnkPragma:
    return nil
  for p in prag:
    case p.kind
    of nnkIdent, nnkSym:
      if p.eqIdent(name):
        return p # flag pragma present, no arg
    of nnkExprColonExpr, nnkCall:
      if p[0].eqIdent(name):
        return p[1]
    else:
      discard
  nil

proc typePragmas*(impl: NimNode): NimNode =
  ## The nnkPragma node attached to a typeDef's name, or nil.
  if impl[0].kind == nnkPragmaExpr:
    impl[0][1]
  else:
    nil

proc fieldInfo*(identDefs: NimNode): tuple[name: NimNode, prag: NimNode,
                                          typ: NimNode] =
  var nameNode = identDefs[0]
  var prag: NimNode = nil
  if nameNode.kind == nnkPragmaExpr:
    prag = nameNode[1]
    nameNode = nameNode[0]
  if nameNode.kind == nnkPostfix:
    nameNode = nameNode[1]
  (nameNode, prag, identDefs[^2])

proc addStyleApplications(stmts, prag, target: NimNode) =
  ## Styling pragmas (plan-2 D3), valid at type level (target = self) and
  ## field level (target = self.field).
  let borderArg = pragmaArg(prag, "border")
  if borderArg != nil:
    stmts.add quote do:
      `target`.border = `borderArg`
  let btArg = pragmaArg(prag, "boxTitle")
  if btArg != nil:
    stmts.add quote do:
      `target`.borderTitle = `btArg`
  if pragmaArg(prag, "shadow") != nil:
    stmts.add quote do:
      `target`.shadow = true
  let fgArg = pragmaArg(prag, "fg")
  if fgArg != nil:
    stmts.add quote do:
      `target`.styleOv.fg = `fgArg`
  let bgArg = pragmaArg(prag, "bg")
  if bgArg != nil:
    stmts.add quote do:
      `target`.styleOv.bg = `bgArg`
  let ffgArg = pragmaArg(prag, "focusFg")
  if ffgArg != nil:
    stmts.add quote do:
      `target`.styleOv.focusFg = `ffgArg`
  let fbgArg = pragmaArg(prag, "focusBg")
  if fbgArg != nil:
    stmts.add quote do:
      `target`.styleOv.focusBg = `fbgArg`

macro mount*(T: typedesc): untyped =
  ## Build an instance of the pragma-annotated view type T: construct,
  ## wire children into the declared layout container, set captions/docks/
  ## stretch, bind `action:` commands and `bindTo:` handlers.
  var sym = T.getTypeInst
  if sym.kind == nnkBracketExpr:
    sym = sym[1]
  let impl = sym.getImpl
  impl.expectKind nnkTypeDef
  var objTy = impl[2]
  if objTy.kind == nnkRefTy:
    objTy = objTy[0]
  if objTy.kind != nnkObjectTy:
    error("mount(T): T must be a ref object view type", T)
  let recList = objTy[2]
  let tprag = typePragmas(impl)

  let self = genSym(nskLet, "self")
  let cont = genSym(nskLet, "container")
  var stmts = newStmtList()
  stmts.add quote do:
    let `self` = `sym`()
    initView(`self`)

  let titleArg = pragmaArg(tprag, "title")
  if titleArg != nil:
    stmts.add quote do:
      setCaption(`self`, `titleArg`)
  let tdock = pragmaArg(tprag, "dock")
  if tdock != nil:
    stmts.add quote do:
      `self`.dock = `tdock`
  addStyleApplications(stmts, tprag, self)

  # layout container selection
  let spacingArg = pragmaArg(tprag, "spacing")
  let spacing = if spacingArg != nil: spacingArg else: newLit(0)
  let gridArg = pragmaArg(tprag, "grid")
  if pragmaArg(tprag, "vbox") != nil:
    stmts.add quote do:
      let inner = newVBox(`spacing`)
      inner.dock = dkFill
      add(Group(`self`), inner)
      let `cont`: Group = inner
  elif pragmaArg(tprag, "hbox") != nil:
    stmts.add quote do:
      let inner = newHBox(`spacing`)
      inner.dock = dkFill
      add(Group(`self`), inner)
      let `cont`: Group = inner
  elif gridArg != nil:
    stmts.add quote do:
      let inner = newGrid(`gridArg`, `spacing`)
      inner.dock = dkFill
      add(Group(`self`), inner)
      let `cont`: Group = inner
  else:
    stmts.add quote do:
      let `cont`: Group = Group(`self`)

  # children, in declaration order
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue
    let (fname, fprag, ftyp) = fieldInfo(identDefs)
    if pragmaArg(fprag, "child") == nil:
      continue
    # user {.view.} component types mount recursively; everything else goes
    # through the createView overloads (bound at the expansion site).
    # Splice the type as a FRESH ident: a typed sym lifted out of the record
    # AST carries type `T` (not typedesc[T]) and fails typedesc params.
    var isUserView = false
    if ftyp.kind == nnkSym:
      let fimpl = ftyp.getImpl
      if fimpl != nil and fimpl.kind == nnkTypeDef:
        isUserView = pragmaArg(typePragmas(fimpl), "view") != nil
    let ftypId = if ftyp.kind == nnkSym: ident(ftyp.strVal) else: ftyp
    let createCall =
      if isUserView: newCall(ident("mount"), ftypId)
      else: newCall(ident("createView"), ftypId)
    stmts.add quote do:
      `self`.`fname` = `createCall`
    let capArg = pragmaArg(fprag, "caption")
    if capArg != nil:
      stmts.add quote do:
        setCaption(`self`.`fname`, `capArg`)
    let dockArg = pragmaArg(fprag, "dock")
    if dockArg != nil:
      stmts.add quote do:
        `self`.`fname`.dock = `dockArg`
    let stretchArg = pragmaArg(fprag, "stretch")
    if stretchArg != nil:
      stmts.add quote do:
        setStretch(`self`.`fname`, `stretchArg`)
    let actionArg = pragmaArg(fprag, "action")
    if actionArg != nil:
      stmts.add quote do:
        `self`.`fname`.command = `actionArg`
    addStyleApplications(stmts, fprag, newDotExpr(self, fname))
    # value binding (plan-2 D4): direct store, or via a sync RequestBroker
    # generated by uiEvents(T) — the field stores what the provider returns
    let bindValArg = pragmaArg(fprag, "bindValue")
    let bindReqArg = pragmaArg(fprag, "bindRequest")
    if bindReqArg != nil:
      if bindReqArg.kind notin {nnkStrLit, nnkRStrLit}:
        error("bindRequest expects a string literal request name", bindReqArg)
      let reqId = ident(bindReqArg.strVal)
      if bindValArg != nil:
        let bf = ident(bindValArg.strVal)
        stmts.add quote do:
          bindValueSlot(`self`.`fname`,
                        proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                          {.cast(gcsafe).}:
                            {.cast(raises: []).}:
                              let r = request(`reqId`, widgetValue(sender))
                              if r.isOk:
                                `self`.`bf` = r.get)
      else:
        stmts.add quote do:
          bindValueSlot(`self`.`fname`,
                        proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                          {.cast(gcsafe).}:
                            {.cast(raises: []).}:
                              discard request(`reqId`, widgetValue(sender)))
    elif bindValArg != nil:
      if bindValArg.kind notin {nnkStrLit, nnkRStrLit}:
        error("bindValue expects a string literal field name", bindValArg)
      let bf = ident(bindValArg.strVal)
      stmts.add quote do:
        bindValueSlot(`self`.`fname`,
                      proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                        {.cast(gcsafe).}:
                          `self`.`bf` = widgetValue(sender))
    let bindArg = pragmaArg(fprag, "bindTo")
    if bindArg != nil:
      if bindArg.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
        error("bindTo expects a string literal handler name", bindArg)
      let handler = ident(bindArg.strVal)
      # cast(gcsafe): mount may be expanded at module scope, where `self`
      # is a global; the framework is single-threaded by design (plan §0.1)
      stmts.add quote do:
        bindSlot(`self`.`fname`,
                 proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                   {.cast(gcsafe).}:
                     `handler`(`self`, sender))
    # typed event emission (plan-2 D5): activation emits the uiEvents(T)-
    # generated broker event, payload snapshotted from the widget
    let emitsArg = pragmaArg(fprag, "emits")
    if emitsArg != nil:
      if emitsArg.kind notin {nnkStrLit, nnkRStrLit}:
        error("emits expects a string literal event name", emitsArg)
      let evId = ident(emitsArg.strVal)
      stmts.add quote do:
        bindSlot(`self`.`fname`,
                 proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                   {.cast(gcsafe).}:
                     uiEmit(sender, `evId`))
    stmts.add quote do:
      add(`cont`, `self`.`fname`)

  stmts.add self
  result = newBlockStmt(stmts)

proc createView*[T: View](t: typedesc[T]): T =
  ## Fallback for user-defined {.view.} component types: mount recursively.
  mount(T)

template ui*(g: Group, body: untyped) =
  ## Escape hatch for dynamic/loop/conditional content: exposes the target
  ## container as `it` and runs arbitrary code against it.
  block:
    let it {.inject.} = g
    body
