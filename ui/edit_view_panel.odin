package ui

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

EDIT_TOOLBAR_H :: f32(32)
EDIT_PROPS_H   :: f32(90)

EditSphere :: struct {
	center:   [3]f32, // world position
	radius:   f32,
	mat_type: int,    // 0=lambertian, 1=metallic, 2=dielectric
	color:    [3]f32, // albedo/base color
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

	// Scene
	objects:      [dynamic]EditSphere,
	selected_idx: int, // -1 = nothing selected

	// Drag-float property fields
	// prop_drag_idx: -1=none  0=cx  1=cy  2=cz  3=radius
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Viewport left-drag to move selected object
	drag_obj_active: bool,
	drag_plane_y:    f32,    // Y of the horizontal movement plane
	drag_offset_xz:  [2]f32, // grab-point offset in world XZ so the object doesn't snap

	initialized: bool,
}

init_edit_view :: proc(ev: ^EditViewState) {
	ev.orbit_yaw      = 0.5
	ev.orbit_pitch    = 0.3
	ev.orbit_distance = 15.0
	ev.orbit_target   = rl.Vector3{0, 0, 0}
	ev.selected_idx   = -1
	ev.prop_drag_idx  = -1

	append(&ev.objects, EditSphere{center = {-3, 0.5, 0}, radius = 0.5, mat_type = 0, color = {0.8, 0.2, 0.2}})
	append(&ev.objects, EditSphere{center = { 0, 0.5, 0}, radius = 0.5, mat_type = 1, color = {0.2, 0.2, 0.8}})
	append(&ev.objects, EditSphere{center = { 3, 0.5, 0}, radius = 0.5, mat_type = 0, color = {0.2, 0.8, 0.2}})

	update_orbit_camera(ev)
	ev.initialized = true
}

// build_world_from_edit_view converts EditSpheres to raytrace Objects for rt.start_render.
// Prepends a grey ground plane. Caller owns and must delete the returned slice.
build_world_from_edit_view :: proc(ev: ^EditViewState) -> [dynamic]rt.Object {
	world := make([dynamic]rt.Object)

	append(&world, rt.Object(rt.Sphere{
		center   = {0, -1000, 0},
		radius   = 1000,
		material = rt.lambertian{albedo = {0.5, 0.5, 0.5}},
	}))

	for s in ev.objects {
		mat: rt.material
		switch s.mat_type {
		case 0: mat = rt.lambertian{albedo = s.color}
		case 1: mat = rt.metalic{albedo = s.color, fuzz = 0.1}
		case 2: mat = rt.dieletric{ref_idx = 1.5}
		case:   mat = rt.lambertian{albedo = s.color}
		}
		append(&world, rt.Object(rt.Sphere{
			center   = s.center,
			radius   = s.radius,
			material = mat,
		}))
	}

	return world
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

// compute_viewport_ray casts a perspective ray through the given mouse position.
// When require_inside=true (default) returns false if mouse is outside vp_rect.
// When require_inside=false the UV is clamped to viewport edges — useful during
// active drags where the mouse may wander outside the panel.
compute_viewport_ray :: proc(
	ev: ^EditViewState, mouse: rl.Vector2, vp_rect: rl.Rectangle,
	require_inside: bool = true,
) -> (ray: rl.Ray, ok: bool) {
	if require_inside && !rl.CheckCollisionPointRec(mouse, vp_rect) {
		return {}, false
	}
	if ev.tex_w <= 0 || ev.tex_h <= 0 { return {}, false }

	u := clamp((mouse.x - vp_rect.x) / vp_rect.width,  f32(0), f32(1))
	v := clamp((mouse.y - vp_rect.y) / vp_rect.height, f32(0), f32(1))

	forward := rl.Vector3Normalize(ev.cam3d.target - ev.cam3d.position)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, ev.cam3d.up))
	up      := rl.Vector3CrossProduct(right, forward)

	aspect := f32(ev.tex_w) / f32(ev.tex_h)
	half_h := math.tan(ev.cam3d.fovy * math.PI / 360.0)
	half_w := half_h * aspect

	ndc_x := (u * 2.0 - 1.0) * half_w
	ndc_y := (1.0 - v * 2.0) * half_h

	dir := rl.Vector3Normalize(forward + right * ndc_x + up * ndc_y)
	return rl.Ray{position = ev.cam3d.position, direction = dir}, true
}

// ray_hit_plane_y intersects a ray with the horizontal plane y=plane_y.
// Returns the XZ world hit as Vector2{x, z}, or false when the ray is
// nearly parallel to the plane or points away from it.
ray_hit_plane_y :: proc(ray: rl.Ray, plane_y: f32) -> (xz: rl.Vector2, ok: bool) {
	dy := ray.direction.y
	if abs(dy) < 1e-4 { return {}, false }
	t := (plane_y - ray.position.y) / dy
	if t < 0 { return {}, false }
	return rl.Vector2{
		ray.position.x + t * ray.direction.x,
		ray.position.z + t * ray.direction.z,
	}, true
}

