package editor

// ImguiPanelVis tracks which Dear ImGui panels are currently open.
// Each field maps 1-to-1 with an imgui.Begin p_open argument so ImGui's
// built-in close button writes directly to the bool.
ImguiPanelVis :: struct {
    render:          bool,
    unified_viewport: bool,
    stats:           bool,
    console:         bool,
    system_info:     bool,
    camera:          bool,
    details:         bool,
    camera_preview:  bool,
    texture_view:    bool,
    content_browser: bool,
    outliner:        bool,
    imgui_metrics:   bool,
}

// _imgui_panel_vis_ptr returns a pointer to the visibility bool for the
// given panel ID, or nil if the ID is unrecognised.
_imgui_panel_vis_ptr :: proc(vis: ^ImguiPanelVis, id: string) -> ^bool {
    switch id {
    case PANEL_ID_RENDER:          return &vis.render
    case PANEL_ID_UNIFIED_VIEWPORT:return &vis.unified_viewport
    case PANEL_ID_STATS:           return &vis.stats
    case PANEL_ID_CONSOLE:         return &vis.console
    case PANEL_ID_SYSTEM_INFO:     return &vis.system_info
    case PANEL_ID_CAMERA:          return &vis.camera
    case PANEL_ID_DETAILS:         return &vis.details
    case PANEL_ID_CAMERA_PREVIEW:  return &vis.camera_preview
    case PANEL_ID_TEXTURE_VIEW:    return &vis.texture_view
    case PANEL_ID_CONTENT_BROWSER: return &vis.content_browser
    case PANEL_ID_OUTLINER:        return &vis.outliner
    }
    return nil
}
