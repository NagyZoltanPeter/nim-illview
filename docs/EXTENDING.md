# Extending illview: the widget contract

What a widget written outside the library must implement, and which
extension points the declarative layer resolves at the expansion site so a
third-party widget is treated exactly like a stock one. Everything here is
verified by `tests/test_mount.nim` and `tests/test_ctx_vocab.nim`.

## 1. The View contract (`src/illview/core/view.nim`)

A widget is a `ref object of View` (leaf) or `of Group` (container). Every
constructor calls `initView(result)`. The renderer never type-cases on
concrete widgets; a custom widget gets the same routing, theming, borders,
focus and modal plumbing as a built-in one.

| Method | Default | Override when |
| --- | --- | --- |
| `draw(v, dc: DrawContext)` | nothing | always — paint the content area (coordinates are content-local; the parent draws your border/shadow) |
| `measure(v): (w, h: SizeHint)` | `v.hint` | your preferred size depends on content |
| `arrange(v, r: Rect)` | sets `bounds` | you lay out children yourself (containers) |
| `handleEvent(v, ev: Event): bool` | `false` | you consume keys/mouse/paste/focus; return `true` to stop bubbling |
| `handlesHotkey` / `triggerHotkey` | none | you own an Alt-accelerator |
| `borderKind` / `clientRect` / `borderStyle` / `titleStyle` / `drawOverlay` | border-aware defaults | custom chrome |

Services reach the App only through closures on the root group:
`invalidate()`, `publish(cmd)`, `runModal(g)`, `endModal(cmd)`,
`commandEnabled(cmd)`. A detached subtree simply no-ops.

Method pragma contract: `{.gcsafe, raises: [].}` on every override.

## 2. Broker routing (`src/illview/vocab.nim`)

- `w.brokerCtx` — the widget's instance route, allocated on first use
  (deviation #28). `w.hasBrokerCtx` tells whether anyone ever asked for it.
- `installSignal(w, SetX): body` — one handler per signal type on `w`'s
  route, teardown recorded for `dispose()`. Deferred until the ctx
  materializes.
- `installFocusMe(w)` — lets `FocusMe.signal(w.brokerCtx)` focus it.
- Emit vocab events only `if w.hasBrokerCtx:` (see the cookbook §15).
- `dispose(w)` exactly once when a subtree is permanently gone
  (deviation #16).

## 3. Declarative-layer extension points (`src/illview/dsl/`)

`mount(T)` and `uiEvents(T)` generate calls that are resolved **where the
macro is expanded**, so overloads you declare in your own module apply.

| Overload | Needed for | Stock example (`dsl/mount.nim`) |
| --- | --- | --- |
| `createView(t: typedesc[W]): W` | `w {.child.}: W` in a `{.view.}` type — **required** for any non-`{.view.}` type; missing it is a compile error, never a silent default-construction | `createView(typedesc[Input]) = newInput()` |
| `setCaption(w: W, s: string)` | `{.caption: "…".}` | `Label` → `setText` |
| `bindSlot(w: W, h: proc(sender: W))` | `{.bindTo.}`, `{.emits.}` — the widget's primary action slot | `Button.onClick` |
| `bindValueSlot(w: W, h: proc(sender: W))` | `{.bindValue.}`, `{.bindRequest.}` — the value-change slot | `Input.onChange` |
| `widgetValue(w: W): V` | `{.bindValue.}` — the value snapshot | `Input.text` |
| `uiValueKind(t: typedesc[W]): UiPayloadKind` (template) | `{.emits.}` payload shape and the `set<Field>` writer: `upText`, `upChecked`, `upSelected`, or `upNone` | `Input` → `upText` |

`{.view.}` component types need none of these: `mount` recurses into them.

`on: {EventType: "handler"}` accepts `proc(self: T)` or `proc(self: T,
ev: EventType)`; any other signature is a compile error naming the two
accepted shapes.

## 4. Pragma placement

Type-level: `view`, `title`, `dock`, `hbox`, `vbox`, `grid`, `form`,
`spacing`, and the style pragmas. Field-level: `child`, `caption`, `dock`,
`stretch`, `alignSelf`, `anchors`, `padding`, `action`, `bindTo`,
`bindValue`, `bindRequest`, `emits`, `on`, and the style pragmas. A DSL
pragma in the wrong position, or a field carrying DSL pragmas without
`child`, is a compile error (plan-5 P34); a misspelled pragma is a Nim error
already, since every DSL pragma is a `{.pragma.}` template.
