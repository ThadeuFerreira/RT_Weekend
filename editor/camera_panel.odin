package editor

import "core:fmt"
import rl "vendor:raylib"
import "RT_Weekend:core"

// CameraPanelState: camera panel drag state (which field is being dragged).
CameraPanelState :: struct {
	drag_idx:       int,   // 0..9: from_xyz, at_xyz, vfov, defocus, focus_dist, max_depth
	drag_start_x:   f32,
	drag_start_val: f32,
}

CAMERA_PANEL_LINE_H :: f32(24)
CAMERA_PROP_LW  :: f32(40)  // label width
CAMERA_PROP_GAP :: f32(4)
CAMERA_PROP_FW  :: f32(64)
CAMERA_PROP_FH  :: f32(18)

// camera_panel_field_rects returns 10 value-box rectangles for the camera panel content area.
// [0,1,2]=lookfrom xyz, [3,4,5]=lookat xyz, [6]=vfov, [7]=defocus, [8]=focus_dist, [9]=max_depth
camera_panel_field_rects :: proc(r: rl.Rectangle) -> [10]rl.Rectangle {
	x0 := r.x + 8
	y0 := r.y + 8
	off := CAMERA_PROP_LW + CAMERA_PROP_GAP
	row := CAMERA_PANEL_LINE_H
	return [10]rl.Rectangle{
		{x0 + off, y0 + 0*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // from x
		{x0 + off + 70, y0 + 0*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // from y
		{x0 + off + 140, y0 + 0*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // from z
		{x0 + off, y0 + 1*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // at x
		{x0 + off + 70, y0 + 1*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // at y
		{x0 + off + 140, y0 + 1*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // at z
		{x0 + off, y0 + 2*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // vfov
		{x0 + off + 70, y0 + 2*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // defocus
		{x0 + off + 140, y0 + 2*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // focus_dist
		{x0 + off, y0 + 3*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // max_depth
	}
}

draw_camera_panel_drag_field :: proc(app: ^App, label: cstring, value: f32, box: rl.Rectangle, active: bool, mouse: rl.Vector2) {
	hovered := rl.CheckCollisionPointRec(mouse, box)
	bg: rl.Color
	switch {
	case active:  bg = rl.Color{50, 90, 165, 255}
	case hovered: bg = rl.Color{55, 62, 88,  255}
	case:         bg = rl.Color{32, 35, 52,  255}
	}
	border := (active || hovered) ? ACCENT_COLOR : BORDER_COLOR
	rl.DrawRectangleRec(box, bg)
	rl.DrawRectangleLinesEx(box, 1, border)
	draw_ui_text(app, fmt.ctprintf("%.3f", value), i32(box.x) + 5, i32(box.y) + 2, 11, CONTENT_TEXT_COLOR)
	draw_ui_text(app, label, i32(box.x) - i32(CAMERA_PROP_LW + CAMERA_PROP_GAP) + 2, i32(box.y) + 2, 11, CONTENT_TEXT_COLOR)
}

draw_camera_panel_content :: proc(app: ^App, content: rl.Rectangle) {
	cp := &app.e_camera_panel
	p  := &app.c_camera_params
	mouse := rl.GetMousePosition()

	rl.DrawRectangleRec(content, rl.Color{25, 28, 40, 240})
	rl.DrawRectangleLinesEx(content, 1, BORDER_COLOR)

	x0 := content.x + 8
	y0 := content.y + 8
	row := CAMERA_PANEL_LINE_H
	fs := i32(11)

	draw_ui_text(app, "From", i32(x0), i32(y0 + 0*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "At",   i32(x0), i32(y0 + 1*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "FOV / Defocus / Focus", i32(x0), i32(y0 + 2*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Max depth", i32(x0), i32(y0 + 3*row), fs, CONTENT_TEXT_COLOR)

	fields := camera_panel_field_rects(content)
	draw_camera_panel_drag_field(app, "X", p.lookfrom[0], fields[0], cp.drag_idx == 0, mouse)
	draw_camera_panel_drag_field(app, "Y", p.lookfrom[1], fields[1], cp.drag_idx == 1, mouse)
	draw_camera_panel_drag_field(app, "Z", p.lookfrom[2], fields[2], cp.drag_idx == 2, mouse)
	draw_camera_panel_drag_field(app, "X", p.lookat[0], fields[3], cp.drag_idx == 3, mouse)
	draw_camera_panel_drag_field(app, "Y", p.lookat[1], fields[4], cp.drag_idx == 4, mouse)
	draw_camera_panel_drag_field(app, "Z", p.lookat[2], fields[5], cp.drag_idx == 5, mouse)
	draw_camera_panel_drag_field(app, "", p.vfov, fields[6], cp.drag_idx == 6, mouse)
	draw_camera_panel_drag_field(app, "", p.defocus_angle, fields[7], cp.drag_idx == 7, mouse)
	draw_camera_panel_drag_field(app, "", p.focus_dist, fields[8], cp.drag_idx == 8, mouse)
	draw_camera_panel_drag_field(app, "D", f32(p.max_depth), fields[9], cp.drag_idx == 9, mouse)

	draw_ui_text(app, "Edits apply to next render. Use Edit View Render to use orbit camera.", i32(x0), i32(y0 + 4*row + 4), 10, rl.Color{120, 130, 148, 180})
}

update_camera_panel_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	cp := &app.e_camera_panel
	p  := &app.c_camera_params
	content := rect

	if cp.drag_idx >= 0 {
		if !lmb {
			cp.drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else {
			delta := mouse.x - cp.drag_start_x
			switch cp.drag_idx {
			case 0: p.lookfrom[0] = cp.drag_start_val + delta * 0.02
			case 1: p.lookfrom[1] = cp.drag_start_val + delta * 0.02
			case 2: p.lookfrom[2] = cp.drag_start_val + delta * 0.02
			case 3: p.lookat[0] = cp.drag_start_val + delta * 0.02
			case 4: p.lookat[1] = cp.drag_start_val + delta * 0.02
			case 5: p.lookat[2] = cp.drag_start_val + delta * 0.02
			case 6:
				p.vfov = cp.drag_start_val + delta * 0.1
				if p.vfov < 1 { p.vfov = 1 }
				if p.vfov > 120 { p.vfov = 120 }
			case 7:
				p.defocus_angle = cp.drag_start_val + delta * 0.02
				if p.defocus_angle < 0 { p.defocus_angle = 0 }
			case 8:
				p.focus_dist = cp.drag_start_val + delta * 0.05
				if p.focus_dist < 0.1 { p.focus_dist = 0.1 }
			case 9:
				p.max_depth = int(cp.drag_start_val + delta * 0.5)
				if p.max_depth < 1 { p.max_depth = 1 }
				if p.max_depth > 100 { p.max_depth = 100 }
			}
		}
		return
	}

	if lmb_pressed {
		fields := camera_panel_field_rects(content)
		for i in 0..<10 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) {
				cp.drag_idx = i
				cp.drag_start_x = mouse.x
				switch i {
				case 0: cp.drag_start_val = p.lookfrom[0]
				case 1: cp.drag_start_val = p.lookfrom[1]
				case 2: cp.drag_start_val = p.lookfrom[2]
				case 3: cp.drag_start_val = p.lookat[0]
				case 4: cp.drag_start_val = p.lookat[1]
				case 5: cp.drag_start_val = p.lookat[2]
				case 6: cp.drag_start_val = p.vfov
				case 7: cp.drag_start_val = p.defocus_angle
				case 8: cp.drag_start_val = p.focus_dist
				case 9: cp.drag_start_val = f32(p.max_depth)
				}
				rl.SetMouseCursor(.CROSSHAIR)
				if g_app != nil { g_app.input_consumed = true }
				return
			}
		}
	}
}
