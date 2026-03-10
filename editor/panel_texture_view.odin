// panel_texture_view.odin — Texture View panel: rasterized preview of the current material texture.
// Shows the selected sphere's albedo (or ground texture when nothing selected) so the user can
// visualize ConstantTexture, CheckerTexture, and ImageTexture changes in real time.

package editor

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"
import "RT_Weekend:core"

TEXTURE_PREVIEW_SIZE :: 256

TextureViewPanelState :: struct {
	preview_tex: rl.Texture2D,
	preview_w:   i32,
	preview_h:   i32,
	valid:       bool,
	last_sig:    string,
}

// texture_view_resolve_image_path returns an absolute path for loading. Relative paths are resolved against the scene file directory.
texture_view_resolve_image_path :: proc(app: ^App, image_path: string) -> string {
	if len(image_path) == 0 do return ""
	when ODIN_OS == .Windows {
		if len(image_path) >= 3 && image_path[1] == ':' && (image_path[2] == '\\' || image_path[2] == '/') {
			return strings.clone(image_path)
		}
	} else {
		if image_path[0] == '/' {
			return strings.clone(image_path)
		}
	}
	scene_dir := "."
	if len(app.current_scene_path) > 0 {
		scene_dir = filepath.dir(app.current_scene_path)
	}
	return strings.concatenate({scene_dir, filepath.SEPARATOR_STRING, image_path})
}

// texture_view_sig builds a string descriptor of the current texture for cache invalidation.
texture_view_sig :: proc(app: ^App, tex: core.Texture) -> string {
	switch t in tex {
	case core.ConstantTexture:
		return fmt.aprintf("c %.3f %.3f %.3f", t.color[0], t.color[1], t.color[2])
	case core.CheckerTexture:
		return fmt.aprintf("k %.2f %.3f %.3f %.3f %.3f %.3f %.3f",
			t.scale, t.even[0], t.even[1], t.even[2], t.odd[0], t.odd[1], t.odd[2])
	case core.ImageTexture:
		return fmt.aprintf("i %s", t.path)
	case core.NoiseTexture:
		return fmt.aprintf("n %.3f", t.scale)
	case core.MarbleTexture:
		return fmt.aprintf("m %.3f", t.scale)
	}
	// Always return heap-allocated signatures so callers can safely delete().
	return fmt.aprintf("none")
}

// texture_view_current returns the texture to preview: selected sphere's albedo, or ground texture.
texture_view_current :: proc(app: ^App) -> (tex: core.Texture, has_tex: bool) {
	ev := &app.e_edit_view
	if ev.selection_kind == .Sphere && ev.selected_idx >= 0 && ev.selected_idx < SceneManagerLen(ev.scene_mgr) {
		if sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx); ok {
			return sphere.albedo, true
		}
	}
	// No sphere selected: show ground texture (same union shape as core.Texture via rt.Texture)
	gt := app_active_ground_texture(app)
	return gt, true
}

// texture_view_build_image creates a Raylib Image from core.Texture.
// For Constant/Checker the caller must UnloadImage(img). For ImageTexture, caller must delete(buf_to_free).
texture_view_build_image :: proc(app: ^App, tex: core.Texture) -> (img: rl.Image, buf_to_free: []u8, ok: bool) {
	w, h := i32(TEXTURE_PREVIEW_SIZE), i32(TEXTURE_PREVIEW_SIZE)
	switch t in tex {
	case core.ConstantTexture:
		col := rl.Color{
			u8(clamp(t.color[0], 0, 1) * 255),
			u8(clamp(t.color[1], 0, 1) * 255),
			u8(clamp(t.color[2], 0, 1) * 255),
			255,
		}
		img = rl.GenImageColor(w, h, col)
		return img, nil, true
	case core.CheckerTexture:
		even := rl.Color{
			u8(clamp(t.even[0], 0, 1) * 255),
			u8(clamp(t.even[1], 0, 1) * 255),
			u8(clamp(t.even[2], 0, 1) * 255),
			255,
		}
		odd := rl.Color{
			u8(clamp(t.odd[0], 0, 1) * 255),
			u8(clamp(t.odd[1], 0, 1) * 255),
			u8(clamp(t.odd[2], 0, 1) * 255),
			255,
		}
		checks_x := max(1, i32(f32(w) * t.scale / 16))
		checks_y := max(1, i32(f32(h) * t.scale / 16))
		img = rl.GenImageChecked(w, h, checks_x, checks_y, even, odd)
		return img, nil, true
	case core.NoiseTexture:
		// Generate noise preview using Raylib's GenImagePerlinNoise (stb_perlin fBm, 6 octaves).
		safe_scale := t.scale > 0 ? t.scale : 4.0
		img = rl.GenImagePerlinNoise(w, h, 0, 0, safe_scale)
		return img, nil, true
	case core.MarbleTexture:
		// Generate marble preview using the same CPU turbulence as the ray tracer.
		safe_scale := t.scale > 0 ? t.scale : 4.0
		img = rl.GenImageColor(w, h, rl.BLACK)
		pixels := cast([^]rl.Color)img.data
		for py in 0..<h {
			for px in 0..<w {
				nx := f32(px) * safe_scale / f32(w)
				ny := f32(py) * safe_scale / f32(h)
				turb := rt.perlin_turbulence({nx, ny, 1.0})
				val  := 0.5 * (1.0 + math.sin(safe_scale * ny + 10.0 * turb))
				bv   := u8(clamp(val, 0.0, 1.0) * 255.0)
				pixels[py * w + px] = rl.Color{bv, bv, bv, 255}
			}
		}
		return img, nil, true
	case core.ImageTexture:
		// Resolve path: use cache if present; else resolve relative to scene dir and load on demand.
		cache_key := t.path
		if app.image_texture_cache == nil || t.path not_in app.image_texture_cache {
			resolved := texture_view_resolve_image_path(app, t.path)
			defer delete(resolved)
			if len(resolved) > 0 {
				app_ensure_image_cached(app, resolved)
				cache_key = resolved
			} else {
				app_ensure_image_cached(app, t.path)
			}
		}
		if app.image_texture_cache == nil || cache_key not_in app.image_texture_cache {
			return {}, nil, false
		}
		rt_img := app.image_texture_cache[cache_key]
		if rt_img == nil do return {}, nil, false
		iw := rt.texture_image_width(rt_img)
		ih := rt.texture_image_height(rt_img)
		if iw <= 0 || ih <= 0 do return {}, nil, false
		bytes := rt.texture_image_byte_slice(rt_img)
		if len(bytes) == 0 do return {}, nil, false
		// Raylib upload: use RGBA for broad backend support (some don't support R8G8B8).
		n := iw * ih
		buf := make([]u8, n * 4)
		for i in 0 ..< n {
			buf[i*4 + 0] = bytes[i*3 + 0]
			buf[i*4 + 1] = bytes[i*3 + 1]
			buf[i*4 + 2] = bytes[i*3 + 2]
			buf[i*4 + 3] = 255
		}
		img = rl.Image{
			data    = raw_data(buf),
			width   = i32(iw),
			height  = i32(ih),
			mipmaps = 1,
			format  = .UNCOMPRESSED_R8G8B8A8,
		}
		return img, buf, true
	}
	return {}, nil, false
}

