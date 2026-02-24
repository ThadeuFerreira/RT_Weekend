package ui

import rl "vendor:raylib"

MAX_PANELS_PER_LEAF :: 8
MAX_DOCK_NODES      :: 64
MAX_DOCK_PANELS     :: 64

DOCK_TAB_BAR_HEIGHT :: f32(22)
DOCK_TAB_PADDING    :: f32(8)

DockNodeType :: enum {
    DOCK_NODE_LEAF,
    DOCK_NODE_SPLIT,
}

DockSplitAxis :: enum {
    DOCK_SPLIT_HORIZONTAL, // top/bottom
    DOCK_SPLIT_VERTICAL,   // left/right
}

DockDrawCallback :: proc(rect: rl.Rectangle, user_data: rawptr)

DockPanel :: struct {
    id:            int, // Index into app.panels.
    visible:       bool,
    DrawCallback:  DockDrawCallback,
    userData:      rawptr,
}

DockNode :: struct {
    type: DockNodeType,

    // Common
    rect:   rl.Rectangle,
    parent: int,

    // Split node
    axis:   DockSplitAxis,
    childA: int,
    childB: int,
    split:  f32, // 0..1 for childA

    // Leaf node
    panelCount:  int,
    panels:      [MAX_PANELS_PER_LEAF]int, // Index into DockLayout.panels.
    activePanel: int, // Tab index [0, panelCount)
}

DockLayout :: struct {
    nodes:      [MAX_DOCK_NODES]DockNode, 
    nodeCount:  int,
    root:       int,
    center_leaf:int,
    center_split_view: bool,

    panels:     [MAX_DOCK_PANELS]DockPanel,
    panelCount: int,
}

layout_init :: proc(layout: ^DockLayout) {
    if layout == nil { return }
    layout.nodeCount = 0
    layout.panelCount = 0
    layout.root = -1
    layout.center_leaf = -1
    layout.center_split_view = false
}

layout_add_panel :: proc(layout: ^DockLayout, panel_idx: int) -> int {
    if layout == nil || layout.panelCount >= MAX_DOCK_PANELS { return -1 }
    idx := layout.panelCount
    layout.panels[idx] = DockPanel{
        id = panel_idx,
        visible = true,
    }
    layout.panelCount += 1
    return idx
}

layout_add_leaf :: proc(layout: ^DockLayout, panel_indices: []int, active_panel: int, parent: int = -1) -> int {
    if layout == nil || layout.nodeCount >= MAX_DOCK_NODES { return -1 }
    idx := layout.nodeCount
    node := &layout.nodes[idx]
    node^ = DockNode{
        type   = .DOCK_NODE_LEAF,
        parent = parent,
    }
    n := min(len(panel_indices), MAX_PANELS_PER_LEAF)
    for i in 0..<n {
        node.panels[i] = panel_indices[i]
    }
    node.panelCount = n
    if n > 0 {
        node.activePanel = clamp(active_panel, 0, n - 1)
    } else {
        node.activePanel = 0
    }
    layout.nodeCount += 1
    return idx
}

layout_add_split :: proc(layout: ^DockLayout, axis: DockSplitAxis, child_a, child_b: int, split: f32, parent: int = -1) -> int {
    if layout == nil || layout.nodeCount >= MAX_DOCK_NODES { return -1 }
    idx := layout.nodeCount
    layout.nodes[idx] = DockNode{
        type   = .DOCK_NODE_SPLIT,
        parent = parent,
        axis   = axis,
        childA = child_a,
        childB = child_b,
        split  = clamp(split, 0.05, 0.95),
    }
    layout.nodeCount += 1
    if child_a >= 0 && child_a < layout.nodeCount {
        layout.nodes[child_a].parent = idx
    }
    if child_b >= 0 && child_b < layout.nodeCount {
        layout.nodes[child_b].parent = idx
    }
    return idx
}

layout_find_panel_index :: proc(app: ^App, id: string) -> int {
    if app == nil { return -1 }
    for i in 0..<len(app.panels) {
        if app.panels[i].id == id { return i }
    }
    return -1
}

layout_build_default :: proc(app: ^App, layout: ^DockLayout) {
    if app == nil || layout == nil { return }
    layout_init(layout)

    p_render := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_RENDER))
    p_edit   := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_EDIT_VIEW))
    p_stats  := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_STATS))
    p_sys    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_SYSTEM_INFO))
    p_log    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_LOG))
    p_cam    := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_CAMERA))
    p_props  := layout_add_panel(layout, layout_find_panel_index(app, PANEL_ID_OBJECT_PROPS))

    center_leaf := layout_add_leaf(layout, []int{p_render, p_edit}, 0)
    upper_right := layout_add_leaf(layout, []int{p_stats, p_sys}, 0)
    lower_right := layout_add_leaf(layout, []int{p_log, p_cam, p_props}, 0)

    right_split := layout_add_split(layout, .DOCK_SPLIT_HORIZONTAL, upper_right, lower_right, 0.45)
    root        := layout_add_split(layout, .DOCK_SPLIT_VERTICAL, center_leaf, right_split, 0.72)
    layout.root = root
    layout.center_leaf = center_leaf
    layout.center_split_view = false
}

