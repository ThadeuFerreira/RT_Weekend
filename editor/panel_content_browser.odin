package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"
import "RT_Weekend:core"

CONTENT_BROWSER_FILTER_MAX :: 128
CONTENT_BROWSER_ROW_H      :: f32(22)

ContentBrowserAssetKind :: enum {
    Texture,
    Scene,
}

ContentBrowserAsset :: struct {
    kind: ContentBrowserAssetKind,
    name: string,
    path: string,
}

ContentBrowserState :: struct {
    assets:         [dynamic]ContentBrowserAsset,
    selected_idx:   int,
    scroll_y:       f32,
    filter_input:   [CONTENT_BROWSER_FILTER_MAX]u8,
    filter_len:     int,
    filter_active:  bool,
    scanned:        bool,
    scan_requested: bool,

    preview_tex:    rl.Texture2D,
    preview_w:      i32,
    preview_h:      i32,
    preview_valid:  bool,
    preview_sig:    string,
}

content_browser_free_assets :: proc(st: ^ContentBrowserState) {
    if st == nil { return }
    for asset in st.assets {
        delete(asset.name)
        delete(asset.path)
    }
    delete(st.assets)
    st.assets = nil
    st.selected_idx = -1
}

content_browser_clear_preview :: proc(st: ^ContentBrowserState) {
    if st == nil { return }
    if st.preview_valid {
        rl.UnloadTexture(st.preview_tex)
        st.preview_valid = false
    }
    delete(st.preview_sig)
    st.preview_sig = ""
    st.preview_w = 0
    st.preview_h = 0
}

content_browser_free_state :: proc(st: ^ContentBrowserState) {
    if st == nil { return }
    content_browser_clear_preview(st)
    content_browser_free_assets(st)
}

content_browser_filter_string :: proc(st: ^ContentBrowserState) -> string {
    if st == nil || st.filter_len <= 0 { return "" }
    return string(st.filter_input[:st.filter_len])
}

content_browser_matches_filter :: proc(asset: ContentBrowserAsset, filter: string) -> bool {
    if len(filter) == 0 { return true }
    filter_lower := strings.to_lower(filter)
    defer delete(filter_lower)
    name_lower := strings.to_lower(asset.name)
    defer delete(name_lower)
    if strings.contains(name_lower, filter_lower) { return true }
    path_lower := strings.to_lower(asset.path)
    defer delete(path_lower)
    return strings.contains(path_lower, filter_lower)
}

content_browser_append_asset :: proc(st: ^ContentBrowserState, kind: ContentBrowserAssetKind, root: string, fi: os.File_Info) {
    rel_path := strings.concatenate({root, filepath.SEPARATOR_STRING, fi.name})
    append(&st.assets, ContentBrowserAsset{
        kind = kind,
        name = strings.clone(fi.name),
        path = rel_path,
    })
}

content_browser_is_texture_file :: proc(name: string) -> bool {
    lower := strings.to_lower(name)
    defer delete(lower)
    return strings.has_suffix(lower, ".png") || strings.has_suffix(lower, ".jpg") || strings.has_suffix(lower, ".jpeg")
}

content_browser_is_scene_file :: proc(name: string) -> bool {
    lower := strings.to_lower(name)
    defer delete(lower)
    return strings.has_suffix(lower, ".json")
}

content_browser_scan_root :: proc(st: ^ContentBrowserState, root: string, kind: ContentBrowserAssetKind) {
    if st == nil { return }
    f, open_err := os.open(root, os.O_RDONLY)
    if open_err != os.ERROR_NONE { return }
    defer os.close(f)

    fis, read_err := os.read_dir(f, -1)
    if read_err != os.ERROR_NONE { return }
    defer os.file_info_slice_delete(fis)

    slice.sort_by(fis, proc(a, b: os.File_Info) -> bool {
        return a.name < b.name
    })

    for fi in fis {
        if fi.is_dir { continue }
        switch kind {
        case .Texture:
            if !content_browser_is_texture_file(fi.name) { continue }
        case .Scene:
            if !content_browser_is_scene_file(fi.name) { continue }
        }
        content_browser_append_asset(st, kind, root, fi)
    }
}

content_browser_scan_assets :: proc(app: ^App) {
    if app == nil { return }
    st := &app.e_content_browser
    content_browser_free_assets(st)
    content_browser_clear_preview(st)
    st.scroll_y = 0

    content_browser_scan_root(st, "assets/textures", .Texture)
    content_browser_scan_root(st, "scenes", .Scene)

    st.scanned = true
    st.scan_requested = false
    if len(st.assets) > 0 {
        st.selected_idx = clamp(st.selected_idx, 0, len(st.assets) - 1)
    } else {
        st.selected_idx = -1
    }
}

