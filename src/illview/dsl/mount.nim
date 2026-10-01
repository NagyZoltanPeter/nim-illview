## mount(T) — compile-time construction of a pragma-annotated view type
## (Phase 5): emits constructor, parent/child wiring, layout container
## selection and action/slot binding. The nested `ui:` template is the
## escape hatch for dynamic/loop/conditional content.

import std/[macros, unicode, strutils]
import ../core/[geometry, view, bus]
import ../layout/layout
import ./pragmas
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

proc setCaption*(w: Button, s: string) = w.applyCaption(s)

proc setCaption*(w: Checkbox, s: string) = w.applyCaption(s)

proc setCaption*(w: Label, s: string) = w.setText(s)
proc setCaption*(w: Input, s: string) = w.setText(s)
proc setCaption*(w: Window, s: string) = w.title = s
proc setCaption*(w: GroupBox, s: string) = w.borderTitle = s

proc setStretch*(v: View, n: int) =
  v.hint.w.stretch = n
  v.hint.h.stretch = n

type SlotProc[W] = proc(sender: W) {.gcsafe, raises: [].}

proc chain*[W](a, b: SlotProc[W]): SlotProc[W] =
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

# value shape for emits:/bindValue (deviation #29): resolved at the expansion
# site through overloads, so a third-party widget joins by declaring one —
# never by matching a type NAME (a user type called `Input` is not ours).
type UiPayloadKind* = enum
  upNone, upText, upChecked, upSelected

template uiValueKind*(t: typedesc[Input]): UiPayloadKind = upText
template uiValueKind*(t: typedesc[Editor]): UiPayloadKind = upText
template uiValueKind*(t: typedesc[Checkbox]): UiPayloadKind = upChecked
template uiValueKind*(t: typedesc[Radio]): UiPayloadKind = upSelected
template uiValueKind*(t: typedesc[ListView]): UiPayloadKind = upSelected
template uiValueKind*(t: typedesc[Table]): UiPayloadKind = upSelected
template uiValueKind*(t: typedesc): UiPayloadKind = upNone

# --- pragma placement (deviation #29) --------------------------------------------
# A DSL pragma in the wrong position, or on a field without {.child.}, used to
# be ignored silently. Typos are already Nim errors (every DSL pragma is a
# {.pragma.} template), so only KNOWN names are checked here.

const
  stylePragmaNames = ["border", "boxTitle", "shadow", "fg", "bg", "focusFg", "focusBg"]
  typePragmaNames = ["view", "title", "dock", "hbox", "vbox", "grid", "form", "spacing"]
  fieldPragmaNames = ["child", "caption", "dock", "stretch", "alignSelf", "anchors",
                      "padding", "action", "bindTo", "bindValue", "bindRequest",
                      "emits", "on"]

proc pragmaNames(prag: NimNode): seq[string] =
  if prag == nil or prag.kind != nnkPragma:
    return
  for p in prag:
    case p.kind
    of nnkIdent, nnkSym:
      result.add p.strVal
    of nnkExprColonExpr, nnkCall:
      if p[0].kind in {nnkIdent, nnkSym}:
        result.add p[0].strVal
    else:
      discard

proc rejectMisplaced(prag: NimNode, atType: bool, what: string) =
  for n in pragmaNames(prag):
    if n in stylePragmaNames:
      continue
    if atType and n in fieldPragmaNames and n notin typePragmaNames:
      error("{." & n & ".} is a field-level pragma; not valid on " & what, prag)
    if not atType and n in typePragmaNames and n notin fieldPragmaNames:
      error("{." & n & ".} is a type-level pragma; not valid on " & what, prag)

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