layout_compute_rects :: proc(layout: ^DockLayout, node_idx: int, rect: rl.Rectangle) {
    if layout == nil || node_idx < 0 || node_idx >= layout.nodeCount { return }
    node := &layout.nodes[node_idx]
    node.rect = rect

    if node.type == .DOCK_NODE_LEAF {
        return
    }

    split := clamp(node.split, 0.05, 0.95)
    if node.axis == .DOCK_SPLIT_VERTICAL {
        w_a := rect.width * split
        w_b := rect.width - w_a
        rect_a := rl.Rectangle{rect.x, rect.y, w_a, rect.height}
        rect_b := rl.Rectangle{rect.x + w_a, rect.y, w_b, rect.height}
        layout_compute_rects(layout, node.childA, rect_a)
        layout_compute_rects(layout, node.childB, rect_b)
    } else {
        h_a := rect.height * split
        h_b := rect.height - h_a
        rect_a := rl.Rectangle{rect.x, rect.y, rect.width, h_a}
        rect_b := rl.Rectangle{rect.x, rect.y + h_a, rect.width, h_b}
        layout_compute_rects(layout, node.childA, rect_a)
        layout_compute_rects(layout, node.childB, rect_b)
    }
}

layout_draw_tabs :: proc(app: ^App, layout: ^DockLayout, node: ^DockNode, mouse: rl.Vector2, lmb_pressed: bool) {
    if app == nil || layout == nil || node == nil || node.type != .DOCK_NODE_LEAF { return }
    if node.panelCount <= 0 { return }

    tab_bar := rl.Rectangle{node.rect.x, node.rect.y, node.rect.width, DOCK_TAB_BAR_HEIGHT}
    rl.DrawRectangleRec(tab_bar, TITLE_BG_COLOR)
    rl.DrawRectangleLinesEx(tab_bar, 1, BORDER_COLOR)

    x := tab_bar.x + 2
    for i in 0..<node.panelCount {
        panel_ref_idx := node.panels[i]
        if panel_ref_idx < 0 || panel_ref_idx >= layout.panelCount { continue }
        panel_idx := layout.panels[panel_ref_idx].id
        if panel_idx < 0 || panel_idx >= len(app.panels) { continue }
        p := app.panels[panel_idx]
        if p == nil { continue }
        label := p.title
        w := f32(rl.MeasureText(label, 14)) + DOCK_TAB_PADDING * 2
        tab_rect := rl.Rectangle{x, tab_bar.y + 2, w, tab_bar.height - 4}
        hovered := rl.CheckCollisionPointRec(mouse, tab_rect)
        active := node.activePanel == i
        color := active ? PANEL_BG_COLOR : rl.Color{45, 45, 65, 255}
        if hovered && !active {
            color = rl.Color{58, 58, 82, 255}
        }
        rl.DrawRectangleRec(tab_rect, color)
        rl.DrawRectangleLinesEx(tab_rect, 1, BORDER_COLOR)
        rl.DrawText(label, i32(tab_rect.x + DOCK_TAB_PADDING), i32(tab_rect.y + 3), 14, TITLE_TEXT_COLOR)

        if lmb_pressed && hovered {
            node.activePanel = i
        }
        x += w + 2
    }
}

layout_leaf_active_panel :: proc(app: ^App, layout: ^DockLayout, node: ^DockNode) -> ^FloatingPanel {
    if app == nil || layout == nil || node == nil || node.panelCount <= 0 { return nil }
    tab_idx := clamp(node.activePanel, 0, node.panelCount - 1)
    panel_ref_idx := node.panels[tab_idx]
    if panel_ref_idx < 0 || panel_ref_idx >= layout.panelCount { return nil }
    panel_idx := layout.panels[panel_ref_idx].id
    if panel_idx < 0 || panel_idx >= len(app.panels) { return nil }
    return app.panels[panel_idx]
}

layout_handle_center_split_toggle_click :: proc(layout: ^DockLayout, panel: ^FloatingPanel, mouse: rl.Vector2, lmb_pressed: bool) {
    if layout == nil || panel == nil || !lmb_pressed { return }
    if !panel_has_split_toggle(panel^) { return }
    if rl.CheckCollisionPointRec(mouse, panel_split_toggle_rect(panel^)) {
        layout.center_split_view = !layout.center_split_view
    }
}

