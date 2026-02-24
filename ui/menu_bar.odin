package ui

import "core:strings"
import rl "vendor:raylib"

// Height of the top menu bar strip. Panels can be drawn below this; menu is drawn last so it stays on top.
MENU_BAR_HEIGHT :: f32(24)

MENU_ITEM_HEIGHT :: f32(22)
MENU_PADDING     :: 8
DROP_SHADOW      :: 2

// MenuBarState holds which dropdown (if any) is open. open_menu_index -1 = none.
MenuBarState :: struct {
	open_menu_index: int,
}

// MenuEntry is a single item in a dropdown. action nil = stub (no-op or log only).
MenuEntry :: struct {
	label:  cstring,
	action: proc(app: ^App),
}

// Menu is a top-level item (e.g. "File") with its dropdown entries.
Menu :: struct {
	title:  cstring,
	entries: []MenuEntry,
}

// --- Stub actions (to be implemented later) ---

menu_action_file_new :: proc(app: ^App) {
	app_push_log(app, strings.clone("File → New (not implemented)"))
}

menu_action_import :: proc(app: ^App) {
	app_push_log(app, strings.clone("File → Import (not implemented)"))
}

menu_action_exit :: proc(app: ^App) {
	app_push_log(app, strings.clone("File → Exit (not implemented)"))
}

menu_action_restart :: proc(app: ^App) {
	// TODO: implement — e.g. call app_restart_render with current or new scene
	app_push_log(app, strings.clone("Render → Restart (not implemented)"))
}

// Package-level menu data so get_menus() returns a slice of static memory (no dangling refs).
g_file_entries: [3]MenuEntry = {
	{"New",    menu_action_file_new},
	{"Import", menu_action_import},
	{"Exit",   menu_action_exit},
}
g_render_entries: [1]MenuEntry = {
	{"Restart", menu_action_restart},
}
g_menus: [2]Menu = {
	{"File",   g_file_entries[:]},
	{"Render", g_render_entries[:]},
}

// get_menus returns the static menu definition. Caller does not own the slice.
get_menus :: proc() -> []Menu {
	return g_menus[:]
}

// menu_bar_update handles click to open/close dropdowns and to invoke actions. Call before drawing.
menu_bar_update :: proc(app: ^App, state: ^MenuBarState, mouse: rl.Vector2, lmb_pressed: bool) {
	if app == nil || state == nil { return }
	menus := get_menus()
	sw := f32(rl.GetScreenWidth())
	bar_rect := rl.Rectangle{0, 0, sw, MENU_BAR_HEIGHT}

	if lmb_pressed {
		// Check if click is inside open dropdown first
		if state.open_menu_index >= 0 && state.open_menu_index < len(menus) {
			menu := &menus[state.open_menu_index]
			item_w := f32(120)
			px: f32 = MENU_PADDING
			for k in 0..<state.open_menu_index {
				px += f32(rl.MeasureText(menus[k].title, 14)) + MENU_PADDING * 2
			}
			dropdown_rect := rl.Rectangle{
				px,
				MENU_BAR_HEIGHT + DROP_SHADOW,
				item_w,
				f32(len(menu.entries)) * MENU_ITEM_HEIGHT,
			}
			if rl.CheckCollisionPointRec(mouse, dropdown_rect) {
				// Click on an entry
				local_y := mouse.y - dropdown_rect.y
				idx := i32(local_y / MENU_ITEM_HEIGHT)
				if idx >= 0 && idx < i32(len(menu.entries)) {
					entry := &menu.entries[idx]
					if entry.action != nil {
						entry.action(app)
					}
				}
				state.open_menu_index = -1
				return
			}
		}

		// Check top-level menu items
		x: f32 = MENU_PADDING
		for i in 0..<len(menus) {
			menu := &menus[i]
			w := f32(rl.MeasureText(menu.title, 14)) + MENU_PADDING * 2
			item_rect := rl.Rectangle{x, 0, w, MENU_BAR_HEIGHT}
			if rl.CheckCollisionPointRec(mouse, item_rect) {
				if state.open_menu_index == i {
					state.open_menu_index = -1
				} else {
					state.open_menu_index = i
				}
				return
			}
			x += w
		}

		// Click outside: close dropdown
		if state.open_menu_index >= 0 {
			state.open_menu_index = -1
		}
	}
}

// menu_bar_draw draws the bar and the open dropdown. Call after panels so the bar stays on top.
menu_bar_draw :: proc(app: ^App, state: ^MenuBarState) {
	if app == nil || state == nil { return }
	menus := get_menus()
	sw := f32(rl.GetScreenWidth())

	// Bar background
	bar_rect := rl.Rectangle{0, 0, sw, MENU_BAR_HEIGHT}
	rl.DrawRectangleRec(bar_rect, TITLE_BG_COLOR)
	rl.DrawRectangle(0, i32(MENU_BAR_HEIGHT), i32(sw), 1, BORDER_COLOR)

	// Top-level labels
	x: f32 = MENU_PADDING
	for i in 0..<len(menus) {
		menu := &menus[i]
		rl.DrawText(menu.title, i32(x) + MENU_PADDING, 5, 14, TITLE_TEXT_COLOR)
		x += f32(rl.MeasureText(menu.title, 14)) + MENU_PADDING * 2
	}

	// Open dropdown
	if state.open_menu_index >= 0 && state.open_menu_index < len(menus) {
		menu := &menus[state.open_menu_index]
		item_w := f32(120)
		dropdown_h := f32(len(menu.entries)) * MENU_ITEM_HEIGHT
		px: f32 = MENU_PADDING
		for k in 0..<state.open_menu_index {
			px += f32(rl.MeasureText(menus[k].title, 14)) + MENU_PADDING * 2
		}
		dropdown_rect := rl.Rectangle{px, MENU_BAR_HEIGHT + DROP_SHADOW, item_w, dropdown_h}
		rl.DrawRectangleRec(dropdown_rect, PANEL_BG_COLOR)
		rl.DrawRectangleLinesEx(dropdown_rect, 1, BORDER_COLOR)
		for j in 0..<len(menu.entries) {
			entry := &menu.entries[j]
			ry := dropdown_rect.y + f32(j) * MENU_ITEM_HEIGHT
			rl.DrawText(entry.label, i32(dropdown_rect.x) + 6, i32(ry) + 3, 13, CONTENT_TEXT_COLOR)
		}
	}
}
