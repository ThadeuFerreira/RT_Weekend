package editor

import "core:fmt"
import "RT_Weekend:core"

// Toolkit-agnostic World Outliner logic: row count, row index → selection, labels, scroll math.
// No Raylib; used by panel_outliner.odin for draw/input glue.

// outliner_total_rows returns the number of list rows (one per SceneManager object).
outliner_total_rows :: proc(sm: ^SceneManager) -> int {
	return SceneManagerLen(sm)
}

// outliner_row_to_selection maps a 0-based row index to (selection kind, object index into sm.objects).
outliner_row_to_selection :: proc(sm: ^SceneManager, row: int) -> (kind: EditViewSelectionKind, idx: int, ok: bool) {
	if sm == nil || row < 0 || row >= len(sm.objects) {
		return .None, -1, false
	}
	switch e in sm.objects[row] {
	case core.SceneSphere:
		return .Sphere, row, true
	case core.SceneQuad:
		return .Quad, row, true
	case core.SceneVolume:
		return .Volume, row, true
	}
	return .None, -1, false
}

// outliner_row_label returns display text for a row (e.g. "O Sphere #1"). Caller uses result immediately.
outliner_row_label :: proc(kind: EditViewSelectionKind, idx: int) -> cstring {
	switch kind {
	case .Sphere:
		return fmt.ctprintf("O Sphere #%d", idx + 1)
	case .Quad:
		return fmt.ctprintf("Q Quad #%d", idx + 1)
	case .Volume:
		return fmt.ctprintf("V Volume #%d", idx + 1)
	case .None, .Camera:
		return ""
	}
	return ""
}

// outliner_scroll_clamped clamps scroll_y to [0, max(0, total_h - visible_h)].
outliner_scroll_clamped :: proc(scroll_y, total_h, visible_h: f32) -> f32 {
	max_scroll := max(total_h - visible_h, 0)
	return clamp(scroll_y, 0, max_scroll)
}

// outliner_scroll_after_wheel returns new scroll after a wheel delta (e.g. wheel * row_h * 3).
outliner_scroll_after_wheel :: proc(scroll_y, wheel_delta, total_h, visible_h, row_h: f32) -> f32 {
	max_scroll := max(total_h - visible_h, 0)
	return clamp(scroll_y - wheel_delta * row_h * 3, 0, max_scroll)
}
