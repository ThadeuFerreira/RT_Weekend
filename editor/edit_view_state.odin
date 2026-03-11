package editor

import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

EditViewCameraMode :: enum {
	Orbit,
	FreeFly,
}

// EditViewState holds all state for the Edit View panel (viewport, orbit camera, selection, drag, etc.).
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
	camera_mode:     EditViewCameraMode,

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
	grid_visible: bool,
	grid_density: f32,
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
	export_scratch: [dynamic]core.SceneSphere, // reused by ExportToSceneSpheres callers; no per-frame alloc
	selection_kind: EditViewSelectionKind,      // what is selected
	selected_idx:   int,                   // when Sphere/Quad: index into objects; else -1

	// Drag-float property fields (sphere only)
	// prop_drag_idx: -1=none  0=cx  1=cy  2=cz  3=radius
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Viewport left-drag to move selected object (sphere or quad)
	drag_obj_active:   bool,
	drag_plane_y:      f32,    // Y of the horizontal movement plane
	drag_offset_xz:   [2]f32, // grab-point offset in world XZ so the object doesn't snap
	drag_before:      core.SceneSphere, // sphere state captured at viewport-drag start
	drag_before_quad: rt.Quad,          // quad state captured at viewport-drag start

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
	ev.grid_visible   = true
	ev.grid_density   = 1.0
	ev.nav_keys_consumed = false
	ev.selection_kind = .None
	ev.selected_idx   = -1
	ev.prop_drag_idx  = -1
	ev.cam_prop_drag_idx = -1
	ev.cam_rot_drag_axis = -1
	ev.show_frustum_gizmo  = true
	ev.show_focal_indicator = true
	ev.show_aabbs          = false
	ev.aabb_selected_only  = false
	ev.show_bvh_hierarchy  = false
	ev.aabb_max_depth     = -1
	ev.viz_bvh_root             = nil
	ev.viz_bvh_dirty             = true
	ev.viewport_sphere_cache_dirty = true

	// initialize scene manager and seed with a few spheres
	ev.scene_mgr = new_scene_manager()
	ev.export_scratch = make([dynamic]core.SceneSphere)
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

scene_manager_bounds :: proc(sm: ^SceneManager) -> (bmin, bmax: [3]f32, ok: bool) {
	if sm == nil || len(sm.objects) == 0 {
		return {}, {}, false
	}
	bmin = {1e30, 1e30, 1e30}
	bmax = {-1e30, -1e30, -1e30}
	found := false
	for obj in sm.objects {
		#partial switch o in obj {
		case core.SceneSphere:
			// Ignore the very large "ground" sphere when present.
			if o.center[1] < -100 && o.radius > 100 {
				continue
			}
			r := o.radius
			p0 := o.center - [3]f32{r, r, r}
			p1 := o.center + [3]f32{r, r, r}
			if o.is_moving {
				p0m := o.center1 - [3]f32{r, r, r}
				p1m := o.center1 + [3]f32{r, r, r}
				if p0m[0] < p0[0] { p0[0] = p0m[0] }
				if p0m[1] < p0[1] { p0[1] = p0m[1] }
				if p0m[2] < p0[2] { p0[2] = p0m[2] }
				if p1m[0] > p1[0] { p1[0] = p1m[0] }
				if p1m[1] > p1[1] { p1[1] = p1m[1] }
				if p1m[2] > p1[2] { p1[2] = p1m[2] }
			}
			if p0[0] < bmin[0] { bmin[0] = p0[0] }
			if p0[1] < bmin[1] { bmin[1] = p0[1] }
			if p0[2] < bmin[2] { bmin[2] = p0[2] }
			if p1[0] > bmax[0] { bmax[0] = p1[0] }
			if p1[1] > bmax[1] { bmax[1] = p1[1] }
			if p1[2] > bmax[2] { bmax[2] = p1[2] }
			found = true
		case rt.Quad:
			bb := rt.quad_bounding_box(o)
			if bb.x.min < bmin[0] { bmin[0] = bb.x.min }
			if bb.y.min < bmin[1] { bmin[1] = bb.y.min }
			if bb.z.min < bmin[2] { bmin[2] = bb.z.min }
			if bb.x.max > bmax[0] { bmax[0] = bb.x.max }
			if bb.y.max > bmax[1] { bmax[1] = bb.y.max }
			if bb.z.max > bmax[2] { bmax[2] = bb.z.max }
			found = true
		}
	}
	if !found {
		return {}, {}, false
	}
	return bmin, bmax, true
}

scene_geometry_center :: proc(sm: ^SceneManager) -> (center: [3]f32, ok: bool) {
	bmin, bmax, ok_bounds := scene_manager_bounds(sm)
	if !ok_bounds {
		return {}, false
	}
	center = (bmin + bmax) * 0.5
	return center, true
}

// frame_editor_camera_horizontal fits the whole scene in view and looks at center.
// Camera is aligned to the horizontal plane (pitch=0, world-up).
frame_editor_camera_horizontal :: proc(ev: ^EditViewState, vertical_fov_deg: f32 = 45.0, fit_padding: f32 = 1.15) -> bool {
	if ev == nil {
		return false
	}
	bmin, bmax, ok := scene_manager_bounds(ev.scene_mgr)
	if !ok {
		return false
	}
	center := (bmin + bmax) * 0.5
	half := (bmax - bmin) * 0.5
	pad := fit_padding
	if pad < 1.0 { pad = 1.0 }

	// Horizontal framing from a fixed-height camera:
	// fit XY extents by FOV, then add Z half-extent so near/far spread remains visible.
	half_xy := math.sqrt(half[0]*half[0] + half[1]*half[1]) * pad
	vfov_rad := max(vertical_fov_deg, f32(5.0)) * (math.PI / 180.0)
	dist := half_xy / max(math.tan(vfov_rad * 0.5), f32(1e-4))
	dist += half[2] * pad
	if dist < 2.0 { dist = 2.0 }

	ev.camera_mode = .Orbit
	ev.orbit_target = rl.Vector3{center[0], center[1], center[2]}
	ev.orbit_distance = dist
	ev.camera_pitch = 0
	ev.camera_yaw = 0

	// Keep free-fly state in sync for callers that toggle mode later.
	lookfrom := center + [3]f32{0, 0, dist}
	ev.fly_lookfrom = lookfrom
	ev.fly_pitch = 0
	ev.fly_yaw = math.PI
	return true
}

scene_scale_recommendations :: proc(sm: ^SceneManager) -> (center: [3]f32, radius, move_speed: f32) {
	center = {0, 0, 0}
	radius = 8.0
	move_speed = 2.0
	bmin, bmax, ok := scene_manager_bounds(sm)
	if !ok {
		return
	}
	center = (bmin + bmax) * 0.5
	d := bmax - bmin
	diag := math.sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
	if diag < 1.0 { diag = 1.0 }
	radius = max(diag * 0.45, f32(3.0))
	move_speed = clamp(diag * 0.06, f32(0.2), f32(300.0))
	return
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
		offset := max(radius * 0.35, f32(2.0))
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

update_orbit_camera :: proc(ev: ^EditViewState) {
	if ev.camera_mode == .FreeFly {
		pitch := clamp(ev.fly_pitch, f32(-math.PI * 0.49), f32(math.PI * 0.49))
		ev.fly_pitch = pitch
		forward := rl.Vector3{
			math.cos(pitch) * math.sin(ev.fly_yaw),
			math.sin(pitch),
			math.cos(pitch) * math.cos(ev.fly_yaw),
		}
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
