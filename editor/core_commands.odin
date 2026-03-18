package editor

// CommandID constants — string keys so future plugins can add commands without recompiling.
CMD_FILE_NEW         :: "file.new"
CMD_FILE_IMPORT      :: "file.import"
CMD_FILE_SAVE        :: "file.save"
CMD_FILE_SAVE_AS     :: "file.save_as"
CMD_FILE_EXIT        :: "file.exit"

CMD_VIEW_RENDER      :: "view.panel.render"
CMD_VIEW_STATS       :: "view.panel.stats"
CMD_VIEW_CONSOLE     :: "view.panel.console"
CMD_VIEW_SYSINFO     :: "view.panel.sysinfo"
CMD_VIEW_EDIT        :: "view.panel.viewport"
CMD_VIEW_CAMERA      :: "view.panel.camera"
CMD_VIEW_PROPS       :: "view.panel.details"
CMD_VIEW_PREVIEW     :: "view.panel.camera_preview"
CMD_VIEW_TEXTURE     :: "view.panel.texture"
CMD_VIEW_CONTENT_BROWSER :: "view.panel.content_browser"
CMD_VIEW_OUTLINER    :: "view.panel.outliner"

CMD_VIEW_SAVE_PRESET    :: "view.preset.save"

CMD_UNDO             :: "edit.undo"
CMD_REDO             :: "edit.redo"
CMD_EDIT_COPY        :: "edit.copy"
CMD_EDIT_PASTE       :: "edit.paste"
CMD_EDIT_DUPLICATE   :: "edit.duplicate"

CMD_RENDER_RESTART   :: "render.restart"
CMD_BENCHMARK_START  :: "render.benchmark.start"
CMD_BENCHMARK_STOP   :: "render.benchmark.stop"

CMD_SCENE_LOAD_EXAMPLE :: "scene.example.load"

// Edit View context menu (viewport right-click)
CMD_EDIT_VIEW_ALIGN_CAMERA    :: "edit_view.align_camera"
CMD_EDIT_VIEW_FRAME_GEOMETRY  :: "edit_view.frame_geometry"
CMD_EDIT_VIEW_CAMERA_MODE     :: "edit_view.camera_mode"
CMD_EDIT_VIEW_LOCK_AXIS_X     :: "edit_view.lock_axis_x"
CMD_EDIT_VIEW_LOCK_AXIS_Y     :: "edit_view.lock_axis_y"
CMD_EDIT_VIEW_LOCK_AXIS_Z     :: "edit_view.lock_axis_z"
CMD_EDIT_VIEW_GRID_VISIBLE    :: "edit_view.grid_visible"
CMD_EDIT_VIEW_GRID_DENSITY_PLUS  :: "edit_view.grid_density_plus"
CMD_EDIT_VIEW_GRID_DENSITY_MINUS :: "edit_view.grid_density_minus"
CMD_EDIT_VIEW_SPEED_SLOW      :: "edit_view.speed_slow"
CMD_EDIT_VIEW_SPEED_MEDIUM   :: "edit_view.speed_medium"
CMD_EDIT_VIEW_SPEED_FAST     :: "edit_view.speed_fast"
CMD_EDIT_VIEW_SPEED_VERY_FAST :: "edit_view.speed_very_fast"

MAX_COMMANDS :: 64

// Command holds a single registered action with optional enable/check predicates.
Command :: struct {
    id:           string,
    label:        string,       // display text
    shortcut:     string,       // display only (no auto-binding)
    action:       proc(app: ^App),
    enabled_proc: proc(app: ^App) -> bool, // nil = always enabled
    checked_proc: proc(app: ^App) -> bool, // nil = no checkmark
}

// CommandRegistry holds all registered commands in a fixed backing array.
CommandRegistry :: struct {
    commands: [MAX_COMMANDS]Command,
    count:    int,
}

// cmd_register adds a command to the registry. No-op if registry is full or id is empty.
cmd_register :: proc(reg: ^CommandRegistry, cmd: Command) {
    if reg == nil || reg.count >= MAX_COMMANDS || len(cmd.id) == 0 { return }
    reg.commands[reg.count] = cmd
    reg.count += 1
}

// cmd_find returns a pointer to the command with the given id, or nil if not found.
cmd_find :: proc(reg: ^CommandRegistry, id: string) -> ^Command {
    if reg == nil { return nil }
    for i in 0..<reg.count {
        if reg.commands[i].id == id { return &reg.commands[i] }
    }
    return nil
}

// cmd_execute invokes the command's action if it exists and is enabled.
cmd_execute :: proc(app: ^App, id: string) {
    cmd := cmd_find(&app.commands, id)
    if cmd == nil || cmd.action == nil { return }
    if cmd.enabled_proc != nil && !cmd.enabled_proc(app) { return }
    cmd.action(app)
}

// cmd_is_enabled returns true when the command is enabled (enabled_proc nil = true).
cmd_is_enabled :: proc(app: ^App, id: string) -> bool {
    cmd := cmd_find(&app.commands, id)
    if cmd == nil { return false }
    if cmd.enabled_proc == nil { return true }
    return cmd.enabled_proc(app)
}

// cmd_is_checked returns true when the command has a checked state that is true.
cmd_is_checked :: proc(app: ^App, id: string) -> bool {
    cmd := cmd_find(&app.commands, id)
    if cmd == nil || cmd.checked_proc == nil { return false }
    return cmd.checked_proc(app)
}
