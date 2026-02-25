package ui

import rl "vendor:raylib"

// Height of the top menu bar strip. Panels can be drawn below this; menu is drawn last so it stays on top.
MENU_BAR_HEIGHT :: f32(24)

MENU_ITEM_HEIGHT :: f32(22)
MENU_PADDING     :: 8
DROP_SHADOW      :: 2
DROPDOWN_W       :: f32(180)

// MenuBarState holds which dropdown (if any) is open. open_menu_index -1 = none.
MenuBarState :: struct {
    open_menu_index: int,
}

// MenuEntryDyn is a single item in a dynamic dropdown.
MenuEntryDyn :: struct {
    label:    string,
    cmd_id:   string,        // CommandID constant; used to look up enabled/checked
    disabled: bool,
    checked:  bool,
    shortcut: string,        // display only
    separator: bool,         // when true, draw a horizontal rule (label/cmd_id ignored)
}

// MenuDyn is a top-level menu entry with its dynamic dropdown entries.
MenuDyn :: struct {
    title:   string,
    entries: []MenuEntryDyn,
}

// get_menus_dynamic builds the menu list each frame using the temp allocator.
// Menus reflect live state (panel visibility checkmarks, enabled states).
get_menus_dynamic :: proc(app: ^App) -> []MenuDyn {
    if app == nil { return nil }

    // View panel entries
    view_panel_entries := []MenuEntryDyn{
        {label = "Render Preview", cmd_id = CMD_VIEW_RENDER,  checked = cmd_is_checked(app, CMD_VIEW_RENDER)},
        {label = "Stats",          cmd_id = CMD_VIEW_STATS,   checked = cmd_is_checked(app, CMD_VIEW_STATS)},
        {label = "Log",            cmd_id = CMD_VIEW_LOG,     checked = cmd_is_checked(app, CMD_VIEW_LOG)},
        {label = "System Info",    cmd_id = CMD_VIEW_SYSINFO, checked = cmd_is_checked(app, CMD_VIEW_SYSINFO)},
        {label = "Edit View",      cmd_id = CMD_VIEW_EDIT,    checked = cmd_is_checked(app, CMD_VIEW_EDIT)},
        {label = "Camera",         cmd_id = CMD_VIEW_CAMERA,  checked = cmd_is_checked(app, CMD_VIEW_CAMERA)},
        {label = "Object Props",   cmd_id = CMD_VIEW_PROPS,   checked = cmd_is_checked(app, CMD_VIEW_PROPS)},
        {label = "Preview Port",   cmd_id = CMD_VIEW_PREVIEW, checked = cmd_is_checked(app, CMD_VIEW_PREVIEW)},
        {separator = true},
        {label = "Default Layout",        cmd_id = CMD_VIEW_PRESET_DEFAULT},
        {label = "Rendering Focus Layout", cmd_id = CMD_VIEW_PRESET_RENDER},
        {label = "Editing Focus Layout",  cmd_id = CMD_VIEW_PRESET_EDIT},
        {separator = true},
        {label = "Save Layout As…", cmd_id = CMD_VIEW_SAVE_PRESET},
    }

    file_entries := []MenuEntryDyn{
        {label = "New",      cmd_id = CMD_FILE_NEW,     shortcut = "Ctrl+N"},
        {label = "Import…",  cmd_id = CMD_FILE_IMPORT,  shortcut = "Ctrl+O"},
        {separator = true},
        {label = "Save",     cmd_id = CMD_FILE_SAVE,    shortcut = "Ctrl+S", disabled = !cmd_is_enabled(app, CMD_FILE_SAVE)},
        {label = "Save As…", cmd_id = CMD_FILE_SAVE_AS},
        {separator = true},
        {label = "Exit",     cmd_id = CMD_FILE_EXIT,    shortcut = "Alt+F4"},
    }

    render_entries := []MenuEntryDyn{
        {label = "Restart", cmd_id = CMD_RENDER_RESTART, shortcut = "F5", disabled = !cmd_is_enabled(app, CMD_RENDER_RESTART)},
    }

    menus := make([]MenuDyn, 3, context.temp_allocator)
    menus[0] = MenuDyn{title = "File",   entries = file_entries}
    menus[1] = MenuDyn{title = "View",   entries = view_panel_entries}
    menus[2] = MenuDyn{title = "Render", entries = render_entries}
    return menus
}

