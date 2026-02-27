package editor

import "RT_Weekend:core"

EDIT_HISTORY_MAX :: 128

ModifySphereAction :: struct {
    idx:    int,
    before: core.Core_SceneSphere,
    after:  core.Core_SceneSphere,
}

AddSphereAction :: struct {
    idx:    int,
    sphere: core.Core_SceneSphere,
}

DeleteSphereAction :: struct {
    idx:    int,
    sphere: core.Core_SceneSphere,
}

ModifyCameraAction :: struct {
    before: core.Core_CameraParams,
    after:  core.Core_CameraParams,
}

EditAction :: union { ModifySphereAction, AddSphereAction, DeleteSphereAction, ModifyCameraAction }

EditHistory :: struct {
    actions: [dynamic]EditAction,
    cursor:  int,
}

edit_history_free :: proc(h: ^EditHistory) {
    delete(h.actions)
}

// edit_history_push truncates the redo branch, evicts the oldest entry when at capacity,
// appends the new action, and advances the cursor.
edit_history_push :: proc(h: ^EditHistory, action: EditAction) {
    // Truncate redo branch
    resize(&h.actions, h.cursor)
    // Evict oldest entry when at capacity
    if len(h.actions) >= EDIT_HISTORY_MAX {
        ordered_remove(&h.actions, 0)
    }
    append(&h.actions, action)
    h.cursor = len(h.actions)
}

// edit_history_undo decrements the cursor and returns the action to be reverted.
edit_history_undo :: proc(h: ^EditHistory) -> (action: EditAction, ok: bool) {
    if h.cursor <= 0 { return }
    h.cursor -= 1
    return h.actions[h.cursor], true
}

// edit_history_redo returns the action at the cursor and advances it.
edit_history_redo :: proc(h: ^EditHistory) -> (action: EditAction, ok: bool) {
    if h.cursor >= len(h.actions) { return }
    action = h.actions[h.cursor]
    h.cursor += 1
    return action, true
}

edit_history_can_undo :: proc(h: ^EditHistory) -> bool {
    return h.cursor > 0
}

edit_history_can_redo :: proc(h: ^EditHistory) -> bool {
    return h.cursor < len(h.actions)
}
