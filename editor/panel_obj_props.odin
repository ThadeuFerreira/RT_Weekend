package editor

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

// Layout constants for the Object Properties panel.
// Separate from PROP_* in edit_view_panel.odin to fit a narrower panel.
OP_LW  :: f32(12)                          // label width  (1–2 chars at fs=11)
OP_GAP :: f32(2)                           // gap between label and field box
OP_FW  :: f32(50)                          // field box width
OP_FH  :: f32(18)                          // field box height
OP_SP  :: f32(4)                           // spacing after a field group
OP_COL :: OP_LW + OP_GAP + OP_FW + OP_SP  // = 68 px per column

// NoisePreview caches a generated Perlin/Marble preview texture to avoid per-frame regeneration.
NoisePreview :: struct {
	tex:       rl.Texture2D,
	scale:     f32,
	is_marble: bool,
}

// noise_preview_update regenerates the preview texture if the scale or type changed.
// For NoiseTexture: uses rl.GenImagePerlinNoise (stb_perlin fBm). For MarbleTexture: custom CPU generation.
noise_preview_update :: proc(np: ^NoisePreview, is_marble: bool, scale: f32) {
	if np.tex.id != 0 && np.scale == scale && np.is_marble == is_marble { return }
	if np.tex.id != 0 { rl.UnloadTexture(np.tex) }
	safe_scale := scale > 0 ? scale : 4.0
	if is_marble {
		// Generate marble preview: 0.5*(1+sin(scale*y + 10*turb(x,y,1))).
		// Uses the same CPU turbulence function as the ray tracer for visual consistency.
		img := rl.GenImageColor(64, 64, rl.BLACK)
		pixels := cast([^]rl.Color)img.data
		for py in 0..<64 {
			for px in 0..<64 {
				nx := f32(px) * safe_scale / 64.0
				ny := f32(py) * safe_scale / 64.0
				turb := rt.perlin_turbulence({nx, ny, 1.0})
				val  := 0.5 * (1.0 + math.sin(safe_scale * ny + 10.0 * turb))
				bv   := u8(clamp(val, 0.0, 1.0) * 255.0)
				pixels[py * 64 + px] = rl.Color{bv, bv, bv, 255}
			}
		}
		np.tex = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
	} else {
		// Use Raylib's GenImagePerlinNoise (stb_perlin fBm, 6 octaves, lacunarity=2, gain=0.5).
		img := rl.GenImagePerlinNoise(64, 64, 0, 0, safe_scale)
		np.tex = rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
	}
	np.scale     = safe_scale
	np.is_marble = is_marble
}

// noise_preview_unload frees the cached texture if one exists.
noise_preview_unload :: proc(np: ^NoisePreview) {
	if np.tex.id != 0 {
		rl.UnloadTexture(np.tex)
		np.tex = {}
	}
}

// ObjectPropsPanelState holds per-frame drag state for the Object Properties panel.
// For sphere: data in app.e_edit_view.objects[selected_idx]. For camera: app.c_camera_params.
// Drag indices: sphere 0–10 (xyz, radius, motion dX dY dZ, rgb, mat_param); camera 0–11 (from xyz, at xyz, vfov, defocus, focus, max_depth, shutter).
// Drag index 11 = Noise/Marble scale. Volume props: 100 + i*4 + 0 = density, +1..+3 = albedo R,G,B.
// When a volume is selected: 200+0..2 = translate X,Y,Z; 3 = rotate_y_deg; 4 = density; 5,6,7 = albedo R,G,B; 8 = scale (uniform).
OP_VOLUME_DRAG_BASE         :: 100
OP_VOLUME_SELECTED_DRAG_BASE :: 200
OP_VOLUME_SELECTED_DRAG_COUNT :: 9
ObjectPropsPanelState :: struct {
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Before-state captured at drag start (for undo history)
	drag_before_sphere: core.SceneSphere,
	drag_before_c_camera_params: core.CameraParams,
	drag_before_volume: core.SceneVolume,

	// Perlin noise preview (cached; regenerated when scale or type changes)
	noise_preview: NoisePreview,
}

