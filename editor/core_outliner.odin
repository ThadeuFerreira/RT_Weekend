package editor

import "core:fmt"
import "RT_Weekend:core"
import rt "RT_Weekend:raytrace"

// Toolkit-agnostic World Outliner logic: row count, row index → selection, labels, scroll math.
// No Raylib; used by panel_outliner.odin for draw/input glue.

// outliner_total_rows returns the number of list rows (scene objects + volumes).
outliner_total_rows :: proc(sm: ^SceneManager, volume_count: int) -> int {
	return SceneManagerLen(sm) + volume_count
}

// outliner_row_to_selection maps a 0-based row index to (selection kind, object index).
// When kind is .Sphere or .Quad, idx is the sphere/quad index; when .Volume, idx is the volume index.
outliner_row_to_selection :: proc(sm: ^SceneManager, volume_count: int, row: int) -> (kind: EditViewSelectionKind, idx: int, ok: bool) {
	obj_count := SceneManagerLen(sm)
	if row < 0 { return .None, -1, false }
	if row < obj_count {
		sphere_idx := 0
		quad_idx   := 0
		if sm != nil {
			for obj, i in sm.objects {
				if i == row {
					#partial switch _ in obj {
					case core.SceneSphere:
						return .Sphere, sphere_idx, true
					case rt.Quad:
						return .Quad, quad_idx, true
					}
				}
				#partial switch _ in obj {
				case core.SceneSphere: sphere_idx += 1
				case rt.Quad:         quad_idx   += 1
				}
			}
		}
		return .None, -1, false
	}
	if row < obj_count + volume_count {
		return .Volume, row - obj_count, true
	}
	return .None, -1, false
}

// outliner_row_label returns display text for a row (e.g. "O Sphere #1"). Caller uses result immediately.
outliner_row_label :: proc(kind: EditViewSelectionKind, idx: int) -> cstring {
	switch kind {
	case .Sphere: return fmt.ctprintf("O Sphere #%d", idx + 1)
	case .Quad:   return fmt.ctprintf("Q Quad #%d", idx + 1)
	case .Volume: return fmt.ctprintf("V Volume #%d", idx + 1)
	case .None, .Camera: return ""
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
