package editor

import rl "vendor:raylib"

// draw_preview_port_content renders a rasterized 3D preview from the render camera
// (app.c_camera_params) and scene (via scene manager export) into the panel content area.
draw_preview_port_content :: proc(app: ^App, content: rl.Rectangle) {
	new_w := i32(content.width)
	new_h := i32(content.height)

	if new_w != app.preview_port_w || new_h != app.preview_port_h {
		if app.preview_port_w > 0 {
			rl.UnloadRenderTexture(app.preview_port_tex)
		}
		if new_w > 0 && new_h > 0 {
			app.preview_port_tex = rl.LoadRenderTexture(new_w, new_h)
		}
		app.preview_port_w = new_w
		app.preview_port_h = new_h
	}

	if app.preview_port_w <= 0 || app.preview_port_h <= 0 { return }

	cp := &app.c_camera_params
	cam3d := rl.Camera3D{
		position   = rl.Vector3{cp.lookfrom[0], cp.lookfrom[1], cp.lookfrom[2]},
		target     = rl.Vector3{cp.lookat[0], cp.lookat[1], cp.lookat[2]},
		up         = rl.Vector3{cp.vup[0], cp.vup[1], cp.vup[2]},
		fovy       = cp.vfov,
		projection = .PERSPECTIVE,
	}

	rl.BeginTextureMode(app.preview_port_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(cam3d)
	rl.DrawGrid(20, 1.0)

	ExportToSceneSpheres(app.edit_view.scene_mgr, &app.edit_view.export_scratch)
	for s in app.edit_view.export_scratch {
		center := rl.Vector3{s.center[0], s.center[1], s.center[2]}
		col := rl.Color{
			u8(clamp(s.albedo[0], f32(0), f32(1)) * 255),
			u8(clamp(s.albedo[1], f32(0), f32(1)) * 255),
			u8(clamp(s.albedo[2], f32(0), f32(1)) * 255),
			255,
		}
		rl.DrawSphere(center, s.radius, col)
		rl.DrawSphereWires(center, s.radius, 8, 8, rl.Color{30, 30, 30, 180})
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	src := rl.Rectangle{0, 0, f32(app.preview_port_w), -f32(app.preview_port_h)}
	rl.DrawTexturePro(app.preview_port_tex.texture, src, content, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}