pick_sphere :: proc(ev: ^EditViewState, ray: rl.Ray) -> int {
	best_idx  := -1
	best_dist := f32(1e30)

	for i in 0..<len(ev.objects) {
		s      := ev.objects[i]
		center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		hit    := rl.GetRayCollisionSphere(ray, center, s.radius)
		if hit.hit && hit.distance > 0 && hit.distance < best_dist {
			best_dist = hit.distance
			best_idx  = i
		}
	}

	return best_idx
}

draw_viewport_3d :: proc(ev: ^EditViewState, vp_rect: rl.Rectangle) {
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

	for i in 0..<len(ev.objects) {
		s      := ev.objects[i]
		center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		col: rl.Color
		if i == ev.selected_idx {
			col = rl.YELLOW
		} else {
			col = rl.Color{u8(s.color[0]*255), u8(s.color[1]*255), u8(s.color[2]*255), 255}
		}
		rl.DrawSphere(center, s.radius, col)
		rl.DrawSphereWires(center, s.radius, 8, 8, rl.Color{30, 30, 30, 180})
	}

	// Draw a move indicator on the selected sphere during drag
	if ev.drag_obj_active && ev.selected_idx >= 0 {
		s := ev.objects[ev.selected_idx]
		c := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		rl.DrawCircle3D(c, s.radius + 0.08, rl.Vector3{1, 0, 0}, 90, rl.Color{255, 220, 0, 200})
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
	rl.DrawText(fmt.ctprintf("%.3f", value), i32(box.x) + 5, i32(box.y) + 4, 11, CONTENT_TEXT_COLOR)
	// Label to the left
	rl.DrawText(label, i32(box.x) - i32(PROP_LW + PROP_GAP) + 2, i32(box.y) + 4, 12, CONTENT_TEXT_COLOR)
}

draw_edit_properties :: proc(ev: ^EditViewState, rect: rl.Rectangle, mouse: rl.Vector2) {
	rl.DrawRectangleRec(rect, rl.Color{25, 28, 40, 240})
	rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)

	if ev.selected_idx < 0 || ev.selected_idx >= len(ev.objects) {
		rl.DrawText("No object selected",
			i32(rect.x) + 8, i32(rect.y) + 10, 12, CONTENT_TEXT_COLOR)
		rl.DrawText("Click a sphere in the viewport to select it",
			i32(rect.x) + 8, i32(rect.y) + 30, 11, rl.Color{140, 150, 165, 200})
		return
	}

	s      := ev.objects[ev.selected_idx]
	fields := prop_field_rects(rect)

	// Row 0 — position X Y Z
	draw_drag_field("X", s.center[0], fields[0], ev.prop_drag_idx == 0, mouse)
	draw_drag_field("Y", s.center[1], fields[1], ev.prop_drag_idx == 1, mouse)
	draw_drag_field("Z", s.center[2], fields[2], ev.prop_drag_idx == 2, mouse)

	// Row 1 — radius + material label
	draw_drag_field("R", s.radius, fields[3], ev.prop_drag_idx == 3, mouse)

	mat_names := [3]cstring{"Lambertian", "Metallic", "Dielectric"}
	mat_name  := mat_names[clamp(s.mat_type, 0, 2)]
	mat_x := i32(rect.x) + 8 + i32(PROP_COL)
	mat_y := i32(rect.y) + 8 + 30 + 4
	rl.DrawText("Mat:",    mat_x,      mat_y, 12, CONTENT_TEXT_COLOR)
	rl.DrawText(mat_name,  mat_x + 36, mat_y, 12, ACCENT_COLOR)

	// Hint
	rl.DrawText(
		"Drag field to adjust  •  Click+drag sphere in view to move",
		i32(rect.x) + 8, i32(rect.y) + i32(EDIT_PROPS_H) - 18, 11,
		rl.Color{120, 130, 148, 180},
	)
}

// ── Panel draw ─────────────────────────────────────────────────────────────

