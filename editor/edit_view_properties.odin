package editor

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

// EDIT_PROPS_H is the height of the properties strip at the bottom of the Edit View panel.
EDIT_PROPS_H :: f32(120)

// PROP_LW  = label width  (single char "X"/"Y"/"Z"/"R" at fs=12)
// PROP_GAP = gap between label and value box
// PROP_FW  = value-box width
// PROP_FH  = value-box height
// PROP_SP  = spacing after each field group
PROP_LW  :: f32(14)
PROP_GAP :: f32(4)
PROP_FW  :: f32(60)
PROP_FH  :: f32(20)
PROP_SP  :: f32(10)
PROP_COL :: PROP_LW + PROP_GAP + PROP_FW + PROP_SP // 88 px per column

// cam_orbit_prop_rects returns 7 drag-float rects for the camera properties strip.
// [0,1,2] = Pos X/Y/Z, [3,4,5] = yaw°/pitch°/dist, [6] = roll° on row 2.
cam_orbit_prop_rects :: proc(r: rl.Rectangle) -> [7]rl.Rectangle {
	x0  := r.x + 8
	y0  := r.y + 8
	off := PROP_LW + PROP_GAP
	return [7]rl.Rectangle{
		{x0 + 0*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0 + 1*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0 + 2*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0 + 0*PROP_COL + off, y0 + 30, PROP_FW, PROP_FH},
		{x0 + 1*PROP_COL + off, y0 + 30, PROP_FW, PROP_FH},
		{x0 + 2*PROP_COL + off, y0 + 30, PROP_FW, PROP_FH},
		{x0 + 0*PROP_COL + off, y0 + 60, PROP_FW, PROP_FH},
	}
}

// prop_field_rects returns the four drag-float value boxes in screen space.
// [0]=cx  [1]=cy  [2]=cz  [3]=radius. Rows: 0-2 on row0, 3 on row1.
prop_field_rects :: proc(r: rl.Rectangle) -> [4]rl.Rectangle {
	x0 := r.x + 8
	y0 := r.y + 8
	off := PROP_LW + PROP_GAP
	return [4]rl.Rectangle{
		{x0 + 0*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0 + 1*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0 + 2*PROP_COL + off, y0,      PROP_FW, PROP_FH},
		{x0              + off, y0 + 30, PROP_FW, PROP_FH},
	}
}

// draw_drag_field draws a single labeled drag-float widget.
// The label is placed immediately to the left of the value box.
draw_drag_field :: proc(app: ^App, label: cstring, value: f32, box: rl.Rectangle, active: bool, mouse: rl.Vector2) {
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
	draw_ui_text(app, fmt.ctprintf("%.3f", value), i32(box.x) + 5, i32(box.y) + 4, 11, CONTENT_TEXT_COLOR)
	// Label to the left
	draw_ui_text(app, label, i32(box.x) - i32(PROP_LW + PROP_GAP) + 2, i32(box.y) + 4, 12, CONTENT_TEXT_COLOR)
}

