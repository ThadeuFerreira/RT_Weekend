package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import "RT_Weekend:core"
import "RT_Weekend:util"
import rt "RT_Weekend:raytrace"

// Layout constants for the Object Properties panel.
// Separate from PROP_* in edit_view_panel.odin to fit a narrower panel.
OP_LW  :: f32(12)                          // label width  (1–2 chars at fs=11)
OP_GAP :: f32(2)                           // gap between label and field box
OP_FW  :: f32(50)                          // field box width
OP_FH  :: f32(18)                          // field box height
OP_SP  :: f32(4)                           // spacing after a field group
OP_COL :: OP_LW + OP_GAP + OP_FW + OP_SP  // = 68 px per column

// ObjectPropsPanelState holds per-frame drag state for the Object Properties panel.
// For sphere: data in app.e_edit_view.objects[selected_idx]. For camera: app.c_camera_params.
// Drag indices: sphere 0–10 (xyz, radius, motion dX dY dZ, rgb, mat_param); camera 0–11 (from xyz, at xyz, vfov, defocus, focus, max_depth, shutter).
ObjectPropsPanelState :: struct {
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Before-state captured at drag start (for undo history)
	drag_before_sphere: core.SceneSphere,
	drag_before_c_camera_params: core.CameraParams,
}

// OpLayout holds every interactive rectangle for a single frame, computed once
// by op_compute_layout and consumed by both the draw and update procs.
OpLayout :: struct {
	lx, x0:        f32,           // left edge for labels/buttons; left edge for field boxes
	y_transform:   f32,           // y of TRANSFORM section header
	y_motion:      f32,           // y of MOTION section header (dX dY dZ)
	y_material:    f32,           // y of MATERIAL section header
	y_color:       f32,           // y of COLOR section header
	boxes_xyz:     [3]rl.Rectangle,
	box_radius:    rl.Rectangle,
	boxes_motion:  [3]rl.Rectangle, // dX dY dZ (center1 - center)
	mat_rects:     [3]rl.Rectangle,
	has_mat_param: bool,
	box_mat_param: rl.Rectangle,   // fuzz (metallic) or IOR (dielectric)
	// COLOR section (constant texture):
	boxes_rgb:     [3]rl.Rectangle,
	swatch:        rl.Rectangle,
	// IMAGE TEXTURE section (Lambertian only):
	btn_browse:    rl.Rectangle,   // "Browse…" button (full-width when no image; left half when image set)
	btn_clear:     rl.Rectangle,   // "×" clear button (right of browse; only shown when image set)
	has_image:     bool,           // true when current sphere has ImageTexture albedo
}