draw_edit_view_content :: proc(app: ^App, content: rl.Rectangle) {
	ev    := &app.edit_view
	mouse := rl.GetMousePosition()

	// Toolbar
	toolbar_rect := rl.Rectangle{content.x, content.y, content.width, EDIT_TOOLBAR_H}
	rl.DrawRectangleRec(toolbar_rect, rl.Color{40, 42, 58, 255})
	rl.DrawRectangleLinesEx(toolbar_rect, 1, BORDER_COLOR)

	btn_add   := rl.Rectangle{content.x + 8, content.y + 5, 90, 22}
	add_hover := rl.CheckCollisionPointRec(mouse, btn_add)
	rl.DrawRectangleRec(btn_add, add_hover ? rl.Color{80, 130, 200, 255} : rl.Color{55, 85, 140, 255})
	rl.DrawText("Add Sphere", i32(btn_add.x) + 6, i32(btn_add.y) + 4, 12, rl.RAYWHITE)

	if ev.selected_idx >= 0 {
		btn_del   := rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
		del_hover := rl.CheckCollisionPointRec(mouse, btn_del)
		rl.DrawRectangleRec(btn_del, del_hover ? rl.Color{200, 60, 60, 255} : rl.Color{140, 40, 40, 255})
		rl.DrawText("Delete", i32(btn_del.x) + 8, i32(btn_del.y) + 4, 12, rl.RAYWHITE)
	}

	btn_render   := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	render_busy  := !app.finished
	render_hover := !render_busy && rl.CheckCollisionPointRec(mouse, btn_render)
	rl.DrawRectangleRec(btn_render,
		render_busy  ? rl.Color{45, 75,  45,  200} :
		render_hover ? rl.Color{80, 190, 80,  255} :
		               rl.Color{50, 140, 50,  255})
	rl.DrawText(
		render_busy ? cstring("Rendering…") : cstring("Render"),
		i32(btn_render.x) + 6, i32(btn_render.y) + 4, 12, rl.RAYWHITE)

	// 3D viewport
	vp_rect := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	draw_viewport_3d(ev, vp_rect)

	// Properties strip
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}
	draw_edit_properties(ev, props_rect, mouse)
}

// ── Panel update ───────────────────────────────────────────────────────────

update_edit_view_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev      := &app.edit_view
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

	// ── Priority 1: active property-field drag ──────────────────────────
	if ev.prop_drag_idx >= 0 {
		if !lmb {
			ev.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else if ev.selected_idx >= 0 && ev.selected_idx < len(ev.objects) {
			delta := mouse.x - ev.prop_drag_start_x
			s     := &ev.objects[ev.selected_idx]
			switch ev.prop_drag_idx {
			case 0: s.center[0] = ev.prop_drag_start_val + delta * 0.01
			case 1: s.center[1] = ev.prop_drag_start_val + delta * 0.01
			case 2: s.center[2] = ev.prop_drag_start_val + delta * 0.01
			case 3:
				s.radius = ev.prop_drag_start_val + delta * 0.005
				if s.radius < 0.05 { s.radius = 0.05 }
			}
		}
		return
	}

	// ── Priority 2: active viewport object drag ─────────────────────────
	if ev.drag_obj_active {
		if !lmb {
			ev.drag_obj_active = false
		} else if ev.selected_idx >= 0 && ev.selected_idx < len(ev.objects) {
			// require_inside=false: keep dragging even when mouse leaves viewport
			if ray, ok := compute_viewport_ray(ev, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					s           := &ev.objects[ev.selected_idx]
					s.center[0]  = xz.x - ev.drag_offset_xz[0]
					s.center[2]  = xz.y - ev.drag_offset_xz[1]
				}
			}
		}
		return
	}

	// ── Toolbar buttons ─────────────────────────────────────────────────
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, btn_add) {
			append(&ev.objects, EditSphere{
				center = {0, 0.5, 0}, radius = 0.5, mat_type = 0, color = {0.7, 0.7, 0.7},
			})
			ev.selected_idx = len(ev.objects) - 1
			return
		}
		if ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, btn_del) {
			ordered_remove(&ev.objects, ev.selected_idx)
			ev.selected_idx = -1
			return
		}
		if app.finished && rl.CheckCollisionPointRec(mouse, btn_render) {
			app_restart_render(app, build_world_from_edit_view(ev))
			return
		}
	}

	// ── Property drag-field: start drag on click ────────────────────────
	if ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, props_rect) {
		fields := prop_field_rects(props_rect)
		vals   := [4]f32{
			ev.objects[ev.selected_idx].center[0],
			ev.objects[ev.selected_idx].center[1],
			ev.objects[ev.selected_idx].center[2],
			ev.objects[ev.selected_idx].radius,
		}
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
					return
				}
			}
		}
		if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else { rl.SetMouseCursor(.DEFAULT) }
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

	// Left-click: select sphere and optionally start drag
	if lmb_pressed && mouse_in_vp {
		if ray, ok := compute_viewport_ray(ev, mouse, vp_rect); ok {
			picked := pick_sphere(ev, ray)
			if picked >= 0 {
				ev.selected_idx    = picked
				// Immediately arm drag so holding after click moves the sphere
				ev.drag_obj_active = true
				ev.drag_plane_y    = ev.objects[picked].center[1]
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					ev.drag_offset_xz = {
						xz.x - ev.objects[picked].center[0],
						xz.y - ev.objects[picked].center[2],
					}
				}
			} else {
				ev.selected_idx    = -1
				ev.drag_obj_active = false
			}
		}
	}

	// Keyboard nudge (still available while not dragging)
	MOVE_SPEED   :: f32(0.05)
	RADIUS_SPEED :: f32(0.02)
	if ev.selected_idx >= 0 && ev.selected_idx < len(ev.objects) {
		s := &ev.objects[ev.selected_idx]
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
	}
}