content_browser_selected_asset :: proc(app: ^App) -> ^ContentBrowserAsset {
    if app == nil { return nil }
    st := &app.e_content_browser
    if st.selected_idx < 0 || st.selected_idx >= len(st.assets) { return nil }
    return &st.assets[st.selected_idx]
}

content_browser_assign_texture :: proc(app: ^App, texture_path: string) -> bool {
    if app == nil || len(texture_path) == 0 { return false }
    ev := &app.e_edit_view
    if ev.selection_kind != .Sphere || ev.selected_idx < 0 {
        app_push_log(app, strings.clone("Content Browser: select a sphere first"))
        return false
    }
    sphere, ok := GetSceneSphere(ev.scene_mgr, ev.selected_idx)
    if !ok {
        app_push_log(app, strings.clone("Content Browser: selected sphere unavailable"))
        return false
    }
    if sphere.material_kind != .Lambertian {
        app_push_log(app, strings.clone("Content Browser: image textures require a Lambertian sphere"))
        return false
    }

    owned_path := strings.clone(texture_path)
    before := sphere
    sphere.albedo = core.ImageTexture{path = owned_path}
    sphere.texture_kind = .Image
    sphere.image_path = owned_path
    app_ensure_image_cached(app, owned_path)
    SetSceneSphere(ev.scene_mgr, ev.selected_idx, sphere)
    edit_history_push(&app.edit_history, ModifySphereAction{idx = ev.selected_idx, before = before, after = sphere})
    mark_scene_dirty(app)
    app_push_log(app, fmt.aprintf("Texture assigned: %s", filepath.base(texture_path)))
    return true
}

content_browser_open_scene :: proc(app: ^App, scene_path: string) {
    if app == nil || len(scene_path) == 0 { return }
    file_import_from_path(app, strings.clone(scene_path))
}

content_browser_ensure_preview :: proc(app: ^App) {
    if app == nil { return }
    st := &app.e_content_browser
    asset := content_browser_selected_asset(app)
    if asset == nil || asset.kind != .Texture {
        content_browser_clear_preview(st)
        return
    }

    sig := fmt.aprintf("texture %s", asset.path)
    defer delete(sig)
    if st.preview_valid && st.preview_sig == sig { return }

    content_browser_clear_preview(st)

    img, buf_to_free, ok := texture_view_build_image(app, core.ImageTexture{path = asset.path})
    if !ok { return }

    st.preview_tex = rl.LoadTextureFromImage(img)
    if buf_to_free != nil {
        delete(buf_to_free)
    } else {
        rl.UnloadImage(img)
    }
    if !rl.IsTextureValid(st.preview_tex) {
        rl.UnloadTexture(st.preview_tex)
        return
    }

    st.preview_valid = true
    st.preview_w = img.width
    st.preview_h = img.height
    st.preview_sig = strings.clone(sig)
}

content_browser_layout :: proc(content: rl.Rectangle) -> (filter_rect, refresh_rect, list_rect, preview_rect, primary_btn, secondary_btn: rl.Rectangle) {
    padding := f32(8)
    filter_h := f32(22)
    button_w := f32(70)

    filter_rect = rl.Rectangle{content.x + padding, content.y + padding, content.width - padding*3 - button_w, filter_h}
    refresh_rect = rl.Rectangle{filter_rect.x + filter_rect.width + padding, filter_rect.y, button_w, filter_h}

    body_y := filter_rect.y + filter_h + padding
    body_h := content.height - (body_y - content.y) - padding
    list_w := max(content.width * 0.52, f32(160))
    list_rect = rl.Rectangle{content.x + padding, body_y, list_w, body_h}

    side_x := list_rect.x + list_rect.width + padding
    side_w := max(content.x + content.width - side_x - padding, f32(120))
    preview_h := max(body_h - 56, f32(100))
    preview_rect = rl.Rectangle{side_x, body_y, side_w, preview_h}
    primary_btn = rl.Rectangle{side_x, preview_rect.y + preview_rect.height + padding, side_w, 22}
    secondary_btn = rl.Rectangle{side_x, primary_btn.y + 26, side_w, 22}
    return
}

content_browser_draw_button :: proc(app: ^App, rect: rl.Rectangle, label: cstring, enabled: bool, hovered: bool) {
    bg := rl.Color{56, 60, 74, 255}
    fg := CONTENT_TEXT_COLOR
    if !enabled {
        bg = rl.Color{38, 40, 48, 255}
        fg = rl.Color{120, 126, 140, 180}
    } else if hovered {
        bg = rl.Color{72, 78, 98, 255}
    }
    rl.DrawRectangleRec(rect, bg)
    rl.DrawRectangleLinesEx(rect, 1, BORDER_COLOR)
    draw_ui_text(app, label, i32(rect.x) + 8, i32(rect.y) + 4, 10, fg)
}

