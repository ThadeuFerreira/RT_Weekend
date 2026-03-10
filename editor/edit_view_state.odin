package editor

import "core:math"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

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