draw_texture_view_content :: proc(app: ^App, content: rl.Rectangle) {
	tex, has_tex := texture_view_current(app)
	if !has_tex {
		draw_ui_text(app, "No texture",
			i32(content.x) + 10, i32(content.y) + 20, 12, CONTENT_TEXT_COLOR)
		draw_ui_text(app, "Select a sphere in Edit View to preview its material.",
			i32(content.x) + 10, i32(content.y) + 42, 10, rl.Color{140, 150, 165, 200})
		return
	}

	sig := texture_view_sig(app, tex)
	defer delete(sig)
	need_rebuild := !app.e_texture_view.valid || app.e_texture_view.last_sig != sig

	if need_rebuild {
		if app.e_texture_view.valid {
			rl.UnloadTexture(app.e_texture_view.preview_tex)
			app.e_texture_view.valid = false
		}
		delete(app.e_texture_view.last_sig)
		app.e_texture_view.last_sig = strings.clone(sig)

		img, buf_to_free, ok := texture_view_build_image(app, tex)
		if !ok {
			draw_ui_text(app, "Texture unavailable",
				i32(content.x) + 10, i32(content.y) + 20, 12, CONTENT_TEXT_COLOR)
			if it, is_img := tex.(core.ImageTexture); is_img {
				draw_ui_text(app, fmt.ctprintf("Image: %s", it.path),
					i32(content.x) + 10, i32(content.y) + 42, 10, rl.Color{160, 80, 80, 200})
			}
			return
		}
		app.e_texture_view.preview_tex = rl.LoadTextureFromImage(img)
		if buf_to_free != nil {
			delete(buf_to_free)
		} else {
			rl.UnloadImage(img)
		}
		if rl.IsTextureValid(app.e_texture_view.preview_tex) {
			app.e_texture_view.preview_w = img.width
			app.e_texture_view.preview_h = img.height
			app.e_texture_view.valid = true
		} else {
			rl.UnloadTexture(app.e_texture_view.preview_tex)
			app.e_texture_view.valid = false
			draw_ui_text(app, "Texture unavailable",
				i32(content.x) + 10, i32(content.y) + 20, 12, CONTENT_TEXT_COLOR)
			draw_ui_text(app, "Failed to upload to GPU.",
				i32(content.x) + 10, i32(content.y) + 42, 10, rl.Color{160, 80, 80, 200})
			return
		}
	}

	if !app.e_texture_view.valid do return

	tw := f32(app.e_texture_view.preview_w)
	th := f32(app.e_texture_view.preview_h)
	if tw <= 0 || th <= 0 do return
	content_aspect := content.width / content.height
	tex_aspect := tw / th
	preview_w, preview_h: f32
	if content_aspect > tex_aspect {
		preview_h = content.height
		preview_w = content.height * tex_aspect
	} else {
		preview_w = content.width
		preview_h = content.width / tex_aspect
	}
	dest := rl.Rectangle{
		content.x + (content.width - preview_w) * 0.5,
		content.y + (content.height - preview_h) * 0.5,
		preview_w,
		preview_h,
	}
	src := rl.Rectangle{0, 0, tw, th}
	rl.DrawTexturePro(app.e_texture_view.preview_tex, src, dest, rl.Vector2{0, 0}, 0.0, rl.WHITE)
}
