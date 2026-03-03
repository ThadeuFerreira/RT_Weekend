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
EDIT_PROPS_H   :: f32(120)

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

	// Orbit camera parameters (spherical coords around target)
	camera_yaw:      f32,
	camera_pitch:    f32,
	orbit_distance:  f32,
	orbit_target:    rl.Vector3,

	// Right-drag orbit state
	rmb_held:     bool,
	last_mouse:   rl.Vector2,
	rmb_press_pos: rl.Vector2,
	rmb_drag_dist: f32,

	// Context menu state
	ctx_menu_open:    bool,
	ctx_menu_pos:     rl.Vector2,
	ctx_menu_hit_idx: int,

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

	// Camera orbit property drag (properties strip when camera is selected)
	// -1=none; 0,1,2=Pos X/Y/Z; 3,4,5=yaw°/pitch°/dist; 6=roll°
	cam_prop_drag_idx:       int,
	cam_prop_drag_start_x:   f32,
	cam_prop_drag_start_val: f32,

	// Camera body drag in viewport (translates render camera in XZ plane)
	cam_drag_active:       bool,
	cam_drag_plane_y:      f32,
	cam_drag_start_hit_xz: [2]f32,   // world XZ under cursor at drag start
	cam_drag_start_lookfrom: rl.Vector3, // render cam lookfrom captured at drag start
	cam_drag_start_lookat:   rl.Vector3, // render cam lookat  captured at drag start

	// Camera rotation ring drag: 1=yaw ring, 0=pitch ring, -1=none
	cam_rot_drag_axis:    int,
	cam_rot_drag_start_x: f32,
	cam_rot_drag_start_y: f32,

	// Camera gizmo toggles (Edit View toolbar)
	show_frustum_gizmo:  bool,
	show_focal_indicator: bool,

	initialized: bool,
}

init_edit_view :: proc(ev: ^EditViewState) {
	ev.camera_yaw      = 0.5
	ev.camera_pitch    = 0.3
	ev.orbit_distance = 15.0
	ev.orbit_target   = rl.Vector3{0, 0, 0}
	ev.selection_kind = .None
	ev.selected_idx   = -1
	ev.prop_drag_idx  = -1
	ev.cam_prop_drag_idx = -1
	ev.cam_rot_drag_axis = -1
	ev.show_frustum_gizmo  = true
	ev.show_focal_indicator = true

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
	pitch := ev.camera_pitch
	if pitch >  math.PI * 0.45 { pitch =  math.PI * 0.45 }
	if pitch < -math.PI * 0.45 { pitch = -math.PI * 0.45 }
	ev.camera_pitch = pitch

	dist := ev.orbit_distance
	if dist < 1.0 { dist = 1.0 }
	ev.orbit_distance = dist

	t := ev.orbit_target
	pos := rl.Vector3{
		t.x + dist * math.cos(pitch) * math.sin(ev.camera_yaw),
		t.y + dist * math.sin(pitch),
		t.z + dist * math.cos(pitch) * math.cos(ev.camera_yaw),
	}
	ev.cam3d = rl.Camera3D{
		position   = pos,
		target     = t,
		up         = rl.Vector3{0, 1, 0},
		fovy       = 45.0,
		projection = .PERSPECTIVE,
	}
}

// _compute_camera_basis builds the orthonormal right/up0 basis from view direction (singularity handling in one place).
// ok = false if lookfrom/lookat are degenerate (e.g. coincident or looking straight up/down with fallback also degenerate).
_compute_camera_basis :: proc(lookfrom, lookat: [3]f32) -> (right, up0: [3]f32, ok: bool) {
	fwd := [3]f32{lookat[0] - lookfrom[0], lookat[1] - lookfrom[1], lookat[2] - lookfrom[2]}
	len_sq := fwd[0]*fwd[0] + fwd[1]*fwd[1] + fwd[2]*fwd[2]
	if len_sq < 1e-10 { return {}, {}, false }
	fwd = rt.unit_vector(fwd)
	world_up := [3]f32{0, 1, 0}
	right = rt.cross(fwd, world_up)
	right_len_sq := right[0]*right[0] + right[1]*right[1] + right[2]*right[2]
	if right_len_sq < 1e-10 {
		right = rt.cross(fwd, [3]f32{1, 0, 0})
		right_len_sq = right[0]*right[0] + right[1]*right[1] + right[2]*right[2]
		if right_len_sq < 1e-10 { return {}, {}, false }
	}
	right = rt.unit_vector(right)
	up0 = rt.unit_vector(rt.cross(right, fwd))
	return right, up0, true
}

// compute_vup_from_forward_and_roll returns a normalized up vector from view direction and roll (radians).
// forward = lookat - lookfrom; roll rotates the up vector around the view axis (0 = world up).
compute_vup_from_forward_and_roll :: proc(lookfrom, lookat: [3]f32, roll: f32) -> (vup: [3]f32) {
	right, up0, ok := _compute_camera_basis(lookfrom, lookat)
	if !ok { return {0, 1, 0} }
	vup = {
		math.cos(roll)*up0[0] + math.sin(roll)*right[0],
		math.cos(roll)*up0[1] + math.sin(roll)*right[1],
		math.cos(roll)*up0[2] + math.sin(roll)*right[2],
	}
	return rt.unit_vector(vup)
}

