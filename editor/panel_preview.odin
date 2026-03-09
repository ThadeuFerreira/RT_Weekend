package editor

import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// get_render_aspect returns the aspect ratio (width/height) used by the render from app.r_aspect_ratio.
get_render_aspect :: proc(app: ^App) -> f32 {
	if app.r_aspect_ratio == 0 {
		return 4.0 / 3.0
	}
	return 16.0 / 9.0
}

// draw_preview_port_content renders a rasterized 3D preview from the render camera
// (app.c_camera_params) and scene (via scene manager) into the panel content area.
// The preview uses the same aspect ratio as the ray-traced render (4:3 or 16:9) and letterboxes
// within the panel so the framing matches the final output.
draw_preview_port_content :: proc(app: ^App, content: rl.Rectangle) {
	aspect := get_render_aspect(app)
	content_aspect := content.width / content.height
	preview_w, preview_h: f32
	if content_aspect > aspect {
		preview_h = content.height
		preview_w = content.height * aspect
	} else {
		preview_w = content.width
		preview_h = content.width / aspect
	}
	new_w := i32(preview_w)
	new_h := i32(preview_h)
	if new_w < 1 { new_w = 1 }
	if new_h < 1 { new_h = 1 }

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
	ev := &app.e_edit_view
	sm := ev.scene_mgr
	if sm != nil {
		for i in 0..<len(sm.objects) {
			selected := (ev.selection_kind == .Sphere || ev.selection_kind == .Quad) && ev.selected_idx == i
			#partial switch o in sm.objects[i] {
			case core.SceneSphere:
				s := o
				col: rl.Color
				if selected { col = rl.YELLOW }
				else {
					disp_col := [3]f32{0.5, 0.5, 0.5}
					#partial switch tex in s.albedo {
					case core.ConstantTexture: disp_col = tex.color
					case core.CheckerTexture: disp_col = tex.even
					}
					col = rl.Color{
						u8(clamp(disp_col[0], 0.0, 1.0) * 255),
						u8(clamp(disp_col[1], 0.0, 1.0) * 255),
						u8(clamp(disp_col[2], 0.0, 1.0) * 255),
						255,
					}
				}
				rl.DrawSphere(s.center, s.radius, col)
				rl.DrawSphereWires(s.center, s.radius, 4, 4, rl.BLUE)
			case rt.Quad:
				q := o
				col: rl.Color
				if selected { col = rl.YELLOW }
				else {
					dc := rt.material_display_color(q.material)
					col = rl.Color{
						u8(clamp(dc[0], 0.0, 1.0) * 255),
						u8(clamp(dc[1], 0.0, 1.0) * 255),
						u8(clamp(dc[2], 0.0, 1.0) * 255),
						255,
					}
				}
				draw_quad_3d(q, col)
			}
		}
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	// Letterbox: draw texture centered in content, preserving aspect
	dest := rl.Rectangle{
		content.x + (content.width - preview_w) * 0.5,
		content.y + (content.height - preview_h) * 0.5,
		preview_w,
		preview_h,
	}
	src := rl.Rectangle{0, 0, f32(app.preview_port_w), -f32(app.preview_port_h)}
	rl.DrawTexturePro(app.preview_port_tex.texture, src, dest, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}