draw_edit_properties :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, objs: []core.SceneSphere) {
	ev := &app.e_edit_view
	rl.DrawRectangleRec(rect, rl.Color{25, 28, 40, 240})
	rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)

	if ev.selection_kind == .None {
		draw_ui_text(app, "No object selected",
			i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Click a sphere or the camera in the viewport to select it",
			i32(rect.x) + 8, i32(rect.y) + 30, 11, rl.Color{140, 150, 165, 200})
		return
	}

	if ev.selection_kind == .Volume {
		draw_ui_text(app, "Volume selected",
			i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Edit in Details panel",
			i32(rect.x) + 8, i32(rect.y) + 30, 11, rl.Color{140, 150, 165, 200})
		return
	}

	if ev.selection_kind == .Quad {
		if quad, ok := GetSceneQuad(ev.scene_mgr, ev.selected_idx); ok {
			dc := rt.material_display_color(quad.material)
			mat_label := "Lambertian"
			#partial switch _ in quad.material {
			case rt.metallic:     mat_label = "Metallic"
			case rt.dielectric:   mat_label = "Dielectric"
			case rt.diffuse_light: mat_label = "Emitter"
			}
			draw_ui_text(app, "Quad selected",
				i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
			draw_ui_text(app, fmt.ctprintf("Material: %s", mat_label),
				i32(rect.x) + 8, i32(rect.y) + 28, 11, rl.Color{160, 170, 190, 220})
			swatch := rl.Rectangle{rect.x + 8, rect.y + 48, 24, 18}
			swatch_col := rl.Color{
				u8(clamp(dc[0], 0.0, 1.0) * 255),
				u8(clamp(dc[1], 0.0, 1.0) * 255),
				u8(clamp(dc[2], 0.0, 1.0) * 255),
				255,
			}
			rl.DrawRectangleRec(swatch, swatch_col)
			rl.DrawRectangleLinesEx(swatch, 1, BORDER_COLOR)
			draw_ui_text(app, "Edit material in Details panel",
				i32(rect.x) + 8, i32(rect.y) + 72, 10, rl.Color{120, 130, 148, 180})
		} else {
			draw_ui_text(app, "Quad selected",
				i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
		}
		return
	}

	if ev.selection_kind == .Camera {
		RAD2DEG :: f32(180.0 / math.PI)
		cp := &app.c_camera_params
		yaw, pitch, dist := cam_forward_angles(cp.lookfrom, cp.lookat)
		roll := roll_from_vup(cp.lookfrom, cp.lookat, cp.vup)
		fields := cam_orbit_prop_rects(rect)
		vals := [7]f32{
			cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2],
			yaw * RAD2DEG, pitch * RAD2DEG, dist,
			roll * RAD2DEG,
		}
		labels := [7]cstring{"X", "Y", "Z", "Yaw", "Pit", "Dst", "Roll"}

		// Row 0 label "Pos"
		draw_ui_text(app, "Pos", i32(rect.x) + 8, i32(rect.y) + 8 + 4, 11, CONTENT_TEXT_COLOR)
		draw_drag_field(app, labels[0], vals[0], fields[0], ev.cam_prop_drag_idx == 0, mouse)
		draw_drag_field(app, labels[1], vals[1], fields[1], ev.cam_prop_drag_idx == 1, mouse)
		draw_drag_field(app, labels[2], vals[2], fields[2], ev.cam_prop_drag_idx == 2, mouse)

		// Row 1 — yaw / pitch / distance
		draw_drag_field(app, labels[3], vals[3], fields[3], ev.cam_prop_drag_idx == 3, mouse)
		draw_drag_field(app, labels[4], vals[4], fields[4], ev.cam_prop_drag_idx == 4, mouse)
		draw_drag_field(app, labels[5], vals[5], fields[5], ev.cam_prop_drag_idx == 5, mouse)

		// Row 2 — roll
		draw_drag_field(app, labels[6], vals[6], fields[6], ev.cam_prop_drag_idx == 6, mouse)

		// Hint
		draw_ui_text(app,
			"Drag field \u2022 Drag gizmo to move \u2022 Drag ring to rotate",
			i32(rect.x) + 8, i32(rect.y) + i32(EDIT_PROPS_H) - 18, 11,
			rl.Color{120, 130, 148, 180},
		)
		return
	}

	// Sphere selected (use scene_mgr so index matches when scene has quads)
	if ev.selected_idx < 0 { return }
	sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
	if !ok { return }
	fields := prop_field_rects(rect)

	// Row 0 — position X Y Z
	draw_drag_field(app, "X", sphere.center[0], fields[0], ev.prop_drag_idx == 0, mouse)
	draw_drag_field(app, "Y", sphere.center[1], fields[1], ev.prop_drag_idx == 1, mouse)
	draw_drag_field(app, "Z", sphere.center[2], fields[2], ev.prop_drag_idx == 2, mouse)

	// Row 1 — radius + material label
	draw_drag_field(app, "R", sphere.radius, fields[3], ev.prop_drag_idx == 3, mouse)

	mat_name  := material_name(sphere.material_kind)
	mat_x := i32(rect.x) + 8 + i32(PROP_COL)
	mat_y := i32(rect.y) + 8 + 30 + 4
	draw_ui_text(app, "Mat:",    mat_x,      mat_y, 12, CONTENT_TEXT_COLOR)
	draw_ui_text(app, mat_name,  mat_x + 36, mat_y, 12, ACCENT_COLOR)

	// Hint
	draw_ui_text(app,
		"Drag field to adjust  •  Click+drag sphere in view to move",
		i32(rect.x) + 8, i32(rect.y) + i32(EDIT_PROPS_H) - 18, 11,
		rl.Color{120, 130, 148, 180},
	)
}
