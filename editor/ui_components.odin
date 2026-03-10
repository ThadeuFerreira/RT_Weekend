// ui_components.odin — Reusable UI building blocks: Button, Toggle, Dropdown.
// Use these by value; configure rect, label, and optional style, then call draw/hit procs.
// Composable: toolbars and panels build from buttons, toggles, and dropdowns.

package editor

import rl "vendor:raylib"

// ─── Button ─────────────────────────────────────────────────────────────

ButtonStyle :: struct {
	bg, bg_hover, border, text: rl.Color,
	font_size: i32,
}

// Default style: blue-ish primary action (Add, From View, etc.).
DEFAULT_BUTTON_STYLE :: ButtonStyle{
	bg       = rl.Color{55,  85, 140, 255},
	bg_hover = rl.Color{80, 130, 200, 255},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 12,
}

// Danger style: red (Delete, Cancel, etc.).
BUTTON_STYLE_DANGER :: ButtonStyle{
	bg       = rl.Color{140, 40, 40, 255},
	bg_hover = rl.Color{200, 60, 60, 255},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 12,
}

// Success style: green (Render, Save, OK).
BUTTON_STYLE_SUCCESS :: ButtonStyle{
	bg       = rl.Color{50, 140, 50, 255},
	bg_hover = rl.Color{80, 190, 80, 255},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 12,
}

// Neutral style: gray (secondary actions, e.g. D+ / D-).
BUTTON_STYLE_NEUTRAL :: ButtonStyle{
	bg       = rl.Color{45, 55, 70, 255},
	bg_hover = rl.Color{55, 68, 88, 255},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 11,
}

// Render button: busy state (dim green, no hover change).
BUTTON_STYLE_RENDER_BUSY :: ButtonStyle{
	bg       = rl.Color{45, 75, 45, 200},
	bg_hover = rl.Color{45, 75, 45, 200},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 12,
}

// Render button: ready state (bright green, click to start).
BUTTON_STYLE_RENDER_READY :: ButtonStyle{
	bg       = rl.Color{80, 220, 80, 255},
	bg_hover = rl.Color{80, 220, 80, 255},
	border   = BORDER_COLOR,
	text     = rl.RAYWHITE,
	font_size = 12,
}

Button :: struct {
	rect:    rl.Rectangle,
	label:   cstring,
	style:   ButtonStyle,
	enabled: bool,
}

// button_hover returns true if mouse is over the button rect.
button_hover :: proc(rect: rl.Rectangle, mouse: rl.Vector2) -> bool {
	return rl.CheckCollisionPointRec(mouse, rect)
}

// draw_button draws the button and returns whether it is hovered. When disabled, uses dimmer bg.
draw_button :: proc(app: ^App, b: Button, mouse: rl.Vector2) -> (hovered: bool) {
	hovered = b.enabled && button_hover(b.rect, mouse)
	bg := b.style.bg
	if !b.enabled {
		bg = rl.Color{
			b.style.bg.r / 2,
			b.style.bg.g / 2,
			b.style.bg.b / 2,
			b.style.bg.a,
		}
	} else if hovered {
		bg = b.style.bg_hover
	}
	rl.DrawRectangleRec(b.rect, bg)
	rl.DrawRectangleLinesEx(b.rect, 1, b.style.border)
	draw_ui_text(app, b.label, i32(b.rect.x) + 6, i32(b.rect.y) + 4, b.style.font_size, b.style.text)
	return hovered
}

// ─── Toggle ──────────────────────────────────────────────────────────────

ToggleStyle :: struct {
	bg_off, bg_off_hover, bg_on, bg_on_hover: rl.Color,
	border_off, border_on, text: rl.Color,
	font_size: i32,
}

// Default toggle: gray when off, teal when on; accent border when on.
DEFAULT_TOGGLE_STYLE :: ToggleStyle{
	bg_off       = rl.Color{45, 55, 70, 255},
	bg_off_hover = rl.Color{55, 68, 88, 255},
	bg_on        = rl.Color{70, 120, 130, 255},
	bg_on_hover  = rl.Color{90, 150, 160, 255},
	border_off   = BORDER_COLOR,
	border_on    = ACCENT_COLOR,
	text         = rl.RAYWHITE,
	font_size    = 11,
}

