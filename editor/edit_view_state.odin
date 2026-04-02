package editor

import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

EditViewCameraMode :: enum {
	Orbit,
	FreeFly,
}

// EditorCameraBinding controls whether the editor camera is locked to the
// render camera (RenderCamera) or free to navigate independently (FreeFly).
EditorCameraBinding :: enum {
	RenderCamera, // editor view = render view (default)
	FreeFly,    // editor detached; render camera stays put
}

// EditViewState holds all state for the Edit View panel (viewport, orbit camera, selection, drag, etc.).
EditViewState :: struct {
	// Off-screen 3D viewport
	viewport_tex: rl.RenderTexture2D,
	tex_w, tex_h: i32,

	// Raylib 3D camera (recomputed every frame from orbit params)
	cam3d: rl.Camera3D,
	// Viewport redraw tracking to avoid per-frame render+readback+upload when idle.
	viewport_needs_redraw: bool,
	prev_cam_pos:          rl.Vector3,
	prev_cam_target:       rl.Vector3,
	prev_scene_version:    u64,
	prev_visual_version:   u64,
	visual_version:        u64,

	// Orbit camera parameters (spherical coords around target)
	camera_yaw:      f32,
	camera_pitch:    f32,
	orbit_distance:  f32,
	orbit_target:    rl.Vector3,
	camera_mode:     EditViewCameraMode,
	camera_binding:  EditorCameraBinding, // RenderCamera (default) or FreeFly

	// Free-fly camera parameters
	fly_lookfrom: [3]f32,
	fly_yaw:      f32,
	fly_pitch:    f32,
	move_speed:   f32, // world-units per second
	speed_factor: f32, // user multiplier (wheel-adjusted)
	lock_axis_x:  bool,
	lock_axis_y:  bool,
	lock_axis_z:  bool,

	// View grid controls
	grid_visible:       bool,
	grid_density:       f32,
	grid_scale_tier:    int,  // grid LOD exponent (10^tier meters, tier in [-1,3])
	grid_current_cell:  f32,  // primary grid cell size in meters (decade / density)
	nav_keys_consumed: bool,

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
	selection_kind: EditViewSelectionKind, // what is selected
	selected_idx:   int,                   // when Sphere/Quad: index into objects; else -1

	// Drag-float property fields (sphere only)
	// prop_drag_idx: -1=none  0=cx  1=cy  2=cz  3=radius
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Viewport left-drag to move selected object (sphere, quad, or volume)
	drag_obj_active:    bool,
	drag_plane_y:      f32,    // Y of the horizontal movement plane
	drag_offset_xz:    [2]f32, // grab-point offset in world XZ so the object doesn't snap
	drag_before: core.SceneEntity, // entity state captured at viewport-drag start

	// Keyboard nudge history tracking
	nudge_active: bool,          // true while any nudge key is held
	nudge_before: core.SceneEntity, // entity state captured at first nudge keydown

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
	// Shared across all three mutually exclusive camera drag types (body, rot ring, prop strip):
	// captures the full camera state at drag start so the undo action has a valid "before".
	cam_drag_before_params: core.CameraParams,

	// Camera rotation ring drag: 1=yaw ring, 0=pitch ring, -1=none
	cam_rot_drag_axis:    int,
	cam_rot_drag_start_x: f32,
	cam_rot_drag_start_y: f32,

	// Camera gizmo toggles (Edit View toolbar)
	show_frustum_gizmo:  bool,
	show_focal_indicator: bool,

	// AABB Visualization
	show_aabbs:         bool, // master toggle
	aabb_selected_only: bool, // show only selected sphere AABB
	show_bvh_hierarchy: bool, // show BVH internal nodes (depth-coded)
	aabb_max_depth:    int,   // BVH depth limit; -1 = unlimited
	// Cached BVH for hierarchy viz; rebuilt only when scene changes (viz_bvh_dirty).
	viz_bvh_root:  ^rt.BVHNode,
	viz_bvh_dirty: bool,

	add_dropdown_open: bool, // "Add Object" dropdown expanded

	// Background color picker (toolbar above viewport)
	bg_picker_open:     bool,
	bg_drag_idx:        int,   // -1=none, 0=R, 1=G, 2=B
	bg_drag_start_x:    f32,
	bg_drag_start_val:  f32,

	// Per-sphere model+texture cache for ImageTexture display in the 3D viewport.
	// Indexed by sm.objects index; only sphere slots are populated.
	viewport_sphere_cache:       [dynamic]ViewportSphereCacheEntry,
	viewport_sphere_cache_dirty: bool,

	initialized: bool,
}

