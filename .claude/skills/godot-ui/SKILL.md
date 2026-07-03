---
name: godot-ui
description: Godot 4.x UI development — Control nodes, anchors and containers, themes and styling, responsive multi-resolution layout, focus and gamepad navigation, HUDs, menus, and UI animation (including 4.7 Control offset transforms). Use when building any menu, HUD, inventory screen, dialog, settings page, or fixing UI layout/scaling problems.
---

# Godot UI (4.x, current through 4.7)

## The two layout systems — never fight them

1. **Anchors + offsets** — for free-floating Controls positioned relative to their parent's rect. Use anchor presets ("Full Rect", "Center", "Bottom Right"...) via the toolbar.
2. **Containers** — parents that OWN their children's position/size (HBoxContainer, VBoxContainer, GridContainer, MarginContainer, PanelContainer, CenterContainer, ScrollContainer, HFlowContainer, TabContainer, SplitContainer, AspectRatioContainer, SubViewportContainer, FoldableContainer 4.5+).

**Inside a container, manual `position`/`size`/anchors on children are overwritten every layout pass.** The knobs that work inside containers: `size_flags_horizontal/vertical` (Fill, Expand, Shrink Center/End), `custom_minimum_size`, `stretch_ratio`, and the container's own properties (separation via theme override).

**4.7 exception:** Control **offset transforms** let you visually translate/rotate/scale a Control *without* affecting layout — the layout slot stays put, the pixels move. This is the right tool for juicing container children (button hover wiggle, card fan-out) that previously required wrapper nodes or reparenting hacks.

Standard skeleton:

```
HUD (CanvasLayer)
└── Root (Control, Full Rect anchors)
    └── MarginContainer (Full Rect, margins via theme override ~16-48px)
        └── VBoxContainer / actual layout…
```

- UI lives under a `CanvasLayer` so the 2D/3D camera doesn't move it.
- Separate CanvasLayers by z-need: HUD (layer 1), pause menu (layer 10), transition fade (layer 100).

## Multi-resolution setup

Project Settings > Display > Window:
- Stretch Mode `canvas_items` — the default right answer; UI scales with resolution, stays sharp.
- Aspect `keep` (letterbox) or `expand` (UI root grows — design anchors for it; most modern choice).
- Pixel-art UI: either integer `Scale` with `viewport` stretch, or `canvas_items` + nearest filtering + design at a small base size.
- Runtime UI scale slider: `get_tree().root.content_scale_factor = 1.25`.
- Test at multiple sizes constantly: aspect extremes 16:9 ↔ 21:9 ↔ phone portrait. Anchors handle it if you designed with containers; hard-coded positions never do.

## Theming

- One `Theme` resource on the UI root; children inherit. Per-node deviations: **theme overrides** (right-click property > "Copy as Override" workflow in the theme editor).
- Theme = per-Control-type (and custom "type variations") sets of: StyleBoxes, fonts, font sizes, colors, constants (separation, margins), icons.
- `StyleBoxFlat` covers 90% of game UI: bg color, corner radius, borders, shadows, content margins (content margins are how you pad Buttons/Panels — not MarginContainers inside every button).
- **Type variations** for semantic styles: define `DangerButton` variation in the theme, set `theme_type_variation = "DangerButton"` on the node. No per-node override spam.
- Fonts: import a variable/dynamic font once; sizes via theme. Enable multichannel SDF for scalable crisp text, or per-size for pixel fonts (disable antialiasing, set fixed size, snap to pixel).
- Code access: `get_theme_color(&"font_color", &"Button")`, `add_theme_stylebox_override(...)`.

## Focus & input (keyboard/gamepad support is not optional)

- `focus_mode = All` on interactables; first focus on menu open: `first_button.grab_focus()` (do it deferred if the menu was just added).
- Neighbors auto-resolve in containers; override `focus_neighbor_*` / `focus_next/previous` for irregular layouts.
- `ui_accept`, `ui_cancel`, `ui_up/down/left/right` built-in actions drive Control navigation — don't reinvent with raw input.
- Mouse + gamepad coexistence: on `mouse_entered`, `grab_focus()` so hover and focus states agree; hide the OS cursor on joypad input if desired.
- Input consumption order: `_input` → Control `_gui_input`/focus handling → shortcuts → `_unhandled_input`. **Gameplay input belongs in `_unhandled_input`** so open UI eats it naturally. A full-rect Control with `mouse_filter = Stop` blocks clicks to the game; `Ignore` lets them through; `Pass` handles-and-propagates. Most "clicks go through my menu" / "can't click the game" bugs are `mouse_filter`.
- Pause menus: CanvasLayer + `process_mode = WHEN_PAUSED`; open/close on `ui_cancel` in `_unhandled_input`, then `get_viewport().set_input_as_handled()`.
- Mobile: `VirtualJoystick` node (4.7+) for touch sticks; TouchScreenButton for world-space buttons; Control buttons work with touch out of the box (enable "Emulate Mouse From Touch" default).

