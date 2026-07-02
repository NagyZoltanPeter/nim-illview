## Custom pragmas for the declarative layer (Phase 5, plan §1).
## `bindTo` is named so because `bind` is a reserved word.
##
## Type-level: view, title(s), hbox, vbox, grid(cols), spacing(n), dock(d)
## Field-level: child, caption(s), dock(d), stretch(n), action(c), bindTo(m)

import ../core/[geometry, bus, theme, view]

template view*() {.pragma.}
  ## Marks a type as a mountable illview screen/component.

template child*() {.pragma.}
  ## Marks a field as a child widget: mount() constructs it and adds it to
  ## the enclosing view (or its layout container).

template title*(s: string) {.pragma.}
  ## Window title (type-level).

template caption*(s: string) {.pragma.}
  ## Initial caption/text of the widget (button/checkbox/label/input/window).

template dock*(d: Dock) {.pragma.}
  ## Dock anchor for the field (or the mounted view itself at type level).

template stretch*(n: int) {.pragma.}
  ## Stretch weight (applied to both axes of the field's size hint).

template hbox*() {.pragma.}
  ## Lay the children out in a horizontal box (type-level).

template vbox*() {.pragma.}
  ## Lay the children out in a vertical box (type-level).

template grid*(cols: int) {.pragma.}
  ## Lay the children out in a grid with `cols` columns (type-level).

template spacing*(n: int) {.pragma.}
  ## Spacing for the hbox/vbox/grid container (type-level).

template action*(c: Command) {.pragma.}
  ## Broker command: the widget auto-publishes UiAction(c, id) on activation.

template bindTo*(m: string) {.pragma.}
  ## Wires the field's PRIMARY closure slot to the named proc on the
  ## enclosing view: proc m(self: EnclosingType, sender: FieldType).
  ## Primary slots: Button.onClick, Checkbox.onToggle, Radio.onSelect,
  ## ListView.onActivate, Input.onSubmit, Editor.onChange.

# --- styling (iteration 2, plan-2 D3) ----------------------------------------

template border*(k: BorderKind) {.pragma.}
  ## Border drawn by the parent; content area shrinks by 1 cell per side.

template boxTitle*(s: string) {.pragma.}
  ## Title on the top border (requires a border).

template shadow*() {.pragma.}
  ## TV-style shadow (recolors the cells right/below of the view).

template fg*(c: ForegroundColor) {.pragma.}
  ## Foreground override merged over the theme token.

template bg*(c: BackgroundColor) {.pragma.}
  ## Background override merged over the theme token.

template focusFg*(c: ForegroundColor) {.pragma.}
  ## Foreground while the view is focused.

template focusBg*(c: BackgroundColor) {.pragma.}
  ## Background while the view is focused.
