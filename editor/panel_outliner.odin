package editor

import rl "vendor:raylib"

OUTLINER_ROW_H :: f32(22)

OutlinerPanelState :: struct {
	scroll_y: f32,
}

update_outliner_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev := &app.e_edit_view
	st := &app.e_outliner
	sm := ev.scene_mgr
	vol_count := len(app.e_volumes)
	total_h   := f32(outliner_total_rows(sm, vol_count)) * OUTLINER_ROW_H

	// Scroll: handle wheel in update so input is not tied to draw order.
	if rl.CheckCollisionPointRec(mouse, rect) {
		wheel := vk_get_wheel_delta()
		if wheel != 0 {
			st.scroll_y = outliner_scroll_after_wheel(st.scroll_y, f32(wheel), total_h, rect.height, OUTLINER_ROW_H)
		}
	}

	if !lmb_pressed { return }
	if !rl.CheckCollisionPointRec(mouse, rect) { return }

	local_y := mouse.y - rect.y + st.scroll_y
	row     := int(local_y / OUTLINER_ROW_H)

	kind, idx, ok := outliner_row_to_selection(sm, vol_count, row)
	if ok {
		set_selection(ev, kind, idx)
	}
}
