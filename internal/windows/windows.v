module windows

import os

// This file wraps the C helpers in V terms. It cannot import `trash`, so every
// failure is a plain error whose text is the refusal reason.

// attr_directory is `FILE_ATTRIBUTE_DIRECTORY`.
pub const attr_directory = u32(0x10)

// attr_reparse_point is `FILE_ATTRIBUTE_REPARSE_POINT`.
pub const attr_reparse_point = u32(0x400)

// error_file_not_found and error_path_not_found are the two Win32 codes that
// mean "the target does not exist", the only failure `-f` silences.
const error_file_not_found = 2
const error_path_not_found = 3

// error_text renders a Win32 error code with the system's own message.
pub fn error_text(code int) string {
	mut buf := []u8{len: 1024}
	C.trash_error_text(code, buf.data, buf.len)
	return unsafe { tos_clone(buf.data) }
}

// attributes returns the attributes of `path`, or an error with the system's
// message when the path cannot be inspected.
pub fn attributes(path string) !u32 {
	mut code := 0
	attrs := unsafe { C.trash_attributes(path.to_wide(), &code) }
	if code != 0 {
		return error(error_text(code))
	}
	return attrs
}

// is_missing reports whether `path` does not exist. Any other failure (access
// denied, invalid path) is not treated as missing, so `-f` cannot silence it.
pub fn is_missing(path string) bool {
	mut code := 0
	unsafe {
		C.trash_attributes(path.to_wide(), &code)
	}
	return code == error_file_not_found || code == error_path_not_found
}

// is_volume_root_junction reports whether `path` is a junction whose target is
// a volume root, which counts as a mount point for the guards.
pub fn is_volume_root_junction(path string) !bool {
	mut code := 0
	result := unsafe { C.trash_is_volume_root_junction(path.to_wide(), &code) }
	if result < 0 {
		return error(error_text(code))
	}
	return result == 1
}

// path_size returns the logical size of `path` in bytes.
pub fn path_size(path string) !u64 {
	mut code := 0
	size := unsafe { C.trash_path_size(path.to_wide(), &code) }
	if code != 0 {
		return error(error_text(code))
	}
	return size
}

// volume_root returns the volume root (for example `C:\`) that holds `path`.
pub fn volume_root(path string) !string {
	mut buf := []u8{len: 512}
	code := unsafe { C.trash_volume_root(path.to_wide(), buf.data, buf.len) }
	if code < 0 {
		return error(error_text(-code))
	}
	return unsafe { tos_clone(buf.data) }
}

// quota_allows refuses an object of `size` bytes that would not fit into the
// Recycle Bin of the volume that holds `path`.
pub fn quota_allows(path string, size u64) ! {
	mut buf := []u8{len: 1024}
	result := unsafe { C.trash_quota_allows(path.to_wide(), size, buf.data, buf.len) }
	if result <= 0 {
		return error(unsafe { tos_clone(buf.data) })
	}
}

// place sends every path to the Recycle Bin in one operation and returns one
// reason per path, '' meaning success; no trash path is reported.
pub fn place(paths []string) []string {
	mut reasons := []string{len: paths.len}
	if paths.len == 0 {
		return reasons
	}
	mut wide := []&u16{cap: paths.len}
	for path in paths {
		wide << path.to_wide()
	}
	mut item_hr := []int{len: paths.len}
	mut aborted := 0
	mut buf := []u8{len: 1024}
	result := unsafe {
		C.trash_place_many(wide.data, paths.len, item_hr.data, &aborted, buf.data, buf.len)
	}
	message := unsafe { tos_clone(buf.data) }
	if result == -1 {
		for i in 0 .. reasons.len {
			reasons[i] = message
		}
		return reasons
	}
	for i, hr in item_hr {
		if hr != 0 {
			reasons[i] = hr_text(hr)
		}
	}
	if result != 0 {
		for i in 0 .. reasons.len {
			if reasons[i] == '' {
				reasons[i] = message
			}
		}
		return reasons
	}
	if aborted != 0 {
		for i in 0 .. reasons.len {
			if reasons[i] == '' {
				reasons[i] = 'the operation was aborted'
			}
		}
	}
	return reasons
}

// hr_text renders an HRESULT that came back from a single item.
fn hr_text(hr int) string {
	return 'the shell API failed (HRESULT 0x${u32(hr):08X})'
}

// is_empty_dir reports whether a directory has no entries other than `.`/`..`.
pub fn is_empty_dir(path string) bool {
	entries := os.ls(path) or { return false }
	return entries.len == 0
}
