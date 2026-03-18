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
    kind:      ContentBrowserAssetKind,
    name:      string,
    path:      string,
    name_lower: string,
    path_lower: string,
}

ContentBrowserState :: struct {
    assets:         [dynamic]ContentBrowserAsset,
    selected_idx:   int,
    scroll_y:       f32,
    filter_input:   [CONTENT_BROWSER_FILTER_MAX]u8,
    filter_len:     int,
    filter_active:  bool,
    filter_lower:   string,
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
        delete(asset.name_lower)
        delete(asset.path_lower)
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
    delete(st.filter_lower)
    st.filter_lower = ""
}

content_browser_filter_string :: proc(st: ^ContentBrowserState) -> string {
    if st == nil || st.filter_len <= 0 { return "" }
    return string(st.filter_input[:st.filter_len])
}

content_browser_matches_filter :: proc(asset: ContentBrowserAsset, filter_lower: string) -> bool {
    if len(filter_lower) == 0 { return true }
    return strings.contains(asset.name_lower, filter_lower) || strings.contains(asset.path_lower, filter_lower)
}

content_browser_append_asset :: proc(st: ^ContentBrowserState, kind: ContentBrowserAssetKind, root: string, fi: os.File_Info) {
    rel_path := strings.concatenate({root, filepath.SEPARATOR_STRING, fi.name})
    name_lower := strings.to_lower(fi.name)
    path_lower := strings.to_lower(rel_path)
    defer delete(name_lower)
    defer delete(path_lower)
    append(&st.assets, ContentBrowserAsset{
        kind       = kind,
        name       = strings.clone(fi.name),
        path       = rel_path,
        name_lower = strings.clone(name_lower),
        path_lower = strings.clone(path_lower),
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

