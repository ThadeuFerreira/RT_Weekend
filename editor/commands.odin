package editor

// CommandID constants — string keys so future plugins can add commands without recompiling.
CMD_FILE_NEW         :: "file.new"
CMD_FILE_IMPORT      :: "file.import"
CMD_FILE_SAVE        :: "file.save"
CMD_FILE_SAVE_AS     :: "file.save_as"
CMD_FILE_EXIT        :: "file.exit"

CMD_VIEW_RENDER      :: "view.panel.render"
CMD_VIEW_STATS       :: "view.panel.stats"
CMD_VIEW_LOG         :: "view.panel.log"
CMD_VIEW_SYSINFO     :: "view.panel.sysinfo"
CMD_VIEW_EDIT        :: "view.panel.edit"
CMD_VIEW_CAMERA      :: "view.panel.camera"
CMD_VIEW_PROPS       :: "view.panel.props"
CMD_VIEW_PREVIEW     :: "view.panel.preview"

CMD_VIEW_PRESET_DEFAULT :: "view.preset.default"
CMD_VIEW_PRESET_RENDER  :: "view.preset.render_focus"
CMD_VIEW_PRESET_EDIT    :: "view.preset.edit_focus"
CMD_VIEW_SAVE_PRESET    :: "view.preset.save"

CMD_RENDER_RESTART   :: "render.restart"

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
