module trash

// The composed reasons are a public contract: a test
// that only restates the table is still the cheapest way to notice a silent
// wording change.
fn test_composed_reasons() {
	expected := {
		ErrorKind.root:   'refusing to trash a filesystem root'
		.current_dir:     'refusing to trash the current directory'
		.dot_dot:         "refusing to trash '.' or '..'"
		.trash_dir:       'refusing to trash the trash directory or one of its ancestors'
		.mount_point:     'is a mount point'
		.contains_mount:  'contains a mount point'
		.mount_table:     'cannot read the mount table'
		.needs_recursive: 'Is a directory'
		.not_a_directory: 'Not a directory'
		.dir_not_empty:   'Directory not empty'
		.no_usable_trash: 'no usable trash directory on this volume'
		.path_too_long:   'path too long for the Recycle Bin'
		.invalid_path:    'invalid path for the Recycle Bin'
		.quota:           'the object does not fit in the Recycle Bin'
	}
	for kind, text in expected {
		assert TrashError{ kind: kind }.msg() == text
	}
}

fn test_os_error_keeps_platform_text() {
	err := os_error(2, 'No such file or directory')
	assert err.msg() == 'No such file or directory'
	assert err.is_missing()
}

fn test_policy_errors_are_never_missing() {
	assert !TrashError{ kind: .root }.is_missing()
	assert !os_error(13, 'Permission denied').is_missing()
}
