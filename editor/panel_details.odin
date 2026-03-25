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
	drag_before_sphere: core.SceneSphere,
	drag_before_quad: rt.Quad,
	drag_before_volume: core.SceneVolume,
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
	v := app.e_volumes[idx]
	imgui.Text(fmt.ctprintf("Volume %d", idx))

	imgui.DragFloat3("Translate", &v.translate, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_volume = v }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		app.e_volumes[idx] = v
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyVolumeAction{idx = idx, before = st.drag_before_volume, after = v})
			mark_scene_dirty(app)
		}
	}

	imgui.DragFloat("Rotate Y (deg)", &v.rotate_y_deg, 0.2, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_volume = v }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		app.e_volumes[idx] = v
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyVolumeAction{idx = idx, before = st.drag_before_volume, after = v})
			mark_scene_dirty(app)
		}
	}

	imgui.DragFloat("Density", &v.density, 0.002, 0.0001, 1.0, "%.4f")
	if imgui.IsItemActivated() { st.drag_before_volume = v }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		v.density = clamp(v.density, f32(0.0001), f32(1))
		app.e_volumes[idx] = v
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyVolumeAction{idx = idx, before = st.drag_before_volume, after = v})
			mark_scene_dirty(app)
		}
	}

	imgui.ColorEdit3("Albedo", &v.albedo)
	if imgui.IsItemActivated() { st.drag_before_volume = v }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		v.albedo[0] = clamp(v.albedo[0], f32(0), f32(1))
		v.albedo[1] = clamp(v.albedo[1], f32(0), f32(1))
		v.albedo[2] = clamp(v.albedo[2], f32(0), f32(1))
		app.e_volumes[idx] = v
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyVolumeAction{idx = idx, before = st.drag_before_volume, after = v})
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
	if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		SetSceneSphere(ev.scene_mgr, idx, sphere)
	}

	imgui.DragFloat("Radius", &sphere.radius, 0.01, 0.001, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		if sphere.radius < 0.001 { sphere.radius = 0.001 }
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
		mark_scene_dirty(app)
	} else if imgui.IsItemEdited() {
		if sphere.radius < 0.001 { sphere.radius = 0.001 }
		SetSceneSphere(ev.scene_mgr, idx, sphere)
	}

	kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
	current := c.int(sphere.material_kind)
	imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
	if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		sphere.material_kind = cast(core.MaterialKind)current
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
		mark_scene_dirty(app)
	}

	motion: [3]f32 = {0, 0, 0}
	if sphere.is_moving {
		motion[0] = sphere.center1[0] - sphere.center[0]
		motion[1] = sphere.center1[1] - sphere.center[1]
		motion[2] = sphere.center1[2] - sphere.center[2]
	}
	imgui.DragFloat3("Motion dX/Y/Z", &motion, 0.02, 0, 0, "%.3f")
	if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		sphere.center1[0] = sphere.center[0] + motion[0]
		sphere.center1[1] = sphere.center[1] + motion[1]
		sphere.center1[2] = sphere.center[2] + motion[2]
		sphere.is_moving = (sphere.center1[0] != sphere.center[0] || sphere.center1[1] != sphere.center[1] || sphere.center1[2] != sphere.center[2])
		SetSceneSphere(ev.scene_mgr, idx, sphere)
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
			mark_scene_dirty(app)
		}
	}

	switch sphere.material_kind {
	case .Lambertian:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
		}
		if it, is_img := sphere.albedo.(core.ImageTexture); is_img {
			imgui.Text(fmt.ctprintf("Image: %s", filepath.base(it.path)))
			if imgui.SmallButton("× Clear") {
				st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx)
				sphere.albedo = core.ConstantTexture{color = {0.5, 0.5, 0.5}}
				sphere.texture_kind = .Constant
				sphere.image_path = ""
				SetSceneSphere(ev.scene_mgr, idx, sphere)
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
			imgui.SameLine()
		}
		if imgui.SmallButton("Browse…") {
			default_dir := util.dialog_default_dir(app.current_scene_path)
			img_path, ok2 := util.open_file_dialog(default_dir, util.IMAGE_FILTER_DESC, util.IMAGE_FILTER_EXT)
			delete(default_dir)
			if ok2 {
				st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx)
				sphere.albedo = core.ImageTexture{path = img_path}
				sphere.texture_kind = .Image
				sphere.image_path = img_path
				app_ensure_image_cached(app, img_path)
				SetSceneSphere(ev.scene_mgr, idx, sphere)
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
		}
	case .Metallic:
		col: [3]f32 = {0.5, 0.5, 0.5}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Albedo", &col)
		if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
		}
		imgui.DragFloat("Fuzz", &sphere.fuzz, 0.01, 0, 1, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.fuzz = clamp(sphere.fuzz, f32(0), f32(1))
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
		}
	case .Dielectric:
		imgui.DragFloat("IOR", &sphere.ref_idx, 0.01, 1, 3, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.ref_idx = clamp(sphere.ref_idx, f32(1), f32(3))
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
				mark_scene_dirty(app)
			}
		}
	case .DiffuseLight:
		col: [3]f32 = {1, 1, 1}
		if ct, okc := sphere.albedo.(core.ConstantTexture); okc { col = ct.color }
		imgui.ColorEdit3("Emit", &col)
		if imgui.IsItemActivated() { st.drag_before_sphere, _ = GetSceneSphere(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			sphere.albedo = core.ConstantTexture{color = col}
			SetSceneSphere(ev.scene_mgr, idx, sphere)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifySphereAction{idx = idx, before = st.drag_before_sphere, after = sphere})
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

	kinds := [4]cstring{"Lambertian", "Metallic", "Dielectric", "DiffuseLight"}
	current: c.int = 0
	#partial switch _ in quad.material {
	case rt.lambertian:    current = 0
	case rt.metallic:      current = 1
	case rt.dielectric:    current = 2
	case rt.diffuse_light: current = 3
	}
	imgui.ComboChar("Material", &current, &kinds[0], c.int(len(kinds)))
	if imgui.IsItemActivated() { st.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() {
		col := [3]f32{0.5, 0.5, 0.5}
		#partial switch m in quad.material {
		case rt.lambertian:
			if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
			else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
		case rt.metallic:
			col = m.albedo
		case rt.diffuse_light:
			intensity := max(m.emit[0], max(m.emit[1], m.emit[2]))
			if intensity > 0 { col = {m.emit[0]/intensity, m.emit[1]/intensity, m.emit[2]/intensity} } else { col = {1, 1, 1} }
		}
		switch int(current) {
		case 0: quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
		case 1: quad.material = rt.metallic{albedo = col, fuzz = 0.1}
		case 2: quad.material = rt.dielectric{ref_idx = 1.5}
		case 3: quad.material = rt.diffuse_light{emit = {2, 2, 2}}
		}
		SetSceneQuad(ev.scene_mgr, idx, quad)
		edit_history_push(&app.edit_history, ModifyQuadAction{idx = idx, before = st.drag_before_quad, after = quad})
		mark_scene_dirty(app)
	}

	col := [3]f32{0.5, 0.5, 0.5}
	param: f32 = 0.1
	is_emitter := false
	#partial switch m in quad.material {
	case rt.lambertian:
		if ct, ok2 := m.albedo.(rt.ConstantTexture); ok2 { col = ct.color }
		else if ck, ok2 := m.albedo.(rt.CheckerTexture); ok2 { col = ck.even }
	case rt.metallic:
		col = m.albedo
		param = m.fuzz
	case rt.dielectric:
		param = m.ref_idx
	case rt.diffuse_light:
		is_emitter = true
		intensity := max(m.emit[0], max(m.emit[1], m.emit[2]))
		if intensity > 0 { col = {m.emit[0]/intensity, m.emit[1]/intensity, m.emit[2]/intensity} } else { col = {1, 1, 1} }
		param = intensity
	}

	imgui.ColorEdit3(is_emitter ? "Emit Color" : "Color", &col)
	if imgui.IsItemActivated() { st.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, idx) }
	if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
		if is_emitter {
			quad.material = rt.diffuse_light{emit = {col[0]*param, col[1]*param, col[2]*param}}
		} else {
			#partial switch m in quad.material {
			case rt.lambertian:
				quad.material = rt.lambertian{albedo = rt.ConstantTexture{color = col}}
			case rt.metallic:
				quad.material = rt.metallic{albedo = col, fuzz = clamp(param, f32(0), f32(1))}
			}
		}
		SetSceneQuad(ev.scene_mgr, idx, quad)
		if imgui.IsItemDeactivatedAfterEdit() {
			edit_history_push(&app.edit_history, ModifyQuadAction{idx = idx, before = st.drag_before_quad, after = quad})
			mark_scene_dirty(app)
		}
	}

	if is_emitter {
		imgui.DragFloat("Intensity", &param, 0.02, 0, 50, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			if param < 0 { param = 0 }
			quad.material = rt.diffuse_light{emit = {col[0]*param, col[1]*param, col[2]*param}}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyQuadAction{idx = idx, before = st.drag_before_quad, after = quad})
				mark_scene_dirty(app)
			}
		}
	} else if current == 1 {
		imgui.DragFloat("Fuzz", &param, 0.01, 0, 1, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.material = rt.metallic{albedo = col, fuzz = clamp(param, f32(0), f32(1))}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyQuadAction{idx = idx, before = st.drag_before_quad, after = quad})
				mark_scene_dirty(app)
			}
		}
	} else if current == 2 {
		imgui.DragFloat("IOR", &param, 0.01, 1, 3, "%.3f")
		if imgui.IsItemActivated() { st.drag_before_quad, _ = GetSceneQuad(ev.scene_mgr, idx) }
		if imgui.IsItemDeactivatedAfterEdit() || imgui.IsItemEdited() {
			quad.material = rt.dielectric{ref_idx = clamp(param, f32(1), f32(3))}
			SetSceneQuad(ev.scene_mgr, idx, quad)
			if imgui.IsItemDeactivatedAfterEdit() {
				edit_history_push(&app.edit_history, ModifyQuadAction{idx = idx, before = st.drag_before_quad, after = quad})
				mark_scene_dirty(app)
			}
		}
	}
}
