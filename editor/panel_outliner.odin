package editor

import rl "vendor:raylib"

OUTLINER_ROW_H :: f32(22)

OutlinerPanelState :: struct {
	scroll_y:  f32,
	row_table: [dynamic]OutlinerRowEntry,
}

draw_outliner_content :: proc(app: ^App, content: rl.Rectangle) {
	ev    := &app.e_edit_view
	st    := &app.e_outliner
	mouse := rl.GetMousePosition()
	sm    := ev.scene_mgr
	vol_count := len(app.e_volumes)

	total_rows := outliner_total_rows(sm, vol_count)
	total_h    := f32(total_rows) * OUTLINER_ROW_H
	visible_h  := content.height
	st.scroll_y = outliner_scroll_clamped(st.scroll_y, total_h, visible_h)

	outliner_fill_row_table(sm, vol_count, &st.row_table)

	rl.BeginScissorMode(i32(content.x), i32(content.y), i32(content.width), i32(content.height))
	defer rl.EndScissorMode()

	for row in 0 ..< total_rows {
		entry := st.row_table[row]
		kind, idx := entry.kind, entry.idx
		ry := content.y + f32(row) * OUTLINER_ROW_H - st.scroll_y
		visible := ry + OUTLINER_ROW_H >= content.y && ry <= content.y + content.height
		if !visible { continue }
		row_rect := rl.Rectangle{content.x, ry, content.width, OUTLINER_ROW_H}
		is_sel   := ev.selection_kind == kind && ev.selected_idx == idx
		if is_sel {
			rl.DrawRectangleRec(row_rect, rl.Color{60, 100, 160, 200})
		} else if rl.CheckCollisionPointRec(mouse, row_rect) {
			rl.DrawRectangleRec(row_rect, rl.Color{50, 55, 75, 180})
		}
		label := outliner_row_label(kind, idx)
		draw_ui_text(app, label, i32(content.x) + 8, i32(ry) + 4, 12, CONTENT_TEXT_COLOR)
	}

	if total_rows == 0 {
		draw_ui_text(app, "No objects in scene", i32(content.x) + 8, i32(content.y) + 10, 12, rl.Color{140, 150, 170, 180})
	}
}

update_outliner_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev := &app.e_edit_view
	st := &app.e_outliner
	sm := ev.scene_mgr
	vol_count := len(app.e_volumes)
	total_rows := outliner_total_rows(sm, vol_count)
	total_h    := f32(total_rows) * OUTLINER_ROW_H
	visible_h  := rect.height

	// Scroll: handle wheel in update so input is not tied to draw order.
	if rl.CheckCollisionPointRec(mouse, rect) {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			st.scroll_y = outliner_scroll_after_wheel(st.scroll_y, f32(wheel), total_h, visible_h, OUTLINER_ROW_H)
		}
	}

	if !lmb_pressed { return }
	if !rl.CheckCollisionPointRec(mouse, rect) { return }

	local_y := mouse.y - rect.y + st.scroll_y
	row     := int(local_y / OUTLINER_ROW_H)

	kind, idx, ok := outliner_row_to_selection(sm, vol_count, row)
	if ok {
		ev.selection_kind = kind
		ev.selected_idx   = idx
	}
}
