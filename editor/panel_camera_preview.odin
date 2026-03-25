package editor

import rl "vendor:raylib"

render_camera_preview_to_texture :: proc(app: ^App, width, height: i32) {
	if width <= 0 || height <= 0 { return }

	if width != app.preview_port_w || height != app.preview_port_h {
		if app.preview_port_w > 0 {
			rl.UnloadRenderTexture(app.preview_port_tex)
		}
		app.preview_port_tex = rl.LoadRenderTexture(width, height)
		app.preview_port_w = width
		app.preview_port_h = height
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

	ev := &app.e_edit_view
	ensure_viewport_sphere_cache_filled(app, ev)
	rl.BeginTextureMode(app.preview_port_tex)
	rl.ClearBackground(rl.Color{20, 25, 35, 255})
	rl.BeginMode3D(cam3d)
	rl.DrawGrid(20, 1.0)
	draw_viewport_scene_objects(app, ev, .None, -1)
	rl.EndMode3D()
	rl.EndTextureMode()
}