// Sphere drag index assignments (prop_drag_idx): 0–3 = TRANSFORM (xyz, radius), 8–10 = MOTION (dX dY dZ), 4–6 = COLOR (rgb), 7 = MATERIAL param (fuzz/ior). Layout order in UI is TRANSFORM → MOTION → MATERIAL → COLOR.
op_compute_layout :: proc(content: rl.Rectangle, mat_kind: core.MaterialKind, albedo: core.Texture = nil) -> OpLayout {
	lo: OpLayout
	lo.lx = content.x + 8
	lo.x0 = lo.lx + OP_LW + OP_GAP

	cy := content.y + 6

	// TRANSFORM
	lo.y_transform = cy
	cy += 18

	lo.boxes_xyz = [3]rl.Rectangle{
		{lo.x0,             cy, OP_FW, OP_FH},
		{lo.x0 + OP_COL,   cy, OP_FW, OP_FH},
		{lo.x0 + 2*OP_COL, cy, OP_FW, OP_FH},
	}
	cy += OP_FH + 6

	lo.box_radius = rl.Rectangle{lo.x0, cy, OP_FW, OP_FH}
	cy += OP_FH + 6

	// MOTION (dX dY dZ = center1 - center)
	lo.y_motion = cy
	cy += 18
	lo.boxes_motion = [3]rl.Rectangle{
		{lo.x0,             cy, OP_FW, OP_FH},
		{lo.x0 + OP_COL,   cy, OP_FW, OP_FH},
		{lo.x0 + 2*OP_COL, cy, OP_FW, OP_FH},
	}
	cy += OP_FH + 10

	// MATERIAL
	lo.y_material = cy
	cy += 18

	bw := (content.width - 16) / 3.0 - 2
	lo.mat_rects = [3]rl.Rectangle{
		{lo.lx,             cy, bw, 22},
		{lo.lx + bw + 2,   cy, bw, 22},
		{lo.lx + 2*(bw+2), cy, bw, 22},
	}
	cy += 28

	lo.has_mat_param  = mat_kind != .Lambertian
	lo.box_mat_param  = rl.Rectangle{lo.x0, cy, OP_FW, OP_FH}
	if lo.has_mat_param { cy += OP_FH + 6 }
	cy += 4

	// COLOR / IMAGE TEXTURE
	lo.y_color = cy
	cy += 18

	_, lo.has_image = albedo.(core.ImageTexture)

	if !lo.has_image {
		// Constant/Checker: show RGB drag fields + swatch
		lo.boxes_rgb = [3]rl.Rectangle{
			{lo.x0,             cy, OP_FW, OP_FH},
			{lo.x0 + OP_COL,   cy, OP_FW, OP_FH},
			{lo.x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		cy += OP_FH + 6
		lo.swatch = rl.Rectangle{lo.lx, cy, 42, 30}
		cy += 34
	}

	// Browse / Clear buttons (always shown for Lambertian)
	if mat_kind == .Lambertian {
		content_w := content.width - 16
		if lo.has_image {
			// [Browse…] | [×]
			browse_w := content_w - 26
			lo.btn_browse = rl.Rectangle{lo.lx, cy, browse_w, 22}
			lo.btn_clear  = rl.Rectangle{lo.lx + browse_w + 4, cy, 20, 22}
		} else {
			// [Browse Image…] full width
			lo.btn_browse = rl.Rectangle{lo.lx, cy, content_w, 22}
		}
	}

	return lo
}

// Camera layout in Object Properties: same 12 fields as camera panel (incl. shutter open/close), using OP_* for consistency.
OP_CAM_ROW :: f32(20)
op_camera_field_rects :: proc(content: rl.Rectangle) -> [12]rl.Rectangle {
	x0 := content.x + 8
	y0 := content.y + 6
	off := OP_LW + OP_GAP
	row := OP_CAM_ROW
	return [12]rl.Rectangle{
		{x0 + off,             y0 + 0*row, OP_FW, OP_FH},
		{x0 + off + OP_COL,   y0 + 0*row, OP_FW, OP_FH},
		{x0 + off + 2*OP_COL, y0 + 0*row, OP_FW, OP_FH},
		{x0 + off,             y0 + 1*row, OP_FW, OP_FH},
		{x0 + off + OP_COL,   y0 + 1*row, OP_FW, OP_FH},
		{x0 + off + 2*OP_COL, y0 + 1*row, OP_FW, OP_FH},
		{x0 + off,             y0 + 2*row, OP_FW, OP_FH},
		{x0 + off + OP_COL,   y0 + 2*row, OP_FW, OP_FH},
		{x0 + off + 2*OP_COL, y0 + 2*row, OP_FW, OP_FH},
		{x0 + off,             y0 + 3*row, OP_FW, OP_FH},
		{x0 + off + OP_COL,   y0 + 3*row, OP_FW, OP_FH},
		{x0 + off + 2*OP_COL, y0 + 3*row, OP_FW, OP_FH},
	}
}

// ── visual helpers 

op_section_label :: proc(app: ^App, text: cstring, x, y: f32) {
	draw_ui_text(app, text, i32(x), i32(y), 10, rl.Color{160, 170, 195, 200})
}

op_drag_field :: proc(app: ^App, label: cstring, value: f32, box: rl.Rectangle, active: bool, mouse: rl.Vector2) {
	hovered := rl.CheckCollisionPointRec(mouse, box)
	bg: rl.Color
	switch {
	case active:  bg = rl.Color{50, 90,  165, 255}
	case hovered: bg = rl.Color{55, 62,  88,  255}
	case:         bg = rl.Color{32, 35,  52,  255}
	}
	border := (active || hovered) ? ACCENT_COLOR : BORDER_COLOR
	rl.DrawRectangleRec(box, bg)
	rl.DrawRectangleLinesEx(box, 1, border)
	draw_ui_text(app, fmt.ctprintf("%.3f", value), i32(box.x) + 3, i32(box.y) + 4, 10, CONTENT_TEXT_COLOR)
	draw_ui_text(app, label, i32(box.x) - i32(OP_LW + OP_GAP) + 1, i32(box.y) + 4, 11, CONTENT_TEXT_COLOR)
}

op_mat_button :: proc(app: ^App, label: cstring, rect: rl.Rectangle, active: bool, mouse: rl.Vector2) {
	hovered := rl.CheckCollisionPointRec(mouse, rect)
	bg: rl.Color
	switch {
	case active:  bg = rl.Color{60, 110, 200, 255}
	case hovered: bg = rl.Color{55, 62,  88,  255}
	case:         bg = rl.Color{38, 42,  60,  255}
	}
	border := active ? ACCENT_COLOR : BORDER_COLOR
	rl.DrawRectangleRec(rect, bg)
	rl.DrawRectangleLinesEx(rect, 1, border)
	tw  := measure_ui_text(app, label, 10).width
	tx  := i32(rect.x) + (i32(rect.width) - tw) / 2
	col := active ? rl.RAYWHITE : CONTENT_TEXT_COLOR
	draw_ui_text(app, label, tx, i32(rect.y) + 5, 10, col)
}

// op_try_start_drag checks hover; if lmb_pressed, arms a drag on the field.
// Returns true when the mouse is inside the box.
op_try_start_drag :: proc(
	box: rl.Rectangle, idx: int, val: f32,
	st: ^ObjectPropsPanelState, mouse: rl.Vector2, lmb_pressed: bool,
) -> bool {
	if !rl.CheckCollisionPointRec(mouse, box) { return false }
	if lmb_pressed {
		st.prop_drag_idx       = idx
		st.prop_drag_start_x   = mouse.x
		st.prop_drag_start_val = val
		rl.SetMouseCursor(.RESIZE_EW)
	}
	return true
}

// ── draw 

draw_object_props_content :: proc(app: ^App, content: rl.Rectangle) {
	ev    := &app.e_edit_view
	st    := &app.e_object_props
	mouse := rl.GetMousePosition()

	if ev.selection_kind == .None {
		draw_ui_text(app, "No object select",
			i32(content.x) + 10, i32(content.y) + 20, 12, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Click a sphere or the camera in the Edit View.",
			i32(content.x) + 10, i32(content.y) + 40, 11, rl.Color{140, 150, 165, 200})
		return
	}

	if ev.selection_kind == .Camera {
		c_params := &app.c_camera_params
		op_section_label(app, "CAMERA (non-deletable)", content.x + 8, content.y + 6)
		fields := op_camera_field_rects(content)
		y0 := content.y + 6 + 18
		draw_ui_text(app, "From", i32(content.x) + 8, i32(y0), 10, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "At",   i32(content.x) + 8, i32(y0 + OP_CAM_ROW), 10, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "FOV / Defocus / Focus", i32(content.x) + 8, i32(y0 + 2*OP_CAM_ROW), 10, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Max D / Shutter", i32(content.x) + 8, i32(y0 + 3*OP_CAM_ROW), 10, CONTENT_TEXT_COLOR)
		op_drag_field(app, "X", c_params.lookfrom[0], fields[0], st.prop_drag_idx == 0, mouse)
		op_drag_field(app, "Y", c_params.lookfrom[1], fields[1], st.prop_drag_idx == 1, mouse)
		op_drag_field(app, "Z", c_params.lookfrom[2], fields[2], st.prop_drag_idx == 2, mouse)
		op_drag_field(app, "X", c_params.lookat[0], fields[3], st.prop_drag_idx == 3, mouse)
		op_drag_field(app, "Y", c_params.lookat[1], fields[4], st.prop_drag_idx == 4, mouse)
		op_drag_field(app, "Z", c_params.lookat[2], fields[5], st.prop_drag_idx == 5, mouse)
		op_drag_field(app, "", c_params.vfov, fields[6], st.prop_drag_idx == 6, mouse)
		op_drag_field(app, "", c_params.defocus_angle, fields[7], st.prop_drag_idx == 7, mouse)
		op_drag_field(app, "", c_params.focus_dist, fields[8], st.prop_drag_idx == 8, mouse)
		op_drag_field(app, "D", f32(c_params.max_depth), fields[9], st.prop_drag_idx == 9, mouse)
		op_drag_field(app, "Op", c_params.shutter_open, fields[10], st.prop_drag_idx == 10, mouse)
		op_drag_field(app, "Cl", c_params.shutter_close, fields[11], st.prop_drag_idx == 11, mouse)
		return
	}

	// Quad selected — material only (Q, u, v not editable here)
	if ev.selection_kind == .Quad && ev.selected_idx >= 0 {
		quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx)
		if !ok { return }
		lx := content.x + 8
		cy := content.y + 6
		op_section_label(app, "QUAD — MATERIAL", lx, cy)
		cy += 20
		bw := (content.width - 16) / 3.0 - 2
		mat_rects := [3]rl.Rectangle{
			{lx, cy, bw, 22},
			{lx + bw + 2, cy, bw, 22},
			{lx + 2*(bw+2), cy, bw, 22},
		}
		is_lambertian := false
		is_metallic := false
		is_dielectric := false
		#partial switch _ in quad.material {
		case rt.lambertian:  is_lambertian = true
		case rt.metallic:    is_metallic = true
		case rt.dielectric:  is_dielectric = true
		}
		op_mat_button(app, "Lambertian", mat_rects[0], is_lambertian, mouse)
		op_mat_button(app, "Metallic",   mat_rects[1], is_metallic,   mouse)
		op_mat_button(app, "Diel.",      mat_rects[2], is_dielectric, mouse)
		cy += 28
		x0 := lx + OP_LW + OP_GAP
		box_rgb := [3]rl.Rectangle{
			{x0, cy, OP_FW, OP_FH},
			{x0 + OP_COL, cy, OP_FW, OP_FH},
			{x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		box_param := rl.Rectangle{x0, cy + OP_FH + 6, OP_FW, OP_FH}
		op_section_label(app, "COLOR", lx, cy - 2)
		col := [3]f32{0.5, 0.5, 0.5}
		#partial switch m in quad.material {
		case rt.lambertian:
			if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
			else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
		case rt.metallic:
			col = m.albedo
		}
		op_drag_field(app, "R", col[0], box_rgb[0], st.prop_drag_idx == 20, mouse)
		op_drag_field(app, "G", col[1], box_rgb[1], st.prop_drag_idx == 21, mouse)
		op_drag_field(app, "B", col[2], box_rgb[2], st.prop_drag_idx == 22, mouse)
		cy += OP_FH + 8
		if is_metallic {
			fz: f32 = 0.1
			if m, ok2 := quad.material.(rt.metallic); ok2 { fz = m.fuzz }
			op_section_label(app, "Fuzz", lx, cy - 2)
			op_drag_field(app, "Fz", fz, box_param, st.prop_drag_idx == 23, mouse)
		} else if is_dielectric {
			ir: f32 = 1.5
			if d, ok2 := quad.material.(rt.dielectric); ok2 { ir = d.ref_idx }
			op_section_label(app, "IOR", lx, cy - 2)
			op_drag_field(app, "Ir", ir, box_param, st.prop_drag_idx == 23, mouse)
		}
		return
	}

	// Sphere selected
	if ev.selected_idx < 0 || ev.selected_idx >= SceneManagerLen(ev.scene_mgr) { return }
	sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
	if !ok { return }
	lo := op_compute_layout(content, sphere.material_kind, sphere.albedo)

	// TRANSFORM
	op_section_label(app, "TRANSFORM", lo.lx, lo.y_transform)
	op_drag_field(app, "X", sphere.center[0], lo.boxes_xyz[0], st.prop_drag_idx == 0, mouse)
	op_drag_field(app, "Y", sphere.center[1], lo.boxes_xyz[1], st.prop_drag_idx == 1, mouse)
	op_drag_field(app, "Z", sphere.center[2], lo.boxes_xyz[2], st.prop_drag_idx == 2, mouse)
	op_drag_field(app, "R", sphere.radius,    lo.box_radius,   st.prop_drag_idx == 3, mouse)

	// MOTION (offset = center1 - center)
	motion_offset: [3]f32 = {0, 0, 0}
	if sphere.is_moving {
		motion_offset[0] = sphere.center1[0] - sphere.center[0]
		motion_offset[1] = sphere.center1[1] - sphere.center[1]
		motion_offset[2] = sphere.center1[2] - sphere.center[2]
	}
	op_section_label(app, "MOTION", lo.lx, lo.y_motion)
	op_drag_field(app, "dX", motion_offset[0], lo.boxes_motion[0], st.prop_drag_idx == 8, mouse)
	op_drag_field(app, "dY", motion_offset[1], lo.boxes_motion[1], st.prop_drag_idx == 9, mouse)
	op_drag_field(app, "dZ", motion_offset[2], lo.boxes_motion[2], st.prop_drag_idx == 10, mouse)

	// MATERIAL
	op_section_label(app, "MATERIAL", lo.lx, lo.y_material)
	op_mat_button(app, "Lambertian", lo.mat_rects[0], sphere.material_kind == .Lambertian, mouse)
	op_mat_button(app, "Metallic",   lo.mat_rects[1], sphere.material_kind == .Metallic,   mouse)
	op_mat_button(app, "Diel.",      lo.mat_rects[2], sphere.material_kind == .Dielectric, mouse)
	if sphere.material_kind == .Metallic {
		op_drag_field(app, "Fz", sphere.fuzz,    lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	} else if sphere.material_kind == .Dielectric {
		op_drag_field(app, "Ir", sphere.ref_idx, lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	}

	// COLOR / IMAGE TEXTURE
	op_section_label(app, "COLOR", lo.lx, lo.y_color)

	if lo.has_image {
		// Show basename of the image path
		if it, ok2 := sphere.albedo.(core.ImageTexture); ok2 {
			base := filepath.base(it.path)
			label := fmt.ctprintf("Img: %s", base)
			draw_ui_text(app, label, i32(lo.lx), i32(lo.y_color) + 18, 10, CONTENT_TEXT_COLOR)
		}
	} else {
		// RGB drag fields + swatch
		disp_col := [3]f32{0.5, 0.5, 0.5}
		if ct, ok2 := sphere.albedo.(core.ConstantTexture); ok2 { disp_col = ct.color }
		else if ct2, ok2 := sphere.albedo.(core.CheckerTexture); ok2 { disp_col = ct2.even }

		op_drag_field(app, "R", disp_col[0], lo.boxes_rgb[0], st.prop_drag_idx == 4, mouse)
		op_drag_field(app, "G", disp_col[1], lo.boxes_rgb[1], st.prop_drag_idx == 5, mouse)
		op_drag_field(app, "B", disp_col[2], lo.boxes_rgb[2], st.prop_drag_idx == 6, mouse)

		swatch_col := rl.Color{
			u8(clamp(disp_col[0], f32(0), f32(1)) * 255),
			u8(clamp(disp_col[1], f32(0), f32(1)) * 255),
			u8(clamp(disp_col[2], f32(0), f32(1)) * 255),
			255,
		}
		rl.DrawRectangleRec(lo.swatch, swatch_col)
		rl.DrawRectangleLinesEx(lo.swatch, 1, BORDER_COLOR)
	}

	// Browse / Clear buttons (Lambertian only)
	if sphere.material_kind == .Lambertian {
		browse_hov := rl.CheckCollisionPointRec(mouse, lo.btn_browse)
		browse_bg := browse_hov ? rl.Color{70, 90, 140, 255} : rl.Color{45, 55, 80, 255}
		rl.DrawRectangleRec(lo.btn_browse, browse_bg)
		rl.DrawRectangleLinesEx(lo.btn_browse, 1, BORDER_COLOR)
		draw_ui_text(app, "Browse Image\xe2\x80\xa6", i32(lo.btn_browse.x) + 4, i32(lo.btn_browse.y) + 4, 10, CONTENT_TEXT_COLOR)

		if lo.has_image {
			clear_hov := rl.CheckCollisionPointRec(mouse, lo.btn_clear)
			clear_bg := clear_hov ? rl.Color{160, 60, 60, 255} : rl.Color{90, 40, 40, 255}
			rl.DrawRectangleRec(lo.btn_clear, clear_bg)
			rl.DrawRectangleLinesEx(lo.btn_clear, 1, BORDER_COLOR)
			draw_ui_text(app, "\xc3\x97", i32(lo.btn_clear.x) + 4, i32(lo.btn_clear.y) + 4, 10, rl.RAYWHITE)
		}
	}
}

// ── update 

update_object_props_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev := &app.e_edit_view
	st := &app.e_object_props

	if ev.selection_kind == .None {
		if st.prop_drag_idx >= 0 {
			st.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		}
		return
	}

	// ── Camera selected: drag 0–11 → app.c_camera_params
	if ev.selection_kind == .Camera {
		c_params := &app.c_camera_params
		if st.prop_drag_idx >= 0 {
			if !lmb {
				// Commit camera drag to history
				edit_history_push(&app.edit_history, ModifyCameraAction{
					before = st.drag_before_c_camera_params,
					after  = app.c_camera_params,
				})
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Camera property"))
				st.prop_drag_idx = -1
				rl.SetMouseCursor(.DEFAULT)
			} else {
				delta := mouse.x - st.prop_drag_start_x
				switch st.prop_drag_idx {
				case 0: c_params.lookfrom[0] = st.prop_drag_start_val + delta * 0.02
				case 1: c_params.lookfrom[1] = st.prop_drag_start_val + delta * 0.02
				case 2: c_params.lookfrom[2] = st.prop_drag_start_val + delta * 0.02
				case 3: c_params.lookat[0] = st.prop_drag_start_val + delta * 0.02
				case 4: c_params.lookat[1] = st.prop_drag_start_val + delta * 0.02
				case 5: c_params.lookat[2] = st.prop_drag_start_val + delta * 0.02
				case 6:
					c_params.vfov = st.prop_drag_start_val + delta * 0.1
					if c_params.vfov < 1 { c_params.vfov = 1 }
					if c_params.vfov > 120 { c_params.vfov = 120 }
				case 7:
					c_params.defocus_angle = st.prop_drag_start_val + delta * 0.02
					if c_params.defocus_angle < 0 { c_params.defocus_angle = 0 }
				case 8:
					c_params.focus_dist = st.prop_drag_start_val + delta * 0.05
					if c_params.focus_dist < 0.1 { c_params.focus_dist = 0.1 }
				case 9:
					c_params.max_depth = int(st.prop_drag_start_val + delta * 0.5)
					if c_params.max_depth < 1 { c_params.max_depth = 1 }
					if c_params.max_depth > 100 { c_params.max_depth = 100 }
				case 10:
					c_params.shutter_open = st.prop_drag_start_val + delta * 0.005
					if c_params.shutter_open < 0 { c_params.shutter_open = 0 }
					if c_params.shutter_open > 1 { c_params.shutter_open = 1 }
					if c_params.shutter_open > c_params.shutter_close { c_params.shutter_close = c_params.shutter_open }
				case 11:
					c_params.shutter_close = st.prop_drag_start_val + delta * 0.005
					if c_params.shutter_close < 0 { c_params.shutter_close = 0 }
					if c_params.shutter_close > 1 { c_params.shutter_close = 1 }
					if c_params.shutter_close < c_params.shutter_open { c_params.shutter_open = c_params.shutter_close }
				}
				rl.SetMouseCursor(.RESIZE_EW)
			}
			return
		}
		fields := op_camera_field_rects(rect)
		vals := [12]f32{
			c_params.lookfrom[0], c_params.lookfrom[1], c_params.lookfrom[2],
			c_params.lookat[0], c_params.lookat[1], c_params.lookat[2],
			c_params.vfov, c_params.defocus_angle, c_params.focus_dist, f32(c_params.max_depth),
			c_params.shutter_open, c_params.shutter_close,
		}
		any_hovered := false
		for i in 0..<12 {
			if op_try_start_drag(fields[i], i, vals[i], st, mouse, lmb_pressed) {
				any_hovered = true
				if lmb_pressed {
					// Capture camera state at drag start
					st.drag_before_c_camera_params = app.c_camera_params
				}
			}
		}
		if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else if rl.CheckCollisionPointRec(mouse, rect) { rl.SetMouseCursor(.DEFAULT) }
		return
	}

	// ── Quad selected: material editing only
	if ev.selection_kind == .Quad && ev.selected_idx >= 0 {
		quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx)
		if !ok { return }
		lx := rect.x + 8
		cy := rect.y + 6 + 20
		bw := (rect.width - 16) / 3.0 - 2
		mat_rects := [3]rl.Rectangle{
			{lx, cy, bw, 22},
			{lx + bw + 2, cy, bw, 22},
			{lx + 2*(bw+2), cy, bw, 22},
		}
		cy += 28
		x0 := lx + OP_LW + OP_GAP
		box_rgb := [3]rl.Rectangle{
			{x0, cy, OP_FW, OP_FH},
			{x0 + OP_COL, cy, OP_FW, OP_FH},
			{x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		box_param := rl.Rectangle{x0, cy + OP_FH + 6, OP_FW, OP_FH}

		if st.prop_drag_idx >= 0 && st.prop_drag_idx >= 20 && st.prop_drag_idx <= 23 {
			if !lmb {
				st.prop_drag_idx = -1
				rl.SetMouseCursor(.DEFAULT)
			} else {
				delta := mouse.x - st.prop_drag_start_x
				col := [3]f32{0.5, 0.5, 0.5}
				#partial switch m in quad.material {
				case rt.lambertian:
					if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
					else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
				case rt.metallic: col = m.albedo
				}
				switch st.prop_drag_idx {
				case 20:
					col[0] = st.prop_drag_start_val + delta * 0.005
					col[0] = clamp(col[0], 0.0, 1.0)
				case 21:
					col[1] = st.prop_drag_start_val + delta * 0.005
					col[1] = clamp(col[1], 0.0, 1.0)
				case 22:
					col[2] = st.prop_drag_start_val + delta * 0.005
					col[2] = clamp(col[2], 0.0, 1.0)
				case 23:
					if m, is_metal := quad.material.(rt.metallic); is_metal {
						fz := st.prop_drag_start_val + delta * 0.002
						fz = clamp(fz, 0.0, 1.0)
						quad.material = rt.metallic{albedo = m.albedo, fuzz = fz}
					} else if _, is_diel := quad.material.(rt.dielectric); is_diel {
						ir := st.prop_drag_start_val + delta * 0.01
						if ir < 1.0 { ir = 1.0 }
						if ir > 3.0 { ir = 3.0 }
						quad.material = rt.dielectric{ref_idx = ir}
					}
					SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
					mark_scene_dirty(app)
					return
				}
				#partial switch _ in quad.material {
				case rt.lambertian:
					quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
				case rt.metallic:
					fz: f32 = 0.1
					if m, ok2 := quad.material.(rt.metallic); ok2 { fz = m.fuzz }
					quad.material = rt.metallic{albedo = col, fuzz = fz}
				}
				SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				mark_scene_dirty(app)
			}
			return
		}
		if lmb_pressed {
			if rl.CheckCollisionPointRec(mouse, mat_rects[0]) {
				col := [3]f32{0.5, 0.5, 0.5}
				#partial switch m in quad.material {
				case rt.lambertian:
					if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
				case rt.metallic: col = m.albedo
				}
				quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
				SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Quad: Lambertian"))
				return
			}
			if rl.CheckCollisionPointRec(mouse, mat_rects[1]) {
				col := [3]f32{0.5, 0.5, 0.5}
				if m, ok2 := quad.material.(rt.metallic); ok2 { col = m.albedo }
				quad.material = rt.metallic{albedo = col, fuzz = 0.1}
				SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Quad: Metallic"))
				return
			}
			if rl.CheckCollisionPointRec(mouse, mat_rects[2]) {
				quad.material = rt.dielectric{ref_idx = 1.5}
				SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Quad: Dielectric"))
				return
			}
		}
		col := [3]f32{0.5, 0.5, 0.5}
		#partial switch m in quad.material {
		case rt.lambertian:
			if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
			else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
		case rt.metallic: col = m.albedo
		}
		param_val: f32 = 0.1
		if m, ok2 := quad.material.(rt.metallic); ok2 { param_val = m.fuzz }
		else if d, ok2 := quad.material.(rt.dielectric); ok2 { param_val = d.ref_idx }
		any_hov := false
		if op_try_start_drag(box_rgb[0], 20, col[0], st, mouse, lmb_pressed) { any_hov = true }
		if op_try_start_drag(box_rgb[1], 21, col[1], st, mouse, lmb_pressed) { any_hov = true }
		if op_try_start_drag(box_rgb[2], 22, col[2], st, mouse, lmb_pressed) { any_hov = true }
		if op_try_start_drag(box_param, 23, param_val, st, mouse, lmb_pressed) { any_hov = true }
		if any_hov { rl.SetMouseCursor(.RESIZE_EW) } else if rl.CheckCollisionPointRec(mouse, rect) { rl.SetMouseCursor(.DEFAULT) }
		return
	}

	// ── Sphere selected
	if ev.selected_idx < 0 || ev.selected_idx >= SceneManagerLen(ev.scene_mgr) {
		if st.prop_drag_idx >= 0 {
			st.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		}
		return
	}
	// read-modify-write via scene manager so different object types can be supported
	sphere, ok2 := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
	if !ok2 { return }

	// ── Priority 1: active drag
	if st.prop_drag_idx >= 0 {
		if !lmb {
			// Commit sphere property drag to history
			if s_after, ok3 := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok3 {
				edit_history_push(&app.edit_history, ModifySphereAction{
					idx    = ev.selected_idx,
					before = st.drag_before_sphere,
					after  = s_after,
				})
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Sphere property"))
			}
			st.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else {
			delta := mouse.x - st.prop_drag_start_x
			switch st.prop_drag_idx {
			case 0: sphere.center[0] = st.prop_drag_start_val + delta * 0.01
			case 1: sphere.center[1] = st.prop_drag_start_val + delta * 0.01
			case 2: sphere.center[2] = st.prop_drag_start_val + delta * 0.01
			case 3: sphere.radius    = max(st.prop_drag_start_val + delta * 0.005, f32(0.05))
			case 4..=6:
				cur_col := [3]f32{0.5, 0.5, 0.5}
				if ct, ok := sphere.albedo.(core.ConstantTexture); ok { cur_col = ct.color }
				else if ct2, ok := sphere.albedo.(core.CheckerTexture); ok { cur_col = ct2.even }
				if st.prop_drag_idx == 4 { cur_col[0] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1)) }
				if st.prop_drag_idx == 5 { cur_col[1] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1)) }
				if st.prop_drag_idx == 6 { cur_col[2] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1)) }
				sphere.albedo = core.ConstantTexture{color = cur_col}
			case 7:
				if sphere.material_kind == .Metallic {
					sphere.fuzz    = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1))
				} else if sphere.material_kind == .Dielectric {
					sphere.ref_idx = max(st.prop_drag_start_val + delta * 0.005, f32(1.0))
				}
			case 8:
				sphere.center1[0] = sphere.center[0] + (st.prop_drag_start_val + delta * 0.01)
				// Direct f32 comparison is safe here (same stored values, no extra math). Dragging offset to zero correctly clears is_moving.
				sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
			case 9:
				sphere.center1[1] = sphere.center[1] + (st.prop_drag_start_val + delta * 0.01)
				sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
			case 10:
				sphere.center1[2] = sphere.center[2] + (st.prop_drag_start_val + delta * 0.01)
				sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
			}
			rl.SetMouseCursor(.RESIZE_EW)
			// persist changes back to the scene manager
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
		}
		return
	}

	lo := op_compute_layout(rect, sphere.material_kind, sphere.albedo)

	// ── Material toggle clicks
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[0]) {
			before := sphere
			sphere.material_kind = .Lambertian
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
			mark_scene_dirty(app)
			app_push_log(app, strings.clone("Material: Lambertian"))
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[1]) {
			before := sphere
			if sphere.material_kind != .Metallic && sphere.fuzz <= 0 { sphere.fuzz = 0.1 }
			sphere.material_kind = .Metallic
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
			mark_scene_dirty(app)
			app_push_log(app, strings.clone("Material: Metallic"))
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[2]) {
			before := sphere
			sphere.material_kind = .Dielectric
			if sphere.ref_idx < 1.0 { sphere.ref_idx = 1.5 }
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
			mark_scene_dirty(app)
			app_push_log(app, strings.clone("Material: Dielectric"))
			if g_app != nil { g_app.input_consumed = true }
			return
		}

		// ── Browse Image button (Lambertian only)
		if sphere.material_kind == .Lambertian && rl.CheckCollisionPointRec(mouse, lo.btn_browse) {
			default_dir := util.dialog_default_dir(app.current_scene_path)
			img_path, ok2 := util.open_file_dialog(default_dir, util.IMAGE_FILTER_DESC, util.IMAGE_FILTER_EXT)
			delete(default_dir)
			if ok2 {
				before := sphere
				sphere.albedo = core.ImageTexture{path = img_path}
				app_ensure_image_cached(app, img_path)
				SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
				edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
				mark_scene_dirty(app)
				app_push_log(app, fmt.aprintf("Texture: %s", filepath.base(img_path)))
			}
			if g_app != nil { g_app.input_consumed = true }
			return
		}

		// ── Clear image button (Lambertian with ImageTexture)
		if sphere.material_kind == .Lambertian && lo.has_image && rl.CheckCollisionPointRec(mouse, lo.btn_clear) {
			before := sphere
			sphere.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
			mark_scene_dirty(app)
			app_push_log(app, strings.clone("Texture cleared"))
			if g_app != nil { g_app.input_consumed = true }
			return
		}
	}

	// ── Drag-field hover / start-drag
	motion_offset: [3]f32 = {0, 0, 0}
	if sphere.is_moving {
		motion_offset[0] = sphere.center1[0] - sphere.center[0]
		motion_offset[1] = sphere.center1[1] - sphere.center[1]
		motion_offset[2] = sphere.center1[2] - sphere.center[2]
	}
	any_hovered := false
	if op_try_start_drag(lo.boxes_xyz[0], 0, sphere.center[0], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_xyz[1], 1, sphere.center[1], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_xyz[2], 2, sphere.center[2], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.box_radius,   3, sphere.radius,    st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_motion[0], 8, motion_offset[0], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_motion[1], 9, motion_offset[1], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_motion[2], 10, motion_offset[2], st, mouse, lmb_pressed) { any_hovered = true }
	// RGB drag only when not an image texture
	if !lo.has_image {
		drag_col := [3]f32{0.5, 0.5, 0.5}
		if ct, ok := sphere.albedo.(core.ConstantTexture); ok { drag_col = ct.color }
		else if ct2, ok := sphere.albedo.(core.CheckerTexture); ok { drag_col = ct2.even }
		if op_try_start_drag(lo.boxes_rgb[0], 4, drag_col[0], st, mouse, lmb_pressed) { any_hovered = true }
		if op_try_start_drag(lo.boxes_rgb[1], 5, drag_col[1], st, mouse, lmb_pressed) { any_hovered = true }
		if op_try_start_drag(lo.boxes_rgb[2], 6, drag_col[2], st, mouse, lmb_pressed) { any_hovered = true }
	}
	if lo.has_mat_param {
		mat_val := sphere.material_kind == .Metallic ? sphere.fuzz : sphere.ref_idx
		if op_try_start_drag(lo.box_mat_param, 7, mat_val, st, mouse, lmb_pressed) { any_hovered = true }
	}
	// Capture before-state when a drag starts
	if lmb_pressed && any_hovered {
		st.drag_before_sphere = sphere
	}

	if any_hovered {
		rl.SetMouseCursor(.RESIZE_EW)
	} else if rl.CheckCollisionPointRec(mouse, rect) {
		rl.SetMouseCursor(.DEFAULT)
	}
}
