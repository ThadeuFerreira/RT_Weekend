package editor

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

// calculate_render_dimensions computes width and height from app settings.
// Returns false if dimensions are out of bounds (16k max, 720p min).
calculate_render_dimensions :: proc(app: ^App) -> (width, height: int, ok: bool) {
    h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
    if !h_ok || h <= 0 {
        return 0, 0, false
    }

    aspect: f32
    if app.r_aspect_ratio == 0 {
        aspect = 4.0 / 3.0
    } else {
        aspect = 16.0 / 9.0
    }
    w := int(f32(h) * aspect)

    // Check bounds (16k max, 720p min)
    if h < MIN_RENDER_HEIGHT || h > MAX_RENDER_HEIGHT {
        return w, h, false
    }
    if w < MIN_RENDER_WIDTH || w > MAX_RENDER_WIDTH {
        return w, h, false
    }

    return w, h, true
}

EDIT_TOOLBAR_H :: f32(32)
EDIT_PROPS_H   :: f32(90)

// Selection kind: none, a sphere (index in objects), or the render camera (non-deletable).
EditViewSelectionKind :: enum {
	None,
	Sphere,
	Camera,
}

EditViewState :: struct {
	// Off-screen 3D viewport
	viewport_tex: rl.RenderTexture2D,
	tex_w, tex_h: i32,

	// Raylib 3D camera (recomputed every frame from orbit params)
	cam3d: rl.Camera3D,

	// Orbit camera parameters
	orbit_yaw:      f32,
	orbit_pitch:    f32,
	orbit_distance: f32,
	orbit_target:   rl.Vector3,

	// Right-drag orbit state
	rmb_held:   bool,
	last_mouse: rl.Vector2,

	// Scene manager (holds scene spheres for now; adapter for future polymorphism)
	scene_mgr:      ^SceneManager,
	export_scratch: [dynamic]core.SceneSphere, // reused by ExportToSceneSpheres callers; no per-frame alloc
	selection_kind: EditViewSelectionKind,      // what is selected
	selected_idx:   int,                   // when Sphere: index into objects; else -1

	// Drag-float property fields (sphere only)
	// prop_drag_idx: -1=none  0=cx  1=cy  2=cz  3=radius
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Viewport left-drag to move selected object (sphere only)
	drag_obj_active: bool,
	drag_plane_y:    f32,    // Y of the horizontal movement plane
	drag_offset_xz:  [2]f32, // grab-point offset in world XZ so the object doesn't snap
	drag_before:     core.SceneSphere, // sphere state captured at viewport-drag start

	// Keyboard nudge history tracking
	nudge_active: bool,             // true while any nudge key is held
	nudge_before: core.SceneSphere, // sphere state captured at first nudge keydown

	initialized: bool,
}