// get_orbit_camera_pose returns lookfrom and lookat for the current editor orbit camera.
// Used by "From View"; vup is not returned so the handler can leave c_camera_params.vup unchanged and preserve roll.
get_orbit_camera_pose :: proc(ev: ^EditViewState) -> (lookfrom, lookat: [3]f32) {
	pitch := ev.camera_pitch
	dist  := ev.orbit_distance
	t     := ev.orbit_target
	lookat = {t.x, t.y, t.z}
	lookfrom = {
		t.x + dist * math.cos(pitch) * math.sin(ev.camera_yaw),
		t.y + dist * math.sin(pitch),
		t.z + dist * math.cos(pitch) * math.cos(ev.camera_yaw),
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
		sphere := objs[i]
		center := rl.Vector3{sphere.center[0], sphere.center[1], sphere.center[2]}
		col: rl.Color
		if ev.selection_kind == .Sphere && i == ev.selected_idx {
			col = rl.YELLOW
		} else {
			col = rl.Color{u8(sphere.albedo[0]*255), u8(sphere.albedo[1]*255), u8(sphere.albedo[2]*255), 255}
		}
		rl.DrawSphere(center, sphere.radius, col)
		rl.DrawSphereWires(center, sphere.radius, 8, 8, rl.Color{30, 30, 30, 180})
	}

	// Render camera gizmo (body) and optional frustum / focal indicator
	cp := &app.c_camera_params
	cam_pos := rl.Vector3{cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
	cam_at  := rl.Vector3{cp.lookat[0], cp.lookat[1], cp.lookat[2]}
	vup     := rl.Vector3{cp.vup[0], cp.vup[1], cp.vup[2]}
	draw_camera_gizmo(cam_pos, cam_at, vup, ev.selection_kind == .Camera)

	if ev.selection_kind == .Camera {
		draw_camera_rotation_rings(cam_pos, ev.cam_rot_drag_axis)
	}

	aspect := (app.r_aspect_ratio == 0 ? (4.0 / 3.0) : (16.0 / 9.0))
	if ev.show_frustum_gizmo {
		ul, ur, lr, ll := get_camera_viewport_corners(cp, f32(aspect))
		draw_frustum_wireframe(
			cam_pos,
			vec3_from_core(ul), vec3_from_core(ur), vec3_from_core(lr), vec3_from_core(ll),
			rl.Color{0, 200, 220, 180},
		)
	}
	if ev.show_focal_indicator {
		fwd := rl.Vector3Normalize(cam_at - cam_pos)
		focus_point := cam_pos + fwd * cp.focus_dist
		draw_focal_distance_indicator(cam_pos, focus_point, rl.RED, rl.RED)
	}

	// Draw a move indicator on the selected sphere during drag
	if ev.drag_obj_active && ev.selection_kind == .Sphere && ev.selected_idx >= 0 {
		if ev.selected_idx >= 0 && ev.selected_idx < len(objs) {
			sphere := objs[ev.selected_idx]
			c := rl.Vector3{sphere.center[0], sphere.center[1], sphere.center[2]}
			rl.DrawCircle3D(c, sphere.radius + 0.08, rl.Vector3{1, 0, 0}, 90, rl.Color{255, 220, 0, 200})
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

// cam_forward_angles returns yaw, pitch, dist of the camera's forward direction
// (lookat - lookfrom). Rotation is always relative to the camera's own center.
cam_forward_angles :: proc(lookfrom, lookat: [3]f32) -> (yaw, pitch, dist: f32) {
	d := [3]f32{lookat[0]-lookfrom[0], lookat[1]-lookfrom[1], lookat[2]-lookfrom[2]}
	dist = math.sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
	if dist < 0.001 { dist = 0.001 }
	pitch = math.asin(clamp(d[1]/dist, f32(-1), f32(1)))
	yaw   = math.atan2(d[0], d[2])
	return
}

// roll_from_vup returns the roll angle (radians) that would produce the given vup from lookfrom/lookat.
// vup = cos(roll)*up0 + sin(roll)*right => roll = atan2(dot(vup, right), dot(vup, up0)).
roll_from_vup :: proc(lookfrom, lookat, vup: [3]f32) -> f32 {
	right, up0, ok := _compute_camera_basis(lookfrom, lookat)
	if !ok { return 0 }
	return math.atan2(
		right[0]*vup[0] + right[1]*vup[1] + right[2]*vup[2],
		up0[0]*vup[0] + up0[1]*vup[1] + up0[2]*vup[2],
	)
}

// lookat_from_angles computes only the lookat point from position and forward angles (yaw, pitch, dist).
// Does not touch vup — use when changing yaw/pitch/distance so roll stays independent.
lookat_from_angles :: proc(lookfrom: [3]f32, yaw, pitch, dist: f32) -> [3]f32 {
	return [3]f32{
		lookfrom[0] + dist * math.cos(pitch) * math.sin(yaw),
		lookfrom[1] + dist * math.sin(pitch),
		lookfrom[2] + dist * math.cos(pitch) * math.cos(yaw),
	}
}

// lookat_from_forward computes lookat and vup from camera position, forward angles, distance, and roll.
// Use only when roll is being applied; for yaw/pitch/dist changes use lookat_from_angles and leave vup unchanged.
lookat_from_forward :: proc(lookfrom: [3]f32, yaw, pitch, dist, roll: f32) -> (lookat, vup: [3]f32) {
	lookat = lookat_from_angles(lookfrom, yaw, pitch, dist)
	vup = compute_vup_from_forward_and_roll(lookfrom, lookat, roll)
	return
}

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
		draw_drag_field(labels[0], vals[0], fields[0], ev.cam_prop_drag_idx == 0, mouse)
		draw_drag_field(labels[1], vals[1], fields[1], ev.cam_prop_drag_idx == 1, mouse)
		draw_drag_field(labels[2], vals[2], fields[2], ev.cam_prop_drag_idx == 2, mouse)

		// Row 1 — yaw / pitch / distance
		draw_drag_field(labels[3], vals[3], fields[3], ev.cam_prop_drag_idx == 3, mouse)
		draw_drag_field(labels[4], vals[4], fields[4], ev.cam_prop_drag_idx == 4, mouse)
		draw_drag_field(labels[5], vals[5], fields[5], ev.cam_prop_drag_idx == 5, mouse)

		// Row 2 — roll
		draw_drag_field(labels[6], vals[6], fields[6], ev.cam_prop_drag_idx == 6, mouse)

		// Hint
		draw_ui_text(app,
			"Drag field \u2022 Drag gizmo to move \u2022 Drag ring to rotate",
			i32(rect.x) + 8, i32(rect.y) + i32(EDIT_PROPS_H) - 18, 11,
			rl.Color{120, 130, 148, 180},
		)
		return
	}

	// Sphere selected
	if ev.selected_idx < 0 || ev.selected_idx >= len(objs) { return }
	sphere := objs[ev.selected_idx]
	fields := prop_field_rects(rect)

	// Row 0 — position X Y Z
	draw_drag_field("X", sphere.center[0], fields[0], ev.prop_drag_idx == 0, mouse)
	draw_drag_field("Y", sphere.center[1], fields[1], ev.prop_drag_idx == 1, mouse)
	draw_drag_field("Z", sphere.center[2], fields[2], ev.prop_drag_idx == 2, mouse)

	// Row 1 — radius + material label
	draw_drag_field("R", sphere.radius, fields[3], ev.prop_drag_idx == 3, mouse)

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

// ── Context menu helpers ────────────────────────────────────────────────────

CTX_MENU_W :: f32(160)

// ctx_menu_build_items returns a temp-allocated slice of menu entries for the context menu.
@(private="file")
ctx_menu_build_items :: proc(app: ^App, ev: ^EditViewState) -> []MenuEntryDyn {
	items := make([dynamic]MenuEntryDyn, context.temp_allocator)
	append(&items, MenuEntryDyn{label = "Add Sphere"})
	if ev.ctx_menu_hit_idx >= 0 {
		append(&items, MenuEntryDyn{separator = true})
		append(&items, MenuEntryDyn{label = "Copy",      cmd_id = CMD_EDIT_COPY,      disabled = !cmd_is_enabled(app, CMD_EDIT_COPY),      shortcut = "Ctrl+C"})
		append(&items, MenuEntryDyn{label = "Duplicate", cmd_id = CMD_EDIT_DUPLICATE, disabled = !cmd_is_enabled(app, CMD_EDIT_DUPLICATE), shortcut = "Ctrl+D"})
		append(&items, MenuEntryDyn{label = "Paste",     cmd_id = CMD_EDIT_PASTE,     disabled = !cmd_is_enabled(app, CMD_EDIT_PASTE),     shortcut = "Ctrl+V"})
		append(&items, MenuEntryDyn{separator = true})
		append(&items, MenuEntryDyn{label = "Delete"})
	} else {
		append(&items, MenuEntryDyn{separator = true})
		append(&items, MenuEntryDyn{label = "Paste", cmd_id = CMD_EDIT_PASTE, disabled = !cmd_is_enabled(app, CMD_EDIT_PASTE), shortcut = "Ctrl+V"})
	}
	return items[:]
}

// ctx_menu_screen_rect returns the screen-clamped bounding rectangle for the open context menu.
@(private="file")
ctx_menu_screen_rect :: proc(app: ^App, ev: ^EditViewState) -> rl.Rectangle {
	items := ctx_menu_build_items(app, ev)
	h     := entry_list_height(items)
	sw    := f32(rl.GetScreenWidth())
	sh    := f32(rl.GetScreenHeight())
	x := ev.ctx_menu_pos.x
	y := ev.ctx_menu_pos.y
	if x + CTX_MENU_W > sw { x = sw - CTX_MENU_W }
	if y + h > sh           { y = sh - h           }
	if x < 0               { x = 0                }
	if y < 0               { y = 0                }
	return rl.Rectangle{x, y, CTX_MENU_W, h}
}

// draw_edit_view_context_menu draws the right-click context menu on top of everything.
@(private="file")
draw_edit_view_context_menu :: proc(app: ^App, ev: ^EditViewState) {
	items := ctx_menu_build_items(app, ev)
	rect  := ctx_menu_screen_rect(app, ev)
	mouse := rl.GetMousePosition()

	rl.DrawRectangleRec(rect, PANEL_BG_COLOR)
	rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)

	ey: f32 = 0
	for &entry in items {
		ih := entry_height(entry)
		ry := rect.y + ey

		if entry.separator {
			sep_y := i32(ry + ih * 0.5)
			rl.DrawRectangle(i32(rect.x) + 4, sep_y, i32(rect.width) - 8, 1, BORDER_COLOR)
			ey += ih
			continue
		}

		item_rect := rl.Rectangle{rect.x, ry, CTX_MENU_W, ih}
		item_hov  := rl.CheckCollisionPointRec(mouse, item_rect)
		text_col  := CONTENT_TEXT_COLOR
		if entry.disabled {
			text_col = rl.Color{100, 105, 120, 180}
		} else if item_hov {
			rl.DrawRectangleRec(item_rect, rl.Color{60, 65, 95, 255})
		}

		label_c := make_cstring_temp(entry.label)
		draw_ui_text(app, label_c, i32(rect.x) + 8, i32(ry) + 3, 13, text_col)

		if len(entry.shortcut) > 0 {
			sc_c := make_cstring_temp(entry.shortcut)
			sc_w := measure_ui_text(app, sc_c, 11).width
			sc_x := i32(rect.x + CTX_MENU_W) - sc_w - 6
			draw_ui_text(app, sc_c, sc_x, i32(ry) + 5, 11, rl.Color{140, 150, 170, 200})
		}

		ey += ih
	}
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

	// Frustum / Focal toggles (camera gizmo visibility)
	btn_frustum := rl.Rectangle{content.x + 174, content.y + 5, 56, 22}
	btn_focal   := rl.Rectangle{content.x + 234, content.y + 5, 40, 22}
	frustum_hover := rl.CheckCollisionPointRec(mouse, btn_frustum)
	focal_hover   := rl.CheckCollisionPointRec(mouse, btn_focal)
	frustum_bg := (ev.show_frustum_gizmo ? rl.Color{70, 120, 130, 255} : rl.Color{45, 55, 70, 255})
	if frustum_hover { frustum_bg = ev.show_frustum_gizmo ? rl.Color{90, 150, 160, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_frustum, frustum_bg)
	rl.DrawRectangleLinesEx(btn_frustum, 1, ev.show_frustum_gizmo ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "Frustum", i32(btn_frustum.x) + 4, i32(btn_frustum.y) + 4, 11, rl.RAYWHITE)
	focal_bg := (ev.show_focal_indicator ? rl.Color{130, 70, 70, 255} : rl.Color{45, 55, 70, 255})
	if focal_hover { focal_bg = ev.show_focal_indicator ? rl.Color{160, 90, 90, 255} : rl.Color{55, 68, 88, 255} }
	rl.DrawRectangleRec(btn_focal, focal_bg)
	rl.DrawRectangleLinesEx(btn_focal, 1, ev.show_focal_indicator ? ACCENT_COLOR : BORDER_COLOR)
	draw_ui_text(app, "Focal", i32(btn_focal.x) + 6, i32(btn_focal.y) + 4, 11, rl.RAYWHITE)

	// "From View" — sync orbit (editor) camera → render camera
	btn_fromview  := rl.Rectangle{content.x + content.width - 178, content.y + 5, 82, 22}
	fv_hover      := rl.CheckCollisionPointRec(mouse, btn_fromview)
	rl.DrawRectangleRec(btn_fromview, fv_hover ? rl.Color{80, 110, 170, 255} : rl.Color{55, 75, 120, 255})
	draw_ui_text(app, "From View", i32(btn_fromview.x) + 6, i32(btn_fromview.y) + 4, 12, rl.RAYWHITE)

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

	// Context menu drawn last so it renders on top of everything
	if ev.ctx_menu_open {
		draw_edit_view_context_menu(app, ev)
	}
}

// pick_rotation_ring returns which of the 3 world-axis rings is closest to the mouse,
// or -1 if none is within the pixel threshold.
//   0 = X ring (red,   YZ plane)
//   1 = Y ring (green, XZ plane)
//   2 = Z ring (blue,  XY plane)
// Uses sampled world points projected to screen space so the hit zone scales with zoom
// and handles all viewing angles (rings that are edge-on become narrow, as expected).
pick_rotation_ring :: proc(mouse, vp_offset: rl.Vector2, cam_pos: rl.Vector3, cam3d: rl.Camera3D) -> int {
	SAMPLE_N   :: 32
	HIT_THRESH :: f32(10) // pixels

	best_axis := -1
	best_dist := HIT_THRESH

	for axis in 0..<3 {
		for i in 0..<SAMPLE_N {
			t  := f32(i) * (2.0 * math.PI / SAMPLE_N)
			ct := math.cos(t) * CAM_RING_R
			st := math.sin(t) * CAM_RING_R
			p: rl.Vector3
			switch axis {
			case 0: p = cam_pos + {0, ct, st}  // YZ plane — X axis ring
			case 1: p = cam_pos + {ct, 0, st}  // XZ plane — Y axis ring
			case 2: p = cam_pos + {ct, st, 0}  // XY plane — Z axis ring
			}
			proj := rl.GetWorldToScreen(p, cam3d)
			proj.x += vp_offset.x
			proj.y += vp_offset.y
			dmx := mouse.x - proj.x
			dmy := mouse.y - proj.y
			d := math.sqrt(dmx*dmx + dmy*dmy)
			if d < best_dist {
				best_dist = d
				best_axis = axis
			}
		}
	}
	return best_axis
}

// ── Panel update ───────────────────────────────────────────────────────────

update_edit_view_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
	ev      := &app.e_edit_view
	content := rect

	// Orbit camera is always updated at the end, even on early return.
	defer update_orbit_camera(ev)

	// Shared rects (mirror draw proc)
	btn_add      := rl.Rectangle{content.x + 8,                    content.y + 5, 90, 22}
	btn_del      := rl.Rectangle{content.x + 106,                  content.y + 5, 60, 22}
	btn_frustum  := rl.Rectangle{content.x + 174,                  content.y + 5, 56, 22}
	btn_focal    := rl.Rectangle{content.x + 234,                  content.y + 5, 40, 22}
	btn_fromview := rl.Rectangle{content.x + content.width - 178,  content.y + 5, 82, 22}
	btn_render   := rl.Rectangle{content.x + content.width - 90,   content.y + 5, 82, 22}
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

	// ── Priority 0: Context menu input (highest priority when open) ───────
	if ev.ctx_menu_open {
		app.input_consumed = true
		if rl.IsMouseButtonPressed(.LEFT) {
			items := ctx_menu_build_items(app, ev)
			rect  := ctx_menu_screen_rect(app, ev)
			if rl.CheckCollisionPointRec(mouse, rect) {
				local_y := mouse.y - rect.y
				ey: f32 = 0
				for &entry in items {
					ih := entry_height(entry)
					if !entry.separator && !entry.disabled && local_y >= ey && local_y < ey + ih {
						if entry.label == "Add Sphere" {
							AppendDefaultSphere(ev.scene_mgr)
							new_idx := SceneManagerLen(ev.scene_mgr) - 1
							ev.selection_kind = .Sphere
							ev.selected_idx   = new_idx
							if new_sphere, ok := GetSceneSphere(ev.scene_mgr, new_idx); ok {
								edit_history_push(&app.edit_history, AddSphereAction{idx = new_idx, sphere = new_sphere})
								app_push_log(app, strings.clone("Add sphere"))
							}
							app.r_render_pending = true
						} else if entry.label == "Delete" {
							del_idx := ev.ctx_menu_hit_idx
							if del_sphere, ok := GetSceneSphere(ev.scene_mgr, del_idx); ok {
								edit_history_push(&app.edit_history, DeleteSphereAction{idx = del_idx, sphere = del_sphere})
								app_push_log(app, strings.clone("Delete sphere"))
							}
							OrderedRemove(ev.scene_mgr, del_idx)
							ev.selection_kind = .None
							ev.selected_idx   = -1
							app.r_render_pending = true
						} else if len(entry.cmd_id) > 0 {
							cmd_execute(app, entry.cmd_id)
						}
						break
					}
					ey += ih
				}
			}
			ev.ctx_menu_open = false
		} else if rl.IsKeyPressed(.ESCAPE) {
			ev.ctx_menu_open = false
		}
		return
	}

	// ── Priority A: camera rotation ring drag ────────────────────────────
	// Free-flow: rotation is centered on the camera's own position (lookfrom).
	// The forward vector (lookat - lookfrom) is rotated; lookfrom stays fixed.
	//   axis 0 = X ring → rotate around {1,0,0}
	//   axis 1 = Y ring → rotate around {0,1,0}
	//   axis 2 = Z ring → rotate around {0,0,1}
	if ev.cam_rot_drag_axis >= 0 {
		if !lmb {
			ev.cam_rot_drag_axis = -1
			rl.SetMouseCursor(.DEFAULT)
			app.r_render_pending = true
		} else {
			dx := mouse.x - ev.cam_rot_drag_start_x
			sf := ev.cam_drag_start_lookfrom
			sa := ev.cam_drag_start_lookat
			// forward = lookat - lookfrom (camera center stays, forward direction rotates)
			forward := rl.Vector3{sa.x - sf.x, sa.y - sf.y, sa.z - sf.z}
			axis_vec: rl.Vector3
			switch ev.cam_rot_drag_axis {
			case 0: axis_vec = {1, 0, 0}
			case 1: axis_vec = {0, 1, 0}
			case 2: axis_vec = {0, 0, 1}
			}
			new_forward := rl.Vector3RotateByAxisAngle(forward, axis_vec, dx * 0.005)
			app.c_camera_params.lookat = {
				sf.x + new_forward.x,
				sf.y + new_forward.y,
				sf.z + new_forward.z,
			}
			// lookfrom is unchanged — camera rotates around its own center
		}
		return
	}

	// ── Priority B: camera body drag in viewport (XZ plane) ──────────────
	if ev.cam_drag_active {
		if !lmb {
			ev.cam_drag_active = false
			app.r_render_pending = true
		} else {
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
					dx := xz.x - ev.cam_drag_start_hit_xz[0]
					dz := xz.y - ev.cam_drag_start_hit_xz[1]
					app.c_camera_params.lookfrom[0] = ev.cam_drag_start_lookfrom.x + dx
					app.c_camera_params.lookfrom[2] = ev.cam_drag_start_lookfrom.z + dz
					app.c_camera_params.lookat[0]   = ev.cam_drag_start_lookat.x + dx
					app.c_camera_params.lookat[2]   = ev.cam_drag_start_lookat.z + dz
				}
			}
		}
		return
	}

	// ── Priority C: camera property-field drag ────────────────────────────
	if ev.cam_prop_drag_idx >= 0 {
		if !lmb {
			ev.cam_prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
			app.r_render_pending = true
		} else {
			DEG2RAD :: f32(math.PI / 180.0)
			delta := mouse.x - ev.cam_prop_drag_start_x
			sf := ev.cam_drag_start_lookfrom
			sa := ev.cam_drag_start_lookat
			s_yaw, s_pitch, s_dist := cam_forward_angles(
				{sf.x, sf.y, sf.z}, {sa.x, sa.y, sa.z})
			switch ev.cam_prop_drag_idx {
			case 0: // Pos X — translate whole camera (maintain look direction)
				d := delta * 0.02
				app.c_camera_params.lookfrom[0] = sf.x + d
				app.c_camera_params.lookat[0]   = sa.x + d
			case 1: // Pos Y
				d := delta * 0.02
				app.c_camera_params.lookfrom[1] = sf.y + d
				app.c_camera_params.lookat[1]   = sa.y + d
			case 2: // Pos Z
				d := delta * 0.02
				app.c_camera_params.lookfrom[2] = sf.z + d
				app.c_camera_params.lookat[2]   = sa.z + d
			case 3: // Yaw — rotate forward only; vup unchanged (independent gimbal)
				new_yaw := s_yaw + delta * 0.5 * DEG2RAD
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, new_yaw, s_pitch, s_dist)
			case 4: // Pitch — forward only; vup unchanged
				new_pitch := clamp(s_pitch + delta * 0.3 * DEG2RAD,
					f32(-math.PI * 0.45), f32(math.PI * 0.45))
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, s_yaw, new_pitch, s_dist)
			case 5: // Distance — forward only; vup unchanged
				new_dist := max(s_dist + delta * 0.05, f32(1.0))
				app.c_camera_params.lookat = lookat_from_angles(
					{sf.x, sf.y, sf.z}, s_yaw, s_pitch, new_dist)
			case 6: // Roll — only update vup; no gimbal lock, so allow full ±π
				new_roll := clamp(ev.cam_prop_drag_start_val + delta * 0.005,
					f32(-math.PI), f32(math.PI))
				app.c_camera_params.vup = compute_vup_from_forward_and_roll(
					app.c_camera_params.lookfrom, app.c_camera_params.lookat, new_roll)
			}
		}
		return
	}

	// ── Priority 1: active property-field drag (sphere only) ─────────────
	if ev.prop_drag_idx >= 0 {
		if !lmb {
			ev.prop_drag_idx = -1
			rl.SetMouseCursor(.DEFAULT)
		} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			delta := mouse.x - ev.prop_drag_start_x
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				switch ev.prop_drag_idx {
				case 0: sphere.center[0] = ev.prop_drag_start_val + delta * 0.01
				case 1: sphere.center[1] = ev.prop_drag_start_val + delta * 0.01
				case 2: sphere.center[2] = ev.prop_drag_start_val + delta * 0.01
				case 3:
					sphere.radius = ev.prop_drag_start_val + delta * 0.005
					if sphere.radius < 0.05 { sphere.radius = 0.05 }
				}
				SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
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
				if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
					edit_history_push(&app.edit_history, ModifySphereAction{
						idx    = ev.selected_idx,
						before = ev.drag_before,
						after  = sphere,
					})
					app_push_log(app, strings.clone("Move sphere"))
					app.r_render_pending = true
				}
			}
		} else if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
			// require_inside=false: keep dragging even when mouse leaves viewport
			if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
				if xz, ok2 := ray_hit_plane_y(ray, ev.drag_plane_y); ok2 {
					if sphere, ok3 := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok3 {
						sphere.center[0] = xz.x - ev.drag_offset_xz[0]
						sphere.center[2] = xz.y - ev.drag_offset_xz[1]
						SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
					}
				}
			}
		}
		return
	}

	// ── Toolbar buttons ─────────────────────────────────────────────────
	if lmb_pressed {
		if rl.CheckCollisionPointRec(mouse, btn_frustum) {
			ev.show_frustum_gizmo = !ev.show_frustum_gizmo
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if rl.CheckCollisionPointRec(mouse, btn_focal) {
			ev.show_focal_indicator = !ev.show_focal_indicator
			if g_app != nil { g_app.input_consumed = true }
			return
		}
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
		if rl.CheckCollisionPointRec(mouse, btn_fromview) {
			// Sync editor orbit camera → render camera (lookfrom/lookat only; preserve vup/roll)
			lookfrom, lookat := get_orbit_camera_pose(ev)
			app.c_camera_params.lookfrom = lookfrom
			app.c_camera_params.lookat   = lookat
			app.r_render_pending = true
			if g_app != nil { g_app.input_consumed = true }
			return
		}
		if app.finished && rl.CheckCollisionPointRec(mouse, btn_render) {
			// Use render camera params as-is (modified via gizmo or From View)

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
	// "From view" copies orbit camera into camera_params so Render uses current view
	// Removed - now integrated into render button behavior

	// ── Property drag-field: start drag on click (camera) ────────────────
	if ev.selection_kind == .Camera && rl.CheckCollisionPointRec(mouse, props_rect) {
		fields := cam_orbit_prop_rects(props_rect)
		any_hovered := false
		for i in 0..<7 {
			if rl.CheckCollisionPointRec(mouse, fields[i]) {
				any_hovered = true
				if lmb_pressed {
					cp := &app.c_camera_params
					ev.cam_prop_drag_idx       = i
					ev.cam_prop_drag_start_x   = mouse.x
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					if i == 6 {
						ev.cam_prop_drag_start_val = roll_from_vup(cp.lookfrom, cp.lookat, cp.vup)
					}
					rl.SetMouseCursor(.RESIZE_EW)
					return
				}
			}
		}
		if any_hovered { rl.SetMouseCursor(.RESIZE_EW) } else { rl.SetMouseCursor(.DEFAULT) }
	}

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

	// ── Viewport: orbit, zoom, select, drag-start ────────────────────────
	mouse_in_vp := rl.CheckCollisionPointRec(mouse, vp_rect)

	// Right-mouse orbit + context menu disambiguation
	RMB_DRAG_THRESHOLD :: f32(5.0)
	rmb_pressed := rl.IsMouseButtonPressed(.RIGHT)
	rmb_down    := rl.IsMouseButtonDown(.RIGHT)
	rmb_release := rl.IsMouseButtonReleased(.RIGHT)

	if rmb_pressed && mouse_in_vp {
		ev.rmb_press_pos = mouse
		ev.rmb_drag_dist = 0
		ev.rmb_held      = false
		ev.last_mouse    = mouse
	}
	if rmb_down {
		delta := rl.Vector2{mouse.x - ev.rmb_press_pos.x, mouse.y - ev.rmb_press_pos.y}
		dist  := math.sqrt(delta.x*delta.x + delta.y*delta.y)
		if dist > ev.rmb_drag_dist { ev.rmb_drag_dist = dist }
		if ev.rmb_drag_dist >= RMB_DRAG_THRESHOLD {
			ev.rmb_held = true
		}
		if ev.rmb_held {
			orb_delta      := rl.Vector2{mouse.x - ev.last_mouse.x, mouse.y - ev.last_mouse.y}
			ev.camera_yaw   += orb_delta.x * 0.005
			ev.camera_pitch += -orb_delta.y * 0.005
		}
		ev.last_mouse = mouse
	}
	if rmb_release && mouse_in_vp && ev.rmb_drag_dist < RMB_DRAG_THRESHOLD {
		// Short click → open context menu
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect, false); ok {
			hit_idx := PickSphereInManager(ev.scene_mgr, ray)
			if hit_idx >= 0 {
				ev.selection_kind = .Sphere
				ev.selected_idx   = hit_idx
			}
			ev.ctx_menu_open    = true
			ev.ctx_menu_pos     = mouse
			ev.ctx_menu_hit_idx = hit_idx
			app.input_consumed  = true
		}
	}
	if !rmb_down {
		ev.rmb_held = false
	}

	// Scroll zoom
	if mouse_in_vp {
		ev.orbit_distance -= rl.GetMouseWheelMove() * 0.8
	}

	// Left-click: select and begin drag (camera rotation ring / body / sphere)
	if lmb_pressed && mouse_in_vp {
		if ray, ok := compute_viewport_ray(ev.cam3d, ev.tex_w, ev.tex_h, mouse, vp_rect); ok {
			cam_lookfrom := app.c_camera_params.lookfrom
			cam_pos_v3   := rl.Vector3{cam_lookfrom[0], cam_lookfrom[1], cam_lookfrom[2]}
			vp_offset    := rl.Vector2{vp_rect.x, vp_rect.y}

			if ev.selection_kind == .Camera {
				// Camera already selected: check rings first, then body, then sphere, then deselect
				ring := pick_rotation_ring(mouse, vp_offset, cam_pos_v3, ev.cam3d)
				if ring >= 0 {
					// Start ring drag — record render cam start pose
					ev.cam_rot_drag_axis      = ring
					ev.cam_rot_drag_start_x   = mouse.x
					ev.cam_rot_drag_start_y   = mouse.y
					cp := &app.c_camera_params
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					rl.SetMouseCursor(.RESIZE_ALL)
				} else if pick_camera(ray, cam_lookfrom) {
					// Start camera body drag — translate render camera in XZ
					cp := &app.c_camera_params
					ev.cam_drag_active         = true
					ev.cam_drag_plane_y        = cam_pos_v3.y
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
						ev.cam_drag_start_hit_xz = {xz.x, xz.y}
					}
				} else {
					// Try sphere
					picked_sphere := PickSphereInManager(ev.scene_mgr, ray)
					if picked_sphere >= 0 {
						ev.selection_kind  = .Sphere
						ev.selected_idx    = picked_sphere
						ev.drag_obj_active = true
						if sphere, ok3 := GetSceneSphere(ev.scene_mgr, picked_sphere); ok3 {
							ev.drag_before  = sphere
							ev.drag_plane_y = sphere.center[1]
							if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
								ev.drag_offset_xz = {xz.x - sphere.center[0], xz.y - sphere.center[2]}
							}
						}
					} else {
						ev.selection_kind = .None
						ev.selected_idx   = -1
					}
				}
			} else {
				// Camera not selected: sphere first, then camera body
				picked_sphere := PickSphereInManager(ev.scene_mgr, ray)
				if picked_sphere >= 0 {
					ev.selection_kind  = .Sphere
					ev.selected_idx    = picked_sphere
					ev.drag_obj_active = true
					if sphere, ok3 := GetSceneSphere(ev.scene_mgr, picked_sphere); ok3 {
						ev.drag_before  = sphere
						ev.drag_plane_y = sphere.center[1]
						if xz, ok4 := ray_hit_plane_y(ray, ev.drag_plane_y); ok4 {
							ev.drag_offset_xz = {xz.x - sphere.center[0], xz.y - sphere.center[2]}
						}
					}
				} else if pick_camera(ray, cam_lookfrom) {
					cp := &app.c_camera_params
					ev.selection_kind          = .Camera
					ev.selected_idx            = -1
					ev.cam_drag_active         = true
					ev.cam_drag_plane_y        = cam_pos_v3.y
					ev.cam_drag_start_lookfrom = {cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]}
					ev.cam_drag_start_lookat   = {cp.lookat[0],   cp.lookat[1],   cp.lookat[2]}
					if xz, ok2 := ray_hit_plane_y(ray, ev.cam_drag_plane_y); ok2 {
						ev.cam_drag_start_hit_xz = {xz.x, xz.y}
					}
				} else {
					ev.selection_kind = .None
					ev.selected_idx   = -1
				}
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
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				ev.nudge_before = sphere
			}
		}

		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    { sphere.center[2] -= MOVE_SPEED }
			if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  { sphere.center[2] += MOVE_SPEED }
			if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  { sphere.center[0] -= MOVE_SPEED }
			if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { sphere.center[0] += MOVE_SPEED }
			if rl.IsKeyDown(.Q)                         { sphere.center[1] -= MOVE_SPEED }
			if rl.IsKeyDown(.E)                         { sphere.center[1] += MOVE_SPEED }
			if rl.IsKeyDown(.EQUAL) || rl.IsKeyDown(.KP_ADD) {
				sphere.radius += RADIUS_SPEED
			}
			if rl.IsKeyDown(.MINUS) || rl.IsKeyDown(.KP_SUBTRACT) {
				sphere.radius -= RADIUS_SPEED
				if sphere.radius < 0.05 { sphere.radius = 0.05 }
			}
			SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
		}

		// Commit nudge to history when all keys released
		if !any_nudge && ev.nudge_active {
			ev.nudge_active = false
			if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
				edit_history_push(&app.edit_history, ModifySphereAction{
					idx    = ev.selected_idx,
					before = ev.nudge_before,
					after  = sphere,
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
