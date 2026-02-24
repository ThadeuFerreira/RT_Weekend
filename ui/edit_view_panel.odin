package ui

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

EDIT_TOOLBAR_H :: f32(32)
EDIT_PROPS_H   :: f32(70)

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
	orbit_yaw:      f32, // horizontal angle (radians)
	orbit_pitch:    f32, // vertical angle (radians)
	orbit_distance: f32, // distance from target
	orbit_target:   rl.Vector3,

	// Right-drag state
	rmb_held:   bool,
	last_mouse: rl.Vector2,

	// Scene
	objects:      [dynamic]EditSphere,
	selected_idx: int, // -1 = nothing selected

	initialized: bool,
}

init_edit_view :: proc(ev: ^EditViewState) {
	ev.orbit_yaw      = 0.5
	ev.orbit_pitch    = 0.3
	ev.orbit_distance = 15.0
	ev.orbit_target   = rl.Vector3{0, 0, 0}
	ev.selected_idx   = -1

	append(&ev.objects, EditSphere{center = {-3, 0.5, 0}, radius = 0.5, mat_type = 0, color = {0.8, 0.2, 0.2}})
	append(&ev.objects, EditSphere{center = { 0, 0.5, 0}, radius = 0.5, mat_type = 1, color = {0.2, 0.2, 0.8}})
	append(&ev.objects, EditSphere{center = { 3, 0.5, 0}, radius = 0.5, mat_type = 0, color = {0.2, 0.8, 0.2}})

	update_orbit_camera(ev)
	ev.initialized = true
}

// build_world_from_edit_view converts the panel's EditSphere list into a raytrace Object
// slice ready to be passed to rt.start_render. Adds a grey ground plane automatically.
// Caller owns the returned dynamic array and must delete it when done.
build_world_from_edit_view :: proc(ev: ^EditViewState) -> [dynamic]rt.Object {
    world := make([dynamic]rt.Object)

    // Ground plane
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

	yaw := ev.orbit_yaw
	t   := ev.orbit_target

	pos := rl.Vector3{
		t.x + dist * math.cos(pitch) * math.sin(yaw),
		t.y + dist * math.sin(pitch),
		t.z + dist * math.cos(pitch) * math.cos(yaw),
	}

	ev.cam3d = rl.Camera3D{
		position   = pos,
		target     = t,
		up         = rl.Vector3{0, 1, 0},
		fovy       = 45.0,
		projection = .PERSPECTIVE,
	}
}

compute_viewport_ray :: proc(ev: ^EditViewState, mouse: rl.Vector2, vp_rect: rl.Rectangle) -> (ray: rl.Ray, ok: bool) {
	if !rl.CheckCollisionPointRec(mouse, vp_rect) {
		return {}, false
	}
	if ev.tex_w <= 0 || ev.tex_h <= 0 {
		return {}, false
	}

	u := (mouse.x - vp_rect.x) / vp_rect.width
	v := (mouse.y - vp_rect.y) / vp_rect.height

	// Camera basis vectors
	forward := rl.Vector3Normalize(ev.cam3d.target - ev.cam3d.position)
	right   := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, ev.cam3d.up))
	up      := rl.Vector3CrossProduct(right, forward)

	aspect := f32(ev.tex_w) / f32(ev.tex_h)
	half_h := math.tan(ev.cam3d.fovy * math.PI / 360.0) // tan(fovy/2) in radians
	half_w := half_h * aspect

	// Map (u,v) from [0,1] to NDC, flip v for screen-Y convention
	ndc_x := (u * 2.0 - 1.0) * half_w
	ndc_y := (1.0 - v * 2.0) * half_h

	dir := rl.Vector3Normalize(forward + right * ndc_x + up * ndc_y)

	return rl.Ray{position = ev.cam3d.position, direction = dir}, true
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
		if ev.tex_w > 0 {
			rl.UnloadRenderTexture(ev.viewport_tex)
		}
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
		sphere_color: rl.Color
		if i == ev.selected_idx {
			sphere_color = rl.YELLOW
		} else {
			sphere_color = rl.Color{
				u8(s.color[0] * 255),
				u8(s.color[1] * 255),
				u8(s.color[2] * 255),
				255,
			}
		}
		rl.DrawSphere(center, s.radius, sphere_color)
		rl.DrawSphereWires(center, s.radius, 8, 8, rl.Color{30, 30, 30, 180})
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	// Draw to panel rect with Y-flip (Raylib FBO is upside-down)
	src := rl.Rectangle{0, 0, f32(ev.tex_w), -f32(ev.tex_h)}
	rl.DrawTexturePro(ev.viewport_tex.texture, src, vp_rect, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}

draw_edit_properties :: proc(ev: ^EditViewState, rect: rl.Rectangle) {
	rl.DrawRectangleRec(rect, rl.Color{25, 28, 40, 240})
	rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)

	x  := i32(rect.x) + 8
	y  := i32(rect.y) + 6
	fs := i32(12)
	lh := i32(16)

	if ev.selected_idx < 0 || ev.selected_idx >= len(ev.objects) {
		rl.DrawText("No object selected", x, y, fs, CONTENT_TEXT_COLOR)
		return
	}

	s := ev.objects[ev.selected_idx]
	mat_names := [3]cstring{"Lambertian", "Metallic", "Dielectric"}
	mat_name  := mat_names[clamp(s.mat_type, 0, 2)]

	rl.DrawText(
		fmt.ctprintf("Pos: (%.2f, %.2f, %.2f)  Radius: %.2f", s.center[0], s.center[1], s.center[2], s.radius),
		x, y, fs, CONTENT_TEXT_COLOR,
	)
	y += lh

	rl.DrawText(
		fmt.ctprintf("Mat: %s  Color: (%.2f, %.2f, %.2f)", mat_name, s.color[0], s.color[1], s.color[2]),
		x, y, fs, CONTENT_TEXT_COLOR,
	)
	y += lh

	rl.DrawText("WASD/Arrows=move XZ  Q/E=up/down  +/-=radius", x, y, fs, rl.Color{150, 160, 170, 200})
}