// menu_bar_update handles click to open/close dropdowns and to invoke actions. Call before drawing.
// Sets app.input_consumed = true when the menu bar or dropdown consumes a click.
menu_bar_update :: proc(app: ^App, state: ^MenuBarState, mouse: rl.Vector2, lmb_pressed: bool) {
    if app == nil || state == nil { return }
    menus := get_menus_dynamic(app)
    sw := f32(rl.GetScreenWidth())

    if lmb_pressed {
        // Check if click is inside open dropdown first
        if state.open_menu_index >= 0 && state.open_menu_index < len(menus) {
            menu := &menus[state.open_menu_index]
            px: f32 = MENU_PADDING
            for k in 0..<state.open_menu_index {
                title_c := make_cstring_temp(menus[k].title)
                px += f32(measure_ui_text(app, title_c, 14).width) + MENU_PADDING * 2
            }
            visible_count := 0
            for &e in menu.entries {
                if !e.separator { visible_count += 1 }
            }
            // height = total rows (separators take half height)
            drop_h := entry_list_height(menu.entries)
            dropdown_rect := rl.Rectangle{px, MENU_BAR_HEIGHT + DROP_SHADOW, DROPDOWN_W, drop_h}

            if rl.CheckCollisionPointRec(mouse, dropdown_rect) {
                // Find which entry was clicked
                local_y := mouse.y - dropdown_rect.y
                ey: f32 = 0
                for &entry in menu.entries {
                    ih := entry_height(entry)
                    if local_y >= ey && local_y < ey + ih {
                        if !entry.separator && !entry.disabled && len(entry.cmd_id) > 0 {
                            cmd_execute(app, entry.cmd_id)
                        }
                        state.open_menu_index = -1
                        app.input_consumed = true
                        return
                    }
                    ey += ih
                }
                state.open_menu_index = -1
                app.input_consumed = true
                return
            }
        }

        // Check top-level menu items
        x: f32 = MENU_PADDING
        for i in 0..<len(menus) {
            menu := &menus[i]
            title_c := make_cstring_temp(menu.title)
            w := f32(measure_ui_text(app, title_c, 14).width) + MENU_PADDING * 2
            item_rect := rl.Rectangle{x, 0, w, MENU_BAR_HEIGHT}
            if rl.CheckCollisionPointRec(mouse, item_rect) {
                if state.open_menu_index == i {
                    state.open_menu_index = -1
                } else {
                    state.open_menu_index = i
                }
                app.input_consumed = true
                return
            }
            x += w
        }

        // Click outside: close dropdown (if any was open, consume)
        if state.open_menu_index >= 0 {
            app.input_consumed = true
            state.open_menu_index = -1
        }
    }

    // Also consume bar area hover (nothing to do for hover, but keep menu open)
    _ = sw
}

// entry_height returns the pixel height for one menu entry (separator = half row).
entry_height :: proc(e: MenuEntryDyn) -> f32 {
    if e.separator { return MENU_ITEM_HEIGHT * 0.5 }
    return MENU_ITEM_HEIGHT
}

// entry_list_height returns the total pixel height for all entries.
entry_list_height :: proc(entries: []MenuEntryDyn) -> f32 {
    h: f32 = 0
    for &e in entries { h += entry_height(e) }
    return h
}

// make_cstring_temp converts a string to a null-terminated cstring using the temp allocator.
make_cstring_temp :: proc(s: string) -> cstring {
    buf := make([]u8, len(s) + 1, context.temp_allocator)
    copy(buf, s)
    buf[len(s)] = 0
    return cstring(raw_data(buf))
}

