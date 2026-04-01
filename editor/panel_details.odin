package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:util"

// Layout constants for the Details panel.
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


// DetailsPanelState holds per-frame drag state for the Details panel.
// For sphere: data in app.e_edit_view.objects[selected_idx]. For camera: app.c_camera_params.
// Drag indices: sphere 0–10 (xyz, radius, motion dX dY dZ, rgb, mat_param); camera 0–11 (from xyz, at xyz, vfov, defocus, focus, max_depth, shutter).
// Drag index 11 = Noise/Marble scale. Volume props: 100 + i*4 + 0 = density, +1..+3 = albedo R,G,B.
// When a volume is selected: 200+0..2 = translate X,Y,Z; 3 = rotate_y_deg; 4 = density; 5,6,7 = albedo R,G,B; 8 = scale (uniform).
OP_VOLUME_DRAG_BASE         :: 100
OP_VOLUME_SELECTED_DRAG_BASE :: 200
OP_VOLUME_SELECTED_DRAG_COUNT :: 9
DetailsPanelState :: struct {
	prop_drag_idx:       int,
	prop_drag_start_x:   f32,
	prop_drag_start_val: f32,

	// Before-state captured at drag start (for undo history). Lives on App so it resets on scene load.
	drag_before_entity:          core.SceneEntity,
	drag_before_c_camera_params: core.CameraParams,

	// Perlin noise preview (cached; regenerated when scale or type changes)
	noise_preview: NoisePreview,
}

// ─── ImGui Details panel: draw bodies per selection kind ─────────────────────
// Called from imgui_draw_details_panel (imgui_panels_stub.odin). Split out so the
// stub stays readable and each selection kind lives in one place.

@(private)
_details_draw_camera :: proc(app: ^App, st: ^DetailsPanelState) {
	imgui.Text("Camera")

	imgui.DragFloat("FOV", &app.c_camera_params.vfov, 0.5, 1, 120, "%.1f°")
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.DragFloat3("Look From", &app.c_camera_params.lookfrom, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.DragFloat3("Look At", &app.c_camera_params.lookat, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.DragFloat("Defocus Angle", &app.c_camera_params.defocus_angle, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		if app.c_camera_params.defocus_angle < 0 { app.c_camera_params.defocus_angle = 0 }
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.DragFloat("Focus Dist", &app.c_camera_params.focus_dist, 0.05, 0.1, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		if app.c_camera_params.focus_dist < 0.1 { app.c_camera_params.focus_dist = 0.1 }
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.ColorEdit3("Background", &app.c_camera_params.background)
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		app.c_camera_params.background[0] = clamp(app.c_camera_params.background[0], f32(0), f32(1))
		app.c_camera_params.background[1] = clamp(app.c_camera_params.background[1], f32(0), f32(1))
		app.c_camera_params.background[2] = clamp(app.c_camera_params.background[2], f32(0), f32(1))
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.SliderFloat("Shutter Open", &app.c_camera_params.shutter_open, 0, 1)
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		_camera_panel_clamp_shutter(&app.c_camera_params)
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		_camera_panel_clamp_shutter(&app.c_camera_params)
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}

	imgui.SliderFloat("Shutter Close", &app.c_camera_params.shutter_close, 0, 1)
	if imgui.IsItemActivated() { st.drag_before_c_camera_params = app.c_camera_params }
	if imgui.IsItemDeactivatedAfterEdit() {
		_camera_panel_clamp_shutter(&app.c_camera_params)
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
		edit_history_push(&app.edit_history, ModifyCameraAction{before = st.drag_before_c_camera_params, after = app.c_camera_params})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		_camera_panel_clamp_shutter(&app.c_camera_params)
		rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
	}
}

@(private)
_details_draw_volume :: proc(app: ^App, st: ^DetailsPanelState, idx: int) {
	ev := &app.e_edit_view
	ent, ok := GetSceneEntity(ev.scene_mgr, idx)
	if !ok { return }
	vol, is_vol := ent.(core.SceneVolume)
	if !is_vol { return }
	imgui.Text(fmt.ctprintf("Volume %d", idx))

	imgui.DragFloat3("Translate", &vol.translate, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		SetSceneEntity(ev.scene_mgr, idx, core.SceneEntity(vol))
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(vol)})
			mark_scene_dirty(app)
		}
	}

	imgui.DragFloat("Rotate Y (deg)", &vol.rotate_y_deg, 0.2, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		SetSceneEntity(ev.scene_mgr, idx, core.SceneEntity(vol))
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(vol)})
			mark_scene_dirty(app)
		}
	}

	imgui.DragFloat("Density", &vol.density, 0.002, 0.0001, 1.0, "%.4f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		vol.density = clamp(vol.density, f32(0.0001), f32(1))
		SetSceneEntity(ev.scene_mgr, idx, core.SceneEntity(vol))
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(vol)})
			mark_scene_dirty(app)
		}
	}

	imgui.ColorEdit3("Albedo", &vol.albedo)
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		vol.albedo[0] = clamp(vol.albedo[0], f32(0), f32(1))
		vol.albedo[1] = clamp(vol.albedo[1], f32(0), f32(1))
		vol.albedo[2] = clamp(vol.albedo[2], f32(0), f32(1))
		SetSceneEntity(ev.scene_mgr, idx, core.SceneEntity(vol))
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(vol)})
			mark_scene_dirty(app)
		}
	}
}