draw_edit_view_content :: proc(app: ^App, content: rl.Rectangle) {
	ev := &app.edit_view

	// Toolbar
	toolbar_rect := rl.Rectangle{content.x, content.y, content.width, EDIT_TOOLBAR_H}
	rl.DrawRectangleRec(toolbar_rect, rl.Color{40, 42, 58, 255})
	rl.DrawRectangleLinesEx(toolbar_rect, 1, BORDER_COLOR)

	mouse := rl.GetMousePosition()

	// "Add Sphere" button
	btn_add   := rl.Rectangle{content.x + 8, content.y + 5, 90, 22}
	add_hover := rl.CheckCollisionPointRec(mouse, btn_add)
	rl.DrawRectangleRec(btn_add, add_hover ? rl.Color{80, 130, 200, 255} : rl.Color{55, 85, 140, 255})
	rl.DrawText("Add Sphere", i32(btn_add.x) + 6, i32(btn_add.y) + 4, 12, rl.RAYWHITE)

	// "Delete" button — only shown when something is selected
	if ev.selected_idx >= 0 {
		btn_del   := rl.Rectangle{content.x + 106, content.y + 5, 60, 22}
		del_hover := rl.CheckCollisionPointRec(mouse, btn_del)
		rl.DrawRectangleRec(btn_del, del_hover ? rl.Color{200, 60, 60, 255} : rl.Color{140, 40, 40, 255})
		rl.DrawText("Delete", i32(btn_del.x) + 8, i32(btn_del.y) + 4, 12, rl.RAYWHITE)
	}

	// "Render" button — right-aligned; dimmed while a render is in progress
	btn_render     := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}
	render_busy    := !app.finished
	render_hover   := !render_busy && rl.CheckCollisionPointRec(mouse, btn_render)
	render_bg      := render_busy   ? rl.Color{45, 75, 45, 200} :
	                  render_hover  ? rl.Color{80, 190, 80, 255} :
	                                  rl.Color{50, 140, 50, 255}
	render_label   := render_busy   ? cstring("Rendering…") : cstring("Render")
	rl.DrawRectangleRec(btn_render, render_bg)
	rl.DrawText(render_label, i32(btn_render.x) + 6, i32(btn_render.y) + 4, 12, rl.RAYWHITE)

	// 3D viewport
	vp_rect := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	draw_viewport_3d(ev, vp_rect)

	// Properties strip at bottom
	props_rect := rl.Rectangle{
		content.x,
		content.y + content.height - EDIT_PROPS_H,
		content.width,
		EDIT_PROPS_H,
	}
	draw_edit_properties(ev, props_rect)
}

update_edit_view_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev      := &app.edit_view
	content := rect

	// Toolbar button rects
	btn_add := rl.Rectangle{content.x + 8, content.y + 5, 90, 22}
	btn_del := rl.Rectangle{content.x + 106, content.y + 5, 60, 22}

	btn_render := rl.Rectangle{content.x + content.width - 90, content.y + 5, 82, 22}

	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, btn_add) {
			append(&ev.objects, EditSphere{
				center   = {0, 0.5, 0},
				radius   = 0.5,
				mat_type = 0,
				color    = {0.7, 0.7, 0.7},
			})
			ev.selected_idx = len(ev.objects) - 1
		} else if ev.selected_idx >= 0 && rl.CheckCollisionPointRec(mouse, btn_del) {
			ordered_remove(&ev.objects, ev.selected_idx)
			ev.selected_idx = -1
		} else if app.finished && rl.CheckCollisionPointRec(mouse, btn_render) {
			app_restart_render(app, build_world_from_edit_view(ev))
		}
	}

	// Viewport rect
	vp_rect := rl.Rectangle{
		content.x,
		content.y + EDIT_TOOLBAR_H,
		content.width,
		content.height - EDIT_TOOLBAR_H - EDIT_PROPS_H,
	}
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, vp_rect)

	// Right-mouse drag → orbit
	rmb := rl.IsMouseButtonDown(.RIGHT)
	if rmb {
		if ev.rmb_held && (mouse_in_vp || ev.rmb_held) {
			delta          := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			ev.orbit_yaw   += delta.x * 0.005
			ev.orbit_pitch += -delta.y * 0.005
		}
		ev.rmb_held   = true
		ev.last_mouse = mouse
	} else {
		ev.rmb_held = false
	}

	// Scroll wheel → zoom
	if mouse_in_vp {
		wheel := rl.GetMouseWheelMove()
		ev.orbit_distance -= wheel * 0.8
	}

	// Left-click → pick sphere
	if lmb_pressed && mouse_in_vp {
		if ray, ok := compute_viewport_ray(ev, mouse, vp_rect); ok {
			ev.selected_idx = pick_sphere(ev, ray)
		}
	}

	// Keyboard: move/resize selected sphere
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
		if rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD)      { s.radius += RADIUS_SPEED }
		if rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) {
			s.radius -= RADIUS_SPEED
			if s.radius < 0.05 { s.radius = 0.05 }
		}
	}

	update_orbit_camera(ev)
}