proc storeTarget*(self: NimNode, path: string): NimNode =
  ## `bindValue: "field"` -> self.field; `"model.field"` -> self.model.field
  ## (deviation #30): the store may live on a ref model the view holds.
  result = self
  for part in path.split('.'):
    result = newDotExpr(result, ident(part))

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
  rejectMisplaced(tprag, atType = true, "type " & sym.strVal)

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
  elif pragmaArg(tprag, "form") != nil:
    stmts.add quote do:
      let inner = newFormLayout(`spacing`)
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
    rejectMisplaced(fprag, atType = false, "field '" & $fname & "'")
    if pragmaArg(fprag, "child") == nil:
      for n in pragmaNames(fprag):
        if n in fieldPragmaNames or n in stylePragmaNames:
          error("field '" & $fname & "' has {." & n &
                ".} but no {.child.}: it would not be mounted", identDefs)
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
    let alignArg = pragmaArg(fprag, "alignSelf")
    if alignArg != nil:
      stmts.add quote do:
        `self`.`fname`.align = `alignArg`
    let anchorsArg = pragmaArg(fprag, "anchors")
    if anchorsArg != nil:
      stmts.add quote do:
        `self`.`fname`.anchor.edges = `anchorsArg`
    let paddingArg = pragmaArg(fprag, "padding")
    if paddingArg != nil:
      stmts.add quote do:
        `self`.`fname`.padding = `paddingArg`
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
        let store = storeTarget(self, bindValArg.strVal)
        stmts.add quote do:
          bindValueSlot(`self`.`fname`,
                        proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                          {.cast(gcsafe).}:
                            {.cast(raises: []).}:
                              let r = request(`reqId`, widgetValue(sender))
                              if r.isOk:
                                `store` = r.get)
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
      let store = storeTarget(self, bindValArg.strVal)
      stmts.add quote do:
        bindValueSlot(`self`.`fname`,
                      proc(sender: `ftypId`) {.gcsafe, raises: [].} =
                        {.cast(gcsafe).}:
                          `store` = widgetValue(sender))
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
    # instance-ctx listeners (plan-3 D9): on: {EventType: "handler", ...} —
    # each handler listens on THIS widget's brokerCtx, so the same event
    # type on two widgets never cross-talks. All broker idents (listen,
    # Future, asyncSpawn, async) are deliberately unresolvable in THIS
    # module: quote leaves them raw and they bind at the expansion site
    # (same sym-binding trap uievents.nim documents for `emit`).
    let onArg = pragmaArg(fprag, "on")
    if onArg != nil:
      if onArg.kind != nnkTableConstr:
        error("on: expects {EventType: \"handlerName\", ...}", onArg)
      for pair in onArg:
        if pair.kind != nnkExprColonExpr or pair[0].kind notin {nnkIdent, nnkSym} or
           pair[1].kind notin {nnkStrLit, nnkRStrLit}:
          error("on: entries must be EventType: \"handlerName\"", pair)
        let evId = ident(if pair[0].kind == nnkSym: pair[0].strVal else: $pair[0])
        let handler = ident(pair[1].strVal)
        # a handler with neither accepted shape is named in the error instead
        # of falling through to a confusing mismatch (deviation #29)
        let shapeErr = newLit("on: handler '" & pair[1].strVal &
          "' must be proc(self: " & sym.strVal & ") or proc(self: " &
          sym.strVal & ", ev: " & evId.strVal & ")")
        stmts.add quote do:
          when compiles(`evId`.listen(`self`.`fname`.brokerCtx,
              proc(): Future[void] {.async: (raises: []), gcsafe.} = discard)):
            # payload-less event (e.g. Clicked): handler is proc(self)
            discard `evId`.listen(`self`.`fname`.brokerCtx,
              proc(): Future[void] {.async: (raises: []), gcsafe.} =
                {.cast(gcsafe).}:
                  when compiles(`handler`(`self`)):
                    `handler`(`self`)
                  else:
                    {.error: `shapeErr`.})
          else:
            discard `evId`.listen(`self`.`fname`.brokerCtx,
              proc(ev: `evId`): Future[void] {.async: (raises: []), gcsafe.} =
                {.cast(gcsafe).}:
                  when compiles(`handler`(`self`, ev)):
                    `handler`(`self`, ev)
                  elif compiles(`handler`(`self`)):
                    `handler`(`self`)
                  else:
                    {.error: `shapeErr`.})
          # teardown rides the WIDGET's disposers: the listener lives on the
          # widget's ctx and must drop before that ctx is released
          `self`.`fname`.disposers.add(
            proc() {.gcsafe, raises: [].} =
              {.cast(gcsafe).}:
                asyncSpawn `evId`.dropAllListeners(`self`.`fname`.brokerCtx))
    stmts.add quote do:
      add(`cont`, `self`.`fname`)

  stmts.add self
  result = newBlockStmt(stmts)

proc createView*[T: View](t: typedesc[T]): T =
  ## Fallback for a `{.child.}` field type mount() could not classify from
  ## the record AST: a `{.view.}` component mounts recursively; anything else
  ## is a compile error — a silent `T()` here would skip the widget's own
  ## constructor (deviation #29). Custom widgets provide
  ## `proc createView*(t: typedesc[X]): X = newX()` (docs/EXTENDING.md).
  when T.hasCustomPragma(pragmas.view):
    mount(T)
  else:
    {.error: "mount: no createView overload for this {.child.} field type — add {.view.} to it, or define `proc createView*(t: typedesc[X]): X = newX()` in scope (see docs/EXTENDING.md)".}

template ui*(g: Group, body: untyped) =
  ## Escape hatch for dynamic/loop/conditional content: exposes the target
  ## container as `it` and runs arbitrary code against it.
  block:
    let it {.inject.} = g
    body