// Toggle style with red tint when on (e.g. Focal indicator).
TOGGLE_STYLE_ON_RED :: ToggleStyle{
	bg_off       = rl.Color{45, 55, 70, 255},
	bg_off_hover = rl.Color{55, 68, 88, 255},
	bg_on        = rl.Color{130, 70, 70, 255},
	bg_on_hover  = rl.Color{160, 90, 90, 255},
	border_off   = BORDER_COLOR,
	border_on    = ACCENT_COLOR,
	text         = rl.RAYWHITE,
	font_size    = 11,
}

Toggle :: struct {
	rect:  rl.Rectangle,
	label: cstring,
	value: bool,
	style: ToggleStyle,
}

// toggle_hover returns true if mouse is over the toggle rect.
toggle_hover :: proc(rect: rl.Rectangle, mouse: rl.Vector2) -> bool {
	return rl.CheckCollisionPointRec(mouse, rect)
}

// draw_toggle draws the toggle (on/off state) and returns whether it is hovered.
draw_toggle :: proc(app: ^App, t: Toggle, mouse: rl.Vector2) -> (hovered: bool) {
	hovered = toggle_hover(t.rect, mouse)
	bg: rl.Color
	border: rl.Color
	if t.value {
		bg     = hovered ? t.style.bg_on_hover : t.style.bg_on
		border = t.style.border_on
	} else {
		bg     = hovered ? t.style.bg_off_hover : t.style.bg_off
		border = t.style.border_off
	}
	rl.DrawRectangleRec(t.rect, bg)
	rl.DrawRectangleLinesEx(t.rect, 1, border)
	draw_ui_text(app, t.label, i32(t.rect.x) + 4, i32(t.rect.y) + 4, t.style.font_size, t.style.text)
	return hovered
}

// ─── Dropdown ────────────────────────────────────────────────────────────

DropdownItem :: struct {
	label: cstring,
}

// Default colors for dropdown panel and item hover.
DROPDOWN_PANEL_BG   :: rl.Color{50, 52, 70, 255}
DROPDOWN_ITEM_HOVER :: rl.Color{60, 65, 95, 255}

// dropdown_item_rect returns the rectangle for the i-th item (0-based). panel_rect is the full dropdown panel; item_height and gap are per-item.
dropdown_item_rect :: proc(panel_rect: rl.Rectangle, index: int, item_height, gap: f32) -> rl.Rectangle {
	y := panel_rect.y + f32(index) * (item_height + gap) + gap
	return rl.Rectangle{panel_rect.x, y, panel_rect.width, item_height}
}

// draw_dropdown_panel draws the dropdown panel background and border. Items are drawn by the caller (so they can use custom labels/icons).
draw_dropdown_panel :: proc(panel_rect: rl.Rectangle) {
	rl.DrawRectangleRec(panel_rect, DROPDOWN_PANEL_BG)
	rl.DrawRectangleLinesEx(panel_rect, 1, BORDER_COLOR)
}

// draw_dropdown_item draws one item (background if hovered, then label). Returns true if this item is hovered.
draw_dropdown_item :: proc(app: ^App, item_rect: rl.Rectangle, label: cstring, mouse: rl.Vector2) -> (hovered: bool) {
	hovered = rl.CheckCollisionPointRec(mouse, item_rect)
	if hovered {
		rl.DrawRectangleRec(item_rect, DROPDOWN_ITEM_HOVER)
	}
	draw_ui_text(app, label, i32(item_rect.x) + 8, i32(item_rect.y) + 4, 12, rl.RAYWHITE)
	return hovered
}

// dropdown_hit_item returns the 0-based index of the item under mouse, or -1.
dropdown_hit_item :: proc(panel_rect: rl.Rectangle, item_count: int, mouse: rl.Vector2, item_height, gap: f32) -> int {
	for i in 0 ..< item_count {
		r := dropdown_item_rect(panel_rect, i, item_height, gap)
		if rl.CheckCollisionPointRec(mouse, r) {
			return i
		}
	}
	return -1
}
