package ui

import "core:fmt"
import rl "vendor:raylib"
import "RT_Weekend:scene"

// Layout constants for the Object Properties panel.
// Separate from PROP_* in edit_view_panel.odin to fit a narrower panel.
OP_LW  :: f32(12)                          // label width  (1–2 chars at fs=11)
OP_GAP :: f32(2)                           // gap between label and field box
OP_FW  :: f32(50)                          // field box width
OP_FH  :: f32(18)                          // field box height
OP_SP  :: f32(4)                           // spacing after a field group
OP_COL :: OP_LW + OP_GAP + OP_FW + OP_SP  // = 68 px per column

// ObjectPropsPanelState holds per-frame drag state for the Object Properties panel.
// The actual object data lives in app.edit_view.objects[app.edit_view.selected_idx].
ObjectPropsPanelState :: struct {
	// Active drag field index:
	//   -1 = none
	//    0 = center.x   1 = center.y   2 = center.z   3 = radius
	//    4 = albedo.r   5 = albedo.g   6 = albedo.b
	//    7 = fuzz (metallic) or ref_idx (dielectric)
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,
}

// OpLayout holds every interactive rectangle for a single frame, computed once
// by op_compute_layout and consumed by both the draw and update procs.
OpLayout :: struct {
	lx, x0:       f32,           // left edge for labels/buttons; left edge for field boxes
	y_transform:  f32,           // y of TRANSFORM section header
	y_material:   f32,           // y of MATERIAL section header
	y_color:      f32,           // y of COLOR section header
	boxes_xyz:    [3]rl.Rectangle,
	box_radius:   rl.Rectangle,
	mat_rects:    [3]rl.Rectangle,
	has_mat_param: bool,
	box_mat_param: rl.Rectangle, // fuzz (metallic) or IOR (dielectric)
	boxes_rgb:    [3]rl.Rectangle,
	swatch:       rl.Rectangle,
}

op_compute_layout :: proc(content: rl.Rectangle, mat_kind: scene.MaterialKind) -> OpLayout {
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

	// COLOR 
	lo.y_color = cy
	cy += 18

	lo.boxes_rgb = [3]rl.Rectangle{
		{lo.x0,             cy, OP_FW, OP_FH},
		{lo.x0 + OP_COL,   cy, OP_FW, OP_FH},
		{lo.x0 + 2*OP_COL, cy, OP_FW, OP_FH},
	}
	cy += OP_FH + 6

	lo.swatch = rl.Rectangle{lo.lx, cy, 42, 30}
	return lo
}

// ── visual helpers 

op_section_label :: proc(text: cstring, x, y: f32) {
	rl.DrawText(text, i32(x), i32(y), 10, rl.Color{160, 170, 195, 200})
}

op_drag_field :: proc(label: cstring, value: f32, box: rl.Rectangle, active: bool, mouse: rl.Vector2) {
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
	rl.DrawText(fmt.ctprintf("%.3f", value), i32(box.x) + 3, i32(box.y) + 4, 10, CONTENT_TEXT_COLOR)
	rl.DrawText(label, i32(box.x) - i32(OP_LW + OP_GAP) + 1, i32(box.y) + 4, 11, CONTENT_TEXT_COLOR)
}