draw_content_browser_content :: proc(app: ^App, content: rl.Rectangle) {
    if app == nil { return }
    st := &app.e_content_browser
    if st.scan_requested || !st.scanned {
        content_browser_scan_assets(app)
    }

    filter_rect, refresh_rect, list_rect, preview_rect, primary_btn, secondary_btn := content_browser_layout(content)
    mouse := rl.GetMousePosition()
    filter_text := content_browser_filter_string(st)

    border_color := BORDER_COLOR
    if st.filter_active { border_color = ACCENT_COLOR }
    rl.DrawRectangleRec(filter_rect, rl.Color{28, 31, 38, 255})
    rl.DrawRectangleLinesEx(filter_rect, 1, border_color)
    if len(filter_text) > 0 {
        draw_ui_text(app, strings.clone_to_cstring(filter_text, context.temp_allocator), i32(filter_rect.x) + 6, i32(filter_rect.y) + 4, 10, CONTENT_TEXT_COLOR)
    } else {
        draw_ui_text(app, "Filter assets...", i32(filter_rect.x) + 6, i32(filter_rect.y) + 4, 10, rl.Color{130, 138, 152, 180})
    }
    content_browser_draw_button(app, refresh_rect, "Refresh", true, rl.CheckCollisionPointRec(mouse, refresh_rect))

    visible_count := 0
    for asset in st.assets {
        if content_browser_matches_filter(asset, filter_text) { visible_count += 1 }
    }
    total_h := f32(visible_count) * CONTENT_BROWSER_ROW_H
    st.scroll_y = clamp(st.scroll_y, 0, max(total_h - list_rect.height, 0))

    rl.DrawRectangleRec(list_rect, rl.Color{20, 22, 28, 255})
    rl.DrawRectangleLinesEx(list_rect, 1, BORDER_COLOR)
    rl.BeginScissorMode(i32(list_rect.x), i32(list_rect.y), i32(list_rect.width), i32(list_rect.height))
    defer rl.EndScissorMode()

    row := 0
    for asset, asset_idx in st.assets {
        if !content_browser_matches_filter(asset, filter_text) { continue }
        ry := list_rect.y + f32(row) * CONTENT_BROWSER_ROW_H - st.scroll_y
        row += 1
        if ry + CONTENT_BROWSER_ROW_H < list_rect.y || ry > list_rect.y + list_rect.height { continue }

        row_rect := rl.Rectangle{list_rect.x, ry, list_rect.width, CONTENT_BROWSER_ROW_H}
        selected := asset_idx == st.selected_idx
        if selected {
            rl.DrawRectangleRec(row_rect, rl.Color{60, 100, 160, 200})
        } else if rl.CheckCollisionPointRec(mouse, row_rect) {
            rl.DrawRectangleRec(row_rect, rl.Color{45, 50, 65, 180})
        }

        prefix := "T"
        if asset.kind == .Scene { prefix = "S" }
        label := fmt.ctprintf("[%s] %s", prefix, asset.name)
        draw_ui_text(app, label, i32(row_rect.x) + 8, i32(row_rect.y) + 4, 10, CONTENT_TEXT_COLOR)
    }

    if visible_count == 0 {
        draw_ui_text(app, "No assets match the current filter", i32(list_rect.x) + 8, i32(list_rect.y) + 8, 10, rl.Color{140, 150, 165, 200})
    }

    asset := content_browser_selected_asset(app)
    content_browser_ensure_preview(app)

    rl.DrawRectangleRec(preview_rect, rl.Color{20, 22, 28, 255})
    rl.DrawRectangleLinesEx(preview_rect, 1, BORDER_COLOR)

    if asset == nil {
        draw_ui_text(app, "Select an asset", i32(preview_rect.x) + 8, i32(preview_rect.y) + 8, 12, CONTENT_TEXT_COLOR)
    } else {
        draw_ui_text(app, strings.clone_to_cstring(asset.name, context.temp_allocator), i32(preview_rect.x) + 8, i32(preview_rect.y) + 8, 12, CONTENT_TEXT_COLOR)
        draw_ui_text(app, strings.clone_to_cstring(asset.path, context.temp_allocator), i32(preview_rect.x) + 8, i32(preview_rect.y) + 28, 10, rl.Color{140, 150, 165, 200})

        if asset.kind == .Texture && st.preview_valid && st.preview_w > 0 && st.preview_h > 0 {
            tw := f32(st.preview_w)
            th := f32(st.preview_h)
            avail := rl.Rectangle{preview_rect.x + 8, preview_rect.y + 48, preview_rect.width - 16, preview_rect.height - 56}
            tex_aspect := tw / th
            box_aspect := avail.width / avail.height
            draw_w, draw_h: f32
            if box_aspect > tex_aspect {
                draw_h = avail.height
                draw_w = draw_h * tex_aspect
            } else {
                draw_w = avail.width
                draw_h = draw_w / tex_aspect
            }
            dest := rl.Rectangle{
                avail.x + (avail.width - draw_w) * 0.5,
                avail.y + (avail.height - draw_h) * 0.5,
                draw_w,
                draw_h,
            }
            rl.DrawTexturePro(st.preview_tex, rl.Rectangle{0, 0, tw, th}, dest, rl.Vector2{}, 0, rl.WHITE)
        } else if asset.kind == .Scene {
            draw_ui_text(app, "Scene asset", i32(preview_rect.x) + 8, i32(preview_rect.y) + 52, 11, CONTENT_TEXT_COLOR)
            draw_ui_text(app, "Use Open Scene to load it into the editor.", i32(preview_rect.x) + 8, i32(preview_rect.y) + 72, 10, rl.Color{140, 150, 165, 200})
        } else {
            draw_ui_text(app, "Texture preview unavailable", i32(preview_rect.x) + 8, i32(preview_rect.y) + 52, 10, rl.Color{160, 120, 120, 220})
        }
    }

    primary_enabled := asset != nil && asset.kind == .Texture
    secondary_enabled := asset != nil && asset.kind == .Scene
    content_browser_draw_button(app, primary_btn, "Assign Texture", primary_enabled, primary_enabled && rl.CheckCollisionPointRec(mouse, primary_btn))
    content_browser_draw_button(app, secondary_btn, "Open Scene", secondary_enabled, secondary_enabled && rl.CheckCollisionPointRec(mouse, secondary_btn))
}