@(private)
_details_draw_sphere :: proc(app: ^App, st: ^DetailsPanelState, idx: int) {
	ev := &app.e_edit_view
	sphere, ok := GetSceneSphere(ev.scene_mgr, idx)
	if !ok { return }
	imgui.Text(fmt.ctprintf("Sphere %d", idx))

	imgui.DragFloat3("Center", &sphere.center, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		SetSceneSphere(ev.scene_mgr, idx, sphere)
	}

	imgui.DragFloat("Radius", &sphere.radius, 0.01, 0.001, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		if sphere.radius < 0.001 { sphere.radius = 0.001 }
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		if sphere.radius < 0.001 { sphere.radius = 0.001 }
		SetSceneSphere(ev.scene_mgr, idx, sphere)
	}

	kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
	current := c.int(sphere.material_kind)
	imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		sphere.material_kind = cast(core.MaterialKind)current
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
		mark_scene_dirty(app)
	}

	motion: [3]f32 = {0, 0, 0}
	if sphere.is_moving {
		motion[0] = sphere.center1[0] - sphere.center[0]
		motion[1] = sphere.center1[1] - sphere.center[1]
		motion[2] = sphere.center1[2] - sphere.center[2]
	}
	imgui.DragFloat3("Motion dX/Y/Z", &motion, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		sphere.center1[0] = sphere.center[0] + motion[0]
		sphere.center1[1] = sphere.center[1] + motion[1]
		sphere.center1[2] = sphere.center[2] + motion[2]
		sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
			mark_scene_dirty(app)
		}
	}

	switch sphere.material_kind {
	case .Lambertian:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
		if it, is_img := sphere.albedo.(core.ImageTexture); is_img {
			imgui.Text(fmt.ctprintf("Image: %s", filepath.base(it.path)))
			if imgui.SmallButton("× Clear") {
				st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx)
				sphere.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
				sphere.texture_kind = .Constant
				sphere.image_path = ""
				SetSceneSphere(ev.scene_mgr, idx, sphere)
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
			imgui.SameLine()
		}
		if imgui.SmallButton("Browse…") {
			default_dir := util.dialog_default_dir(app.current_scene_path)
			img_path, ok2 := util.open_file_dialog(default_dir, util.IMAGE_FILTER_DESC, util.IMAGE_FILTER_EXT)
			delete(default_dir)
			if ok2 {
				st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx)
				sphere.albedo = core.ImageTexture{path = img_path}
				sphere.texture_kind = .Image
				sphere.image_path = img_path
				app_ensure_image_cached(app, img_path)
				SetSceneSphere(ev.scene_mgr, idx, sphere)
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
	case .Metallic:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
		imgui.DragFloat("Fuzz", &sphere.fuzz, 0.01, 0, 1, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.fuzz = clamp(sphere.fuzz, f32(0), f32(1))
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
	case .Dielectric:
		imgui.DragFloat("IOR", &sphere.ref_idx, 0.01, 1, 3, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.ref_idx = clamp(sphere.ref_idx, f32(1), f32(3))
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
	case .DiffuseLight:
		col: [3]f32 = {1, 1, 1}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Emit", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(sphere)})
				mark_scene_dirty(app)
			}
		}
	case .Isotropic:
		imgui.TextDisabled("Isotropic material editing not supported here")
	}
}

@(private)
_details_draw_quad :: proc(app: ^App, st: ^DetailsPanelState, idx: int) {
	ev := &app.e_edit_view
	quad, ok := GetSceneQuad(ev.scene_mgr, idx)
	if !ok { return }
	imgui.Text(fmt.ctprintf("Quad %d", idx))

	imgui.DragFloat3("Q (corner)", &quad.Q, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
	}

	imgui.DragFloat3("U (edge)", &quad.u, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
	}

	imgui.DragFloat3("V (edge)", &quad.v, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		SetSceneQuad(ev.scene_mgr, idx, quad)
	}

	kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
	current := c.int(quad.material_kind)
	imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
	if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		quad.material_kind = cast(core.MaterialKind)current
		SetSceneQuad(ev.scene_mgr, idx, quad)
		edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
		mark_scene_dirty(app)
	}

	switch quad.material_kind {
	case .Lambertian:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := quad.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.albedo = core.ConstantTexture{color = col}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
				mark_scene_dirty(app)
			}
		}
	case .Metallic:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := quad.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.albedo = core.ConstantTexture{color = col}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
				mark_scene_dirty(app)
			}
		}
		imgui.DragFloat("Fuzz", &quad.fuzz, 0.01, 0, 1, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.fuzz = clamp(quad.fuzz, f32(0), f32(1))
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
				mark_scene_dirty(app)
			}
		}
	case .Dielectric:
		imgui.DragFloat("IOR", &quad.ref_idx, 0.01, 1, 3, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.ref_idx = clamp(quad.ref_idx, f32(1), f32(3))
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
				mark_scene_dirty(app)
			}
		}
	case .DiffuseLight:
		col: [3]f32 = {1, 1, 1}
		if ct, okc := quad.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Emit", &col)
		if imgui.IsItemActivated() { st.drag_before_entity, _ = GetSceneEntity(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.albedo = core.ConstantTexture{color = col}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyEntityAction{idx = idx, before = st.drag_before_entity, after = core.SceneEntity(quad)})
				mark_scene_dirty(app)
			}
		}
	case .Isotropic:
		imgui.TextDisabled("Isotropic material editing not supported here")
	}
}
