package editor

import "core:fmt"
import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

// CameraPanelState: camera panel drag state (which field is being dragged).
CameraPanelState :: struct {
	drag_idx:       int,   // 0..14: from_xyz, at_xyz, vfov, defocus, focus_dist, max_depth, shutter_open/close, background_rgb
	drag_start_x:   f32,
	drag_start_val: f32,
	bg_picker_open: bool,
	bg_drag_idx:    int, // -1=none, 0=R,1=G,2=B
	bg_drag_start_x: f32,
	bg_drag_start_val: f32,

	// ImGui Track B: capture one undo entry per edit gesture.
	imgui_drag_before: core.CameraParams,
	imgui_drag_active: bool,
}

CAMERA_PANEL_LINE_H :: f32(24)
CAMERA_PROP_LW  :: f32(40)  // label width
CAMERA_PROP_GAP :: f32(4)
CAMERA_PROP_FW  :: f32(64)
CAMERA_PROP_FH  :: f32(18)

// camera_panel_field_rects returns 15 value-box rectangles for the camera panel content area.
// [0,1,2]=lookfrom xyz, [3,4,5]=lookat xyz, [6]=vfov, [7]=defocus, [8]=focus_dist, [9]=max_depth, [10,11]=shutter_open/close, [12,13,14]=background rgb
camera_panel_field_rects :: proc(r: rl.Rectangle) -> [15]rl.Rectangle {
	x0 := r.x + 8
	y0 := r.y + 8
	off := CAMERA_PROP_LW + CAMERA_PROP_GAP + 25
	row := CAMERA_PANEL_LINE_H
	return [15]rl.Rectangle{
		{x0 + off, y0 + 0*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // from x
		{x0 + off + 70, y0 + 0*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // from y
		{x0 + off + 140, y0 + 0*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // from z
		{x0 + off, y0 + 1*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // at x
		{x0 + off + 70, y0 + 1*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // at y
		{x0 + off + 140, y0 + 1*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // at z
		{x0 + off, y0 + 2*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // vfov
		{x0 + off, y0 + 3*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // defocus
		{x0 + off, y0 + 4*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // focus_dist
		{x0 + off, y0 + 5*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // max_depth
		{x0 + off, y0 + 6*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // shutter_open
		{x0 + off + 70, y0 + 6*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // shutter_close
		{x0 + off, y0 + 7*row,      CAMERA_PROP_FW, CAMERA_PROP_FH}, // bg r
		{x0 + off + 70, y0 + 7*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // bg g
		{x0 + off + 140, y0 + 7*row, CAMERA_PROP_FW, CAMERA_PROP_FH}, // bg b
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
	e_cam    := &app.e_camera_panel
	c_params := &app.c_camera_params
	mouse := rl.GetMousePosition()

	rl.DrawRectangleRec(content, rl.Color{25, 28, 40, 240})
	rl.DrawRectangleLinesEx(content, 1, BORDER_COLOR)

	x0 := content.x + 8
	y0 := content.y + 8
	row := CAMERA_PANEL_LINE_H
	fs := i32(11)

	draw_ui_text(app, "From", i32(x0), i32(y0 + 0*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "At",   i32(x0), i32(y0 + 1*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "FOV", i32(x0), i32(y0 + 2*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Defocus", i32(x0), i32(y0 + 3*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Focus dist", i32(x0), i32(y0 + 4*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Max depth", i32(x0), i32(y0 + 5*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Shutter", i32(x0), i32(y0 + 6*row), fs, CONTENT_TEXT_COLOR)
	draw_ui_text(app, "Background", i32(x0), i32(y0 + 7*row), fs, CONTENT_TEXT_COLOR)

	fields := camera_panel_field_rects(content)
	draw_camera_panel_drag_field(app, "X", c_params.lookfrom[0], fields[0], e_cam.drag_idx == 0, mouse)
	draw_camera_panel_drag_field(app, "Y", c_params.lookfrom[1], fields[1], e_cam.drag_idx == 1, mouse)
	draw_camera_panel_drag_field(app, "Z", c_params.lookfrom[2], fields[2], e_cam.drag_idx == 2, mouse)
	draw_camera_panel_drag_field(app, "X", c_params.lookat[0], fields[3], e_cam.drag_idx == 3, mouse)
	draw_camera_panel_drag_field(app, "Y", c_params.lookat[1], fields[4], e_cam.drag_idx == 4, mouse)
	draw_camera_panel_drag_field(app, "Z", c_params.lookat[2], fields[5], e_cam.drag_idx == 5, mouse)
	draw_camera_panel_drag_field(app, "", c_params.vfov, fields[6], e_cam.drag_idx == 6, mouse)
	draw_camera_panel_drag_field(app, "", c_params.defocus_angle, fields[7], e_cam.drag_idx == 7, mouse)
	draw_camera_panel_drag_field(app, "", c_params.focus_dist, fields[8], e_cam.drag_idx == 8, mouse)
	draw_camera_panel_drag_field(app, "D", f32(c_params.max_depth), fields[9], e_cam.drag_idx == 9, mouse)
	draw_camera_panel_drag_field(app, "Op", c_params.shutter_open, fields[10], e_cam.drag_idx == 10, mouse)
	draw_camera_panel_drag_field(app, "Cl", c_params.shutter_close, fields[11], e_cam.drag_idx == 11, mouse)
	draw_camera_panel_drag_field(app, "R", c_params.background[0], fields[12], e_cam.drag_idx == 12, mouse)
	draw_camera_panel_drag_field(app, "G", c_params.background[1], fields[13], e_cam.drag_idx == 13, mouse)
	draw_camera_panel_drag_field(app, "B", c_params.background[2], fields[14], e_cam.drag_idx == 14, mouse)

	draw_ui_text(app, "Edits apply to next render. Use Viewport Render to use orbit camera.", i32(x0), i32(y0 + 8*row + 4), 10, rl.Color{120, 130, 148, 180})
}

update_camera_panel_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	e_cam    := &app.e_camera_panel
	c_params := &app.c_camera_params
	content := rect

	if e_cam.drag_idx >= 0 {
		if !lmb {
			e_cam.drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else {
			delta := mouse.x - e_cam.drag_start_x
			switch e_cam.drag_idx {
			case 0: c_params.lookfrom[0] = e_cam.drag_start_val + delta * 0.02
			case 1: c_params.lookfrom[1] = e_cam.drag_start_val + delta * 0.02
			case 2: c_params.lookfrom[2] = e_cam.drag_start_val + delta * 0.02
			case 3: c_params.lookat[0] = e_cam.drag_start_val + delta * 0.02
			case 4: c_params.lookat[1] = e_cam.drag_start_val + delta * 0.02
			case 5: c_params.lookat[2] = e_cam.drag_start_val + delta * 0.02
			case 6:
				c_params.vfov = e_cam.drag_start_val + delta * 0.1
				if c_params.vfov < 1 { c_params.vfov = 1 }
				if c_params.vfov > 120 { c_params.vfov = 120 }
			case 7:
				c_params.defocus_angle = e_cam.drag_start_val + delta * 0.02
				if c_params.defocus_angle < 0 { c_params.defocus_angle = 0 }
			case 8:
				c_params.focus_dist = e_cam.drag_start_val + delta * 0.05
				if c_params.focus_dist < 0.1 { c_params.focus_dist = 0.1 }
			case 9:
				c_params.max_depth = int(e_cam.drag_start_val + delta * 0.5)
				if c_params.max_depth < 1 { c_params.max_depth = 1 }
				if c_params.max_depth > 100 { c_params.max_depth = 100 }
			case 10:
				c_params.shutter_open = e_cam.drag_start_val + delta * 0.005
				if c_params.shutter_open < 0 { c_params.shutter_open = 0 }
				if c_params.shutter_open > 1 { c_params.shutter_open = 1 }
				if c_params.shutter_open > c_params.shutter_close { c_params.shutter_close = c_params.shutter_open }
			case 11:
				c_params.shutter_close = e_cam.drag_start_val + delta * 0.005
				if c_params.shutter_close < 0 { c_params.shutter_close = 0 }
				if c_params.shutter_close > 1 { c_params.shutter_close = 1 }
				if c_params.shutter_close < c_params.shutter_open { c_params.shutter_open = c_params.shutter_close }
			case 12:
				c_params.background[0] = clamp(e_cam.drag_start_val + delta * 0.002, f32(0), f32(1))
				mark_scene_dirty(app)
			case 13:
				c_params.background[1] = clamp(e_cam.drag_start_val + delta * 0.002, f32(0), f32(1))
				mark_scene_dirty(app)
			case 14:
				c_params.background[2] = clamp(e_cam.drag_start_val + delta * 0.002, f32(0), f32(1))
				mark_scene_dirty(app)
			}
		}
		return
	}

	if lmb_pressed {
		fields := camera_panel_field_rects(content)
		for i in 0..<15 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) {
				e_cam.drag_idx = i
				e_cam.drag_start_x = mouse.x
				switch i {
				case 0: e_cam.drag_start_val = c_params.lookfrom[0]
				case 1: e_cam.drag_start_val = c_params.lookfrom[1]
				case 2: e_cam.drag_start_val = c_params.lookfrom[2]
				case 3: e_cam.drag_start_val = c_params.lookat[0]
				case 4: e_cam.drag_start_val = c_params.lookat[1]
				case 5: e_cam.drag_start_val = c_params.lookat[2]
				case 6: e_cam.drag_start_val = c_params.vfov
				case 7: e_cam.drag_start_val = c_params.defocus_angle
				case 8: e_cam.drag_start_val = c_params.focus_dist
				case 9: e_cam.drag_start_val = f32(c_params.max_depth)
				case 10: e_cam.drag_start_val = c_params.shutter_open
				case 11: e_cam.drag_start_val = c_params.shutter_close
				case 12: e_cam.drag_start_val = c_params.background[0]
				case 13: e_cam.drag_start_val = c_params.background[1]
				case 14: e_cam.drag_start_val = c_params.background[2]
				}
				rl.SetMouseCursor(.CROSSHAIR)
				if g_app != nil { g_app.input_consumed = true }
				return
			}
		}
	}
}

// ─── ImGui Camera Panel Helpers ────────────────────────────────────────────────
// These are package-level private procs used by imgui_draw_camera_panel in
// imgui_panels_stub.odin. Placed here to match editor package conventions.

@(private)
_camera_panel_commit_undo_if_needed :: proc(app: ^App) {
	st := &app.e_camera_panel
	if st.imgui_drag_active && imgui.IsItemDeactivatedAfterEdit() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{
			before = st.imgui_drag_before,
			after  = app.c_camera_params,
		})
		mark_scene_dirty(app)
		st.imgui_drag_active = false
	}
}

@(private)
_camera_panel_begin_undo_if_needed :: proc(app: ^App) {
	st := &app.e_camera_panel
	if imgui.IsItemActivated() {
		st.imgui_drag_before = app.c_camera_params
		st.imgui_drag_active = true
	}
}

@(private)
_camera_panel_clamp_shutter :: proc(params: ^core.CameraParams) {
	params.shutter_open  = clamp(params.shutter_open,  f32(0), f32(1))
	params.shutter_close = clamp(params.shutter_close, f32(0), f32(1))
	if params.shutter_open > params.shutter_close {
		params.shutter_close = params.shutter_open
	}
}
