package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

// get_aspect_ratio returns the aspect ratio for the given index (0=4:3, 1=16:9).
get_aspect_ratio :: proc(idx: int) -> f32 {
    if idx == 0 { return 4.0 / 3.0 }
    return 16.0 / 9.0
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

// Resolution bounds (16k max, 720p min)
MIN_RENDER_HEIGHT :: 720
MAX_RENDER_HEIGHT :: 16384
MIN_RENDER_WIDTH :: 1280  // 720p at 16:9 is 1280x720
MAX_RENDER_WIDTH :: 16384

// render_settings_height returns the height of the settings area above the render preview.
render_settings_height :: proc() -> f32 {
    return RENDER_ROW_H + 8 // input row + padding
}

// draw_input_field draws a text input field with label.
// Returns the actual box rectangle for hit testing.
draw_input_field :: proc(
    app: ^App,
    label: cstring,
    text: string,
    x, y: f32,
    w, h: f32,
    active: bool,
    label_offset: f32 = 45,
) -> rl.Rectangle {
    // Label
    draw_ui_text(app, label, i32(x), i32(y + 4), 12, CONTENT_TEXT_COLOR)

    // Input box
    box := rl.Rectangle{x + label_offset, y, w, h}
    bg_color := active ? rl.Color{50, 60, 85, 255} : rl.Color{40, 42, 55, 255}
    border_color := active ? ACCENT_COLOR : BORDER_COLOR
    rl.DrawRectangleRec(box, bg_color)
    rl.DrawRectangleLinesEx(box, 1, border_color)

    // Text content (with cursor if active)
    display_text := text
    show_cursor := active && int(rl.GetTime() * 2) % 2 == 0
    if show_cursor {
        display_text = fmt.aprintf("%s_", text)
    }
    draw_ui_text(app, fmt.ctprintf("%s", display_text), i32(box.x + 6), i32(box.y + 4), 12, CONTENT_TEXT_COLOR)
    if show_cursor {
        delete(display_text)
    }

    return box
}

// draw_dropdown draws a dropdown selector for aspect ratio.
draw_dropdown :: proc(
    app: ^App,
    label: cstring,
    selected_idx: int,
    options: []cstring,
    x, y: f32,
    w, h: f32,
    active: bool,
) -> rl.Rectangle {
    // Label
    draw_ui_text(app, label, i32(x), i32(y + 4), 12, CONTENT_TEXT_COLOR)

    // Dropdown box
    box := rl.Rectangle{x + 55, y, w, h}
    bg_color := active ? rl.Color{50, 60, 85, 255} : rl.Color{40, 42, 55, 255}
    border_color := active ? ACCENT_COLOR : BORDER_COLOR
    rl.DrawRectangleRec(box, bg_color)
    rl.DrawRectangleLinesEx(box, 1, border_color)

    // Selected text
    if selected_idx >= 0 && selected_idx < len(options) {
        draw_ui_text(app, options[selected_idx], i32(box.x + 6), i32(box.y + 4), 12, CONTENT_TEXT_COLOR)
    }

    // Dropdown arrow
    arrow_x := box.x + box.width - 14
    arrow_y := box.y + box.height * 0.5
    rl.DrawLineEx(rl.Vector2{arrow_x, arrow_y - 3}, rl.Vector2{arrow_x + 6, arrow_y + 3}, 1, CONTENT_TEXT_COLOR)
    rl.DrawLineEx(rl.Vector2{arrow_x + 6, arrow_y - 3}, rl.Vector2{arrow_x, arrow_y + 3}, 1, CONTENT_TEXT_COLOR)

    return box
}


// restart_render_with_settings creates a new camera with the specified resolution and samples,
// rebuilds the render texture, and starts a fresh render.
restart_render_with_settings :: proc(app: ^App, width, height, samples: int) {
    if !app.finished { return }

    // Validate resolution bounds
    if height < MIN_RENDER_HEIGHT || height > MAX_RENDER_HEIGHT {
        app_push_log(app, fmt.aprintf("Warning: Height %d is out of bounds (%d-%d)", height, MIN_RENDER_HEIGHT, MAX_RENDER_HEIGHT))
        return
    }
    if width < MIN_RENDER_WIDTH || width > MAX_RENDER_WIDTH {
        app_push_log(app, fmt.aprintf("Warning: Width %d is out of bounds (%d-%d)", width, MIN_RENDER_WIDTH, MAX_RENDER_WIDTH))
        return
    }

    // Free old session
    rt.free_session(app.r_session)
    app.r_session = nil

    // Unload and recreate render texture
    rl.UnloadTexture(app.render_tex)
    img := rl.GenImageColor(i32(width), i32(height), rl.BLACK)
    app.render_tex = rl.LoadTextureFromImage(img)
    rl.UnloadImage(img)

    // Reallocate pixel staging buffer
    delete(app.pixel_staging)
    app.pixel_staging = make([]rl.Color, width * height)

    // Create new camera with new settings
    old_cam := app.r_camera
    app.r_camera = rt.make_camera(width, height, samples)

    // Copy over camera position/orientation params from old camera
    app.r_camera.lookfrom = old_cam.lookfrom
    app.r_camera.lookat = old_cam.lookat
    app.r_camera.vup = old_cam.vup
    app.r_camera.vfov = old_cam.vfov
    app.r_camera.defocus_angle = old_cam.defocus_angle
    app.r_camera.focus_dist = old_cam.focus_dist
    app.r_camera.max_depth = old_cam.max_depth

    // Initialize camera with new dimensions
    rt.init_camera(app.r_camera)

    // Update scene params to match
    rt.copy_camera_to_scene_params(&app.c_camera_params, app.r_camera)

    // Free old camera
    free(old_cam)

    // Reset render state
    app.finished = false
    app.elapsed_secs = 0
    app.render_start = time.now()
    app.r_render_pending = false

    // Start new render
    app.r_session = rt.start_render_auto(app.r_camera, app.r_world, app.num_threads, app.prefer_gpu)
    app_push_log(app, fmt.aprintf("Rendering at %dx%d with %d samples...", width, height, samples))
}

draw_render_content :: proc(app: ^App, content: rl.Rectangle) {
    // Calculate settings area height
    settings_h := render_settings_height()

    // Draw settings background
    settings_rect := rl.Rectangle{content.x, content.y, content.width, settings_h}
    rl.DrawRectangleRec(settings_rect, rl.Color{30, 32, 45, 255})
    rl.DrawLine(i32(content.x), i32(content.y + settings_h), i32(content.x + content.width), i32(content.y + settings_h), BORDER_COLOR)

    // Input row
    input_y := content.y + 4
    base_x := content.x + RENDER_PADDING_X

    // Height input
    height_box := draw_input_field(
        app,
        "Height:",
        app.r_height_input,
        base_x + RENDER_HEIGHT_X, input_y, RENDER_INPUT_W, RENDER_INPUT_H,
        app.r_active_input == 1,
        RENDER_HEIGHT_LABEL_W,
    )

    // Aspect ratio dropdown
    aspect_options := [2]cstring{"4:3", "16:9"}
    aspect_box := draw_dropdown(
        app,
        "Aspect:",
        app.r_aspect_ratio,
        aspect_options[:],
        base_x + RENDER_ASPECT_X, input_y, RENDER_DROPDOWN_W, RENDER_INPUT_H,
        app.r_active_input == 3,
    )

    // Samples input
    samples_box := draw_input_field(
        app,
        "Samples:",
        app.r_samples_input,
        base_x + RENDER_SAMPLES_X, input_y, RENDER_INPUT_W, RENDER_INPUT_H,
        app.r_active_input == 2,
        RENDER_SAMPLES_LABEL_W,
    )

    // Show calculated width
    if width, height, ok := calculate_render_dimensions(app); ok {
        draw_ui_text(app, fmt.ctprintf("= %dx%d", width, height), i32(base_x + RENDER_INFO_X), i32(input_y + 4), 12, rl.Color{140, 150, 165, 255})
    }

    // Render preview area (below settings)
    preview_rect := rl.Rectangle{
        content.x,
        content.y + settings_h,
        content.width,
        content.height - settings_h,
    }

    if app.r_session == nil {
        // No active render - draw placeholder
        rl.DrawRectangleRec(preview_rect, rl.Color{20, 20, 30, 255})
        text := cstring("No active render")
        size := measure_ui_text(app, text, 16)
        text_x := i32(preview_rect.x + (preview_rect.width - f32(size.width)) * 0.5)
        text_y := i32(preview_rect.y + (preview_rect.height - f32(size.height)) * 0.5)
        draw_ui_text(app, text, text_x, text_y, 16, CONTENT_TEXT_COLOR)
        return
    }

    // Draw the rendered image (letterboxed)
    cam := app.r_session.r_camera
    src := rl.Rectangle{0, 0, f32(cam.image_width), f32(cam.image_height)}
    dest := render_dest_rect(app, preview_rect)
    rl.DrawTexturePro(app.render_tex, src, dest, rl.Vector2{0, 0}, 0, rl.WHITE)
}

update_render_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    settings_h := render_settings_height()

    // Recalculate same positions as draw_render_content using shared constants
    input_y := rect.y + 4
    base_x := rect.x + RENDER_PADDING_X

    // Hitboxes must match draw_input_field offsets
    height_box := rl.Rectangle{base_x + RENDER_HEIGHT_X + RENDER_HEIGHT_LABEL_W, input_y, RENDER_INPUT_W, RENDER_INPUT_H}
    aspect_box := rl.Rectangle{base_x + RENDER_ASPECT_X + RENDER_ASPECT_LABEL_W, input_y, RENDER_DROPDOWN_W, RENDER_INPUT_H}
    samp_box := rl.Rectangle{base_x + RENDER_SAMPLES_X + RENDER_SAMPLES_LABEL_W, input_y, RENDER_INPUT_W, RENDER_INPUT_H}

    if lmb_pressed {
        // Check which input was clicked
        if rl.CheckCollisionPointRec(mouse, height_box) {
            app.r_active_input = 1
            if g_app != nil { g_app.input_consumed = true }
        } else if rl.CheckCollisionPointRec(mouse, samp_box) {
            app.r_active_input = 2
            if g_app != nil { g_app.input_consumed = true }
        } else if rl.CheckCollisionPointRec(mouse, aspect_box) {
            app.r_active_input = 3
            if g_app != nil { g_app.input_consumed = true }
        } else {
            // Clicked outside inputs - deactivate
            app.r_active_input = 0
        }
    }

    // Handle aspect ratio dropdown toggle
    if app.r_active_input == 3 && lmb_pressed && rl.CheckCollisionPointRec(mouse, aspect_box) {
        // Toggle between aspect ratios
        app.r_aspect_ratio = (app.r_aspect_ratio + 1) % 2
        app.r_render_pending = true
        if g_app != nil { g_app.input_consumed = true }
    }

    // Handle text input when an input is active
    if app.r_active_input > 0 && app.r_active_input != 3 {
        // Get characters pressed this frame
        for {
            ch := rl.GetCharPressed()
            if ch == 0 { break }

            // Only accept digits for height and samples
            valid := (ch >= '0' && ch <= '9')

            if valid {
                if app.r_active_input == 1 {
                    if len(app.r_height_input) < 5 { // Cap at 5 digits (max ~99999)
                        old := app.r_height_input
                        app.r_height_input = strings.concatenate({old, string([]u8{u8(ch)})})
                        delete(old)
                        app.r_render_pending = true
                    }
                } else if app.r_active_input == 2 {
                    if len(app.r_samples_input) < 4 { // Cap at 4 digits (max ~9999)
                        old := app.r_samples_input
                        app.r_samples_input = strings.concatenate({old, string([]u8{u8(ch)})})
                        delete(old)
                        app.r_render_pending = true
                    }
                }
            }
        }

        // Handle backspace
        if rl.IsKeyPressed(.BACKSPACE) {
            if app.r_active_input == 1 && len(app.r_height_input) > 0 {
                app.r_height_input = app.r_height_input[:len(app.r_height_input)-1]
                app.r_render_pending = true
            } else if app.r_active_input == 2 && len(app.r_samples_input) > 0 {
                app.r_samples_input = app.r_samples_input[:len(app.r_samples_input)-1]
                app.r_render_pending = true
            }
        }
    }
}

// render_dest_rect computes the letterboxed on-screen destination rectangle for the
// render texture inside the given content area. Shared by drawing and hit-testing.
render_dest_rect :: proc(app: ^App, content: rl.Rectangle) -> rl.Rectangle {
    if app.r_session == nil {
        return content
    }
    cam := app.r_session.r_camera
    src_w := f32(cam.image_width)
    src_h := f32(cam.image_height)
    aspect := src_w / src_h

    dest_w := content.width
    dest_h := content.height
    if dest_w / dest_h > aspect {
        dest_w = dest_h * aspect
    } else {
        dest_h = dest_w / aspect
    }

    ox := content.x + (content.width - dest_w) * 0.5
    oy := content.y + (content.height - dest_h) * 0.5
    return rl.Rectangle{ox, oy, dest_w, dest_h}
}
