package editor

import rl "vendor:raylib"

CTX_MENU_W :: f32(280)

// ctx_menu_build_items returns a temp-allocated slice of menu entries for the context menu.
@(private="package") ctx_menu_build_items :: proc(app: ^App, ev: ^EditViewState) -> []MenuEntryDyn {
	items := make([dynamic]MenuEntryDyn, context.temp_allocator)
	append(&items, MenuEntryDyn{label = "Add Sphere"})
	append(&items, MenuEntryDyn{label = "Add Quad"})
	append(&items, MenuEntryDyn{label = "Add Volume"})
	append(&items, MenuEntryDyn{separator = true})
	append(&items, MenuEntryDyn{label = "Align editor camera to render camera", cmd_id = CMD_EDIT_VIEW_ALIGN_CAMERA})
	append(&items, MenuEntryDyn{label = "Frame all geometry (horizontal)", cmd_id = CMD_EDIT_VIEW_FRAME_GEOMETRY})
	append(&items, MenuEntryDyn{
		label   = ev.camera_mode == .FreeFly ? "Switch to orbit mode" : "Switch to free-fly mode",
		cmd_id  = CMD_EDIT_VIEW_CAMERA_MODE,
		checked = ev.camera_mode == .FreeFly,
		shortcut = "F",
	})
	append(&items, MenuEntryDyn{label = "Lock X axis", cmd_id = CMD_EDIT_VIEW_LOCK_AXIS_X, checked = ev.lock_axis_x})
	append(&items, MenuEntryDyn{label = "Lock Y axis", cmd_id = CMD_EDIT_VIEW_LOCK_AXIS_Y, checked = ev.lock_axis_y})
	append(&items, MenuEntryDyn{label = "Lock Z axis", cmd_id = CMD_EDIT_VIEW_LOCK_AXIS_Z, checked = ev.lock_axis_z})
	append(&items, MenuEntryDyn{label = "Grid visible", cmd_id = CMD_EDIT_VIEW_GRID_VISIBLE, checked = ev.grid_visible})
	append(&items, MenuEntryDyn{label = "Grid density +", cmd_id = CMD_EDIT_VIEW_GRID_DENSITY_PLUS})
	append(&items, MenuEntryDyn{label = "Grid density -", cmd_id = CMD_EDIT_VIEW_GRID_DENSITY_MINUS})
	append(&items, MenuEntryDyn{label = "Movement speed: Slow", cmd_id = CMD_EDIT_VIEW_SPEED_SLOW})
	append(&items, MenuEntryDyn{label = "Movement speed: Medium", cmd_id = CMD_EDIT_VIEW_SPEED_MEDIUM})
	append(&items, MenuEntryDyn{label = "Movement speed: Fast", cmd_id = CMD_EDIT_VIEW_SPEED_FAST})
	append(&items, MenuEntryDyn{label = "Movement speed: Very fast", cmd_id = CMD_EDIT_VIEW_SPEED_VERY_FAST})
	append(&items, MenuEntryDyn{separator = true})
	has_deletable := ev.ctx_menu_hit_idx >= 0 || (ev.selection_kind == .Volume && ev.selected_idx >= 0)
	if has_deletable {
		if ev.ctx_menu_hit_idx >= 0 {
			append(&items, MenuEntryDyn{label = "Copy",      cmd_id = CMD_EDIT_COPY,      disabled = !cmd_is_enabled(app, CMD_EDIT_COPY),      shortcut = "Ctrl+C"})
			append(&items, MenuEntryDyn{label = "Duplicate", cmd_id = CMD_EDIT_DUPLICATE, disabled = !cmd_is_enabled(app, CMD_EDIT_DUPLICATE), shortcut = "Ctrl+D"})
			append(&items, MenuEntryDyn{label = "Paste",     cmd_id = CMD_EDIT_PASTE,     disabled = !cmd_is_enabled(app, CMD_EDIT_PASTE),     shortcut = "Ctrl+V"})
		}
		append(&items, MenuEntryDyn{separator = true})
		append(&items, MenuEntryDyn{label = "Delete"})
	} else {
		append(&items, MenuEntryDyn{separator = true})
		append(&items, MenuEntryDyn{label = "Paste", cmd_id = CMD_EDIT_PASTE, disabled = !cmd_is_enabled(app, CMD_EDIT_PASTE), shortcut = "Ctrl+V"})
	}
	return items[:]
}

// ctx_menu_screen_rect returns the screen-clamped bounding rectangle for the open context menu.
@(private="package") ctx_menu_screen_rect :: proc(app: ^App, ev: ^EditViewState) -> rl.Rectangle {
	items := ctx_menu_build_items(app, ev)
	h     := entry_list_height(items)
	sw    := f32(rl.GetScreenWidth())
	sh    := f32(rl.GetScreenHeight())
	x := ev.ctx_menu_pos.x
	y := ev.ctx_menu_pos.y
	if x + CTX_MENU_W > sw { x = sw - CTX_MENU_W }
	if y + h > sh           { y = sh - h           }
	if x < 0               { x = 0                }
	if y < 0               { y = 0                }
	return rl.Rectangle{x, y, CTX_MENU_W, h}
}

// draw_edit_view_context_menu draws the right-click context menu on top of everything.
@(private="package") draw_edit_view_context_menu :: proc(app: ^App, ev: ^EditViewState) {
	items := ctx_menu_build_items(app, ev)
	rect  := ctx_menu_screen_rect(app, ev)
	mouse := rl.GetMousePosition()

	rl.DrawRectangleRec(rect, PANEL_BG_COLOR)
	rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)

	ey: f32 = 0
	for &entry in items {
		ih := entry_height(entry)
		ry := rect.y + ey

		if entry.separator {
			sep_y := i32(ry + ih * 0.5)
			rl.DrawRectangle(i32(rect.x) + 4, sep_y, i32(rect.width) - 8, 1, BORDER_COLOR)
			ey += ih
			continue
		}

		item_rect := rl.Rectangle{rect.x, ry, CTX_MENU_W, ih}
		item_hov  := rl.CheckCollisionPointRec(mouse, item_rect)
		text_col  := CONTENT_TEXT_COLOR
		if entry.disabled {
			text_col = rl.Color{100, 105, 120, 180}
		} else if item_hov {
			rl.DrawRectangleRec(item_rect, rl.Color{60, 65, 95, 255})
		}

		label_x := i32(rect.x) + 8
		if entry.checked {
			draw_ui_text(app, "\u2713", label_x, i32(ry) + 3, 13, text_col)
			label_x += 14
		}
		label_c := make_cstring_temp(entry.label)
		draw_ui_text(app, label_c, label_x, i32(ry) + 3, 13, text_col)

		if len(entry.shortcut) > 0 {
			sc_c := make_cstring_temp(entry.shortcut)
			sc_w := measure_ui_text(app, sc_c, 11).width
			sc_x := i32(rect.x + CTX_MENU_W) - sc_w - 6
			draw_ui_text(app, sc_c, sc_x, i32(ry) + 5, 11, rl.Color{140, 150, 170, 200})
		}

		ey += ih
	}
}
