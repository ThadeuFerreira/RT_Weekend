package ui

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

DEFAULT_CHARSET_COUNT :: 95
// Feature flag: set to true to enable SDF/custom font loading; false uses raylib default font only.
// Override at build time: odin build ... -define:USE_SDF_FONT=true
USE_SDF_FONT :: #config(USE_SDF_FONT, false)
// Base size when loading the font; must be >= max glyph size to avoid "size is bigger than expected font size" (e.g. for '}' 0x7d).
SDF_BASE_SIZE         :: 32
FONTEX_FALLBACK_SIZE  :: 32

// make_asset_path returns an absolute path for a relative asset (e.g. "assets/fonts/x.ttf") using current working directory.
make_asset_path :: proc(relative: cstring) -> string {
	cwd := rl.GetWorkingDirectory()
	cwd_str := strings.clone_from_cstring(cwd)
	defer delete(cwd_str)
	return fmt.aprintf("%s/%s", cwd_str, relative)
}

// load_sdf_font loads a TTF from font_path, builds an SDF font atlas, and loads the SDF fragment shader from shader_path.
// Uses absolute paths (cwd + relative). base_size 16 is used for SDF (raylib example). Returns (font, shader, true) on SDF success.
load_sdf_font :: proc(font_path: cstring, shader_path: cstring, base_size: i32) -> (font: rl.Font, shader: rl.Shader, ok: bool) {
	full_font := make_asset_path(font_path)
	defer delete(full_font)
	font_cstr := strings.clone_to_cstring(full_font)
	defer delete(font_cstr)

	data_size: c.int
	file_data := rl.LoadFileData(font_cstr, &data_size)
	if file_data == nil || data_size <= 0 {
		fmt.eprintln("[SDF] ERROR: failed to load font file:", font_cstr)
		return
	}
	defer rl.UnloadFileData(file_data)

	glyphs := rl.LoadFontData(rawptr(file_data), data_size, base_size, nil, DEFAULT_CHARSET_COUNT, rl.FontType.SDF)
	if glyphs == nil {
		fmt.eprintln("[SDF] ERROR: rl.LoadFontData returned nil glyphs")
		return
	}

	recs: [^]rl.Rectangle
	atlas := rl.GenImageFontAtlas(glyphs, &recs, DEFAULT_CHARSET_COUNT, base_size, 0, 1)
	if atlas.data == nil {
		fmt.eprintln("[SDF] ERROR: rl.GenImageFontAtlas returned empty image")
		rl.UnloadFontData(glyphs, DEFAULT_CHARSET_COUNT)
		return
	}
	defer rl.UnloadImage(atlas)

	font.baseSize     = base_size
	font.glyphCount   = DEFAULT_CHARSET_COUNT
	font.glyphPadding = 0
	font.texture      = rl.LoadTextureFromImage(atlas)
	font.recs         = recs
	font.glyphs       = glyphs

	if !rl.IsTextureValid(font.texture) {
		fmt.eprintln("[SDF] ERROR: font texture upload to GPU failed")
		rl.UnloadFontData(glyphs, DEFAULT_CHARSET_COUNT)
		return
	}

	if !rl.IsFontValid(font) {
		fmt.eprintln("[SDF] ERROR: rl.IsFontValid returned false")
		rl.UnloadFont(font)
		return
	}

	full_shader := make_asset_path(shader_path)
	defer delete(full_shader)
	shader_cstr := strings.clone_to_cstring(full_shader)
	defer delete(shader_cstr)
	shader = rl.LoadShader(nil, shader_cstr)
	if !rl.IsShaderValid(shader) {
		fmt.eprintln("[SDF] ERROR: SDF shader failed to load/compile:", shader_cstr)
		rl.UnloadFont(font)
		return
	}

	rl.SetTextureFilter(font.texture, .BILINEAR)
	ok = true
	return
}

// load_font_ex_fallback loads a TTF with LoadFontEx (no SDF) for better UI text when SDF is unavailable.
load_font_ex_fallback :: proc(font_path: cstring, font_size: i32) -> (font: rl.Font, ok: bool) {
	full := make_asset_path(font_path)
	defer delete(full)
	cstr := strings.clone_to_cstring(full)
	defer delete(cstr)
	font = rl.LoadFontEx(cstr, font_size, nil, 0)
	ok = rl.IsFontValid(font)
	return
}

unload_sdf_font :: proc(font: ^rl.Font, shader: rl.Shader) {
	if font != nil && rl.IsFontValid(font^) {
		rl.UnloadFont(font^)
		font^ = {}
	}
	if rl.IsShaderValid(shader) {
		rl.UnloadShader(shader)
	}
}

unload_ui_font :: proc(font: ^rl.Font, shader: rl.Shader, had_sdf: bool) {
	if font != nil && rl.IsFontValid(font^) {
		rl.UnloadFont(font^)
		font^ = {}
	}
	if had_sdf && rl.IsShaderValid(shader) {
		rl.UnloadShader(shader)
	}
}

draw_text_sdf :: proc(font: rl.Font, shader: rl.Shader, text: cstring, position: rl.Vector2, fontSize: f32, spacing: f32, color: rl.Color) {
	rl.BeginShaderMode(shader)
	rl.DrawTextEx(font, text, position, fontSize, spacing, color)
	rl.EndShaderMode()
}

measure_text_sdf :: proc(font: rl.Font, text: cstring, fontSize: f32, spacing: f32) -> rl.Vector2 {
	return rl.MeasureTextEx(font, text, fontSize, spacing)
}
