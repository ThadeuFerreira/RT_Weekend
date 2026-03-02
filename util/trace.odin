// Chrome JSON trace capture for chrome://tracing and Perfetto.
// Independent of raytrace/profiling (which does aggregate stats for the Stats panel).
// Release builds should use -define:TRACE_CAPTURE_ENABLED=false to disable all capture and file I/O.
package util

import "core:encoding/json"
import "core:strings"
import "core:time"

TRACE_CAPTURE_ENABLED :: #config(TRACE_CAPTURE_ENABLED, true)

TraceEvent :: struct {
	name: string `json:"name"`,
	cat:  string `json:"cat"`,
	ph:   string `json:"ph"`,
	ts:   i64    `json:"ts"`,
	dur:  i64    `json:"dur,omitempty"`,
	pid:  int    `json:"pid"`,
	tid:  int    `json:"tid"`,
	args: map[string]string `json:"args,omitempty"`,
}

TraceFile :: struct {
	trace_events: []TraceEvent `json:"traceEvents"`,
}

TraceScope :: struct {
	active: bool,
	name:   string,
	cat:    string,
	ts_us:  i64,
	pid:    int,
	tid:    int,
}

TraceState :: struct {
	capturing:     bool,
	pid:           int,
	capture_start: time.Time,
	events:        [dynamic]TraceEvent,
	thread_names:  map[int]string,
	metadata:      map[string]string,
}

_trace_state: TraceState

init_trace_state :: proc() {
	if _trace_state.pid == 0 {
		_trace_state.pid = 1
	}
	if _trace_state.thread_names == nil {
		_trace_state.thread_names = make(map[int]string)
	}
	if _trace_state.metadata == nil {
		_trace_state.metadata = make(map[string]string)
	}
}

clear_event_args :: proc(args: map[string]string) {
	if args == nil { return }
	for _, v in args {
		delete(v)
	}
	delete(args)
}

clear_events :: proc() {
	for &e in _trace_state.events {
		delete(e.name)
		delete(e.cat)
		clear_event_args(e.args)
	}
	delete(_trace_state.events)
	_trace_state.events = make([dynamic]TraceEvent)
}

capture_timestamp_us :: proc() -> i64 {
	dt := time.diff(_trace_state.capture_start, time.now())
	return i64(time.duration_microseconds(dt))
}

append_event :: proc(e: TraceEvent) {
	append(&_trace_state.events, e)
}

append_thread_metadata_event :: proc(tid: int, thread_name: string) {
	args := make(map[string]string)
	args["name"] = strings.clone(thread_name)
	append_event(TraceEvent{
		name = strings.clone("thread_name"),
		cat  = strings.clone("meta"),
		ph   = "M",
		ts   = 0,
		pid  = _trace_state.pid,
		tid  = tid,
		args = args,
	})
}

append_process_metadata_event :: proc(process_name: string) {
	args := make(map[string]string)
	args["name"] = strings.clone(process_name)
	append_event(TraceEvent{
		name = strings.clone("process_name"),
		cat  = strings.clone("meta"),
		ph   = "M",
		ts   = 0,
		pid  = _trace_state.pid,
		tid  = 0,
		args = args,
	})
}

append_capture_metadata_events :: proc() {
	for key, value in _trace_state.metadata {
		args := make(map[string]string)
		args["name"] = strings.clone(value)
		append_event(TraceEvent{
			name = strings.clone(key),
			cat  = strings.clone("meta"),
			ph   = "M",
			ts   = 0,
			pid  = _trace_state.pid,
			tid  = 0,
			args = args,
		})
	}
}

trace_is_capturing :: proc() -> bool {
	when TRACE_CAPTURE_ENABLED {
		return _trace_state.capturing
	} else {
		return false
	}
}

trace_set_metadata :: proc(key, value: string) {
	when TRACE_CAPTURE_ENABLED {
		init_trace_state()
		if old, ok := _trace_state.metadata[key]; ok {
			delete(old)
		}
		_trace_state.metadata[key] = strings.clone(value)
	}
}

trace_register_thread :: proc(tid: int, name: string) {
	when TRACE_CAPTURE_ENABLED {
		init_trace_state()
		if old, ok := _trace_state.thread_names[tid]; ok {
			delete(old)
		}
		_trace_state.thread_names[tid] = strings.clone(name)
		if _trace_state.capturing {
			append_thread_metadata_event(tid, name)
		}
	}
}

trace_scope_begin :: proc(name, cat: string, tid: int = 0) -> TraceScope {
	when TRACE_CAPTURE_ENABLED {
		if !_trace_state.capturing {
			return TraceScope{}
		}
		return TraceScope{
			active = true,
			name   = name,
			cat    = cat,
			ts_us  = capture_timestamp_us(),
			pid    = _trace_state.pid,
			tid    = tid,
		}
	} else {
		return TraceScope{}
	}
}

trace_scope_end :: proc(scope: TraceScope) {
	when TRACE_CAPTURE_ENABLED {
		if !scope.active || !_trace_state.capturing { return }
		end_ts_us := capture_timestamp_us()
		dur_us := end_ts_us - scope.ts_us
		if dur_us < 0 {
			dur_us = 0
		}
		append_event(TraceEvent{
			name = strings.clone(scope.name),
			cat  = strings.clone(scope.cat),
			ph   = "X",
			ts   = scope.ts_us,
			dur  = dur_us,
			pid  = scope.pid,
			tid  = scope.tid,
		})
	}
}

sort_events_by_ts :: proc(events: ^[dynamic]TraceEvent) {
	n := len(events^)
	if n <= 1 { return }
	for i in 0..<n-1 {
		min_idx := i
		for j in i+1..<n {
			if events^[j].ts < events^[min_idx].ts {
				min_idx = j
			}
		}
		if min_idx != i {
			events^[i], events^[min_idx] = events^[min_idx], events^[i]
		}
	}
}

trace_start_capture :: proc() {
	when TRACE_CAPTURE_ENABLED {
		init_trace_state()
		clear_events()
		_trace_state.capture_start = time.now()
		_trace_state.capturing = true

		append_process_metadata_event("RT_Weekend")
		for tid, name in _trace_state.thread_names {
			append_thread_metadata_event(tid, name)
		}
		append_capture_metadata_events()
	}
}

trace_stop_capture :: proc() -> ([]u8, bool) {
	when TRACE_CAPTURE_ENABLED {
		if !_trace_state.capturing {
			return nil, false
		}
		_trace_state.capturing = false
		sort_events_by_ts(&_trace_state.events)

		trace_file := TraceFile{
			trace_events = _trace_state.events[:],
		}
		data, err := json.marshal(trace_file)
		if err != nil {
			return nil, false
		}
		return data, true
	} else {
		return nil, false
	}
}
