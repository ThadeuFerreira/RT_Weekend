// native_dialog — Cross-platform native open/save file dialogs via CLI tools.
// No C/C++ libraries: uses zenity (Linux), osascript (macOS), PowerShell (Windows).
// Returns (path, true) on success; ("", false) on cancel or when the helper is unavailable.

package util

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:path/filepath"

// Scene file filter used by the editor for open/save.
SCENE_FILTER_DESC :: "Scene files (*.json)"
SCENE_FILTER_EXT  :: "json"

// open_file_dialog shows a native open-file dialog. default_dir is the starting directory (empty = current dir).
// filter_desc and filter_ext are used for the file type filter (e.g. "Scene files (*.json)", "json").
// Returns (selected path, true) or ("", false) on cancel/failure. Caller must delete the returned path.
open_file_dialog :: proc(default_dir: string, filter_desc: string, filter_ext: string, allocator := context.allocator) -> (path: string, ok: bool) {
	when ODIN_OS == .Linux {
		return _open_file_dialog_zenity(default_dir, filter_desc, filter_ext, false, "", allocator)
	} else when ODIN_OS == .Darwin {
		return _open_file_dialog_osascript(default_dir, filter_ext, allocator)
	} else when ODIN_OS == .Windows {
		return _open_file_dialog_powershell(default_dir, filter_desc, filter_ext, allocator)
	} else {
		return "", false
	}
}

// save_file_dialog shows a native save-file dialog. default_dir and default_name set the starting folder and suggested filename.
// Returns (selected path, true) or ("", false) on cancel/failure. Caller must delete the returned path.
save_file_dialog :: proc(default_dir: string, default_name: string, filter_desc: string, filter_ext: string, allocator := context.allocator) -> (path: string, ok: bool) {
	when ODIN_OS == .Linux {
		return _open_file_dialog_zenity(default_dir, filter_desc, filter_ext, true, default_name, allocator)
	} else when ODIN_OS == .Darwin {
		return _save_file_dialog_osascript(default_dir, default_name, filter_ext, allocator)
	} else when ODIN_OS == .Windows {
		return _save_file_dialog_powershell(default_dir, default_name, filter_desc, filter_ext, allocator)
	} else {
		return "", false
	}
}

// _trim_output strips trailing newline and whitespace from process stdout.
@(private)
_trim_output :: proc(buf: []u8) -> string {
	s := string(buf)
	s = strings.trim_null(s)
	s = strings.trim_space(s)
	return s
}

when ODIN_OS == .Linux {
	_open_file_dialog_zenity :: proc(default_dir: string, filter_desc: string, filter_ext: string, save: bool, default_name: string, allocator := context.allocator) -> (string, bool) {
		// zenity --file-selection [--save] --title="..." [--filename=...] --file-filter='Desc | *.ext'
		args: [dynamic]string
		defer delete(args)
		title := "Open Scene" if !save else "Save Scene As"
		append(&args, "zenity", "--file-selection", fmt.tprintf("--title=%s", title))
		if save {
			append(&args, "--save")
			if len(default_name) > 0 {
				append(&args, fmt.tprintf("--filename=%s", default_name))
			}
		}
		if len(default_dir) > 0 {
			append(&args, fmt.tprintf("--filename=%s/", default_dir))
		}
		filter := strings.concatenate({filter_desc, " | *.", filter_ext}, context.temp_allocator)
		append(&args, fmt.tprintf("--file-filter=%s", filter))

		state, stdout, _, _ := os2.process_exec(os2.Process_Desc{command = args[:]}, context.temp_allocator)
		if !state.success || state.exit_code != 0 || len(stdout) == 0 {
			return "", false
		}
		path_str := _trim_output(stdout)
		if len(path_str) == 0 { return "", false }
		return strings.clone(path_str, allocator), true
	}
}

when ODIN_OS == .Darwin {
	_open_file_dialog_osascript :: proc(default_dir: string, filter_ext: string, allocator := context.allocator) -> (string, bool) {
		// osascript -e 'return POSIX path of (choose file of type {"public.json"} with prompt "Open Scene")'
		script := fmt.tprintf("return POSIX path of (choose file of type {\"public.%s\"} with prompt \"Open Scene\")", filter_ext)
		state, stdout, _, _ := os2.process_exec(os2.Process_Desc{command = {"osascript", "-e", script}}, context.temp_allocator)
		if !state.success || state.exit_code != 0 || len(stdout) == 0 {
			return "", false
		}
		path_str := _trim_output(stdout)
		if len(path_str) == 0 { return "", false }
		return strings.clone(path_str, allocator), true
	}

	_save_file_dialog_osascript :: proc(default_dir: string, default_name: string, filter_ext: string, allocator := context.allocator) -> (string, bool) {
		// choose file name returns a file ref; get POSIX path. default_name used as suggested name.
		script := fmt.tprintf("set f to choose file name with prompt \"Save Scene As\" default name \"%s\"\nreturn POSIX path of f", default_name)
		state, stdout, _, _ := os2.process_exec(os2.Process_Desc{command = {"osascript", "-e", script}}, context.temp_allocator)
		if !state.success || state.exit_code != 0 || len(stdout) == 0 {
			return "", false
		}
		path_str := _trim_output(stdout)
		if len(path_str) == 0 { return "", false }
		return strings.clone(path_str, allocator), true
	}
}

when ODIN_OS == .Windows {
	_open_file_dialog_powershell :: proc(default_dir: string, filter_desc: string, filter_ext: string, allocator := context.allocator) -> (string, bool) {
		// Add-Type OpenFileDialog; ShowDialog; if OK print FileName
		script := fmt.tprintf(
			`Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Filter = "%s (*.%s)|*.%s"
$d.Title = "Open Scene"
if ($d.ShowDialog() -eq 'OK') { $d.FileName }`,
			filter_desc, filter_ext, filter_ext,
		)
		state, stdout, _, _ := os2.process_exec(os2.Process_Desc{command = {"powershell", "-NoProfile", "-Command", script}}, context.temp_allocator)
		if !state.success || state.exit_code != 0 || len(stdout) == 0 {
			return "", false
		}
		path_str := _trim_output(stdout)
		if len(path_str) == 0 { return "", false }
		return strings.clone(path_str, allocator), true
	}

	_save_file_dialog_powershell :: proc(default_dir: string, default_name: string, filter_desc: string, filter_ext: string, allocator := context.allocator) -> (string, bool) {
		script := fmt.tprintf(
			`Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.SaveFileDialog
$d.Filter = "%s (*.%s)|*.%s"
$d.Title = "Save Scene As"
$d.FileName = "%s"
if ($d.ShowDialog() -eq 'OK') { $d.FileName }`,
			filter_desc, filter_ext, filter_ext, default_name,
		)
		state, stdout, _, _ := os2.process_exec(os2.Process_Desc{command = {"powershell", "-NoProfile", "-Command", script}}, context.temp_allocator)
		if !state.success || state.exit_code != 0 || len(stdout) == 0 {
			return "", false
		}
		path_str := _trim_output(stdout)
		if len(path_str) == 0 { return "", false }
		return strings.clone(path_str, allocator), true
	}
}

// dialog_default_dir returns a sensible starting directory for the dialog (e.g. directory of current file, or cwd).
dialog_default_dir :: proc(current_file_path: string, allocator := context.allocator) -> string {
	if len(current_file_path) > 0 {
		if dir := filepath.dir(current_file_path, allocator); len(dir) > 0 {
			return dir
		}
	}
	return filepath.clean(os.get_current_directory(), allocator)
}