update_content_browser_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    _ = lmb
    if app == nil { return }
    st := &app.e_content_browser
    if st.scan_requested || !st.scanned {
        content_browser_scan_assets(app)
    }

    filter_rect, refresh_rect, list_rect, _, primary_btn, secondary_btn := content_browser_layout(rect)

    if st.filter_active {
        for {
            ch := rl.GetCharPressed()
            if ch == 0 { break }
            if st.filter_len < CONTENT_BROWSER_FILTER_MAX - 1 {
                st.filter_input[st.filter_len] = u8(ch)
                st.filter_len += 1
            }
        }
        if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
            if st.filter_len > 0 {
                st.filter_len -= 1
                st.filter_input[st.filter_len] = 0
            }
        }
        if rl.IsKeyPressed(.ESCAPE) {
            st.filter_active = false
        }
    }

    if rl.CheckCollisionPointRec(mouse, list_rect) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            filter_text := content_browser_filter_string(st)
            visible_count := 0
            for asset in st.assets {
                if content_browser_matches_filter(asset, filter_text) { visible_count += 1 }
            }
            max_scroll := max(f32(visible_count) * CONTENT_BROWSER_ROW_H - list_rect.height, 0)
            st.scroll_y = clamp(st.scroll_y - wheel * CONTENT_BROWSER_ROW_H * 3, 0, max_scroll)
            app.input_consumed = true
        }
    }

    if !lmb_pressed { return }
    if !rl.CheckCollisionPointRec(mouse, rect) { return }
    app.input_consumed = true

    if rl.CheckCollisionPointRec(mouse, filter_rect) {
        st.filter_active = true
        return
    }
    st.filter_active = false

    if rl.CheckCollisionPointRec(mouse, refresh_rect) {
        st.scan_requested = true
        return
    }

    if rl.CheckCollisionPointRec(mouse, primary_btn) {
        if asset := content_browser_selected_asset(app); asset != nil && asset.kind == .Texture {
            _ = content_browser_assign_texture(app, asset.path)
        }
        return
    }

    if rl.CheckCollisionPointRec(mouse, secondary_btn) {
        if asset := content_browser_selected_asset(app); asset != nil && asset.kind == .Scene {
            content_browser_open_scene(app, asset.path)
        }
        return
    }

    if rl.CheckCollisionPointRec(mouse, list_rect) {
        filter_text := content_browser_filter_string(st)
        local_y := mouse.y - list_rect.y + st.scroll_y
        row_hit := int(local_y / CONTENT_BROWSER_ROW_H)
        row := 0
        for asset, asset_idx in st.assets {
            if !content_browser_matches_filter(asset, filter_text) { continue }
            if row == row_hit {
                st.selected_idx = asset_idx
                if asset.kind == .Texture {
                    _ = content_browser_assign_texture(app, asset.path)
                }
                return
            }
            row += 1
        }
    }
}