layout_leaf_panel_by_id :: proc(app: ^App, layout: ^DockLayout, node: ^DockNode, panel_id: string) -> ^FloatingPanel {
    if app == nil || layout == nil || node == nil { return nil }
    for i in 0..<node.panelCount {
        panel_ref_idx := node.panels[i]
        if panel_ref_idx < 0 || panel_ref_idx >= layout.panelCount { continue }
        panel_idx := layout.panels[panel_ref_idx].id
        if panel_idx < 0 || panel_idx >= len(app.panels) { continue }
        p := app.panels[panel_idx]
        if p != nil && p.id == panel_id { return p }
    }
    return nil
}

layout_draw_center_split_view :: proc(app: ^App, layout: ^DockLayout, node: ^DockNode, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    render_panel := layout_leaf_panel_by_id(app, layout, node, PANEL_ID_RENDER)
    edit_panel   := layout_leaf_panel_by_id(app, layout, node, PANEL_ID_EDIT_VIEW)
    if render_panel == nil || edit_panel == nil { return }

    gap := f32(4)
    available := node.rect
    top_h := (available.height - gap) * 0.5
    bottom_h := available.height - gap - top_h

    render_panel.rect = rl.Rectangle{available.x, available.y, available.width, top_h}
    edit_panel.rect   = rl.Rectangle{available.x, available.y + top_h + gap, available.width, bottom_h}

    layout_handle_center_split_toggle_click(layout, render_panel, mouse, lmb_pressed)
    layout_handle_center_split_toggle_click(layout, edit_panel, mouse, lmb_pressed)

    if render_panel.update_content != nil {
        render_content_rect := rl.Rectangle{
            render_panel.rect.x,
            render_panel.rect.y + TITLE_BAR_HEIGHT,
            render_panel.rect.width,
            render_panel.rect.height - TITLE_BAR_HEIGHT,
        }
        render_panel.update_content(app, render_content_rect, mouse, lmb, lmb_pressed)
    }
    if edit_panel.update_content != nil {
        edit_content_rect := rl.Rectangle{
            edit_panel.rect.x,
            edit_panel.rect.y + TITLE_BAR_HEIGHT,
            edit_panel.rect.width,
            edit_panel.rect.height - TITLE_BAR_HEIGHT,
        }
        edit_panel.update_content(app, edit_content_rect, mouse, lmb, lmb_pressed)
    }

    draw_panel(render_panel, app)
    draw_panel(edit_panel, app)
}

layout_update_and_draw_leaf :: proc(app: ^App, layout: ^DockLayout, node_idx: int, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    if app == nil || layout == nil { return }
    if node_idx < 0 || node_idx >= layout.nodeCount { return }
    node := &layout.nodes[node_idx]
    if node.panelCount <= 0 { return }
    if node.rect.width <= 0 || node.rect.height <= 0 { return }
    if node_idx == layout.center_leaf && layout.center_split_view {
        layout_draw_center_split_view(app, layout, node, mouse, lmb, lmb_pressed)
        return
    }

    if node.rect.height <= DOCK_TAB_BAR_HEIGHT { return }

    layout_draw_tabs(app, layout, node, mouse, lmb_pressed)

    p := layout_leaf_active_panel(app, layout, node)
    if p == nil || !p.visible { return }

    panel_rect := rl.Rectangle{
        node.rect.x,
        node.rect.y + DOCK_TAB_BAR_HEIGHT,
        node.rect.width,
        node.rect.height - DOCK_TAB_BAR_HEIGHT,
    }
    p.rect = panel_rect
    layout_handle_center_split_toggle_click(layout, p, mouse, lmb_pressed)

    if p.update_content != nil {
        content_rect := rl.Rectangle{
            p.rect.x,
            p.rect.y + TITLE_BAR_HEIGHT,
            p.rect.width,
            p.rect.height - TITLE_BAR_HEIGHT,
        }
        p.update_content(app, content_rect, mouse, lmb, lmb_pressed)
    }

    if p.dim_when_maximized && p.maximized { draw_dim_overlay() }
    draw_panel(p, app)
}

layout_update_and_draw :: proc(app: ^App, layout: ^DockLayout, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    if app == nil || layout == nil || layout.root < 0 { return }

    root_rect := rl.Rectangle{
        0,
        MENU_BAR_HEIGHT,
        f32(rl.GetScreenWidth()),
        f32(rl.GetScreenHeight()) - MENU_BAR_HEIGHT,
    }
    layout_compute_rects(layout, layout.root, root_rect)

    for i in 0..<layout.nodeCount {
        if layout.nodes[i].type != .DOCK_NODE_LEAF { continue }
        layout_update_and_draw_leaf(app, layout, i, mouse, lmb, lmb_pressed)
    }
}