// menu_bar_draw draws the bar and the open dropdown. Call after panels so the bar stays on top.
menu_bar_draw :: proc(app: ^App, state: ^MenuBarState) {
    if app == nil || state == nil { return }
    menus := get_menus_dynamic(app)
    sw := f32(rl.GetScreenWidth())

    // Bar background
    rl.DrawRectangleRec(rl.Rectangle{0, 0, sw, MENU_BAR_HEIGHT}, TITLE_BG_COLOR)
    rl.DrawRectangle(0, i32(MENU_BAR_HEIGHT), i32(sw), 1, BORDER_COLOR)

    mouse := rl.GetMousePosition()

    // Top-level labels
    x: f32 = MENU_PADDING
    for i in 0..<len(menus) {
        menu := &menus[i]
        title_c := make_cstring_temp(menu.title)
        w := f32(measure_ui_text(app, title_c, 14).width) + MENU_PADDING * 2
        active   := state.open_menu_index == i
        hovered  := rl.CheckCollisionPointRec(mouse, rl.Rectangle{x, 0, w, MENU_BAR_HEIGHT})
        bg_color := TITLE_BG_COLOR
        if active {
            bg_color = PANEL_BG_COLOR
        } else if hovered {
            bg_color = rl.Color{70, 70, 100, 255}
        }
        rl.DrawRectangleRec(rl.Rectangle{x, 0, w, MENU_BAR_HEIGHT}, bg_color)
        draw_ui_text(app, title_c, i32(x) + MENU_PADDING, 5, 14, TITLE_TEXT_COLOR)
        x += w
    }

    // Open dropdown
    if state.open_menu_index >= 0 && state.open_menu_index < len(menus) {
        menu := &menus[state.open_menu_index]
        drop_h := entry_list_height(menu.entries)
        px: f32 = MENU_PADDING
        for k in 0..<state.open_menu_index {
            title_c := make_cstring_temp(menus[k].title)
            px += f32(measure_ui_text(app, title_c, 14).width) + MENU_PADDING * 2
        }
        dropdown_rect := rl.Rectangle{px, MENU_BAR_HEIGHT + DROP_SHADOW, DROPDOWN_W, drop_h}
        rl.DrawRectangleRec(dropdown_rect, PANEL_BG_COLOR)
        rl.DrawRectangleLinesEx(dropdown_rect, 1, BORDER_COLOR)

        ey: f32 = 0
        for &entry in menu.entries {
            ih := entry_height(entry)
            ry := dropdown_rect.y + ey

            if entry.separator {
                // Draw a thin horizontal rule
                sep_y := i32(ry + ih * 0.5)
                rl.DrawRectangle(i32(dropdown_rect.x) + 4, sep_y, i32(dropdown_rect.width) - 8, 1, BORDER_COLOR)
                ey += ih
                continue
            }

            item_rect := rl.Rectangle{dropdown_rect.x, ry, DROPDOWN_W, ih}
            item_hov  := rl.CheckCollisionPointRec(mouse, item_rect)
            text_col  := CONTENT_TEXT_COLOR
            if entry.disabled {
                text_col = rl.Color{100, 105, 120, 180}
            } else if item_hov {
                rl.DrawRectangleRec(item_rect, rl.Color{60, 65, 95, 255})
            }

            // Checkmark
            if entry.checked {
                rl.DrawText("✓", i32(dropdown_rect.x) + 4, i32(ry) + 3, 13, ACCENT_COLOR)
            }

            label_c := make_cstring_temp(entry.label)
            draw_ui_text(app, label_c, i32(dropdown_rect.x) + 22, i32(ry) + 3, 13, text_col)

            // Shortcut (right-aligned)
            if len(entry.shortcut) > 0 {
                sc_c := make_cstring_temp(entry.shortcut)
                sc_w := measure_ui_text(app, sc_c, 11).width
                sc_x := i32(dropdown_rect.x + DROPDOWN_W) - sc_w - 6
                draw_ui_text(app, sc_c, sc_x, i32(ry) + 5, 11, rl.Color{140, 150, 170, 200})
            }

            ey += ih
        }
    }
}
