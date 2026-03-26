package viewport

import rl "vendor:raylib"

ViewportTextureProvider :: struct {
	update: proc(provider: ^ViewportTextureProvider, app: rawptr),
	get_texture: proc(provider: ^ViewportTextureProvider, app: rawptr) -> rl.Texture2D,
	resize: proc(provider: ^ViewportTextureProvider, app: rawptr, width, height: int),
}

_provider_noop_update :: proc(provider: ^ViewportTextureProvider, app: rawptr) {
	_ = provider
	_ = app
}

_provider_noop_get_texture :: proc(provider: ^ViewportTextureProvider, app: rawptr) -> rl.Texture2D {
	_ = provider
	_ = app
	return rl.Texture2D{}
}

_provider_noop_resize :: proc(provider: ^ViewportTextureProvider, app: rawptr, width, height: int) {
	_ = provider
	_ = app
	_ = width
	_ = height
}

make_editor_texture_provider :: proc() -> ViewportTextureProvider {
	return ViewportTextureProvider{
		update = _provider_noop_update,
		get_texture = _provider_noop_get_texture,
		resize = _provider_noop_resize,
	}
}

make_raytrace_texture_provider :: proc() -> ViewportTextureProvider {
	return ViewportTextureProvider{
		update = _provider_noop_update,
		get_texture = _provider_noop_get_texture,
		resize = _provider_noop_resize,
	}
}