## Common widgets — the right node

| Need | Node |
|---|---|
| Text | `Label`; styled/inline-images/effects → `RichTextLabel` (BBCode, `[wave]`, `[shake]`, custom effects) |
| Button variants | `Button`, `TextureButton`, `CheckBox`, `CheckButton`, `OptionButton` (dropdown), `MenuButton` |
| Value entry | `LineEdit`, `TextEdit`, `SpinBox`, `HSlider` |
| Progress/HP | `ProgressBar`, `TextureProgressBar` (radial via fill mode) |
| Lists/trees | `ItemList` (simple), `Tree` (columns, hierarchy — powerful, verbose) |
| Popups | `Window`/`AcceptDialog`/`ConfirmationDialog`; transient in-game popups: plain Control + animation (OS-window popups feel wrong in games; set `Window.popup_window`/embed subwindows) |
| Inventory grids | `GridContainer` of button scenes; drag & drop via `_get_drag_data`/`_can_drop_data`/`_drop_data` |
| Tooltips | `tooltip_text`; custom via `_make_custom_tooltip()` |

Dynamic lists: instantiate an entry **scene** per item (entry scene exposes `setup(data)` + signals); clear with `for c in list.get_children(): c.queue_free()`.

## HUD data binding

UI reads game state via signals — never per-frame polling of `get_node("../../Player")`:

```gdscript
# hud.gd — wire in the owner or via an Events bus
func bind(player: Player) -> void:
    player.health_changed.connect(_on_health_changed)
    _on_health_changed(player.health)   # push initial state

func _on_health_changed(hp: int) -> void:
    bar.value = hp
    var t := create_tween()
    t.tween_property(damage_ghost_bar, "value", float(hp), 0.4)\
     .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.3)
```

## UI animation

- Tweens for programmatic transitions (position, modulate, scale). Since containers own layout, tween **offset transforms (4.7+)** or `modulate`/`self_modulate`, or animate a wrapper Control that isn't containerized.
- Menu in/out: slide + fade, 0.15–0.3s, `TRANS_CUBIC`/`EASE_OUT` in, `EASE_IN` out. `await tween.finished` (or `tween_await` 4.7+) before freeing.
- AnimationPlayer for designed sequences (title screens); tweens for reactive states.
- Set `pivot_offset = size / 2` before scale/rotate effects (top-left default pivot looks wrong).
- Typewriter text: `RichTextLabel.visible_ratio` tweened, or `visible_characters` stepped with per-char sounds.
- Damage numbers: Label scene spawned at `camera.unproject_position(world_pos)` (3D) or world pos (2D, on a control-less Node2D), tween up + fade, free on finish.

## Pitfalls

1. Setting `position`/`size` on a container child (silently reverted). Use size flags / min size / 4.7 offset transforms.
2. Anchors set but node inside a container — container wins; anchors ignored.
3. `grab_focus()` in `_ready` of a scene being added this frame → sometimes too early; `call_deferred("grab_focus")`.
4. `mouse_filter` misconfigured full-rect containers eating game clicks (containers default to Ignore, Controls/Panels to Stop — check the actual blocker with the "Mouse > Filter" audit).
5. Text overflow: set `autowrap_mode`, `text_overrun_behavior` (ellipsis), and `custom_minimum_size` — don't rely on English string lengths (localization will break it; use `tr()` keys early).
6. Blurry UI: scale on Controls instead of theme font sizes / content_scale_factor; or filter=Linear on pixel fonts.
7. ScrollContainer child must be a single container with `size_flags` fill/expand and its own min size — otherwise nothing scrolls.
8. Rebuilding whole lists every frame instead of updating changed entries.
9. `Window` dialogs unpaused game state — set process modes; and `exclusive`/`transient` for modal behavior.
10. Theme overrides scattered per-node when a type variation should exist — style drift; consolidate.

## Version notes (4.5–4.7)

- 4.5: `FoldableContainer` (collapsible sections — settings menus, debug panels).
- 4.6: unified editor docking (dev-side, not runtime); UI rendering benefits from faster 2D batching.
- 4.7: **Control offset transforms** (animate containerized UI safely), **VirtualJoystick**, `tween_await()` for signal-waiting tween sequences, inspector section copy/paste speeds theme editing.
