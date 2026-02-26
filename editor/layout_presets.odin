package editor

import "RT_Weekend:interfaces"

// Built-in preset name constants.
PRESET_NAME_DEFAULT :: "Default"
PRESET_NAME_RENDER  :: "Rendering Focus"
PRESET_NAME_EDIT    :: "Editing Focus"

// layout_build_render_focus sets a layout optimized for viewing the render output.
// The render panel takes the full center; stats, log, camera in right column.
layout_build_render_focus :: proc(app: ^App, layout: ^DockLayout) {
    if app == nil || layout == nil { return }
    layout_init(layout)

    p_render := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_RENDER))
    p_stats  := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_STATS))
    p_log    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_LOG))
    p_cam    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_CAMERA))
    p_props  := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_OBJECT_PROPS))
    p_sys    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_SYSTEM_INFO))
    p_edit   := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_EDIT_VIEW))
    p_preview := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_PREVIEW_PORT))

    // Mark non-essential panels as hidden in this layout
    if ep := app_find_panel(app, PANEL_ID_EDIT_VIEW); ep != nil { ep.visible = false }
    if pp := app_find_panel(app, PANEL_ID_PREVIEW_PORT); pp != nil { pp.visible = false }

    center_leaf := layout_add_leaf(layout, []int{p_render, p_edit}, 0)
    right_top   := layout_add_leaf(layout, []int{p_stats, p_sys}, 0)
    right_bot   := layout_add_leaf(layout, []int{p_log, p_cam, p_props, p_preview}, 0)

    right_split := layout_add_split(layout, .DOCK_SPLIT_HORIZONTAL, right_top, right_bot, 0.4)
    root        := layout_add_split(layout, .DOCK_SPLIT_VERTICAL, center_leaf, right_split, 0.75)
    layout.root = root
    layout.center_leaf = center_leaf
    layout.center_split_view = false // Show only render, not split
    layout.center_split_ratio = 0.5
    layout.center_split_dragging = false
}

// layout_build_edit_focus sets a layout optimized for scene editing.
// Render is hidden by default; edit view takes center; props panel visible.
layout_build_edit_focus :: proc(app: ^App, layout: ^DockLayout) {
    if app == nil || layout == nil { return }
    layout_init(layout)

    p_render  := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_RENDER))
    p_edit    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_EDIT_VIEW))
    p_stats   := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_STATS))
    p_log     := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_LOG))
    p_cam     := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_CAMERA))
    p_props   := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_OBJECT_PROPS))
    p_sys     := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_SYSTEM_INFO))
    p_preview := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_PREVIEW_PORT))

    // Render panel hidden in edit focus
    if rp := app_find_panel(app, PANEL_ID_RENDER); rp != nil { rp.visible = false }

    center_leaf := layout_add_leaf(layout, []int{p_edit, p_render}, 0)
    right_top   := layout_add_leaf(layout, []int{p_props, p_cam}, 0)
    right_mid   := layout_add_leaf(layout, []int{p_stats, p_preview, p_sys}, 0)
    right_bot   := layout_add_leaf(layout, []int{p_log}, 0)

    right_bottom := layout_add_split(layout, .DOCK_SPLIT_HORIZONTAL, right_mid, right_bot, 0.6)
    right_split  := layout_add_split(layout, .DOCK_SPLIT_HORIZONTAL, right_top, right_bottom, 0.45)
    root         := layout_add_split(layout, .DOCK_SPLIT_VERTICAL, center_leaf, right_split, 0.72)
    layout.root = root
    layout.center_leaf = center_leaf
    layout.center_split_view = false
    layout.center_split_ratio = 0.5
    layout.center_split_dragging = false
}

// layout_save_named_preset saves the current panel layout as a named preset.
// Transfers ownership of name to the preset. Appends to app.layout_presets.
layout_save_named_preset :: proc(app: ^App, name: string) {
    if app == nil { return }
    snapshot := build_editor_layout_from_app(app)
    if snapshot == nil { return }
    // Deref so we own the struct (not the pointer)
    preset := interfaces.LayoutPreset{
        name   = name,
        layout = snapshot^,
    }
    free(snapshot) // free the pointer shell; the map is now owned by preset.layout
    append(&app.layout_presets, preset)
}

// layout_apply_named_preset applies the layout with the given name from app.layout_presets.
layout_apply_named_preset :: proc(app: ^App, name: string) {
    if app == nil { return }
    for &p in app.layout_presets {
        if p.name == name {
            apply_editor_layout(app, &p.layout)
            return
        }
    }
}
