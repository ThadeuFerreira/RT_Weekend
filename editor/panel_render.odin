package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

// Aspect ratio indices (used by r_aspect_ratio and legacy/ImGui render panels).
RENDER_ASPECT_4_3  :: 0
RENDER_ASPECT_16_9 :: 1

// get_aspect_ratio returns the aspect ratio for the given index (0=4:3, 1=16:9).
get_aspect_ratio :: proc(idx: int) -> f32 {
    if idx == RENDER_ASPECT_4_3 { return 4.0 / 3.0 }
    return 16.0 / 9.0
}

// get_render_aspect returns the aspect ratio (width/height) used by the render from app.r_aspect_ratio.
get_render_aspect :: proc(app: ^App) -> f32 {
    return get_aspect_ratio(app.r_aspect_ratio)
}

// Input field constants
RENDER_INPUT_H :: f32(22)
RENDER_INPUT_W :: f32(70)
RENDER_DROPDOWN_W :: f32(80)
RENDER_ROW_H :: f32(28)

// Layout constants - shared between draw and update
RENDER_PADDING_X :: f32(10)     // Left padding
RENDER_HEIGHT_LABEL_W :: f32(45)  // Width for "Height:" label
RENDER_HEIGHT_X :: f32(10)      // Height input starts at left padding
RENDER_ASPECT_X :: f32(135)     // Aspect dropdown: RENDER_HEIGHT_X + 125
RENDER_ASPECT_LABEL_W :: f32(55)  // Width for "Aspect:" label
RENDER_SAMPLES_X :: f32(280)    // Samples input: RENDER_ASPECT_X + 145
RENDER_SAMPLES_LABEL_W :: f32(60) // Width for "Samples:" label
RENDER_INFO_X :: f32(405)       // Info text: RENDER_SAMPLES_X + 125
RENDER_PROGRESS_TOGGLE_X :: f32(10)
RENDER_PROGRESS_TOGGLE_Y :: f32(RENDER_ROW_H + 6)
RENDER_PROGRESS_TOGGLE_W :: f32(120)

// Resolution bounds (16k max, 720p min)
MIN_RENDER_HEIGHT :: 720
MAX_RENDER_HEIGHT :: 16384
MIN_RENDER_WIDTH :: 1280  // 720p at 16:9 is 1280x720
MAX_RENDER_WIDTH :: 16384

// calculate_render_dimensions computes width and height from app settings.
// Returns false if dimensions are out of bounds (16k max, 720p min).
calculate_render_dimensions :: proc(app: ^App) -> (width, height: int, ok: bool) {
	h, h_ok := strconv.parse_int(strings.trim_space(app.r_height_input))
	if !h_ok || h <= 0 {
		return 0, 0, false
	}
	aspect := get_render_aspect(app)
	w := int(f32(h) * aspect)

	if h < MIN_RENDER_HEIGHT || h > MAX_RENDER_HEIGHT {
		return w, h, false
	}
	if w < MIN_RENDER_WIDTH || w > MAX_RENDER_WIDTH {
		return w, h, false
	}

	return w, h, true
}

// render_settings_height returns the height of the settings area above the render preview.

restart_render_with_settings :: proc(app: ^App, width, height, samples: int) {
    if !app.finished { return }

    // Free old session
    rt.free_session(app.r_session)
    app.r_session = nil

    // Recreate Vulkan render texture at new resolution
    imgui_vk_destroy_texture(&app.vk_render_tex)
    {
        t, ok := imgui_vk_create_texture(i32(width), i32(height))
        if !ok {
            fmt.eprintln("Failed to recreate Vulkan render texture")
            return
        }
        app.vk_render_tex = t
    }

    // Reallocate pixel staging buffer
    delete(app.pixel_staging)
    app.pixel_staging = make([]rl.Color, width * height)

    // Create new camera with new settings and apply current camera params (Viewport / Camera panel state).
    old_cam := app.r_camera
    app.r_camera = rt.make_camera(width, height, samples)
    rt.apply_scene_camera(app.r_camera, &app.c_camera_params)
    rt.init_camera(app.r_camera)
    free(old_cam)

    // Reset render state
    app.finished = false
    app.elapsed_secs = 0
    app.render_start = time.now()
    app.r_render_pending = false

    // Start new render
    _ = app_start_render_session(app)
    app_push_log(app, fmt.tprintf("Rendering at %dx%d with %d samples...", width, height, samples))
}

