module trash

import os

// ErrorKind classifies every failure that `trash` composes itself.
// The user-facing text of each kind is fixed here and is part of the CLI
// contract, so the tests in `errors_test.v` pin it.
pub enum ErrorKind {
	os              // the OS refused; the text comes from the platform
	root            // '/', 'C:\', '\\server\share\'
	current_dir     // the path resolves to the current directory
	dot_dot         // the last component is '.' or '..'
	trash_dir       // the trash directory itself or one of its ancestors
	mount_point     // the path is a mount point
	contains_mount  // a directory that contains a mount point
	mount_table     // the mount table cannot be read
	needs_recursive // a real directory without -r
	not_a_directory // a trailing slash on something that is not a directory
	dir_not_empty   // -d on a non-empty directory
	no_usable_trash // no usable trash directory on this volume
	path_too_long   // Windows: over the shell API limit
	invalid_path    // Windows: reserved name, ':', trailing dot or space
	quota           // Windows: the object does not fit in the Recycle Bin
}

// TrashError is the only error type of the library. `errno` and `detail` are
// meaningful for `.os` only; policy failures carry the fixed text of their kind.
// The field is not called `errno` because that is a C macro.
// The embedded `Error` is what makes the struct usable as a Result value.
pub struct TrashError {
	Error
pub:
	kind       ErrorKind
	errno_code int    // errno on Unix, Win32 error code on Windows; 0 otherwise
	detail     string // the platform's own text for `errno`; '' otherwise
}

// code returns the platform error code, so `-f` can recognise a missing target.
pub fn (e TrashError) code() int {
	return e.errno_code
}

// msg returns the bare reason: no `trash:` prefix, no path.
pub fn (e TrashError) msg() string {
	return match e.kind {
		.os { e.detail }
		.root { 'refusing to trash a filesystem root' }
		.current_dir { 'refusing to trash the current directory' }
		.dot_dot { "refusing to trash '.' or '..'" }
		.trash_dir { 'refusing to trash the trash directory or one of its ancestors' }
		.mount_point { 'is a mount point' }
		.contains_mount { 'contains a mount point' }
		.mount_table { 'cannot read the mount table' }
		.needs_recursive { 'Is a directory' }
		.not_a_directory { 'Not a directory' }
		.dir_not_empty { 'Directory not empty' }
		.no_usable_trash { 'no usable trash directory on this volume' }
		.path_too_long { 'path too long for the Recycle Bin' }
		.invalid_path { 'invalid path for the Recycle Bin' }
		.quota { 'the object does not fit in the Recycle Bin' }
	}
}

// os_error wraps a failed system call. `detail` is supplied by the caller,
// because only the platform layer knows how to render its own error codes.
pub fn os_error(errno int, detail string) TrashError {
	return TrashError{
		kind:       .os
		errno_code: errno
		detail:     detail
	}
}

// is_missing reports whether the target simply does not exist, the only
// failure `-f` silences.
pub fn (e TrashError) is_missing() bool {
	return e.kind == .os && is_missing_code(e.errno_code)
}

// is_missing_error reports whether an error means "this target does not exist",
// which is the only thing `-f` silences.
pub fn is_missing_error(err IError) bool {
	return is_missing_code(err.code())
}

// is_missing_code is `is_missing` for a bare platform code. Windows reports a
// missing leaf and a missing parent with two different codes.
fn is_missing_code(code int) bool {
	$if windows {
		return code == 2 || code == 3 // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
	}
	return code == os.error_code_noent
}