// OpLayout holds every interactive rectangle for a single frame, computed once
// by op_compute_layout and consumed by both the draw and update procs.
OpLayout :: struct {
	lx, x0:        f32,           // left edge for labels/buttons; left edge for field boxes
	y_transform:    f32,           // y of TRANSFORM section header
	y_rotation:     f32,           // y of ROTATION section header
	boxes_rotation: [3]rl.Rectangle,
	y_motion:       f32,           // y of MOTION section header (dX dY dZ)
	y_material:     f32,           // y of MATERIAL section header
	y_color:       f32,           // y of COLOR section header
	boxes_xyz:     [3]rl.Rectangle,
	box_radius:    rl.Rectangle,
	boxes_motion:  [3]rl.Rectangle, // dX dY dZ (center1 - center)
	mat_rects:     [4]rl.Rectangle,
	has_mat_param: bool,
	box_mat_param: rl.Rectangle,   // fuzz (metallic) or IOR (dielectric)
	// COLOR section (constant texture):
	boxes_rgb:     [3]rl.Rectangle,
	swatch:        rl.Rectangle,
	// NOISE/MARBLE section (Lambertian procedural textures):
	has_noise:       bool,           // true when NoiseTexture
	has_marble:      bool,           // true when MarbleTexture
	box_noise_scale: rl.Rectangle,   // scale drag field (drag index 11)
	noise_preview:   rl.Rectangle,   // rect for the 64×64 preview image
	// Texture type buttons (Lambertian only): [Color] [Noise] [Marble]
	has_tex_btns:    bool,
	btn_tex_color:   rl.Rectangle,
	btn_tex_noise:   rl.Rectangle,
	btn_tex_marble:  rl.Rectangle,
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

	// ROTATION
	lo.y_rotation = cy
	cy += 18
	lo.boxes_rotation = [3]rl.Rectangle{
		{lo.x0,             cy, OP_FW, OP_FH},
		{lo.x0 + OP_COL,   cy, OP_FW, OP_FH},
		{lo.x0 + 2*OP_COL, cy, OP_FW, OP_FH},
	}
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

	bw := (content.width - 16) / 4.0 - 2
	lo.mat_rects = [4]rl.Rectangle{
		{lo.lx,               cy, bw, 22},
		{lo.lx + bw + 2,     cy, bw, 22},
		{lo.lx + 2*(bw+2),   cy, bw, 22},
		{lo.lx + 3*(bw+2),   cy, bw, 22},
	}
	cy += 28

	lo.has_mat_param  = mat_kind == .Metallic || mat_kind == .Dielectric
	lo.box_mat_param  = rl.Rectangle{lo.x0, cy, OP_FW, OP_FH}
	if lo.has_mat_param { cy += OP_FH + 6 }
	cy += 4

	// COLOR / EMISSION (Lambertian: texture; DiffuseLight: emission; others: albedo swatch)
	lo.y_color = cy
	cy += 18

	_, lo.has_image  = albedo.(core.ImageTexture)
	_, lo.has_noise  = albedo.(core.NoiseTexture)
	_, lo.has_marble = albedo.(core.MarbleTexture)

	// Texture type mini-buttons for Lambertian: [Color] [Noise] [Marble]
	if mat_kind == .Lambertian {
		lo.has_tex_btns = true
		bw3 := (content.width - 16 - 4) / 3.0
		lo.btn_tex_color  = rl.Rectangle{lo.lx,               cy, bw3, 18}
		lo.btn_tex_noise  = rl.Rectangle{lo.lx + bw3 + 2,     cy, bw3, 18}
		lo.btn_tex_marble = rl.Rectangle{lo.lx + 2*(bw3 + 2), cy, bw3, 18}
		cy += 22
	}

	if lo.has_noise || lo.has_marble {
		// Noise / Marble: scale drag field + preview image
		lo.box_noise_scale = rl.Rectangle{lo.x0, cy, OP_FW, OP_FH}
		cy += OP_FH + 6
		lo.noise_preview = rl.Rectangle{lo.lx, cy, 64, 64}
		cy += 68
	} else if !lo.has_image || mat_kind == .DiffuseLight {
		// Constant/Checker or Light emission: show RGB drag fields + swatch
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
		// Volumes section when scene has volumes (density / albedo editable)
		if len(app.e_volumes) > 0 {
			y0 := content.y + 70
			op_section_label(app, "VOLUMES", content.x + 8, y0)
			y0 += 20
			lx := content.x + 8
			x0 := content.x + 8 + OP_LW + OP_GAP
			for v, i in app.e_volumes {
				vol_label: [32]u8
				vol_str := fmt.bprint(vol_label[:], "Volume ", i + 1)
				if len(vol_str) < len(vol_label) { vol_label[len(vol_str)] = 0 }
				draw_ui_text(app, cast(cstring)&vol_label[0], i32(lx), i32(y0), 10, CONTENT_TEXT_COLOR)
				y0 += OP_FH + 2
				draw_ui_text(app, "Density", i32(lx), i32(y0), 10, CONTENT_TEXT_COLOR)
				box_d := rl.Rectangle{x0, y0, OP_FW, OP_FH}
				op_drag_field(app, "", v.density, box_d, st.prop_drag_idx == OP_VOLUME_DRAG_BASE + i*4 + 0, mouse)
				y0 += OP_FH + 2
				draw_ui_text(app, "Albedo R G B", i32(lx), i32(y0), 10, CONTENT_TEXT_COLOR)
				box_r := rl.Rectangle{x0, y0, OP_FW, OP_FH}
				box_g := rl.Rectangle{x0 + OP_COL, y0, OP_FW, OP_FH}
				box_b := rl.Rectangle{x0 + 2*OP_COL, y0, OP_FW, OP_FH}
				op_drag_field(app, "", v.albedo[0], box_r, st.prop_drag_idx == OP_VOLUME_DRAG_BASE + i*4 + 1, mouse)
				op_drag_field(app, "", v.albedo[1], box_g, st.prop_drag_idx == OP_VOLUME_DRAG_BASE + i*4 + 2, mouse)
				op_drag_field(app, "", v.albedo[2], box_b, st.prop_drag_idx == OP_VOLUME_DRAG_BASE + i*4 + 3, mouse)
				y0 += OP_FH + OP_SP + 8
			}
		}
		return
	}

	if ev.selection_kind == .Volume && ev.selected_idx >= 0 && ev.selected_idx < len(app.e_volumes) {
		v := &app.e_volumes[ev.selected_idx]
		lx := content.x + 8
		cy := content.y + 6
		op_section_label(app, "VOLUME", lx, cy)
		cy += 20
		x0 := lx + OP_LW + OP_GAP
		op_section_label(app, "Translate", lx, cy)
		cy += 18
		box_tx := rl.Rectangle{x0, cy, OP_FW, OP_FH}
		box_ty := rl.Rectangle{x0 + OP_COL, cy, OP_FW, OP_FH}
		box_tz := rl.Rectangle{x0 + 2*OP_COL, cy, OP_FW, OP_FH}
		op_drag_field(app, "X", v.translate[0], box_tx, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 0, mouse)
		op_drag_field(app, "Y", v.translate[1], box_ty, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 1, mouse)
		op_drag_field(app, "Z", v.translate[2], box_tz, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 2, mouse)
		cy += OP_FH + 8
		op_section_label(app, "Rotate Y (deg)", lx, cy)
		cy += 18
		box_rot := rl.Rectangle{x0, cy, OP_FW, OP_FH}
		op_drag_field(app, "", v.rotate_y_deg, box_rot, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 3, mouse)
		cy += OP_FH + 8
		volume_scale_val := (v.box_max[0] - v.box_min[0] + v.box_max[1] - v.box_min[1] + v.box_max[2] - v.box_min[2]) / 3.0
		op_section_label(app, "Scale", lx, cy)
		cy += 18
		box_scale := rl.Rectangle{x0, cy, OP_FW, OP_FH}
		op_drag_field(app, "", volume_scale_val, box_scale, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 8, mouse)
		cy += OP_FH + 8
		op_section_label(app, "Density", lx, cy)
		cy += 18
		box_d := rl.Rectangle{x0, cy, OP_FW, OP_FH}
		op_drag_field(app, "", v.density, box_d, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 4, mouse)
		cy += OP_FH + 8
		op_section_label(app, "Albedo R G B", lx, cy)
		cy += 18
		box_r := rl.Rectangle{x0, cy, OP_FW, OP_FH}
		box_g := rl.Rectangle{x0 + OP_COL, cy, OP_FW, OP_FH}
		box_b := rl.Rectangle{x0 + 2*OP_COL, cy, OP_FW, OP_FH}
		op_drag_field(app, "", v.albedo[0], box_r, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 5, mouse)
		op_drag_field(app, "", v.albedo[1], box_g, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 6, mouse)
		op_drag_field(app, "", v.albedo[2], box_b, st.prop_drag_idx == OP_VOLUME_SELECTED_DRAG_BASE + 7, mouse)
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
		bw := (content.width - 16 - 6) / 4.0  // 4 buttons, 3 gaps of 2
		mat_rects := [4]rl.Rectangle{
			{lx, cy, bw, 22},
			{lx + (bw + 2), cy, bw, 22},
			{lx + 2*(bw+2), cy, bw, 22},
			{lx + 3*(bw+2), cy, bw, 22},
		}
		is_lambertian := false
		is_metallic := false
		is_dielectric := false
		is_emitter := false
		#partial switch _ in quad.material {
		case rt.lambertian:   is_lambertian = true
		case rt.metallic:     is_metallic = true
		case rt.dielectric:   is_dielectric = true
		case rt.diffuse_light: is_emitter = true
		}
		op_mat_button(app, "Lambert", mat_rects[0], is_lambertian, mouse)
		op_mat_button(app, "Metal",   mat_rects[1], is_metallic,   mouse)
		op_mat_button(app, "Diel.",   mat_rects[2], is_dielectric, mouse)
		op_mat_button(app, "Emitter", mat_rects[3], is_emitter,   mouse)
		cy += 28
		op_section_label(app, is_emitter ? "EMISSION" : "COLOR", lx, cy)
		cy += 18
		x0 := lx + OP_LW + OP_GAP
		box_rgb := [3]rl.Rectangle{
			{x0, cy, OP_FW, OP_FH},
			{x0 + OP_COL, cy, OP_FW, OP_FH},
			{x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		box_param := rl.Rectangle{x0, cy + OP_FH + 6, OP_FW, OP_FH}
		col := [3]f32{0.5, 0.5, 0.5}
		emission_intensity: f32 = 1.0
		if is_emitter {
			if d, ok2 := quad.material.(rt.diffuse_light); ok2 {
				emission_intensity = max(d.emit[0], max(d.emit[1], d.emit[2]))
				if emission_intensity > 0 {
					col[0] = d.emit[0] / emission_intensity
					col[1] = d.emit[1] / emission_intensity
					col[2] = d.emit[2] / emission_intensity
				} else {
					col = {1, 1, 1}
				}
			}
		} else {
			#partial switch m in quad.material {
			case rt.lambertian:
				if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
				else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
			case rt.metallic:
				col = m.albedo
			}
		}
		op_drag_field(app, "R", col[0], box_rgb[0], st.prop_drag_idx == 20, mouse)
		op_drag_field(app, "G", col[1], box_rgb[1], st.prop_drag_idx == 21, mouse)
		op_drag_field(app, "B", col[2], box_rgb[2], st.prop_drag_idx == 22, mouse)
		cy += OP_FH + 8
		if is_emitter {
			op_section_label(app, "Intensity", lx, cy - 2)
			op_drag_field(app, "I", emission_intensity, box_param, st.prop_drag_idx == 23, mouse)
		} else if is_metallic {
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

	// ROTATION
	op_section_label(app, "ROTATION", lo.lx, lo.y_rotation)
	op_drag_field(app, "X", sphere.rotation_deg[0], lo.boxes_rotation[0], st.prop_drag_idx == 12, mouse)
	op_drag_field(app, "Y", sphere.rotation_deg[1], lo.boxes_rotation[1], st.prop_drag_idx == 13, mouse)
	op_drag_field(app, "Z", sphere.rotation_deg[2], lo.boxes_rotation[2], st.prop_drag_idx == 14, mouse)

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
	op_mat_button(app, "Light",      lo.mat_rects[3], sphere.material_kind == .DiffuseLight, mouse)
	if sphere.material_kind == .Metallic {
		op_drag_field(app, "Fz", sphere.fuzz,    lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	} else if sphere.material_kind == .Dielectric {
		op_drag_field(app, "Ir", sphere.ref_idx, lo.box_mat_param, st.prop_drag_idx == 7, mouse)
	}

	// COLOR / EMISSION
	op_section_label(app, sphere.material_kind == .DiffuseLight ? "EMISSION" : "COLOR", lo.lx, lo.y_color)

	// Texture type mini-buttons (Lambertian only)
	if lo.has_tex_btns {
		is_color  := !lo.has_noise && !lo.has_marble && !lo.has_image
		op_mat_button(app, "Color",  lo.btn_tex_color,  is_color,       mouse)
		op_mat_button(app, "Noise",  lo.btn_tex_noise,  lo.has_noise,   mouse)
		op_mat_button(app, "Marble", lo.btn_tex_marble, lo.has_marble,  mouse)
	}

	if lo.has_noise || lo.has_marble {
		// Scale drag field
		cur_scale: f32 = 4.0
		if nt, ok2 := sphere.albedo.(core.NoiseTexture);  ok2 { cur_scale = nt.scale }
		if mt, ok2 := sphere.albedo.(core.MarbleTexture); ok2 { cur_scale = mt.scale }
		op_drag_field(app, "Sc", cur_scale, lo.box_noise_scale, st.prop_drag_idx == 11, mouse)
		// Preview image (cached by noise_preview_update in update proc)
		if st.noise_preview.tex.id != 0 {
			rl.DrawTexture(st.noise_preview.tex, i32(lo.noise_preview.x), i32(lo.noise_preview.y), rl.WHITE)
			rl.DrawRectangleLinesEx(lo.noise_preview, 1, BORDER_COLOR)
		}
	} else if lo.has_image {
		// Show basename of the image path
		if it, ok2 := sphere.albedo.(core.ImageTexture); ok2 {
			base := filepath.base(it.path)
			label := fmt.ctprintf("Img: %s", base)
			draw_ui_text(app, label, i32(lo.lx), i32(lo.y_color) + 40, 10, CONTENT_TEXT_COLOR)
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
			if st.prop_drag_idx >= OP_VOLUME_DRAG_BASE && len(app.e_volumes) > 0 {
				if !lmb {
					mark_scene_dirty(app)
					ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
					app_restart_render_with_scene(app, ev.export_scratch[:])
					st.prop_drag_idx = -1
					rl.SetMouseCursor(.DEFAULT)
				} else {
					idx := (st.prop_drag_idx - OP_VOLUME_DRAG_BASE) / 4
					sub := (st.prop_drag_idx - OP_VOLUME_DRAG_BASE) % 4
					if idx >= 0 && idx < len(app.e_volumes) {
						delta := mouse.x - st.prop_drag_start_x
						switch sub {
						case 0:
							app.e_volumes[idx].density = st.prop_drag_start_val + delta * 0.002
							if app.e_volumes[idx].density < 0.0001 { app.e_volumes[idx].density = 0.0001 }
							if app.e_volumes[idx].density > 1 { app.e_volumes[idx].density = 1 }
						case 1: app.e_volumes[idx].albedo[0] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
						case 2: app.e_volumes[idx].albedo[1] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
						case 3: app.e_volumes[idx].albedo[2] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
						}
					}
					rl.SetMouseCursor(.RESIZE_EW)
				}
			} else {
				st.prop_drag_idx = -1
				rl.SetMouseCursor(.DEFAULT)
			}
			return
		}
		// Try start volume drag when nothing selected
		if len(app.e_volumes) > 0 && lmb_pressed {
			y0 := rect.y + 70 + 20
			lx := rect.x + 8
			x0 := rect.x + 8 + OP_LW + OP_GAP
			for _, i in app.e_volumes {
				box_d := rl.Rectangle{x0, y0, OP_FW, OP_FH}
				y0 += OP_FH + 2
				box_r := rl.Rectangle{x0, y0, OP_FW, OP_FH}
				box_g := rl.Rectangle{x0 + OP_COL, y0, OP_FW, OP_FH}
				box_b := rl.Rectangle{x0 + 2*OP_COL, y0, OP_FW, OP_FH}
				y0 += OP_FH + OP_SP + 8
				if op_try_start_drag(box_d, OP_VOLUME_DRAG_BASE + i*4 + 0, app.e_volumes[i].density, st, mouse, true) { return }
				if op_try_start_drag(box_r, OP_VOLUME_DRAG_BASE + i*4 + 1, app.e_volumes[i].albedo[0], st, mouse, true) { return }
				if op_try_start_drag(box_g, OP_VOLUME_DRAG_BASE + i*4 + 2, app.e_volumes[i].albedo[1], st, mouse, true) { return }
				if op_try_start_drag(box_b, OP_VOLUME_DRAG_BASE + i*4 + 3, app.e_volumes[i].albedo[2], st, mouse, true) { return }
			}
		}
		return
	}

	// ── Volume selected: drag OP_VOLUME_SELECTED_DRAG_BASE+0..7 → translate, rotate_y, density, albedo
	if ev.selection_kind == .Volume && ev.selected_idx >= 0 && ev.selected_idx < len(app.e_volumes) {
		idx := ev.selected_idx
		v := &app.e_volumes[idx]
		if st.prop_drag_idx >= OP_VOLUME_SELECTED_DRAG_BASE && st.prop_drag_idx <= OP_VOLUME_SELECTED_DRAG_BASE + 8 {
			if !lmb {
				edit_history_push(&app.edit_history, ModifyVolumeAction{
					idx = idx, before = st.drag_before_volume, after = app.e_volumes[idx],
				})
				mark_scene_dirty(app)
				ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
				app_restart_render_with_scene(app, ev.export_scratch[:])
				st.prop_drag_idx = -1
				rl.SetMouseCursor(.DEFAULT)
			} else {
				delta := mouse.x - st.prop_drag_start_x
				sub := st.prop_drag_idx - OP_VOLUME_SELECTED_DRAG_BASE
				switch sub {
				case 0: v.translate[0] = st.prop_drag_start_val + delta * 0.02
				case 1: v.translate[1] = st.prop_drag_start_val + delta * 0.02
				case 2: v.translate[2] = st.prop_drag_start_val + delta * 0.02
				case 3: v.rotate_y_deg = st.prop_drag_start_val + delta * 0.2
				case 4:
					v.density = st.prop_drag_start_val + delta * 0.002
					if v.density < 0.0001 { v.density = 0.0001 }
					if v.density > 1 { v.density = 1 }
				case 5: v.albedo[0] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
				case 6: v.albedo[1] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
				case 7: v.albedo[2] = clamp(st.prop_drag_start_val + delta*0.005, 0, 1)
				case 8:
					new_scale := st.prop_drag_start_val + delta * 0.02
					if new_scale < 0.01 { new_scale = 0.01 }
					center := (v.box_min + v.box_max) * 0.5
					half := (v.box_max - v.box_min) * 0.5
					old_scale := (half[0] + half[1] + half[2]) / 3.0
					if old_scale < 1e-6 { old_scale = 1e-6 }
					factor := new_scale / old_scale
					v.box_min[0] = center[0] - half[0] * factor
					v.box_min[1] = center[1] - half[1] * factor
					v.box_min[2] = center[2] - half[2] * factor
					v.box_max[0] = center[0] + half[0] * factor
					v.box_max[1] = center[1] + half[1] * factor
					v.box_max[2] = center[2] + half[2] * factor
				}
				rl.SetMouseCursor(.RESIZE_EW)
			}
			return
		}
		if lmb_pressed {
			lx := rect.x + 8
			cy := rect.y + 6 + 20 + 18
			x0 := lx + OP_LW + OP_GAP
			box_tx := rl.Rectangle{x0, cy, OP_FW, OP_FH}
			box_ty := rl.Rectangle{x0 + OP_COL, cy, OP_FW, OP_FH}
			box_tz := rl.Rectangle{x0 + 2*OP_COL, cy, OP_FW, OP_FH}
			cy += OP_FH + 8 + 18
			box_rot := rl.Rectangle{x0, cy, OP_FW, OP_FH}
			cy += OP_FH + 8 + 18
			volume_scale_val := (v.box_max[0] - v.box_min[0] + v.box_max[1] - v.box_min[1] + v.box_max[2] - v.box_min[2]) / 3.0
			box_scale := rl.Rectangle{x0, cy, OP_FW, OP_FH}
			cy += OP_FH + 8 + 18
			box_d := rl.Rectangle{x0, cy, OP_FW, OP_FH}
			cy += OP_FH + 8 + 18
			box_r := rl.Rectangle{x0, cy, OP_FW, OP_FH}
			box_g := rl.Rectangle{x0 + OP_COL, cy, OP_FW, OP_FH}
			box_b := rl.Rectangle{x0 + 2*OP_COL, cy, OP_FW, OP_FH}
			if op_try_start_drag(box_tx, OP_VOLUME_SELECTED_DRAG_BASE + 0, v.translate[0], st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_ty, OP_VOLUME_SELECTED_DRAG_BASE + 1, v.translate[1], st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_tz, OP_VOLUME_SELECTED_DRAG_BASE + 2, v.translate[2], st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_rot, OP_VOLUME_SELECTED_DRAG_BASE + 3, v.rotate_y_deg, st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_scale, OP_VOLUME_SELECTED_DRAG_BASE + 8, volume_scale_val, st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_d, OP_VOLUME_SELECTED_DRAG_BASE + 4, v.density, st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_r, OP_VOLUME_SELECTED_DRAG_BASE + 5, v.albedo[0], st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_g, OP_VOLUME_SELECTED_DRAG_BASE + 6, v.albedo[1], st, mouse, true) { st.drag_before_volume = v^; return }
			if op_try_start_drag(box_b, OP_VOLUME_SELECTED_DRAG_BASE + 7, v.albedo[2], st, mouse, true) { st.drag_before_volume = v^; return }
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
		bw := (rect.width - 16 - 6) / 4.0
		mat_rects := [4]rl.Rectangle{
			{lx, cy, bw, 22},
			{lx + (bw + 2), cy, bw, 22},
			{lx + 2*(bw+2), cy, bw, 22},
			{lx + 3*(bw+2), cy, bw, 22},
		}
		cy += 28
		cy += 18
		x0 := lx + OP_LW + OP_GAP
		box_rgb := [3]rl.Rectangle{
			{x0, cy, OP_FW, OP_FH},
			{x0 + OP_COL, cy, OP_FW, OP_FH},
			{x0 + 2*OP_COL, cy, OP_FW, OP_FH},
		}
		box_param := rl.Rectangle{x0, cy + OP_FH + 6, OP_FW, OP_FH}

		is_emitter := false
		if _, ok2 := quad.material.(rt.diffuse_light); ok2 { is_emitter = true }

		if st.prop_drag_idx >= 0 && st.prop_drag_idx >= 20 && st.prop_drag_idx <= 23 {
			if !lmb {
				st.prop_drag_idx = -1
				rl.SetMouseCursor(.DEFAULT)
			} else {
				delta := mouse.x - st.prop_drag_start_x
				if is_emitter {
					d := quad.material.(rt.diffuse_light)
					intensity := max(d.emit[0], max(d.emit[1], d.emit[2]))
					if intensity <= 0 { intensity = 1.0 }
					col := [3]f32{d.emit[0] / intensity, d.emit[1] / intensity, d.emit[2] / intensity}
					switch st.prop_drag_idx {
					case 20:
						col[0] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 21:
						col[1] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 22:
						col[2] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 23:
						intensity = clamp(st.prop_drag_start_val + delta * 0.02, 0.0, 50.0)
					}
					quad.material = rt.diffuse_light{emit = {col[0] * intensity, col[1] * intensity, col[2] * intensity}}
					SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
					mark_scene_dirty(app)
				} else {
					col := [3]f32{0.5, 0.5, 0.5}
					#partial switch m in quad.material {
					case rt.lambertian:
						if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
						else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
					case rt.metallic: col = m.albedo
					}
					switch st.prop_drag_idx {
					case 20:
						col[0] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 21:
						col[1] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 22:
						col[2] = clamp(st.prop_drag_start_val + delta * 0.005, 0.0, 1.0)
					case 23:
						if m, is_metal := quad.material.(rt.metallic); is_metal {
							fz := clamp(st.prop_drag_start_val + delta * 0.002, 0.0, 1.0)
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
			if rl.CheckCollisionPointRec(mouse, mat_rects[3]) {
				quad.material = rt.diffuse_light{emit = {2, 2, 2}}
				SetSceneQuad(ev.scene_mgr, ev.selected_idx, quad)
				mark_scene_dirty(app)
				app_push_log(app, strings.clone("Quad: Emitter"))
				return
			}
		}
		col := [3]f32{0.5, 0.5, 0.5}
		param_val: f32 = 0.1
		if is_emitter {
			if d, ok2 := quad.material.(rt.diffuse_light); ok2 {
				param_val = max(d.emit[0], max(d.emit[1], d.emit[2]))
				if param_val > 0 {
					col[0] = d.emit[0] / param_val
					col[1] = d.emit[1] / param_val
					col[2] = d.emit[2] / param_val
				} else {
					col = {1, 1, 1}
				}
			} else {
				param_val = 2.0
			}
		} else {
			#partial switch m in quad.material {
			case rt.lambertian:
				if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
				else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
			case rt.metallic: col = m.albedo
			}
			if m, ok2 := quad.material.(rt.metallic); ok2 { param_val = m.fuzz }
			else if d, ok2 := quad.material.(rt.dielectric); ok2 { param_val = d.ref_idx }
		}
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
			case 11:
				new_scale := max(st.prop_drag_start_val + delta * 0.02, f32(0.1))
				switch a in sphere.albedo {
				case core.NoiseTexture:     sphere.albedo = core.NoiseTexture{scale = new_scale}
				case core.MarbleTexture:    sphere.albedo = core.MarbleTexture{scale = new_scale}
				case core.ConstantTexture:  {}
				case core.CheckerTexture:   {}
				case core.ImageTexture:     {}
				}
			case 12: sphere.rotation_deg[0] = st.prop_drag_start_val + delta * 0.5
			case 13: sphere.rotation_deg[1] = st.prop_drag_start_val + delta * 0.5
			case 14: sphere.rotation_deg[2] = st.prop_drag_start_val + delta * 0.5
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
		if rl.CheckCollisionPointRec(mouse, lo.mat_rects[3]) {
			before := sphere
			sphere.material_kind = .DiffuseLight
			// Ensure albedo is set for emission (default white if not already constant)
			if _, ok := sphere.albedo.(core.ConstantTexture); !ok {
				sphere.albedo = core.ConstantTexture{color = {1, 1, 1}}
			}
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
			edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
			mark_scene_dirty(app)
			app_push_log(app, strings.clone("Material: Light"))
			if g_app != nil { g_app.input_consumed = true }
			return
		}

		// ── Texture type buttons (Lambertian only)
		if sphere.material_kind == .Lambertian && lo.has_tex_btns {
			if rl.CheckCollisionPointRec(mouse, lo.btn_tex_color) {
				if _, ok3 := sphere.albedo.(core.ConstantTexture); !ok3 {
					before := sphere
					sphere.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
					sphere.texture_kind = .Constant
					sphere.image_path = ""
					SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
					edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Texture: Solid"))
				}
				if g_app != nil { g_app.input_consumed = true }
				return
			}
			if rl.CheckCollisionPointRec(mouse, lo.btn_tex_noise) {
				if _, ok3 := sphere.albedo.(core.NoiseTexture); !ok3 {
					before := sphere
					sphere.albedo = core.NoiseTexture{scale = 4.0}
					sphere.texture_kind = .Constant
					sphere.image_path = ""
					SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
					edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Texture: Noise"))
				}
				if g_app != nil { g_app.input_consumed = true }
				return
			}
			if rl.CheckCollisionPointRec(mouse, lo.btn_tex_marble) {
				if _, ok3 := sphere.albedo.(core.MarbleTexture); !ok3 {
					before := sphere
					sphere.albedo = core.MarbleTexture{scale = 4.0}
					sphere.texture_kind = .Constant
					sphere.image_path = ""
					SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
					edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
					mark_scene_dirty(app)
					app_push_log(app, strings.clone("Texture: Marble"))
				}
				if g_app != nil { g_app.input_consumed = true }
				return
			}
		}

		// ── Browse Image button (Lambertian only)
		if sphere.material_kind == .Lambertian && rl.CheckCollisionPointRec(mouse, lo.btn_browse) {
			default_dir := util.dialog_default_dir(app.current_scene_path)
			img_path, ok2 := util.open_file_dialog(default_dir, util.IMAGE_FILTER_DESC, util.IMAGE_FILTER_EXT)
			delete(default_dir)
			if ok2 {
				before := sphere
				sphere.albedo = core.ImageTexture{path = img_path}
				sphere.texture_kind = .Image
				sphere.image_path = img_path
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
			sphere.texture_kind = .Constant
			sphere.image_path = ""
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
	// Rotation drag (drag indices 12, 13, 14)
	if op_try_start_drag(lo.boxes_rotation[0], 12, sphere.rotation_deg[0], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_rotation[1], 13, sphere.rotation_deg[1], st, mouse, lmb_pressed) { any_hovered = true }
	if op_try_start_drag(lo.boxes_rotation[2], 14, sphere.rotation_deg[2], st, mouse, lmb_pressed) { any_hovered = true }
	// Noise/Marble scale drag (drag index 11)
	if lo.has_noise || lo.has_marble {
		noise_scale: f32 = 4.0
		if nt, ok := sphere.albedo.(core.NoiseTexture);  ok { noise_scale = nt.scale }
		if mt, ok := sphere.albedo.(core.MarbleTexture); ok { noise_scale = mt.scale }
		if op_try_start_drag(lo.box_noise_scale, 11, noise_scale, st, mouse, lmb_pressed) { any_hovered = true }
	}
	// RGB drag only when not an image texture and not a procedural texture
	if !lo.has_image && !lo.has_noise && !lo.has_marble {
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
	// Update noise preview cache when active
	if lo.has_noise || lo.has_marble {
		cur_scale: f32 = 4.0
		if nt, ok := sphere.albedo.(core.NoiseTexture);  ok { cur_scale = nt.scale }
		if mt, ok := sphere.albedo.(core.MarbleTexture); ok { cur_scale = mt.scale }
		noise_preview_update(&st.noise_preview, lo.has_marble, cur_scale)
	} else {
		noise_preview_unload(&st.noise_preview)
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
