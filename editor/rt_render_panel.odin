package editor

import rl "vendor:raylib"
import rt "RT_Weekend:raytrace"

draw_render_content :: proc(app: ^App, content: rl.Rectangle) {
    cam  := app.r_session.r_camera
    src  := rl.Rectangle{0, 0, f32(cam.image_width), f32(cam.image_height)}
    dest := render_dest_rect(app, content)
    rl.DrawTexturePro(app.render_tex, src, dest, rl.Vector2{0, 0}, 0, rl.WHITE)
}


// render_dest_rect computes the letterboxed on-screen destination rectangle for the
// render texture inside the given content area. Shared by drawing and hit-testing.
render_dest_rect :: proc(app: ^App, content: rl.Rectangle) -> rl.Rectangle {
    cam    := app.r_session.r_camera
    src_w  := f32(cam.image_width)
    src_h  := f32(cam.image_height)
    aspect := src_w / src_h

    dest_w := content.width
    dest_h := content.height
    if dest_w / dest_h > aspect {
        dest_w = dest_h * aspect
    } else {
        dest_h = dest_w / aspect
    }

    ox := content.x + (content.width  - dest_w) * 0.5
    oy := content.y + (content.height - dest_h) * 0.5
    return rl.Rectangle{ox, oy, dest_w, dest_h}
}