op_mat_button :: proc(label: cstring, rect: rl.Rectangle, active: bool, mouse: rl.Vector2) {
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
	tw  := rl.MeasureText(label, 10)
	tx  := i32(rect.x) + (i32(rect.width) - tw) / 2
	col := active ? rl.RAYWHITE : CONTENT_TEXT_COLOR
	rl.DrawText(label, tx, i32(rect.y) + 5, 10, col)
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
	ev    := &app.edit_view
	st    := &app.object_props
	mouse := rl.GetMousePosition()

	if ev.selected_idx < 0 || ev.selected_idx >= len(ev.objects) {
		rl.DrawText("No object selected.",
			i32(content.x) + 10, i32(content.y) + 20, 12, CONTENT_TEXT_COLOR)
		rl.DrawText("Click a sphere in the Edit View.",
			i32(content.x) + 10, i32(content.y) + 40, 11, rl.Color{140, 150, 165, 200})
		return
	}

	s  := ev.objects[ev.selected_idx]   // value copy — read only
	lo := op_compute_layout(content, s.material_kind)

	// TRANSFORM 
	op_section_label("TRANSFORM", lo.lx, lo.y_transform)
	op_drag_field("X", s.center[0], lo.boxes_xyz[0], st.prop_drag_idx == 0, mouse)
	op_drag_field("Y", s.center[1], lo.boxes_xyz[1], st.prop_drag_idx == 1, mouse)
	op_drag_field("Z", s.center[2], lo.boxes_xyz[2], st.prop_drag_idx == 2, mouse)
	op_drag_field("R", s.radius,    lo.box_radius,   st.prop_drag_idx == 3, mouse)

	// MATERIAL 
	op_section_label("MATERIAL", lo.lx, lo.y_material)
	op_mat_button("Lambertian", lo.mat_rects[0], s.material_kind == .Lambertian, mouse)
	op_mat_button("Metallic",   lo.mat_rects[1], s.material_kind == .Metallic,   mouse)
	op_mat_button("Diel.",      lo.mat_rects[2], s.material_kind == .Dielectric, mouse)
	if s.material_kind == .Metallic {
		op_drag_field("Fz", s.fuzz,    lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	} else if s.material_kind == .Dielectric {
		op_drag_field("Ir", s.ref_idx, lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	}

	// COLOR 
	op_section_label("COLOR", lo.lx, lo.y_color)
	op_drag_field("R", s.albedo[0], lo.boxes_rgb[0], st.prop_drag_idx == 4, mouse)
	op_drag_field("G", s.albedo[1], lo.boxes_rgb[1], st.prop_drag_idx == 5, mouse)
	op_drag_field("B", s.albedo[2], lo.boxes_rgb[2], st.prop_drag_idx == 6, mouse)

	// Color swatch
	swatch_col := rl.Color{
		u8(clamp(s.albedo[0], f32(0), f32(1)) * 255),
		u8(clamp(s.albedo[1], f32(0), f32(1)) * 255),
		u8(clamp(s.albedo[2], f32(0), f32(1)) * 255),
		255,
	}
	rl.DrawRectangleRec(lo.swatch, swatch_col)
	rl.DrawRectangleLinesEx(lo.swatch, 1, BORDER_COLOR)
}

// ── update 

update_object_props_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev := &app.edit_view
	st := &app.object_props

	if ev.selected_idx < 0 || ev.selected_idx >= len(ev.objects) {
		if st.prop_drag_idx >= 0 {
			st.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		}
		return
	}

	s := &ev.objects[ev.selected_idx]

	// ── Priority 1: active drag 
	if st.prop_drag_idx >= 0 {
		if !lmb {
			st.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else {
			delta := mouse.x - st.prop_drag_start_x
			switch st.prop_drag_idx {
			case 0: s.center[0] = st.prop_drag_start_val + delta * 0.01
			case 1: s.center[1] = st.prop_drag_start_val + delta * 0.01
			case 2: s.center[2] = st.prop_drag_start_val + delta * 0.01
			case 3: s.radius    = max(st.prop_drag_start_val + delta * 0.005, f32(0.05))
			case 4: s.albedo[0] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1))
			case 5: s.albedo[1] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1))
			case 6: s.albedo[2] = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1))
			case 7:
				if s.material_kind == .Metallic {
					s.fuzz    = clamp(st.prop_drag_start_val + delta * 0.002, f32(0), f32(1))
				} else if s.material_kind == .Dielectric {
					s.ref_idx = max(st.prop_drag_start_val + delta * 0.005, f32(1.0))
				}
			}
			rl.SetMouseCursor(.RESIZE_EW)
		}
		return
	}

	lo := op_compute_layout(rect, s.material_kind)

	// ── Material toggle clicks 
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[0]) {
			s.material_kind = .Lambertian
			return
		}
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[1]) {
			s.material_kind = .Metallic
			if s.fuzz <= 0 { s.fuzz = 0.1 }
			return
		}
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[2]) {
			s.material_kind = .Dielectric
			if s.ref_idx < 1.0 { s.ref_idx = 1.5 }
			return
		}
	}

	// ── Drag-field hover / start-drag 
	any_hovered := false
	if op_try_start_drag(lo.boxes_xyz[0], 0, s.center[0], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_xyz[1], 1, s.center[1], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_xyz[2], 2, s.center[2], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.box_radius,   3, s.radius,    st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_rgb[0], 4, s.albedo[0], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_rgb[1], 5, s.albedo[1], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_rgb[2], 6, s.albedo[2], st, mouse, lmb_pressed) { any_hovered = true }
	if lo.has_mat_param {
		mat_val := s.material_kind == .Metallic ? s.fuzz : s.ref_idx
		if op_try_start_drag(lo.box_mat_param, 7, mat_val, st, mouse, lmb_pressed) { any_hovered = true }
	}

	if any_hovered {
		rl.SetMouseCursor(.RESIZE_EW)
	} else if rl.CheckCollisionPointRec(mouse, rect) {
		rl.SetMouseCursor(.DEFAULT)
	}
}