ViewportSphereCacheEntry :: struct {
	model:   rl.Model,
	tex:     rl.Texture2D,
	radius:  f32,
	tex_sig: string,
}

init_edit_view :: proc(ev: ^EditViewState) {
	ev.camera_yaw      = 0.5
	ev.camera_pitch    = 0.3
	ev.orbit_distance = 15.0
	ev.orbit_target   = rl.Vector3{0, 0, 0}
	ev.camera_mode    = .Orbit
	ev.fly_lookfrom   = {8, 6, 8}
	ev.fly_yaw        = math.atan2(f32(-8.0), f32(-8.0))
	ev.fly_pitch      = -0.35
	ev.move_speed     = 2.0
	ev.speed_factor   = 1.0
	ev.grid_visible      = true
	ev.grid_density      = 1.0
	ev.grid_scale_tier   = -999
	ev.grid_current_cell = 1.0
	ev.nav_keys_consumed = false
	ev.selection_kind = .None
	ev.selected_idx   = -1
	ev.prop_drag_idx  = -1
	ev.cam_prop_drag_idx = -1
	ev.cam_rot_drag_axis = -1
	ev.bg_drag_idx = -1
	ev.show_frustum_gizmo  = true
	ev.show_focal_indicator = true
	ev.show_aabbs          = false
	ev.aabb_selected_only  = false
	ev.show_bvh_hierarchy  = false
	ev.aabb_max_depth     = -1
	ev.viz_bvh_root             = nil
	ev.viz_bvh_dirty             = true
	ev.viewport_sphere_cache_dirty = true
	ev.viewport_needs_redraw = true

	// initialize scene manager and seed with a few spheres
	ev.scene_mgr = new_scene_manager()
	ev.viewport_sphere_cache = make([dynamic]ViewportSphereCacheEntry)
	initial := make([dynamic]core.SceneSphere)
	append(&initial, core.SceneSphere{center = {-3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.8, 0.2, 0.2}}})
	append(&initial, core.SceneSphere{center = { 0, 0.5, 0}, radius = 0.5, material_kind = .Metallic, albedo = core.ConstantTexture{color={0.2, 0.2, 0.8}}, fuzz = 0.1})
	append(&initial, core.SceneSphere{center = { 3, 0.5, 0}, radius = 0.5, material_kind = .Lambertian, albedo = core.ConstantTexture{color={0.2, 0.8, 0.2}}})
	LoadFromSceneSpheres(ev.scene_mgr, initial[:])
	delete(initial)

	update_orbit_camera(ev)
	ev.initialized = true
	// app is not available here; nil is safe — trace event fires if capturing, log panel skipped.
	ui_log_lifecycle(nil, "EditView", "Create")
}

mark_viewport_dirty :: proc(ev: ^EditViewState) {
	if ev == nil { return }
	ev.viewport_needs_redraw = true
}

mark_viewport_visual_dirty :: proc(ev: ^EditViewState) {
	if ev == nil { return }
	ev.visual_version += 1
	ev.viewport_needs_redraw = true
}

