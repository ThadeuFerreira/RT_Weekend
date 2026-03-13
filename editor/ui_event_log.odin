// ui_event_log.odin — Centralized UI event logging and tracing for debug builds.
//
// Three channels work together:
//   1. Chrome trace (util.trace_instant / trace_scope_begin/end) — visible in chrome://tracing
//      and Perfetto when a benchmark capture is active. Records both instant events (mouse
//      clicks, drag transitions, lifecycle) and duration scopes (handler functions).
//   2. App log panel (app_push_log) — shows infrequent action events in the Console panel when
//      app.ui_event_log_enabled is true. Enabled at runtime; does not produce output by default
//      to avoid flooding the panel during normal use.
//   3. stderr (fmt.eprintfln) — per-frame hover notifications when app.ui_event_log_enabled
//      is true. No heap allocation; uses compile-time string formatting only.
//
// Build-time flag: UI_EVENT_LOG_ENABLED (default = ODIN_DEBUG).
//   -define:UI_EVENT_LOG_ENABLED=false  suppress even in debug.
//   When false, every proc in this file compiles to zero instructions (#force_inline + when).
//
// Runtime toggle: app.ui_event_log_enabled
//   Flips log-panel and stderr output on/off without rebuilding.
//   Chrome trace output follows TRACE_CAPTURE_ENABLED (util package).
//
// Logging conventions:
//   Chrome cat   ui.mouse     — hover, click, drag transitions
//   Chrome cat   ui.handler   — Viewport input handler scopes
//   Chrome cat   ui.lifecycle — component create/destroy
//   Console panel "[ui] ..."  — prefixed for grep-ability

package editor

import "core:fmt"
import util "RT_Weekend:util"

// UI_EVENT_LOG_ENABLED controls all UI mouse-event, handler, and lifecycle logging.
// Defaults to true in debug builds (ODIN_DEBUG) and false in release.
UI_EVENT_LOG_ENABLED :: #config(UI_EVENT_LOG_ENABLED, ODIN_DEBUG)

// ui_log_hover emits an instant trace event (ui.mouse / Hover) and writes to stderr when
// app.ui_event_log_enabled is true. Safe to call every frame — no heap allocation; trace
// records only when a benchmark capture is active.
ui_log_hover :: #force_inline proc(app: ^App, component: cstring, mouse_x, mouse_y: f32) {
	when UI_EVENT_LOG_ENABLED {
		util.trace_instant("Hover", "ui.mouse")
		if app != nil && app.ui_event_log_enabled {
			fmt.eprintfln("UI.Mouse.Hover  component=%s  x=%.0f  y=%.0f", component, mouse_x, mouse_y)
		}
	}
}

// ui_log_click emits an instant trace event (ui.mouse / Click) and pushes a log line when
// app.ui_event_log_enabled is true. Call from update handlers only (infrequent; allocates).
ui_log_click :: #force_inline proc(app: ^App, component: string) {
	when UI_EVENT_LOG_ENABLED {
		util.trace_instant("Click", "ui.mouse")
		if app != nil && app.ui_event_log_enabled {
			app_push_log(app, fmt.aprintf("[ui] Click %s", component))
		}
	}
}

// ui_log_drag_start / ui_log_drag_end emit instant trace events (ui.mouse) and log panel
// entries when app.ui_event_log_enabled is true. Call at the frame a drag begins or ends.
ui_log_drag_start :: #force_inline proc(app: ^App, component: string) {
	when UI_EVENT_LOG_ENABLED {
		util.trace_instant("DragStart", "ui.mouse")
		if app != nil && app.ui_event_log_enabled {
			app_push_log(app, fmt.aprintf("[ui] DragStart %s", component))
		}
	}
}

ui_log_drag_end :: #force_inline proc(app: ^App, component: string) {
	when UI_EVENT_LOG_ENABLED {
		util.trace_instant("DragEnd", "ui.mouse")
		if app != nil && app.ui_event_log_enabled {
			app_push_log(app, fmt.aprintf("[ui] DragEnd %s", component))
		}
	}
}

// ui_log_lifecycle emits an instant trace event (ui.lifecycle) and always pushes a log line
// in debug builds (lifecycle events are infrequent and useful regardless of the runtime toggle).
ui_log_lifecycle :: #force_inline proc(app: ^App, component, event: string) {
	when UI_EVENT_LOG_ENABLED {
		util.trace_instant(event, "ui.lifecycle")
		if app != nil {
			app_push_log(app, fmt.aprintf("[ui] %s %s", event, component))
		}
	}
}

// ui_trace_handler_begin / ui_trace_handler_end wrap an input handler function for Chrome
// trace capture (category "ui.handler"). Records a duration event only when a capture is
// active; zero overhead otherwise.
//
// Usage:
//   s := ui_trace_handler_begin("handle_toolbar_input")
//   defer ui_trace_handler_end(s)
ui_trace_handler_begin :: #force_inline proc(name: string) -> util.TraceScope {
	return util.trace_scope_begin(name, "ui.handler")
}

ui_trace_handler_end :: #force_inline proc(s: util.TraceScope) {
	util.trace_scope_end(s)
}