init_edit_view :: proc(ev: ^EditViewState) {
	ev.orbit_yaw      = 0.5
	ev.orbit_pitch    = 0.3
	ev.orbit_distance = 15.0
	ev.orbit_target   = rl.Vector3{0, 0, 0}
	ev.selection_kind = .None
	ev.selected_idx   = -1
	ev.prop_drag_idx  = -1

	// initialize scene manager and seed with a few spheres
	ev.scene_mgr = new_scene_manager()
	ev.export_scratch = make([dynamic]core.SceneSphere)
	initial := make([dynamic]core.SceneSphere)
	append(&initial, core.SceneSphere{center = {-3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.8, 0.2, 0.2}})
	append(&initial, core.SceneSphere{center = { 0, 0.5, 0}, radius = 0.5, material_kind = .Metallic, albedo = {0.2, 0.2, 0.8}, fuzz = 0.1})
	append(&initial, core.SceneSphere{center = { 3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = {0.2, 0.8, 0.2}})
LoadFromSceneSpheres(ev.scene_mgr, initial[:])
	delete(initial)

	update_orbit_camera(ev)
	ev.initialized = true
}

update_orbit_camera :: proc(ev: ^EditViewState) {
	pitch := ev.orbit_pitch
	if pitch >  math.PI * 0.45 { pitch =  math.PI * 0.45 }
	if pitch < -math.PI * 0.45 { pitch = -math.PI * 0.45 }
	ev.orbit_pitch = pitch

	dist := ev.orbit_distance
	if dist < 1.0 { dist = 1.0 }
	ev.orbit_distance = dist

	t := ev.orbit_target
	pos := rl.Vector3{
		t.x + dist * math.cos(pitch) * math.sin(ev.orbit_yaw),
		t.y + dist * math.sin(pitch),
		t.z + dist * math.cos(pitch) * math.cos(ev.orbit_yaw),
	}

	ev.cam3d = rl.Camera3D{
		position   = pos,
		target     = t,
		up         = rl.Vector3{0, 1, 0},
		fovy       = 45.0,
		projection = .PERSPECTIVE,
	}
}

// get_orbit_camera_pose returns lookfrom and lookat for the current orbit (for translating to path-tracer camera).
get_orbit_camera_pose :: proc(ev: ^EditViewState) -> (lookfrom, lookat: [3]f32) {
	pitch := ev.orbit_pitch
	dist  := ev.orbit_distance
	t     := ev.orbit_target
	lookat = {t.x, t.y, t.z}
	lookfrom = {
		t.x + dist * math.cos(pitch) * math.sin(ev.orbit_yaw),
		t.y + dist * math.sin(pitch),
		t.z + dist * math.cos(pitch) * math.cos(ev.orbit_yaw),
	}
	return
}

// compute_viewport_ray casts a perspective ray through the given mouse position.
// When require_inside=true (default) returns false if mouse is outside vp_rect.
// When require_inside=false the UV is clamped to viewport edges — useful during
// active drags where the mouse may wander outside the panel.
// NOTE: viewport / picking helpers were moved into the editor package so they
// can be shared by object implementations without creating package cycles.

draw_viewport_3d :: proc(app: ^App, vp_rect: rl.Rectangle, objs: []core.SceneSphere) {
	ev := &app.e_edit_view
	new_w := i32(vp_rect.width)
	new_h := i32(vp_rect.height)

	if new_w != ev.tex_w || new_h != ev.tex_h {
		if ev.tex_w > 0 { rl.UnloadRenderTexture(ev.viewport_tex) }
		if new_w > 0 && new_h > 0 {
			ev.viewport_tex = rl.LoadRenderTexture(new_w, new_h)
		}
		ev.tex_w = new_w
		ev.tex_h = new_h
	}

	if ev.tex_w <= 0 || ev.tex_h <= 0 { return }

	rl.BeginTextureMode(ev.viewport_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(ev.cam3d)
	rl.DrawGrid(20, 1.0)

	for i in 0..<len(objs) {
		s      := objs[i]
		center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		col: rl.Color
		if ev.selection_kind == .Sphere && i == ev.selected_idx {
			col = rl.YELLOW
		} else {
			col = rl.Color{u8(s.albedo[0]*255), u8(s.albedo[1]*255), u8(s.albedo[2]*255), 255}
		}
		rl.DrawSphere(center, s.radius, col)
		rl.DrawSphereWires(center, s.radius, 8, 8, rl.Color{30, 30, 30, 180})
	}

	// Render camera gizmo: bright pink square base + pyramid (lens) fused, camera-shaped
	cp := &app.c_camera_params
	cam_pos := rl.Vector3{cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
	cam_at  := rl.Vector3{cp.lookat[0], cp.lookat[1], cp.lookat[2]}
	vup     := rl.Vector3{cp.vup[0], cp.vup[1], cp.vup[2]}
	fwd     := rl.Vector3Normalize(cam_at - cam_pos)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(fwd, vup))
	up      := rl.Vector3CrossProduct(right, fwd)
	hw, hh, apex_len := f32(0.14), f32(0.10), f32(0.35)
	c0 := cam_pos - right*hw - up*hh
	c1 := cam_pos + right*hw - up*hh
	c2 := cam_pos + right*hw + up*hh
	c3 := cam_pos - right*hw + up*hh
	apex := cam_pos + fwd * apex_len
	cam_col := ev.selection_kind == .Camera ? rl.YELLOW : rl.Color{255, 105, 180, 255}
	wire_col := ev.selection_kind == .Camera ? rl.Color{220, 200, 0, 200} : rl.Color{180, 80, 120, 200}
	rl.DrawTriangle3D(c0, c1, apex, cam_col)
	rl.DrawTriangle3D(c1, c2, apex, cam_col)
	rl.DrawTriangle3D(c2, c3, apex, cam_col)
	rl.DrawTriangle3D(c3, c0, apex, cam_col)
	rl.DrawTriangle3D(c0, c1, c2, cam_col)
	rl.DrawTriangle3D(c0, c2, c3, cam_col)
	rl.DrawLine3D(c0, c1, wire_col)
	rl.DrawLine3D(c1, c2, wire_col)
	rl.DrawLine3D(c2, c3, wire_col)
	rl.DrawLine3D(c3, c0, wire_col)
	rl.DrawLine3D(c0, apex, wire_col)
	rl.DrawLine3D(c1, apex, wire_col)
	rl.DrawLine3D(c2, apex, wire_col)
	rl.DrawLine3D(c3, apex, wire_col)

	// Draw a move indicator on the selected sphere during drag
	if ev.drag_obj_active && ev.selection_kind == .Sphere && ev.selected_idx >= 0 {
		if ev.selected_idx >= 0 && ev.selected_idx < len(objs) {
			s := objs[ev.selected_idx]
			c := rl.Vector3{s.center[0], s.center[1], s.center[2]}
			rl.DrawCircle3D(c, s.radius + 0.08, rl.Vector3{1, 0, 0}, 90, rl.Color{255, 220, 0, 200})
		}
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	src := rl.Rectangle{0, 0, f32(ev.tex_w), -f32(ev.tex_h)}
	rl.DrawTexturePro(ev.viewport_tex.texture, src, vp_rect, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}

// ── Property strip ─────────────────────────────────────────────────────────

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
draw_drag_field :: proc(label: cstring, value: f32, box: rl.Rectangle, active: bool, mouse: rl.Vector2) {
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
	draw_ui_text(g_app, fmt.ctprintf("%.3f", value), i32(box.x) + 5, i32(box.y) + 4, 11, CONTENT_TEXT_COLOR)
	// Label to the left
	draw_ui_text(g_app, label, i32(box.x) - i32(PROP_LW + PROP_GAP) + 2, i32(box.y) + 4, 12, CONTENT_TEXT_COLOR)
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

	if ev.selection_kind == .Camera {
		draw_ui_text(app, "Camera selected (non-deletable)",
			i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Edit position, target, and options in the Object Properties panel.",
			i32(rect.x) + 8, i32(rect.y) + 30, 11, rl.Color{140, 150, 165, 200})
		return
	}

	// Sphere selected
	if ev.selected_idx < 0 || ev.selected_idx >= len(objs) { return }
	s      := objs[ev.selected_idx]
	fields := prop_field_rects(rect)

	// Row 0 — position X Y Z
	draw_drag_field("X", s.center[0], fields[0], ev.prop_drag_idx == 0, mouse)
	draw_drag_field("Y", s.center[1], fields[1], ev.prop_drag_idx == 1, mouse)
	draw_drag_field("Z", s.center[2], fields[2], ev.prop_drag_idx == 2, mouse)

	// Row 1 — radius + material label
	draw_drag_field("R", s.radius, fields[3], ev.prop_drag_idx == 3, mouse)

	mat_name  := material_name(s.material_kind)
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

// ── Panel draw ─────────────────────────────────────────────────────────────

draw_edit_view_content :: proc(app: ^App, content: rl.Rectangle) {
	ev    := &app.e_edit_view
	mouse := rl.GetMousePosition()

	// Toolbar
	toolbar_rect := rl.Rectangle{content.x, content.y, content.width, EDIT_TOOLBAR_H}
	rl.DrawRectangleRec(toolbar_rect, rl.Color{40, 42, 58, 255})
	rl.DrawRectangleLinesEx(toolbar_rect, 1, BORDER_COLOR)

	btn_add   := rl.Rectangle{content.x + 8, content.y + 5, 90, 22}
	add_hover := rl.CheckCollisionPointRec(mouse, btn_add)
	rl.DrawRectangleRec(btn_add, add_hover ? rl.Color{80, 130, 200, 255} : rl.Color{55, 85, 140, 255})
	draw_ui_text(app, "Add Sphere", i32(btn_add.x) + 6, i32(btn_add.y) + 4, 12, rl.RAYWHITE)

	// Delete only for sphere selection (camera is non-deletable)
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 {
		btn_del   := rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
		del_hover := rl.CheckCollisionPointRec(mouse, btn_del)
		rl.DrawRectangleRec(btn_del, del_hover ? rl.Color{200, 60, 60, 255} : rl.Color{140, 40, 40, 255})
		draw_ui_text(app, "Delete", i32(btn_del.x) + 8, i32(btn_del.y) + 4, 12, rl.RAYWHITE)
	}

	btn_render   := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	render_busy  := !app.finished
	render_ready := app.finished && app.r_render_pending
	render_hover := !render_busy && rl.CheckCollisionPointRec(mouse, btn_render)

	// Button color: bright green when render is pending, normal when not, dim when busy
	btn_color: rl.Color
	if render_busy {
		btn_color = rl.Color{45, 75, 45, 200}
	} else if render_ready {
		btn_color = rl.Color{80, 220, 80, 255} // bright green when pending
	} else if render_hover {
		btn_color = rl.Color{80, 190, 80, 255}
	} else {
		btn_color = rl.Color{50, 140, 50, 255}
	}
	rl.DrawRectangleRec(btn_render, btn_color)

	btn_text := render_busy ? cstring("Rendering…") : (render_ready ? cstring("Render*") : cstring("Render"))
	draw_ui_text(app, btn_text, i32(btn_render.x) + 6, i32(btn_render.y) + 4, 12, rl.RAYWHITE)

	// 3D viewport
	vp_rect := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
	draw_viewport_3d(app, vp_rect, ev.export_scratch[:])

	// Properties strip
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}
	draw_edit_properties(app, props_rect, mouse, ev.export_scratch[:])
}

// ── Panel update ───────────────────────────────────────────────────────────

update_edit_view_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev      := &app.e_edit_view
	content := rect

	// Orbit camera is always updated at the end, even on early return.
	defer update_orbit_camera(ev)

	// Shared rects (mirror draw proc)
	btn_add    := rl.Rectangle{content.x + 8,                    content.y + 5, 90, 22}
	btn_del    := rl.Rectangle{content.x + 106,                  content.y + 5, 60, 22}
	btn_render := rl.Rectangle{content.x + content.width - 90,   content.y + 5, 82, 22}
	vp_rect    := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}

	// ── Priority 1: active property-field drag (sphere only) ─────────────
	if ev.prop_drag_idx >= 0 {
		if !lmb {
			ev.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			delta := mouse.x - ev.prop_drag_start_x
			if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				switch ev.prop_drag_idx {
				case 0: s.center[0] = ev.prop_drag_start_val + delta * 0.01
				case 1: s.center[1] = ev.prop_drag_start_val + delta * 0.01
				case 2: s.center[2] = ev.prop_drag_start_val + delta * 0.01
				case 3:
					s.radius = ev.prop_drag_start_val + delta * 0.005
					if s.radius < 0.05 { s.radius = 0.05 }
				}
SetSceneSphere(ev.scene_mgr, ev.selected_idx, s)
			}
		}
		return
	}

	// ── Priority 2: active viewport object drag (sphere only) ─────────────
	if ev.drag_obj_active {
		if !lmb {
			ev.drag_obj_active = false
			// Commit drag to history
			if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
				if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
					edit_history_push(&app.edit_history, ModifySphereAction{
						idx    = ev.selected_idx,
						before = ev.drag_before,
						after  = s,
					})
					app_push_log(app, strings.clone("Move sphere"))
					app.r_render_pending = true
				}
			}
		} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			// require_inside=false: keep dragging even when mouse leaves viewport
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
						s.center[0]  = xz.x - ev.drag_offset_xz[0]
						s.center[2]  = xz.y - ev.drag_offset_xz[1]
SetSceneSphere(ev.scene_mgr, ev.selected_idx, s)
					}
				}
			}
		}
		return
	}

	// ── Toolbar buttons ─────────────────────────────────────────────────
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, btn_add) {
AppendDefaultSphere(ev.scene_mgr)
			new_idx := SceneManagerLen(ev.scene_mgr) - 1
			ev.selection_kind = .Sphere
			ev.selected_idx   = new_idx
			// Record add in history
			if new_sphere, ok := GetSceneSphere(ev.scene_mgr, new_idx); ok {
				edit_history_push(&app.edit_history, AddSphereAction{idx = new_idx, sphere = new_sphere})
				app_push_log(app, strings.clone("Add sphere"))
			}
			app.r_render_pending = true
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		// Delete only for sphere (camera is non-deletable)
		if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, btn_del) {
			del_idx := ev.selected_idx
			if del_sphere, ok := GetSceneSphere(ev.scene_mgr, del_idx); ok {
				edit_history_push(&app.edit_history, DeleteSphereAction{idx = del_idx, sphere = del_sphere})
				app_push_log(app, strings.clone("Delete sphere"))
			}
OrderedRemove(ev.scene_mgr, del_idx)
			ev.selection_kind = .None
			ev.selected_idx   = -1
			app.r_render_pending = true
			return
		}
		if app.finished && rl.CheckCollisionPointRec(mouse, btn_render) {
			// Copy orbit view to camera params
			lookfrom, lookat := get_orbit_camera_pose(ev)
			app.c_camera_params.lookfrom = lookfrom
			app.c_camera_params.lookat   = lookat
			app.c_camera_params.vup      = [3]f32{0, 1, 0}

			// Export scene
			ExportToSceneSpheres(ev.scene_mgr, &ev.export_scratch)
			delete(app.r_world)
			app.r_world = rt.build_world_from_scene(ev.export_scratch[:])

			// Parse render settings
			width, height, res_ok := calculate_render_dimensions(app)
			samples, samp_ok := strconv.parse_int(app.r_samples_input)

			if !res_ok {
				// Check if it's a parse error or bounds error
				h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
				if !h_ok || h <= 0 {
					app_push_log(app, strings.clone("Invalid height. Must be a positive integer."))
				} else {
					// Bounds error
					if h < MIN_RENDER_HEIGHT {
						app_push_log(app, fmt.aprintf("Warning: Height %d below minimum (%d)", h, MIN_RENDER_HEIGHT))
					} else if h > MAX_RENDER_HEIGHT {
						app_push_log(app, fmt.aprintf("Warning: Height %d exceeds maximum (%d)", h, MAX_RENDER_HEIGHT))
					}
					if width < MIN_RENDER_WIDTH {
						app_push_log(app, fmt.aprintf("Warning: Width %d below minimum (%d)", width, MIN_RENDER_WIDTH))
					} else if width > MAX_RENDER_WIDTH {
						app_push_log(app, fmt.aprintf("Warning: Width %d exceeds maximum (%d)", width, MAX_RENDER_WIDTH))
					}
				}
			} else if !samp_ok || samples <= 0 {
				app_push_log(app, strings.clone("Invalid samples count. Must be a positive integer."))
			} else {
				restart_render_with_settings(app, width, height, samples)
			}

			if g_app != nil { g_app.input_consumed = true }
			return
		}
	}
	// "From view" copies orbit into camera_params so Render uses current orbit view
	// Removed - now integrated into render button behavior

	// ── Property drag-field: start drag on click (sphere only) ───────────
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, props_rect) {
		fields := prop_field_rects(props_rect)
		if tmp, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			vals := [4]f32{ tmp.center[0], tmp.center[1], tmp.center[2], tmp.radius }
			// Hover cursor
			any_hovered := false
			for i in 0..<4 {
				if rl.CheckCollisionPointRec(mouse, fields[i]) {
					any_hovered = true
				if lmb_pressed {
					ev.prop_drag_idx       = i
					ev.prop_drag_start_x   = mouse.x
					ev.prop_drag_start_val = vals[i]
					rl.SetMouseCursor(.RESIZE_EW)
					app.r_render_pending = true
					return
				}
				}
			}
			if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else { rl.SetMouseCursor(.DEFAULT) }
		}
		// (handled above)
	} else {
		rl.SetMouseCursor(.DEFAULT)
	}

	// ── Viewport: orbit, zoom, select, drag-start ───────────────────────
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, vp_rect)

	// Right-mouse orbit
	rmb := rl.IsMouseButtonDown(.RIGHT)
	if rmb {
		if ev.rmb_held {
			delta          := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			ev.orbit_yaw   += delta.x  * 0.005
			ev.orbit_pitch += -delta.y * 0.005
		} else if mouse_in_vp {
			ev.rmb_held = true
		}
		ev.last_mouse = mouse
	} else {
		ev.rmb_held = false
	}

	// Scroll zoom
	if mouse_in_vp {
		ev.orbit_distance -= rl.GetMouseWheelMove() * 0.8
	}

	// Left-click: select sphere or camera (sphere first, then camera)
	if lmb_pressed && mouse_in_vp {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect); ok {
			picked_sphere := PickSphereInManager(ev.scene_mgr, ray)
			if picked_sphere >= 0 {
				ev.selection_kind  = .Sphere
				ev.selected_idx    = picked_sphere
				ev.drag_obj_active = true
				if s, ok := GetSceneSphere(ev.scene_mgr, picked_sphere); ok {
					ev.drag_before     = s  // capture before state for history
					ev.drag_plane_y    = s.center[1]
					if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
						ev.drag_offset_xz = {
							xz.x - s.center[0],
							xz.y - s.center[2],
						}
					}
				}
			} else if pick_camera(ray, app.c_camera_params.lookfrom) {
				ev.selection_kind  = .Camera
				ev.selected_idx    = -1
				ev.drag_obj_active = false
			} else {
				ev.selection_kind  = .None
				ev.selected_idx    = -1
				ev.drag_obj_active = false
			}
		}
	}

	// Keyboard nudge (sphere only)
	MOVE_SPEED   :: f32(0.05)
	RADIUS_SPEED :: f32(0.02)
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		any_nudge :=
			rl.IsKeyDown(.W)     || rl.IsKeyDown(.UP)          ||
			rl.IsKeyDown(.S)     || rl.IsKeyDown(.DOWN)        ||
			rl.IsKeyDown(.A)     || rl.IsKeyDown(.LEFT)        ||
			rl.IsKeyDown(.D)     || rl.IsKeyDown(.RIGHT)       ||
			rl.IsKeyDown(.Q)     || rl.IsKeyDown(.E)           ||
			rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD)      ||
			rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT)

		// Capture before-state on first keydown of a nudge session
		if any_nudge && !ev.nudge_active {
			ev.nudge_active = true
			if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				ev.nudge_before = s
			}
		}

		if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    { s.center[2] -= MOVE_SPEED }
			if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  { s.center[2] += MOVE_SPEED }
			if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  { s.center[0] -= MOVE_SPEED }
			if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { s.center[0] += MOVE_SPEED }
			if rl.IsKeyDown(.Q)                         { s.center[1] -= MOVE_SPEED }
			if rl.IsKeyDown(.E)                         { s.center[1] += MOVE_SPEED }
			if rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD) {
				s.radius += RADIUS_SPEED
			}
			if rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) {
				s.radius -= RADIUS_SPEED
				if s.radius < 0.05 { s.radius = 0.05 }
			}
SetSceneSphere(ev.scene_mgr, ev.selected_idx, s)
		}

		// Commit nudge to history when all keys released
		if !any_nudge && ev.nudge_active {
			ev.nudge_active = false
			if s, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				edit_history_push(&app.edit_history, ModifySphereAction{
					idx    = ev.selected_idx,
					before = ev.nudge_before,
					after  = s,
				})
				app_push_log(app, strings.clone("Nudge sphere"))
				app.r_render_pending = true
			}
		}
	} else {
		// Selection lost — clear nudge state without pushing (nothing to commit)
		ev.nudge_active = false
	}
}