// set_selection marks a new selection and flags a visual redraw only when
// the selection actually changed. Returns true when the selection was updated.
set_selection :: proc(ev: ^EditViewState, kind: EditViewSelectionKind, idx: int) -> bool {
	if ev == nil { return false }
	if ev.selection_kind == kind && ev.selected_idx == idx { return false }
	ev.selection_kind = kind
	ev.selected_idx   = idx
	mark_viewport_visual_dirty(ev)
	return true
}

align_editor_camera_to_render :: proc(ev: ^EditViewState, cp: core.CameraParams, place_in_front: bool) {
	if ev == nil { return }
	from := cp.lookfrom
	at := cp.lookat
	fwd := at - from
	flen := math.sqrt(fwd[0]*fwd[0] + fwd[1]*fwd[1] + fwd[2]*fwd[2])
	if flen < 1e-5 {
		fwd = {0, 0, -1}
	} else {
		fwd /= flen
	}
	_, radius, scene_speed := scene_scale_recommendations(ev.scene_mgr)
	ev.move_speed = scene_speed
	if place_in_front {
		// Min offset avoids clipping through geometry when radius is small; keep well above near clip.
		PLACE_IN_FRONT_MIN_OFFSET :: 2.0
		PLACE_IN_FRONT_NEAR_CLIP  :: 0.01
		offset := max(radius * 0.35, PLACE_IN_FRONT_MIN_OFFSET, 50.0 * PLACE_IN_FRONT_NEAR_CLIP)
		from -= fwd * offset
		at -= fwd * offset
	}
	ev.orbit_target = rl.Vector3{at[0], at[1], at[2]}
	dv := from - at
	dist := math.sqrt(dv[0]*dv[0] + dv[1]*dv[1] + dv[2]*dv[2])
	if dist < 0.5 { dist = 0.5 }
	ev.orbit_distance = dist
	ev.camera_pitch = math.asin(clamp(dv[1]/dist, f32(-1), f32(1)))
	ev.camera_yaw   = math.atan2(dv[0], dv[2])

	ev.fly_lookfrom = from
	ev.fly_pitch = math.asin(clamp(fwd[1], f32(-1), f32(1)))
	ev.fly_yaw   = math.atan2(fwd[0], fwd[2])
}

free_fly_forward :: proc(yaw, pitch: f32) -> rl.Vector3 {
	return {
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		math.cos(pitch) * math.cos(yaw),
	}
}

update_orbit_camera :: proc(ev: ^EditViewState) {
	if ev.camera_mode == .FreeFly {
		pitch := clamp(ev.fly_pitch, f32(-math.PI * 0.49), f32(math.PI * 0.49))
		ev.fly_pitch = pitch
		forward := free_fly_forward(ev.fly_yaw, pitch)
		pos := rl.Vector3{ev.fly_lookfrom[0], ev.fly_lookfrom[1], ev.fly_lookfrom[2]}
		ev.cam3d = rl.Camera3D{
			position   = pos,
			target     = pos + forward,
			up         = rl.Vector3{0, 1, 0},
			fovy       = 45.0,
			projection = .PERSPECTIVE,
		}
		return
	}
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

// get_orbit_camera_pose returns lookfrom and lookat for the current editor orbit camera.
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

// sync_render_camera_from_editor copies the editor camera pose into the shared
// render camera params each frame when camera_binding == .RenderCamera.
// Uses cam3d (already recomputed by update_orbit_camera) so it works for both
// Orbit and FreeFly camera modes.  Returns true when the camera actually moved.
sync_render_camera_from_editor :: proc(ev: ^EditViewState, cp: ^core.CameraParams) -> bool {
	if ev.camera_binding != .RenderCamera { return false }
	p := ev.cam3d.position
	t := ev.cam3d.target
	new_lookfrom := [3]f32{p.x, p.y, p.z}
	new_lookat   := [3]f32{t.x, t.y, t.z}
	if new_lookfrom == cp.lookfrom && new_lookat == cp.lookat { return false }
	cp.lookfrom = new_lookfrom
	cp.lookat   = new_lookat
	return true
}
