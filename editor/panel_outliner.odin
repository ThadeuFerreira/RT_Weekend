package editor

import "core:fmt"
import rl "vendor:raylib"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

OUTLINER_ROW_H :: f32(22)

OutlinerPanelState :: struct {
    scroll_y: f32,
}

draw_outliner_content :: proc(app: ^App, content: rl.Rectangle) {
    ev    := &app.e_edit_view
    st    := &app.e_outliner
    mouse := rl.GetMousePosition()

    sm         := ev.scene_mgr
    total_rows := SceneManagerLen(sm) + len(app.e_volumes)

    total_h    := f32(total_rows) * OUTLINER_ROW_H
    visible_h  := content.height
    max_scroll := max(total_h - visible_h, 0)
    st.scroll_y = clamp(st.scroll_y, 0, max_scroll)

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(mouse, content) && wheel != 0 {
        st.scroll_y = clamp(st.scroll_y - wheel * OUTLINER_ROW_H * 3, 0, max_scroll)
    }

    rl.BeginScissorMode(i32(content.x), i32(content.y), i32(content.width), i32(content.height))
    defer rl.EndScissorMode()

    sphere_idx := 0
    quad_idx   := 0

    if sm != nil {
        for obj, i in sm.objects {
            ry := content.y + f32(i) * OUTLINER_ROW_H - st.scroll_y
            visible := ry + OUTLINER_ROW_H >= content.y && ry <= content.y + content.height
            #partial switch v in obj {
            case core.SceneSphere:
                if visible {
                    row_rect := rl.Rectangle{content.x, ry, content.width, OUTLINER_ROW_H}
                    is_sel   := ev.selection_kind == .Sphere && ev.selected_idx == sphere_idx
                    if is_sel {
                        rl.DrawRectangleRec(row_rect, rl.Color{60, 100, 160, 200})
                    } else if rl.CheckCollisionPointRec(mouse, row_rect) {
                        rl.DrawRectangleRec(row_rect, rl.Color{50, 55, 75, 180})
                    }
                    label := fmt.ctprintf("O Sphere #%d", sphere_idx + 1)
                    draw_ui_text(app, label, i32(content.x) + 8, i32(ry) + 4, 12, CONTENT_TEXT_COLOR)
                }
                sphere_idx += 1
            case rt.Quad:
                if visible {
                    row_rect := rl.Rectangle{content.x, ry, content.width, OUTLINER_ROW_H}
                    is_sel   := ev.selection_kind == .Quad && ev.selected_idx == quad_idx
                    if is_sel {
                        rl.DrawRectangleRec(row_rect, rl.Color{60, 100, 160, 200})
                    } else if rl.CheckCollisionPointRec(mouse, row_rect) {
                        rl.DrawRectangleRec(row_rect, rl.Color{50, 55, 75, 180})
                    }
                    label := fmt.ctprintf("Q Quad #%d", quad_idx + 1)
                    draw_ui_text(app, label, i32(content.x) + 8, i32(ry) + 4, 12, CONTENT_TEXT_COLOR)
                }
                quad_idx += 1
            }
        }
    }

    base_row := SceneManagerLen(sm)
    for i in 0..<len(app.e_volumes) {
        row := base_row + i
        ry  := content.y + f32(row) * OUTLINER_ROW_H - st.scroll_y
        if ry + OUTLINER_ROW_H < content.y || ry > content.y + content.height { continue }
        row_rect := rl.Rectangle{content.x, ry, content.width, OUTLINER_ROW_H}
        is_sel   := ev.selection_kind == .Volume && ev.selected_idx == i
        if is_sel {
            rl.DrawRectangleRec(row_rect, rl.Color{60, 100, 160, 200})
        } else if rl.CheckCollisionPointRec(mouse, row_rect) {
            rl.DrawRectangleRec(row_rect, rl.Color{50, 55, 75, 180})
        }
        label := fmt.ctprintf("V Volume #%d", i + 1)
        draw_ui_text(app, label, i32(content.x) + 8, i32(ry) + 4, 12, CONTENT_TEXT_COLOR)
    }

    if total_rows == 0 {
        draw_ui_text(app, "No objects in scene", i32(content.x) + 8, i32(content.y) + 10, 12, rl.Color{140, 150, 170, 180})
    }
}

update_outliner_content :: proc(app: ^App, rect: rl.Rectangle, mouse: rl.Vector2, lmb: bool, lmb_pressed: bool) {
    if !lmb_pressed { return }
    ev := &app.e_edit_view
    st := &app.e_outliner

    if !rl.CheckCollisionPointRec(mouse, rect) { return }

    sm        := ev.scene_mgr
    local_y   := mouse.y - rect.y + st.scroll_y
    row       := int(local_y / OUTLINER_ROW_H)
    obj_count := SceneManagerLen(sm)
    vol_count := len(app.e_volumes)

    if row < obj_count {
        sphere_idx := 0
        quad_idx   := 0
        if sm != nil {
            for obj, i in sm.objects {
                if i == row {
                    #partial switch _ in obj {
                    case core.SceneSphere:
                        ev.selection_kind = .Sphere
                        ev.selected_idx   = sphere_idx
                    case rt.Quad:
                        ev.selection_kind = .Quad
                        ev.selected_idx   = quad_idx
                    }
                    return
                }
                #partial switch _ in obj {
                case core.SceneSphere: sphere_idx += 1
                case rt.Quad:         quad_idx   += 1
                }
            }
        }
    } else if row < obj_count + vol_count {
        ev.selection_kind = .Volume
        ev.selected_idx   = row - obj_count
    }
}
